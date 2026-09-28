import asyncio
import json

import httpx
import pytest
from starbase_runtime import repository_discovery as discovery


def repo(number):
    return {
        "name": f"repo-{number}",
        "full_name": f"X-McKay/repo-{number}",
        "owner": {"login": "X-McKay"},
        "private": True,
    }


def test_inventory_pages_private_and_fixed_scope():
    seen = []

    def handler(req):
        seen.append(req)
        assert req.method == "GET" and req.url.host == "api.github.com"
        if req.url.path == "/user":
            return httpx.Response(200, json={"login": "X-McKay"})
        assert req.url.params["visibility"] == "all" and req.url.params["affiliation"] == "owner"
        page = int(req.url.params["page"])
        return httpx.Response(200, json=[repo(i) for i in range(100)] if page == 1 else [repo(100)])

    async def run():
        async with httpx.AsyncClient(
            base_url="https://api.github.com", transport=httpx.MockTransport(handler)
        ) as client:
            return await discovery.inventory({"owner": "x-mckay"}, client)

    result = asyncio.run(run())
    assert len(result) == 101 and len(seen) == 3
    assert all(r.startswith("x-mckay/") for r in result)


@pytest.mark.parametrize("mode", ["escape", "duplicate", "capacity", "wrong_login"])
def test_inventory_rejects_incomplete_or_wrong_owner(mode):
    def handler(req):
        if req.url.path == "/user":
            return httpx.Response(
                200, json={"login": "other" if mode == "wrong_login" else "x-mckay"}
            )
        page = int(req.url.params["page"])
        batch = [repo(i) for i in range((page - 1) * 100, page * 100)]
        if mode == "escape":
            batch = [repo(0) | {"full_name": "other/repo-0"}]
        elif mode == "duplicate":
            batch = [repo(0), repo(0)]
        return httpx.Response(200, json=batch)

    async def run():
        async with httpx.AsyncClient(
            base_url="https://api.github.com", transport=httpx.MockTransport(handler)
        ) as client:
            await discovery.inventory({"owner": "x-mckay"}, client)

    with pytest.raises(ValueError, match="authentication|incomplete"):
        asyncio.run(run())


def test_configuration_is_strict(tmp_path, monkeypatch):
    config = tmp_path / "discovery.json"
    monkeypatch.setenv("STARBASE_GITHUB_DISCOVERY_FILE", str(config))
    config.write_text(json.dumps({"owner": "X-McKay", "token_file": str(tmp_path / "token")}))
    configured = discovery.configuration()
    assert configured is not None
    assert configured["interval_seconds"] == 900
    assert configured["owner"] == "x-mckay"
    for bad in [
        {"owner": "../escape", "token_file": "/tmp/token"},
        {"owner": "valid", "token_file": "relative"},
        {"owner": "valid", "token_file": "/tmp/token", "interval_seconds": True},
    ]:
        config.write_text(json.dumps(bad))
        with pytest.raises(ValueError, match="Invalid GitHub discovery configuration"):
            discovery.configuration()


def test_failure_checkpoint_throttles_and_retains_no_partial_inventory(monkeypatch):
    config = {
        "owner": "x-mckay",
        "token_file": "/unused",
        "interval_seconds": 900,
        "discovery_interval_seconds": 3600,
    }
    monkeypatch.setattr(discovery, "configuration", lambda: config)
    monkeypatch.setattr(discovery, "headers", lambda _: {"Authorization": "Bearer synthetic"})
    monkeypatch.setattr(discovery.time, "time", lambda: 1000.0)
    records, posts = [], []

    async def request(method, path, body=None):
        if method == "GET":
            return {"discoveries": records}
        posts.append(body)
        records[:] = [body]
        return body

    async def inventory(*_):
        raise ValueError("incomplete")

    monkeypatch.setattr(discovery, "request", request)
    monkeypatch.setattr(discovery, "inventory", inventory)
    asyncio.run(discovery.reconcile_discovery())
    assert posts[0]["error"] == "incomplete" and posts[0]["repositories"] == []
    asyncio.run(discovery.reconcile_discovery())
    assert len(posts) == 1
    monkeypatch.setattr(discovery.time, "time", lambda: 1300.0)
    asyncio.run(discovery.reconcile_discovery())
    assert len(posts) == 2
    records[0]["complete"] = True
    monkeypatch.setattr(discovery.time, "time", lambda: 1700.0)
    asyncio.run(discovery.reconcile_discovery())
    assert len(posts) == 2
