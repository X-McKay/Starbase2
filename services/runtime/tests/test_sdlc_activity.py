"""Transient activity notes: real loopback HTTP, best effort, never on the critical path."""

import asyncio
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import AsyncMock

import pytest
from pydantic_ai.messages import ModelResponse, ToolCallPart
from pydantic_ai.models.function import FunctionModel
from starbase_runtime import sdlc_activity, sdlc_contract
from starbase_runtime.agents.sdlc.factory import BoundedModel, make_agent
from starbase_runtime.sdlc_workspace import Workspace
from test_sdlc_families import contract, sources


class Core:
    """Minimal stand-in for Core's internal activity route."""

    def __init__(self, delay: float = 0.0, status: int = 200):
        self.received: list[tuple[str, str, dict]] = []
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                time.sleep(delay)
                outer.received.append((self.path, self.headers["Authorization"], body))
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"broadcast":true}')

            def log_message(self, format, *args):  # noqa: A002 - stdlib signature
                pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()


@pytest.fixture
def worker(tmp_path, monkeypatch):
    token = tmp_path / "token"
    token.write_text("worker-secret\n")
    monkeypatch.setenv("STARBASE_TOKEN_FILE", str(token))

    def use(core_url: str):
        monkeypatch.setenv("STARBASE_CORE", core_url)

    return use


def tool_session():
    cap = contract("memory-key")
    ws = Workspace(
        sources("memory-key"), cap, AsyncMock(return_value={"passed": True}), AsyncMock()
    )
    calls = 0

    def model(messages, info):
        nonlocal calls
        calls += 1
        if calls == 1:
            return ModelResponse(parts=[ToolCallPart("inspect_diff", {})])
        return ModelResponse(
            parts=[
                ToolCallPart(
                    info.output_tools[0].name,
                    {"status": "accept", "rationale": "No change needed", "findings": []},
                )
            ]
        )

    return ws, BoundedModel(FunctionModel(model), AsyncMock())


def test_runtime_posts_model_and_tool_notes_for_the_bound_mission(worker):
    core = Core()
    worker(core.url)

    async def exercise():
        sdlc_activity.bind("sdlc-m1")
        ws, wrapped = tool_session()
        with sdlc_activity.role("reviewer"):
            result = await make_agent(wrapped, "reviewer", ws).run("Review")
        assert result.output.status == "accept"
        await sdlc_activity.drain()
        return ws

    try:
        ws = asyncio.run(exercise())
    finally:
        core.close()
    assert {path for path, _, _ in core.received} == {"/internal/v7/missions/sdlc-m1/activity"}
    assert {auth for _, auth, _ in core.received} == {"Bearer worker-secret"}
    notes = [body for _, _, body in core.received]
    kinds = sorted(n["kind"] for n in notes)
    assert kinds == sorted(
        ["model_request_started", "model_request_finished"] * 2 + ["tool_started", "tool_finished"]
    )
    assert all(n["role"] == "reviewer" for n in notes)
    for n in notes:
        sdlc_contract.ActivityNote.model_validate(n)
    finished = [n for n in notes if n["kind"] == "model_request_finished"]
    assert {n["request"] for n in finished} == {1, 2}
    assert all(n["ok"] and "input_tokens" in n and "elapsed_ms" in n for n in finished)
    tool = next(n for n in notes if n["kind"] == "tool_finished")
    assert tool == tool | {"tool": "inspect_diff", "ok": True}
    assert "error" not in tool
    # The mission's retained tool evidence is unchanged by the notes.
    assert [r["tool"] for r in ws.receipts] == ["inspect_diff"]


def test_unbound_or_unauthenticated_work_posts_nothing(worker, monkeypatch):
    core = Core()
    worker(core.url)

    async def unbound():
        sdlc_activity.note("tool_started", tool="inspect_diff")
        await sdlc_activity.drain()

    async def missing_token():
        sdlc_activity.bind("sdlc-m1")
        monkeypatch.setenv("STARBASE_TOKEN_FILE", "/nonexistent/token")
        sdlc_activity.note("tool_started", tool="inspect_diff")
        sdlc_activity.note("not_a_kind")
        await sdlc_activity.drain()

    try:
        asyncio.run(unbound())
        asyncio.run(missing_token())
    finally:
        core.close()
    assert core.received == []


@pytest.mark.parametrize("failure", ["unreachable", "rejected", "slow"])
def test_failing_post_never_breaks_or_slows_the_activity(worker, failure, caplog):
    core = None
    if failure == "unreachable":
        core_url = "http://127.0.0.1:9"  # discard port; connection refused
    else:
        core = Core(delay=3.0 if failure == "slow" else 0.0, status=409)
        core_url = core.url
    worker(core_url)

    async def exercise():
        sdlc_activity.bind("sdlc-m1")
        ws, wrapped = tool_session()
        started = time.monotonic()
        result = await make_agent(wrapped, "reviewer", ws).run("Review")
        elapsed = time.monotonic() - started
        for _ in range(50):
            sdlc_activity.note("tool_started", tool="flood")
        assert len(sdlc_activity._pending) <= sdlc_activity.MAX_IN_FLIGHT
        drained = time.monotonic()
        await sdlc_activity.drain()
        return result, elapsed, time.monotonic() - drained

    try:
        with caplog.at_level("INFO", logger="starbase_runtime.sdlc_activity"):
            result, elapsed, drained = asyncio.run(exercise())
    finally:
        if core:
            core.close()
    assert result.output.status == "accept"
    assert elapsed < 1.0, "notes are detached from the activity's critical path"
    assert drained < sdlc_activity.TIMEOUT_SECONDS + 1.0, "each post is bounded by its timeout"
    assert any("Activity note" in r.getMessage() for r in caplog.records)
