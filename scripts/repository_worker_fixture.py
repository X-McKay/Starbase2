"""Test-only worker: synthetic GitHub HTTP; never loaded by the application worker."""

import asyncio
import base64
import hashlib
from unittest.mock import patch

import httpx
from starbase_runtime import field_sources
from starbase_runtime.worker import run_worker

original_capture = field_sources.capture
SOURCE = b"def added(value):\n    return eval(value)\n"
SHA = hashlib.sha1(b"blob " + str(len(SOURCE)).encode() + b"\0" + SOURCE).hexdigest()


async def handler(request):
    assert request.method == "GET" and request.url.host == "api.github.com"
    assert "authorization" not in request.headers
    path = request.url.path
    pr = {"number": 7, "head": {"sha": "a" * 40}, "base": {"sha": "b" * 40}, "changed_files": 1}
    if path == "/repos/fixture/command/pulls":
        return httpx.Response(200, json=[pr])
    if path == "/repos/fixture/command/pulls/7":
        return httpx.Response(200, json=pr)
    if path == "/repos/fixture/command/pulls/7/files":
        return httpx.Response(
            200,
            json=[
                {
                    "filename": "added.py",
                    "status": "added",
                    "sha": SHA,
                    "additions": 2,
                    "patch": "@@ -0,0 +1,2 @@\n+def added(value):\n+    return eval(value)",
                }
            ],
        )
    if path == "/repos/fixture/command/git/blobs/" + SHA:
        return httpx.Response(
            200,
            json={
                "encoding": "base64",
                "size": len(SOURCE),
                "content": base64.b64encode(SOURCE).decode(),
            },
        )
    raise AssertionError("Unexpected fixture endpoint")


async def capture(target: dict) -> dict:
    if target["kind"] != "github_repository":
        return await original_capture(target)
    assert target["repository"] == "fixture/command" and "token_file" not in target
    async with httpx.AsyncClient(
        base_url="https://api.github.com", transport=httpx.MockTransport(handler)
    ) as client:
        data = await field_sources.repository(target, client)
        data["simulation"] = True
        for pr in data["pulls"]:
            pr["simulation"] = True
        return data


if __name__ == "__main__":
    with patch.object(field_sources, "capture", capture):
        asyncio.run(run_worker())
