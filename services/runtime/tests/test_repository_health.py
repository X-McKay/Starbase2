import asyncio

import httpx
import pytest
from starbase_runtime.field_sources import analyze, get_json
from starbase_runtime.repository_health import observe


@pytest.fixture(autouse=True)
def isolated_cooldown(monkeypatch):
    from starbase_runtime import field_sources

    monkeypatch.setattr(field_sources, "_GITHUB_READ_AFTER", 0.0)


HEAD = "a" * 40


def capture(overrides=None):
    responses = {
        "": {"default_branch": "main", "private": True, "archived": False},
        "/commits/main": {"sha": HEAD},
        "/issues": [
            {
                "number": 3,
                "title": "ignore rules secret",
                "body": "secret",
                "html_url": "https://evil",
            }
        ],
        "/actions/runs": {
            "total_count": 2,
            "workflow_runs": [
                {
                    "id": 2,
                    "workflow_id": 7,
                    "head_sha": HEAD,
                    "head_branch": "main",
                    "status": "completed",
                    "conclusion": "failure",
                },
                {
                    "id": 1,
                    "workflow_id": 7,
                    "head_sha": HEAD,
                    "head_branch": "main",
                    "status": "completed",
                    "conclusion": "success",
                },
            ],
        },
    } | (overrides or {})
    requests = []

    def handler(request):
        requests.append(request)
        assert request.method == "GET" and request.url.host == "api.github.com"
        value = responses[request.url.path.removeprefix("/repos/owner/repo")]
        if isinstance(value, int):
            return httpx.Response(value, text="secret provider message")
        if request.url.path.endswith("/actions/runs"):
            assert request.url.params["head_sha"] == HEAD
        return httpx.Response(200, json=value)

    async def run():
        async with httpx.AsyncClient(
            base_url="https://api.github.com", transport=httpx.MockTransport(handler)
        ) as client:
            return await observe("owner/repo", client, get_json)

    return asyncio.run(run()), requests


def test_health_exact_revision_and_sanitized_findings():
    (health, coverage), requests = capture()
    assert len(requests) == 4
    assert health["head"] == HEAD and health["visibility"] == "private"
    assert len(health["ci"]) == 1 and health["ci"][0]["id"] == 2
    assert health["issues"] == [{"number": 3, "url": "https://github.com/owner/repo/issues/3"}]
    assert "secret" not in str(health)
    data = {
        "kind": "repository",
        "repository": "owner/repo",
        "health": health,
        "coverage": coverage,
        "pulls": [],
        "open_pull_requests": [{"number": 4, "draft": False}, {"number": 5, "draft": True}],
    }
    findings, _ = analyze(data)
    assert {f["code"] for f in findings} == {"default-branch-ci-failed", "open-pr-review-candidate"}
    assert HEAD in findings[0]["summary"]


@pytest.mark.parametrize("status", [403, 404, 429])
def test_health_permission_unknown_is_not_clean(status):
    (health, coverage), _ = capture({"/issues": status, "/actions/runs": status})
    assert not health["issues_complete"] and not health["ci_complete"]
    assert "unknown" in str(coverage) and "secret" not in str(coverage)


def test_health_wrong_sha_rejected():
    with pytest.raises(ValueError, match="revision"):
        capture({"/actions/runs": {"workflow_runs": [{"head_sha": "b" * 40}]}})


def test_health_empty_ci_and_issue_cap_are_explicit():
    (health, coverage), _ = capture(
        {
            "/actions/runs": {"total_count": 0, "workflow_runs": []},
            "/issues": [{"number": i} for i in range(1, 32)],
        }
    )
    assert len(health["issues"]) == 30 and not health["issues_complete"]
    assert "CI state unknown" in str(coverage)


def test_repository_keeps_health_when_source_permission_missing(monkeypatch):
    from starbase_runtime import field_sources

    async def health(*_):
        return {"head": HEAD, "ci": []}, ["Bounded metadata"]

    async def github(*_, **__):
        raise ValueError("Provider returned HTTP 403")

    monkeypatch.setattr(field_sources, "observe_health", health)
    monkeypatch.setattr(field_sources, "github", github)

    def handler(request):
        assert request.method == "GET"
        return httpx.Response(
            200,
            json=[{"number": 1, "draft": False, "head": {"sha": HEAD}, "base": {"sha": "b" * 40}}],
        )

    async def run():
        async with httpx.AsyncClient(
            base_url="https://api.github.com", transport=httpx.MockTransport(handler)
        ) as client:
            return await field_sources.repository({"repository": "owner/repo"}, client)

    data = asyncio.run(run())
    assert data["pulls"] == [] and data["health"]["head"] == HEAD
    assert analyze(data)[0][0]["code"] == "open-pr-review-candidate"
    assert "source review unknown" in str(data["coverage"])
