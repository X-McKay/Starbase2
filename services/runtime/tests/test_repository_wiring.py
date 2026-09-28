import asyncio
import json
from unittest.mock import AsyncMock

import pytest
from starbase_runtime import field, field_dispatch, worker


def test_private_binding_is_owner_scoped_and_never_enters_manifest(monkeypatch, tmp_path):
    config = tmp_path / "discovery.json"
    config.write_text(json.dumps({"owner": "X-McKay", "token_file": str(tmp_path / "secret")}))
    targets = tmp_path / "targets.json"
    targets.write_text("[]")
    monkeypatch.setenv("STARBASE_GITHUB_DISCOVERY_FILE", str(config))
    monkeypatch.setenv("STARBASE_FIELD_TARGETS_FILE", str(targets))
    watches = [
        {"id": "repo-owned", "config": {"repository": "x-mckay/private"}},
        {"id": "repo-other", "config": {"repository": "another/public"}},
    ]
    bound = field.targets(watches)
    assert bound["repo-owned"]["token_file"] == str(tmp_path / "secret")
    assert "token_file" not in bound["repo-other"]
    assert str(tmp_path / "secret") not in json.dumps(field.builds(watches))
    targets.write_text(
        json.dumps(
            [
                {
                    "id": "configured",
                    "agent": "reviewer",
                    "kind": "github_repository",
                    "repository": "x-mckay/private",
                    "token_file": str(tmp_path / "different"),
                }
            ]
        )
    )
    with pytest.raises(ValueError, match="Ambiguous"):
        field.targets(watches)


def test_registration_skips_existing_but_recovers_after_core_replacement(monkeypatch):
    registered = []
    posts = []

    async def request(method, path, body=None):
        if path == "/v4/repositories":
            return {"repositories": []}
        if path == "/v4/snapshot":
            return {"enabled": True, "builds": registered}
        assert method == "POST" and path == "/internal/v4/builds"
        registered.append(body)
        posts.append(body)

    monkeypatch.setattr(field_dispatch, "request", request)
    monkeypatch.setattr(field_dispatch, "builds", lambda _: {"x": {"digest": "one"}})

    async def run():
        await field_dispatch.register_field()
        await field_dispatch.register_field()
        assert len(posts) == 1
        registered.clear()
        await field_dispatch.register_field()
        assert len(posts) == 2

    asyncio.run(run())


def test_discovery_failure_does_not_suppress_current_observations(monkeypatch):
    monkeypatch.setenv("STARBASE_GITHUB_DISCOVERY_FILE", "/operator/config")
    monkeypatch.setenv("STARBASE_TOKEN_FILE", "/operator/token")
    monkeypatch.setattr(worker, "reconcile_discovery", AsyncMock(side_effect=ValueError()))
    for name in ("reconcile", "reconcile_operations", "reconcile_repairs", "reconcile_field"):
        monkeypatch.setattr(worker, name, AsyncMock())
    client = AsyncMock()
    assert not asyncio.run(worker.reconcile_all(client))
    assert isinstance(worker.reconcile_field, AsyncMock)
    worker.reconcile_field.assert_awaited_once_with(client, worker.QUEUE)
