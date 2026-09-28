import asyncio

import httpx
import pytest
from starbase_runtime import field_sources as sources


@pytest.mark.parametrize(
    ("status", "headers", "delay"),
    [
        (429, {"retry-after": "120"}, 120),
        (403, {"x-ratelimit-remaining": "0", "x-ratelimit-reset": "1120"}, 120),
        (403, {"retry-after": "999999999"}, 3600),
        (429, {"retry-after": "NaN", "x-ratelimit-reset": "secret"}, 60),
        (429, {"retry-after": "Thu, 01 Jan 1970 00:18:40 GMT"}, 120),
    ],
)
def test_github_cooldown_shared_failfast_and_provider_scoped(monkeypatch, status, headers, delay):
    monkeypatch.setattr(sources, "_GITHUB_READ_AFTER", 0.0)
    monkeypatch.setattr(sources.time, "monotonic", lambda: 100.0)
    monkeypatch.setattr(sources.time, "time", lambda: 1000.0)
    calls = []

    def handler(req):
        calls.append(req)
        if req.url.host == "api.github.com" and len(calls) == 1:
            return httpx.Response(status, headers=headers, text="token=secret error body")
        return httpx.Response(200, json={"ok": True})

    async def run():
        async with httpx.AsyncClient(
            base_url="https://api.github.com", transport=httpx.MockTransport(handler)
        ) as first:
            with pytest.raises(ValueError, match="^Provider rate limited$"):
                await sources.get_json(first, "/user")
        assert sources._GITHUB_READ_AFTER == 100 + delay
        async with httpx.AsyncClient(
            base_url="https://api.github.com", transport=httpx.MockTransport(handler)
        ) as second:
            with pytest.raises(ValueError, match="^Provider rate limited$"):
                await sources.get_json(second, "/repos/other/repo")
            assert len(calls) == 1
            assert await sources.get_json(second, "https://cluster.example/api/v1/pods") == {
                "ok": True
            }
            monkeypatch.setattr(sources.time, "monotonic", lambda: 100.0 + delay)
            assert await sources.get_json(second, "/user") == {"ok": True}

    asyncio.run(run())


def test_plain_forbidden_does_not_claim_rate_limit(monkeypatch):
    monkeypatch.setattr(sources, "_GITHUB_READ_AFTER", 0.0)

    async def run():
        async with httpx.AsyncClient(
            base_url="https://api.github.com",
            transport=httpx.MockTransport(lambda _: httpx.Response(403, text="secret")),
        ) as client:
            with pytest.raises(ValueError, match="^Provider returned HTTP 403$"):
                await sources.get_json(client, "/user")

    asyncio.run(run())
    assert sources._GITHUB_READ_AFTER == 0
