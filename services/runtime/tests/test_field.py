import asyncio
import base64
import hashlib
import json
import ssl

import httpx
import pytest
from starbase_runtime.field_sources import (
    DEFAULT_TARGETS,
    ROOT,
    added_lines,
    analyze,
    cluster,
    github,
    validate_target,
)
from starbase_runtime.memory import episode, recall, scope


def test_cluster_fixture_and_empty_scope():
    data = json.loads((ROOT / "fixtures/field/cluster.json").read_text())
    findings, coverage = analyze(data)
    assert {f["code"] for f in findings} == {"CrashLoopBackOff", "replicas-unavailable"}
    assert not coverage
    data["resources"] = []
    assert analyze(data)[1]


def test_pr_only_changed_lines_and_no_execution():
    data = json.loads((ROOT / "fixtures/field/pr.json").read_text())
    findings, coverage = analyze(data)
    assert len(findings) == 1 and findings[0]["line"] == 2
    data["files"][0]["added_lines"] = [1]
    assert analyze(data)[0] == []
    assert not coverage


def test_diff_and_scope():
    assert added_lines("@@ -1,2 +1,3 @@\n old\n+added\n same") == [2]
    for target in DEFAULT_TARGETS:
        validate_target(target)
    with pytest.raises(ValueError):
        validate_target(DEFAULT_TARGETS[0] | {"token": "must-not-be-public"})
    with pytest.raises(ValueError):
        validate_target(DEFAULT_TARGETS[0] | {"fixture": "pr"})
    with pytest.raises(ValueError):
        validate_target(
            {
                "id": "x",
                "agent": "reviewer",
                "kind": "github",
                "repository": "x/y/../../secrets",
                "pull": 1,
            }
        )
    with pytest.raises(ValueError):
        validate_target(
            {
                "id": "x",
                "agent": "watchkeeper",
                "kind": "kubernetes",
                "api": "http://cluster",
                "namespaces": ["*"],
            }
        )


def test_github_revision_drift_and_get_only():
    calls = []

    async def handler(request):
        assert request.method == "GET" and request.url.host == "api.github.com"
        calls.append(request.url.path)
        if request.url.path.endswith("/files"):
            return httpx.Response(
                200,
                json=[
                    {
                        "filename": "x.py",
                        "sha": hashlib.sha1(b"blob 18\0def f(): return 1\n").hexdigest(),
                        "status": "modified",
                        "patch": "@@ -1 +1 @@\n-old\n+new",
                    }
                ],
            )
        if "/git/blobs/" in request.url.path:
            return httpx.Response(
                200,
                json={
                    "encoding": "base64",
                    "size": 20,
                    "content": base64.b64encode(b"def f(): return 1\n").decode(),
                },
            )
        return httpx.Response(
            200,
            json={
                "head": {"sha": ("a" if len(calls) == 1 else "d") * 40},
                "base": {"sha": "b" * 40},
                "changed_files": 1,
            },
        )

    async def run():
        async with httpx.AsyncClient(
            base_url="https://api.github.com", transport=httpx.MockTransport(handler)
        ) as client:
            with pytest.raises(ValueError, match="changed"):
                await github({"repository": "owner/repo", "pull": 1}, client)

    asyncio.run(run())


def test_cluster_never_fetches_secrets_logs_or_specs():
    async def handler(request):
        assert request.method == "GET"
        assert request.url.path in [
            "/api/v1/namespaces/test/pods",
            "/apis/apps/v1/namespaces/test/deployments",
        ]
        return httpx.Response(200, json={"items": [], "metadata": {}})

    async def run():
        async with httpx.AsyncClient(
            base_url="https://cluster", transport=httpx.MockTransport(handler)
        ) as client:
            return await cluster({"namespaces": ["test"]}, client)

    assert asyncio.run(run())["resources"] == []


@pytest.mark.parametrize("kind", ["kubernetes", "github", "github_repository"])
def test_capture_uses_provider_specific_accept_headers(kind, monkeypatch, tmp_path):
    from starbase_runtime import field_sources

    token = tmp_path / "token"
    token.write_text("synthetic-observer-token")
    target = {"id": "scoped", "kind": kind, "token_file": str(token)}
    if kind == "kubernetes":
        target.update(agent="watchkeeper", api="https://cluster", namespaces=["test"])
    else:
        target.update(agent="reviewer", repository="owner/repo")
        if kind == "github":
            target["pull"] = 1
    requests = []

    def handler(request):
        requests.append(request)
        assert request.method == "GET"
        assert request.headers["authorization"] == "Bearer synthetic-observer-token"
        if kind == "kubernetes":
            # Kubernetes rejects GitHub's vendor media type with HTTP 406.
            if request.headers["accept"] != "application/json":
                return httpx.Response(406)
            assert "x-github-api-version" not in request.headers
            assert request.url.host == "cluster"
            assert request.url.path in {
                "/api/v1/namespaces/test/pods",
                "/apis/apps/v1/namespaces/test/deployments",
            }
            return httpx.Response(200, json={"items": [], "metadata": {}})
        assert request.url.host == "api.github.com"
        assert request.headers["accept"] == "application/vnd.github+json"
        assert request.headers["x-github-api-version"] == "2026-03-10"
        if request.url.path.endswith(("/files", "/pulls")):
            return httpx.Response(200, json=[])
        return httpx.Response(
            200,
            json={"head": {"sha": "a" * 40}, "base": {"sha": "b" * 40}, "changed_files": 0},
        )

    client = httpx.AsyncClient

    def controlled_client(**kwargs):
        assert isinstance(kwargs["verify"], ssl.SSLContext)
        assert kwargs["verify"].verify_mode == ssl.CERT_REQUIRED
        assert kwargs["verify"].check_hostname
        assert kwargs["follow_redirects"] is False
        assert kwargs["trust_env"] is False
        assert kwargs["timeout"] == 15
        return client(**kwargs, transport=httpx.MockTransport(handler))

    monkeypatch.setattr(field_sources.httpx, "AsyncClient", controlled_client)
    result = asyncio.run(field_sources.capture(target))
    assert result["simulation"] is False
    assert len(requests) == {"kubernetes": 2, "github": 3, "github_repository": 1}[kind]


def memory_record():
    return {
        "id": "fixture-memory",
        "agent": "watchkeeper",
        "target": "cluster-fixture",
        "source_run": "fixture-run",
        "source_digest": "fixture-digest",
        "observed_at": 1000.0,
        "finding": {"key": "fixture-key", "code": "replicas-unavailable"},
        "revision": 1,
        "decision": "approve",
    }


def test_memory_scope_and_revision_identity(monkeypatch):
    m = memory_record()
    first = episode(m)
    assert first.group_id == scope("watchkeeper", "cluster-fixture")
    assert first.uuid != episode(m | {"revision": 2}).uuid
    assert scope("reviewer", "cluster-fixture") != first.group_id
    original_scope = scope("watchkeeper", "cluster-fixture")
    monkeypatch.setenv("STARBASE_INSTALLATION", "other-installation")
    assert scope("watchkeeper", "cluster-fixture") != original_scope
    monkeypatch.setenv("STARBASE_MEMORY_ENABLED", "true")
    with pytest.raises(ValueError, match="scope"):
        asyncio.run(recall("reviewer", "cluster-fixture", [m]))


def test_disabled_queued_work_does_not_contact_temporal(monkeypatch):
    from starbase_runtime import field_dispatch

    async def request(*_):
        return {
            "enabled": False,
            "repositories": [],
            "duties": [],
            "runs": [{"state": "queued", "input": {"id": "waiting"}}],
        }

    monkeypatch.setattr(field_dispatch, "request", request)
    # Any Temporal access would fail on this sentinel object.
    asyncio.run(field_dispatch.reconcile_field(object(), "queue"))


def test_repository_watch_capture_budget_revision_and_no_publication(monkeypatch):
    from starbase_runtime import field_sources

    calls = []
    listed: list[dict] = [
        {"number": i, "head": {"sha": "a" * 40}, "base": {"sha": "b" * 40}} for i in range(1, 12)
    ]

    async def handler(request):
        assert request.method == "GET"
        assert request.url.path == "/repos/owner/repo/pulls"
        assert request.url.params["state"] == "open"
        assert request.url.params["per_page"] == "11"
        return httpx.Response(200, json=listed)

    async def github(target, client, source_budget, file_budget):
        assert source_budget == 80_000 and file_budget == 10
        calls.append(target["pull"])
        data = json.loads((ROOT / "fixtures/field/pr.json").read_text())
        return data | {"number": target["pull"], "head": "a" * 40, "base": "b" * 40}

    monkeypatch.setattr(field_sources, "github", github)

    async def run():
        async with httpx.AsyncClient(
            base_url="https://api.github.com", transport=httpx.MockTransport(handler)
        ) as client:
            result = await field_sources.repository({"repository": "owner/repo"}, client)
            assert calls == list(range(1, 11))
            assert not result["list_complete"] and result["coverage"]
            findings, coverage = analyze(result)
            assert len(findings) == 10 and len({f["key"] for f in findings}) == 10
            assert all(f["subject"].startswith("owner/repo#") for f in findings)
            assert coverage
            listed[0]["head"]["sha"] = "c" * 40
            with pytest.raises(ValueError, match="changed"):
                await field_sources.repository({"repository": "owner/repo"}, client)
            listed.clear()
            empty = await field_sources.repository({"repository": "owner/repo"}, client)
            assert empty["pulls"] == [] and empty["list_complete"]
            assert analyze(empty) == ([], [])

    asyncio.run(run())


def test_watch_credentials_are_explicit_and_repository_scoped(monkeypatch, tmp_path):
    from starbase_runtime.field import targets

    config = tmp_path / "targets.json"
    config.write_text(
        json.dumps(
            [
                {
                    "id": "private-pr",
                    "kind": "github",
                    "agent": "reviewer",
                    "repository": "Owner/Private",
                    "pull": 1,
                    "token_file": str(tmp_path / "token"),
                }
            ]
        )
    )
    monkeypatch.setenv("STARBASE_FIELD_TARGETS_FILE", str(config))
    watches = [
        {"id": "repo-a", "config": {"repository": "owner/private"}},
        {"id": "repo-b", "config": {"repository": "owner/public"}},
    ]
    result = targets(watches)
    assert result["repo-a"]["token_file"] == str(tmp_path / "token")
    assert "token_file" not in result["repo-b"]
    assert not result["repo-a"]["allow_inference"]
