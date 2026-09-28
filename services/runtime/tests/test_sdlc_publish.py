import asyncio
import json

import httpx
import pytest
from starbase_runtime import sdlc_pilot
from starbase_runtime import sdlc_publish as publisher
from starbase_runtime.review import digest

BASE, HEAD, TREE, BLOB = (c * 40 for c in "abcd")


def mission():
    return {
        "id": "sdlc-test",
        "input": {"repository": "X-McKay/algent", "revision": BASE},
        "created_at": 1000,
        "evidence": {"reviewing": {"rationale": "Bounded fix."}},
    }


class Provider:
    def __init__(self, monkeypatch):
        self.claims = set()
        self.posts = []
        self.auths = 0
        self.events = []
        self.branch = None
        self.pulls = []
        self.reviews = []
        self.cancel_at = None
        self.lose = None
        self.base = BASE
        self.runs = []
        self.existing_artifact = False
        self.branch_reads = 0
        self.drift_after_branch = False
        monkeypatch.setattr(publisher, "request", self.core)
        monkeypatch.setattr(
            sdlc_pilot,
            "client",
            lambda: httpx.AsyncClient(
                base_url="https://api.github.com", transport=httpx.MockTransport(self.http)
            ),
        )

    async def core(self, method, path, body):
        assert method == "POST" and path.startswith("/internal/v7/missions/sdlc-test/")
        if path.endswith("/publication"):
            self.auths += 1
            assert body == {
                "revision": BASE,
                "artifact_digest": digest(publisher.artifacts(files())),
            }
            if self.cancel_at == self.auths:
                raise RuntimeError("Core cancelled")
            return {}
        if path.endswith("/effect"):
            claimed = body["kind"] not in self.claims
            self.claims.add(body["kind"])
            return {"claimed": claimed}
        self.events.append(body)
        if self.drift_after_branch and body["key"] == "published-branch":
            self.branch = "e" * 40
        return {}

    def http(self, request):
        assert request.url.host == "api.github.com"
        path = request.url.path.removeprefix("/repos/x-mckay/algent")
        assert path != request.url.path
        if request.method == "GET":
            if path == "":
                value = {"default_branch": "main"}
            elif path == "/commits/main":
                value = {"sha": self.base}
            elif path.startswith("/contents/"):
                return (
                    httpx.Response(200, json={}) if self.existing_artifact else httpx.Response(404)
                )
            elif path.startswith("/git/commits/"):
                value = {"tree": {"sha": TREE}}
            elif path.startswith("/git/ref/heads/"):
                self.branch_reads += 1
                if self.branch is None:
                    return httpx.Response(404)
                value = {"object": {"sha": self.branch}}
            elif path == "/pulls":
                assert request.url.params["state"] == "all"
                value = self.pulls
            elif path == "/pulls/1/reviews":
                value = self.reviews
            elif path == "/actions/runs":
                assert request.url.params["head_sha"] == HEAD
                value = {"workflow_runs": self.runs, "total_count": len(self.runs)}
            else:
                raise AssertionError(path)
            return httpx.Response(200, json=value)
        assert request.method == "POST"
        body = json.loads(request.content)
        self.posts.append((path, body, self.auths))
        if path == "/git/blobs":
            value = {"sha": BLOB}
        elif path == "/git/trees":
            assert set(v["path"] for v in body["tree"]) == set(publisher.artifacts(files()))
            value = {"sha": TREE}
        elif path == "/git/commits":
            assert body["parents"] == [BASE]
            assert body["author"] == body["committer"]
            value = {"sha": HEAD}
        elif path == "/git/refs":
            assert "branch" in self.claims
            self.branch = body["sha"]
            value = {}
        elif path == "/pulls":
            assert "pr" in self.claims
            self.pulls = [
                {
                    "number": 1,
                    "body": body["body"],
                    "head": {"sha": HEAD, "ref": "starbase/sdlc-test"},
                    "base": {"ref": "main"},
                }
            ]
            value = self.pulls[0]
        elif path == "/pulls/1/reviews":
            assert "review" in self.claims and body["event"] == "COMMENT"
            self.reviews = [
                {"id": 2, "body": body["body"], "commit_id": HEAD, "state": "COMMENTED"}
            ]
            value = self.reviews[0]
        else:
            raise AssertionError(path)
        if self.lose == path:
            self.lose = None
            raise httpx.ReadTimeout("secret error text", request=request)
        return httpx.Response(201, json=value)


def files():
    return {sdlc_pilot.SOURCE: "trusted scoped candidate"}


def run():
    return asyncio.run(publisher.publish(mission(), files()))


def test_artifacts_are_trusted_and_bounded():
    assert len(publisher.artifacts(files())) == 3
    with pytest.raises(ValueError):
        publisher.artifacts(files() | {"evil.py": "oops"})
    with pytest.raises(ValueError):
        publisher.artifacts({sdlc_pilot.SOURCE: "x" * 24001})
    assert "pull_request_target" not in publisher.WORKFLOW
    assert "persist-credentials: false" in publisher.WORKFLOW
    assert "python-version: '3.13.5'" in publisher.WORKFLOW


def test_publish_replay_does_not_duplicate_mutable_effects(monkeypatch):
    provider = Provider(monkeypatch)
    assert (
        run()
        == run()
        == {
            "url": "https://github.com/X-McKay/algent/pull/1",
            "number": 1,
            "head": HEAD,
            "branch": "starbase/sdlc-test",
            "review_id": 2,
        }
    )
    for path in ("/git/refs", "/pulls", "/pulls/1/reviews"):
        assert sum(p[0] == path for p in provider.posts) == 1
    # Every actual write has a newer Core authorization than the preceding write.
    auths = [p[2] for p in provider.posts]
    assert auths == sorted(set(auths))


@pytest.mark.parametrize("lost", ["/git/refs", "/pulls", "/pulls/1/reviews"])
def test_lost_responses_reconcile_without_repeating_effect(monkeypatch, lost):
    provider = Provider(monkeypatch)
    provider.lose = lost
    with pytest.raises(publisher.PublicationUnknown, match="requires reconciliation"):
        run()
    assert run()["review_id"] == 2
    assert sum(p[0] == lost for p in provider.posts) == 1


@pytest.mark.parametrize("kind", ["branch", "pr", "review"])
def test_claimed_but_absent_blocks_instead_of_retry(monkeypatch, kind):
    provider = Provider(monkeypatch)
    provider.claims.add(kind)
    with pytest.raises(publisher.PublicationUnknown, match="not visible"):
        run()
    path = {"branch": "/git/refs", "pr": "/pulls", "review": "/pulls/1/reviews"}[kind]
    assert all(p[0] != path for p in provider.posts)


def test_revocation_stops_next_write_and_replays(monkeypatch):
    provider = Provider(monkeypatch)
    provider.cancel_at = 3
    with pytest.raises(RuntimeError, match="Core cancelled"):
        run()
    assert len(provider.posts) == 1
    provider.cancel_at = provider.auths + 1
    with pytest.raises(RuntimeError, match="Core cancelled"):
        run()
    assert len(provider.posts) == 1


def test_source_drift_and_existing_artifacts_fail_closed(monkeypatch):
    provider = Provider(monkeypatch)
    provider.base = "e" * 40
    with pytest.raises(ValueError, match="Base revision changed"):
        run()
    assert not provider.posts
    provider.base = BASE
    provider.existing_artifact = True
    with pytest.raises(ValueError, match="already exists"):
        run()
    assert not provider.posts


def test_wrong_repository_never_calls_provider(monkeypatch):
    provider = Provider(monkeypatch)
    value = mission()
    value["input"]["repository"] = "X-McKay/Starbase2"
    with pytest.raises(ValueError, match="outside pilot"):
        asyncio.run(publisher.publish(value, files()))
    assert provider.auths == 0


def test_branch_conflict_never_updates(monkeypatch):
    provider = Provider(monkeypatch)
    provider.branch = "e" * 40
    with pytest.raises(publisher.PublicationUnknown, match="identity mismatch"):
        run()
    assert all(
        p[0].startswith(("/git/blobs", "/git/trees", "/git/commits")) for p in provider.posts
    )


def test_branch_drift_before_pr_is_fenced(monkeypatch):
    provider = Provider(monkeypatch)
    provider.drift_after_branch = True
    with pytest.raises(publisher.PublicationUnknown, match="changed before effect"):
        run()
    assert not provider.pulls


def test_provider_errors_do_not_expose_response_bodies():
    async def check():
        async with httpx.AsyncClient(
            base_url="https://api.github.com",
            transport=httpx.MockTransport(lambda _: httpx.Response(503, text="secret")),
        ) as http:
            with pytest.raises(publisher.PublicationUnknown, match="server outcome") as error:
                await publisher._json(http, "POST", "/pulls", body={})
            assert "secret" not in str(error.value)

    asyncio.run(check())


def test_exact_head_and_workflow_ci_only(monkeypatch):
    provider = Provider(monkeypatch)

    def check():
        return asyncio.run(publisher.followup({"head": HEAD}))

    assert check()["status"] == "absent"
    provider.runs = [
        {
            "id": 1,
            "head_sha": "e" * 40,
            "path": publisher.WORKFLOW_PATH,
            "status": "completed",
            "conclusion": "success",
        },
        {
            "id": 2,
            "head_sha": HEAD,
            "path": "other.yml",
            "status": "completed",
            "conclusion": "success",
        },
    ]
    assert check()["status"] == "absent"
    provider.runs.append(
        {"id": 3, "head_sha": HEAD, "path": publisher.WORKFLOW_PATH, "status": "queued"}
    )
    assert check()["status"] == "pending"
    provider.runs[-1].update(status="completed", conclusion="failure")
    assert check()["status"] == "failed"
    provider.runs[-1]["conclusion"] = "success"
    assert check()["status"] == "passed"
