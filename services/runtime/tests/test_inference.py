import asyncio

import httpx
from starbase_runtime.inference import configuration, explain


def test_inference_payload_contains_meanings_but_no_source_paths_or_secrets(monkeypatch):
    captured = []

    def handler(request):
        captured.append(request.content.decode())
        return httpx.Response(
            200,
            json={
                "model": "test-model",
                "choices": [
                    {
                        "finish_reason": "stop",
                        "message": {
                            "content": '{"summary":"eval warning","recommendation":"review input"}'
                        },
                    }
                ],
                "usage": {"total_tokens": 4},
            },
        )

    original = httpx.AsyncClient
    monkeypatch.setattr(
        httpx, "AsyncClient", lambda **kw: original(**kw, transport=httpx.MockTransport(handler))
    )
    result = asyncio.run(
        explain(
            {
                "findings": [
                    {"code": "S307", "file": "private-path.py", "message": "secret-test-value"}
                ],
                "files_reviewed": 1,
                "errors": [],
            },
            configuration(),
        )
    )
    assert result["status"] == "available"
    assert "eval" in captured[0]
    assert "private-path" not in captured[0] and "secret-test-value" not in captured[0]


def test_truncated_inference_is_unavailable_without_retry(monkeypatch):
    calls = []

    def handler(request):
        calls.append(request)
        return httpx.Response(
            200, json={"choices": [{"finish_reason": "length", "message": {"content": "{}"}}]}
        )

    original = httpx.AsyncClient
    monkeypatch.setattr(
        httpx, "AsyncClient", lambda **kw: original(**kw, transport=httpx.MockTransport(handler))
    )
    result = asyncio.run(
        explain({"findings": [], "files_reviewed": 1, "errors": []}, configuration())
    )
    assert result["status"] == "unavailable" and len(calls) == 1
