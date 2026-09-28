import asyncio
import copy
import json

import httpx
import pytest
from starbase_runtime import sdlc_pilot
from starbase_runtime import sdlc_revision_publish as adapter
from starbase_runtime.review import digest

HEAD, CANDIDATE, TREE, BLOB = (v * 40 for v in "abcd")
BRANCH = "starbase/sdlc-test"


def source_files():
    return {path: "original" for path in sdlc_pilot.FILES}


def candidate_files():
    return source_files() | {sdlc_pilot.SOURCE: "corrected"}


def mission():
    return {
        "id": "sdlc-test",
        "input": {"repository": "x-mckay/algent"},
        "evidence": {"submitted": {"number": 7, "branch": BRANCH}},
    }


def verification():
    return {
        "id": "verify-one",
        "input": {"head": HEAD},
        "created_at": 1000,
        "evidence": {
            "verified": {"outcome": "passed", "sources": source_files()},
            "testing": {"artifact_digest": digest(candidate_files())},
            "reviewing": {"status": "accept", "rationale": "Narrow correction."},
        },
        "effects": [],
    }


class Provider:
    def __init__(self, monkeypatch):
        self.verification = verification()
        self.head = HEAD
        self.open = True
        self.repo = "X-McKay/algent"
        self.statuses = []
        self.reviews = []
        self.posts = []
        self.auths = 0
        self.cancel_at = None
        self.lose = None
        self.drop = None
        self.drift_on_claim = False
        monkeypatch.setattr(adapter, "request", self.core)
        monkeypatch.setattr(
            sdlc_pilot,
            "client",
            lambda: httpx.AsyncClient(
                base_url="https://api.github.com", transport=httpx.MockTransport(self.http)
            ),
        )

    async def core(self, method, path, body):
        assert method == "POST"
        assert path.startswith("/internal/v7/missions/sdlc-test/verifications/verify-one/")
        if path.endswith("/authorize"):
            self.auths += 1
            if self.auths == self.cancel_at:
                raise RuntimeError("Core revoked")
            return copy.deepcopy(self.verification)
        assert path.endswith("/effect")
        effects = self.verification["effects"]
        match = next((e for e in effects if e["input"]["kind"] == body["kind"]), None)
        if match:
            assert match["input"] == body
            return {"claimed": False, "claim": match}
        effects.append({"input": body})
        if self.drift_on_claim:
            self.head = "e" * 40
        return {"claimed": True, "claim": effects[-1]}

    def http(self, request):
        assert request.url.host == "api.github.com"
        path = request.url.path.removeprefix("/repos/x-mckay/algent")
        assert path != request.url.path
        if request.method == "GET":
            if path == "":
                value = {"default_branch": "main"}
            elif path == "/pulls/7":
                value = {
                    "number": 7,
                    "state": "open" if self.open else "closed",
                    "merged": False,
                    "head": {"sha": self.head, "ref": BRANCH, "repo": {"full_name": self.repo}},
                    "base": {"ref": "main", "repo": {"full_name": "X-McKay/algent"}},
                }
            elif path == f"/commits/{HEAD}/statuses":
                value = self.statuses
            elif path == f"/git/commits/{HEAD}":
                value = {"tree": {"sha": TREE}}
            elif path == "/git/ref/heads/" + BRANCH:
                value = {"object": {"sha": self.head}}
            elif path == "/pulls/7/reviews":
                value = self.reviews
            else:
                raise AssertionError(path)
            return httpx.Response(200, json=value)
        assert request.method in {"POST", "PATCH"}
        body = json.loads(request.content)
        self.posts.append((request.method, path, body, self.auths))
        if self.drop == path:
            self.drop = None
            raise httpx.ReadTimeout("secret transport", request=request)
        if path == f"/statuses/{HEAD}":
            value = body | {"id": len(self.statuses) + 1}
            self.statuses.insert(0, value)
        elif path == "/git/blobs":
            value = {"sha": BLOB}
        elif path == "/git/trees":
            assert body["base_tree"] == TREE
            assert [v["path"] for v in body["tree"]] == [sdlc_pilot.SOURCE]
            value = {"sha": TREE}
        elif path == "/git/commits":
            assert body["parents"] == [HEAD] and body["author"] == body["committer"]
            value = {"sha": CANDIDATE}
        elif path == "/git/refs/heads/" + BRANCH:
            assert request.method == "PATCH" and body == {"sha": CANDIDATE, "force": False}
            self.head = CANDIDATE
            value = {"object": {"sha": self.head}}
        elif path == "/pulls/7/reviews":
            assert body["event"] == "COMMENT" and body["commit_id"] == CANDIDATE
            value = {"id": 41, "body": body["body"], "commit_id": CANDIDATE, "state": "COMMENTED"}
            self.reviews.append(value)
        else:
            raise AssertionError(path)
        if self.lose == path:
            self.lose = None
            raise httpx.ReadTimeout("secret transport", request=request)
        return httpx.Response(201, json=value)


def publish_status(pending=False):
    return asyncio.run(adapter.status(mission(), verification(), pending))


def update():
    return asyncio.run(adapter.update(mission(), verification(), candidate_files()))


def test_status_uses_core_outcome_and_reconciles_exact_marker(monkeypatch):
    provider = Provider(monkeypatch)
    provider.verification["evidence"]["verified"]["outcome"] = "failed"
    assert publish_status()["state"] == "failure"
    assert publish_status()["id"] == 1
    assert len(provider.posts) == 1
    assert provider.statuses[0]["context"] == adapter.CONTEXT
    assert "verify-one" in provider.statuses[0]["description"]


@pytest.mark.parametrize(
    "pending,outcome,expected",
    [
        (True, "failed", "pending"),
        (False, "passed", "success"),
        (False, "infrastructure_blocked", "error"),
    ],
)
def test_status_states(monkeypatch, pending, outcome, expected):
    provider = Provider(monkeypatch)
    provider.verification["evidence"]["verified"]["outcome"] = outcome
    assert publish_status(pending)["state"] == expected


def test_status_lost_response_reconciles_without_duplicate(monkeypatch):
    provider = Provider(monkeypatch)
    provider.lose = f"/statuses/{HEAD}"
    with pytest.raises(adapter.PublicationUnknown):
        publish_status()
    assert publish_status()["state"] == "success"
    assert len(provider.posts) == 1


def test_status_claimed_but_not_visible_never_retries(monkeypatch):
    provider = Provider(monkeypatch)
    provider.drop = f"/statuses/{HEAD}"
    with pytest.raises(adapter.PublicationUnknown):
        publish_status()
    with pytest.raises(adapter.PublicationUnknown, match="Claimed status"):
        publish_status()
    assert len(provider.posts) == 1


@pytest.mark.parametrize("operation", [publish_status, update])
@pytest.mark.parametrize("condition", ["closed", "stale", "foreign"])
def test_closed_stale_or_foreign_pr_never_writes(monkeypatch, operation, condition):
    provider = Provider(monkeypatch)
    if condition == "closed":
        provider.open = False
    elif condition == "stale":
        provider.head = "e" * 40
    else:
        provider.repo = "someone/algent"
    with pytest.raises(ValueError):
        operation()
    assert not provider.posts


def test_update_is_narrow_nonforce_and_idempotent(monkeypatch):
    provider = Provider(monkeypatch)
    assert update() == update()
    patches = [p for p in provider.posts if p[0] == "PATCH"]
    reviews = [p for p in provider.posts if p[1] == "/pulls/7/reviews"]
    assert len(patches) == len(reviews) == 1
    auths = [p[3] for p in provider.posts]
    assert auths == sorted(set(auths))


@pytest.mark.parametrize("path", ["/git/refs/heads/" + BRANCH, "/pulls/7/reviews"])
def test_lost_update_or_review_reconciles(monkeypatch, path):
    provider = Provider(monkeypatch)
    provider.lose = path
    with pytest.raises(adapter.PublicationUnknown):
        update()
    assert update()["head"] == CANDIDATE
    assert sum(p[1] == path for p in provider.posts) == 1


@pytest.mark.parametrize("path", ["/git/refs/heads/" + BRANCH, "/pulls/7/reviews"])
def test_claimed_absent_update_or_review_is_not_retried(monkeypatch, path):
    provider = Provider(monkeypatch)
    provider.drop = path
    with pytest.raises(adapter.PublicationUnknown):
        update()
    with pytest.raises(adapter.PublicationUnknown, match="Claimed"):
        update()
    assert sum(p[1] == path for p in provider.posts) == 1


@pytest.mark.parametrize("operation", [publish_status, update])
def test_revocation_blocks_effects_and_replay(monkeypatch, operation):
    provider = Provider(monkeypatch)
    provider.cancel_at = 3
    with pytest.raises(RuntimeError, match="Core revoked"):
        operation()
    count = len(provider.posts)
    provider.cancel_at = provider.auths + 1
    with pytest.raises(RuntimeError, match="Core revoked"):
        operation()
    assert len(provider.posts) == count


def test_drift_after_claim_blocks_patch(monkeypatch):
    provider = Provider(monkeypatch)
    provider.drift_on_claim = True
    with pytest.raises(ValueError, match="Branch changed"):
        update()
    assert not any(p[0] == "PATCH" for p in provider.posts)


@pytest.mark.parametrize("change", ["extra", "support", "digest", "review"])
def test_candidate_scope_and_evidence_gates(monkeypatch, change):
    provider = Provider(monkeypatch)
    files = candidate_files()
    if change == "extra":
        files["tests/changed.py"] = "oops"
    elif change == "support":
        files["src/utils/logging.py"] = "oops"
    elif change == "digest":
        provider.verification["evidence"]["testing"]["artifact_digest"] = "wrong"
    else:
        provider.verification["evidence"]["reviewing"]["status"] = "revise"
    with pytest.raises(ValueError):
        asyncio.run(adapter.update(mission(), verification(), files))
    assert not provider.posts


def test_status_unknown_outcome_never_self_certifies(monkeypatch):
    provider = Provider(monkeypatch)
    provider.verification["evidence"]["verified"]["outcome"] = "model says pass"
    with pytest.raises(ValueError, match="Core has no"):
        publish_status()
    assert not provider.posts


def test_observe_is_read_only_and_reports_closed(monkeypatch):
    provider = Provider(monkeypatch)
    provider.open = False
    assert asyncio.run(adapter.observe(mission())) == {
        "head": HEAD,
        "open": False,
        "state": "closed",
        "branch": BRANCH,
    }
    assert not provider.posts and provider.auths == 0


@pytest.mark.parametrize("operation", [publish_status, update])
def test_verification_head_must_match_fresh_core_record(monkeypatch, operation):
    provider = Provider(monkeypatch)
    provider.verification["input"]["head"] = "e" * 40
    with pytest.raises(ValueError, match="Core authority"):
        operation()
    assert not provider.posts


def test_old_head_status_cannot_claim_updated_head_success(monkeypatch):
    provider = Provider(monkeypatch)
    old_status = publish_status()
    assert update()["head"] == CANDIDATE
    with pytest.raises(ValueError, match="head changed"):
        publish_status()
    assert old_status["head"] == HEAD
    assert len(provider.statuses) == 1
    assert provider.statuses[0]["description"] == "Starbase verification verify-one: success"


def test_status_coverage_and_other_contexts_cannot_imply_success(monkeypatch):
    provider = Provider(monkeypatch)
    provider.statuses = [
        {
            "id": 9,
            "context": "unrelated",
            "state": "success",
            "description": "Starbase verification verify-one: success",
        }
    ]
    assert publish_status()["id"] != 9
    provider.statuses = [{"context": "unrelated"}] * 100
    count = len(provider.posts)
    with pytest.raises(adapter.PublicationUnknown, match="coverage incomplete"):
        publish_status()
    assert len(provider.posts) == count
