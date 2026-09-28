import asyncio

import pytest
from starbase_runtime import sdlc_capabilities
from starbase_runtime.sdlc_workspace import Limits, Workspace, WorkspaceExhausted


@pytest.fixture
def anyio_backend():
    return "asyncio"


PATH = "src/utils/persistence.py"
SOURCE = """class Store:
    def get_agent_memory(self, agent, memory_key=None):
        if memory_key:
            return 7
        return {}

    def untouched(self):
        return 42
"""


def workspace(*, tester=None, guard=None, limits=None):
    async def test(files):
        return {"passed": "is not None" in files[PATH]}

    async def allow():
        return None

    return Workspace(
        {PATH: SOURCE},
        sdlc_capabilities.contract_for("x-mckay/algent", "memory-key"),
        tester or test,
        guard or allow,
        limits=limits or Limits(),
    )


@pytest.mark.anyio
async def test_inspect_edit_test_exact_digest_and_immutable_receipts():
    ws = workspace()
    initial = ws.source_digest
    assert (await ws.inspect_symbol(PATH))["ok"]
    assert (await ws.search_source("memory_key"))["matches"]
    assert (await ws.apply_patch(PATH, initial, "if memory_key:", "if memory_key is not None:"))[
        "ok"
    ]
    changed = ws.candidate_digest
    assert (await ws.check_candidate())["syntax"] == "valid"
    assert "+        if memory_key is not None:" in (await ws.inspect_diff())["diff"]
    first = await ws.run_public_tests()
    assert first["tested_digest"] == changed and not first["cached"]
    assert (await ws.run_public_tests())["cached"]
    assert (await ws.apply_patch(PATH, ws.source_digest, "return 7", "return 8"))["ok"]
    assert not (await ws.run_public_tests())["cached"]
    assert ws.candidate_digest != changed
    snapshot = ws.snapshot()
    snapshot[PATH] = "changed"
    records = ws.receipts
    records[0]["ok"] = False
    assert ws.receipts[0]["ok"] and ws.snapshot()[PATH] != "changed"


@pytest.mark.anyio
@pytest.mark.parametrize(
    "old,new,error",
    [
        ("return 42", "return 43", "outside"),
        ("memory_key=None", "memory_key=False", "unrelated"),
        ("if memory_key:", "if memory_key", "Syntax error"),
        ("return", "yield", "ambiguous"),
        ("if memory_key:", "if memory_key:", "unchanged"),
    ],
)
async def test_rejected_edits_preserve_workspace(old, new, error):
    ws = workspace()
    before = ws.candidate_digest
    result = await ws.apply_patch(PATH, ws.source_digest, old, new)
    assert not result["ok"] and error in result["error"]
    assert ws.candidate_digest == before
    assert (
        await ws.apply_patch(PATH, ws.source_digest, "if memory_key:", "if memory_key is not None:")
    )["ok"]


@pytest.mark.anyio
async def test_stale_hash_wrong_path_and_whole_symbol():
    ws = workspace()
    assert not (await ws.apply_patch(PATH, "stale", "return 7", "return 8"))["ok"]
    assert not (await ws.apply_patch("other.py", ws.source_digest, "return 7", "return 8"))["ok"]
    new = "def get_agent_memory(self, agent, memory_key=None):\n    return 9"
    assert (await ws.replace_symbol(PATH, ws.source_digest, new))["ok"]
    assert "        return 9" in ws.snapshot()[PATH]
    assert not (
        await ws.replace_symbol(
            PATH, ws.source_digest, new.replace("memory_key=None", "memory_key=1")
        )
    )["ok"]


@pytest.mark.anyio
async def test_duplicate_symbols_rejected_before_any_execution():
    with pytest.raises(ValueError, match="ambiguous"):
        Workspace(
            {PATH: SOURCE + SOURCE},
            {"editable_paths": [PATH], "editable_symbol": "get_agent_memory"},
            workspace()._tester,
            lambda: None,
        )


@pytest.mark.anyio
async def test_repeated_failures_and_no_progress_stop():
    ws = workspace(limits=Limits(repeated_failures=2))
    for _ in range(2):
        assert not (await ws.apply_patch(PATH, "stale", "return 7", "return 8"))["ok"]
    assert (
        "Repeated failed" in (await ws.apply_patch(PATH, "stale", "return 7", "return 8"))["error"]
    )
    ws = workspace(limits=Limits(no_progress=2))
    await ws.inspect_diff()
    await ws.check_candidate()
    with pytest.raises(WorkspaceExhausted):
        await ws.inspect_symbol(PATH)


@pytest.mark.anyio
async def test_cancelled_test_result_is_not_cached():
    blocked = False

    async def guard():
        if blocked:
            raise asyncio.CancelledError()

    async def tester(files):
        nonlocal blocked
        blocked = True
        return {"passed": True}

    ws = workspace(tester=tester, guard=guard)
    with pytest.raises(asyncio.CancelledError):
        await ws.run_public_tests()
    assert ws.receipts[-1]["error"] == "CancelledError"
    assert not ws._cache
    with pytest.raises(asyncio.CancelledError):
        await ws.apply_patch(PATH, ws.source_digest, "return 7", "return 8")
    assert ws.snapshot()[PATH] == SOURCE


@pytest.mark.anyio
async def test_timeout_and_output_limits():
    async def tester(files):
        await asyncio.sleep(1)
        return {}

    ws = workspace(tester=tester, limits=Limits(test_seconds=0.001))
    with pytest.raises(TimeoutError):
        await ws.run_public_tests()
    assert not ws._cache
    ws = workspace(limits=Limits(output_bytes=50))
    assert not (await ws.inspect_symbol(PATH))["ok"]
    ws = workspace(limits=Limits(calls=1))
    await ws.inspect_diff()
    with pytest.raises(WorkspaceExhausted):
        await ws.check_candidate()


@pytest.mark.anyio
async def test_submission_requires_exact_passing_tests_and_diff():
    ws = workspace()
    with pytest.raises(ValueError, match="no source change"):
        ws.finish(ws.candidate_digest)
    await ws.apply_patch(PATH, ws.source_digest, "if memory_key:", "if memory_key is not None:")
    with pytest.raises(ValueError, match="passing public"):
        ws.finish(ws.candidate_digest)
    await ws.run_public_tests()
    with pytest.raises(ValueError, match="exact diff"):
        ws.finish(ws.candidate_digest)
    await ws.inspect_diff()
    assert ws.finish(ws.candidate_digest) == ws.snapshot()
    old_digest = ws.candidate_digest
    await ws.apply_patch(PATH, ws.source_digest, "return 7", "return 8")
    with pytest.raises(ValueError, match="stale"):
        ws.finish(old_digest)
    with pytest.raises(ValueError, match="passing public"):
        ws.finish(ws.candidate_digest)


@pytest.mark.anyio
async def test_guard_validation_failure_is_not_recoverable_tool_error():
    def guard():
        raise ValueError("authority gone")

    ws = workspace(guard=guard)
    with pytest.raises(PermissionError):
        await ws.inspect_diff()
    assert ws.receipts[-1]["error"] == "PermissionError"


@pytest.mark.anyio
async def test_cancellation_after_local_edit_rolls_back_candidate():
    calls = 0

    async def guard():
        nonlocal calls
        calls += 1
        if calls == 2:
            raise asyncio.CancelledError()

    ws = workspace(guard=guard)
    with pytest.raises(asyncio.CancelledError):
        await ws.apply_patch(PATH, ws.source_digest, "return 7", "return 8")
    assert ws.snapshot()[PATH] == SOURCE


@pytest.mark.anyio
async def test_repeated_candidate_cycle_consumes_no_progress_budget():
    ws = workspace(limits=Limits(no_progress=2))
    await ws.apply_patch(PATH, ws.source_digest, "return 7", "return 8")
    await ws.apply_patch(PATH, ws.source_digest, "return 8", "return 7")
    await ws.apply_patch(PATH, ws.source_digest, "return 7", "return 8")
    with pytest.raises(WorkspaceExhausted):
        await ws.inspect_diff()


@pytest.mark.anyio
async def test_authority_revocation_interrupts_inflight_public_tester():
    started, cleaned, revoked = asyncio.Event(), asyncio.Event(), asyncio.Event()

    async def guard():
        if revoked.is_set():
            raise PermissionError("revoked")

    async def tester(files):
        started.set()
        try:
            await asyncio.sleep(30)
        finally:
            cleaned.set()
        return {"passed": True}

    ws = workspace(tester=tester, guard=guard)
    task = asyncio.create_task(ws.run_public_tests())
    await started.wait()
    revoked.set()
    with pytest.raises(PermissionError):
        await asyncio.wait_for(task, 1)
    assert cleaned.is_set()
    assert ws.receipts[-1]["execution"] == {"started": True, "cleanup_awaited": True}
    assert not ws._cache
