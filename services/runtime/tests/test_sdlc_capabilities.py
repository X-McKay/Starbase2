"""Contract-aware admission, evidence-backed handoffs and scheduling controls."""

import asyncio
import copy
import time
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from starbase_runtime import sdlc_capabilities as capabilities
from starbase_runtime import sdlc_pilot as pilot
from starbase_runtime import sdlc_runtime as runtime
from starbase_runtime import sdlc_sandbox
from starbase_runtime.review import digest
from temporalio.client import WorkflowExecutionStatus


def snapshot():
    return {
        "enabled": True,
        "policy": {
            "enabled": True,
            "generation": 1,
            "max_missions": 3,
            "expires_at": time.time() + 300,
        },
        "coordination": {"can_discover": True, "admission": "ready"},
        "capability_catalog": capabilities.catalog(),
        "missions": [],
    }


def test_contract_freezes_executable_scope_and_returns_defensive_copies():
    c = capabilities.contract_for(pilot.REPOSITORY.upper(), pilot.OPPORTUNITY)
    original = copy.deepcopy(c)
    assert c.pop("digest") == digest(c)
    assert set(c["source_paths"]) == sdlc_sandbox.FILES
    assert c["verification"]["case_ids"] == list(sdlc_sandbox.CASE_IDS)
    assert c["limits"]["max_rounds"] == 3
    assert c["merge"] is False
    assert pilot.build()["manifest"]["capability_digest"] == original["digest"]
    c["assignments"][0]["crew"] = "forged"
    assert capabilities.contract_for(pilot.REPOSITORY, pilot.OPPORTUNITY) == original
    with pytest.raises(ValueError):
        capabilities.contract_for("x-mckay/another", pilot.OPPORTUNITY)


def bound_run():
    return {
        "input": {"capability_digest": pilot.CAPABILITY["digest"], "build": pilot.build()},
        "capability": copy.deepcopy(pilot.CAPABILITY),
        "coordination": {"assignments": copy.deepcopy(pilot.CAPABILITY["assignments"])},
        "evidence": {"investigating": {"source_digest": "test-control"}},
    }


def test_assignments_require_dependency_evidence_and_reject_altered_plan():
    run = bound_run()
    task = capabilities.assignment(run, "lead", pilot.CAPABILITY)
    assert task is not None and task["crew"] == "moss"
    with pytest.raises(ValueError, match="dependency"):
        capabilities.assignment(run, "reviewer", pilot.CAPABILITY)
    run["coordination"]["assignments"][0]["crew"] = "prism"
    with pytest.raises(ValueError, match="assignments"):
        capabilities.assignment(run, "lead", pilot.CAPABILITY)
    run = bound_run()
    run["capability"]["merge"] = True
    with pytest.raises(ValueError, match="capability"):
        capabilities.assignment(run, "lead", pilot.CAPABILITY)
    assert capabilities.assignment({"input": {}}, "lead", pilot.CAPABILITY) is None


def test_member_handoff_retains_actual_assignment_and_build(monkeypatch):
    monkeypatch.setattr(runtime.sdlc_tool_bridge, "enabled", lambda build: False)
    run = bound_run()
    member = AsyncMock(return_value={"role": "lead", "output": {"decision": "implement"}})
    monkeypatch.setattr(pilot, "member", member)
    result = asyncio.run(runtime.assigned_member(run, "lead", {"source": "control"}))
    assert result["assignment"]["task"] == "diagnose"
    assert result["build_digest"] == run["input"]["build"]["digest"]
    assert member.await_args is not None
    assert member.await_args.args[1]["assignment"] == result["assignment"]
    run["evidence"]["implementing"] = {"output": {"decision": "abstain"}}
    with pytest.raises(ValueError, match="declined"):
        asyncio.run(runtime.assigned_member(run, "implementer", {}))
    assert member.await_count == 1


@pytest.mark.parametrize("condition", ["unsupported", "no_change", "ready"])
def test_discovery_contract_compatibility_and_no_change(monkeypatch, condition):
    state = snapshot()
    if condition == "unsupported":
        state.pop("capability_catalog")
    monkeypatch.setattr(runtime, "_next_discovery", 0.0)
    monkeypatch.setattr(pilot, "revision", AsyncMock(return_value=("main", "a" * 40)))
    monkeypatch.setattr(pilot, "capture", AsyncMock(return_value={"fixture": "source"}))
    monkeypatch.setattr(pilot, "applicable", lambda _: condition != "no_change")
    request = AsyncMock(return_value=state)
    monkeypatch.setattr(runtime, "request", request)
    asyncio.run(runtime.discover_sdlc(state))
    posts = [call for call in request.await_args_list if call.args[0] == "POST"]
    assert len(posts) == (1 if condition == "ready" else 0)
    if posts:
        assert posts[0].args[2]["capability_digest"] == pilot.CAPABILITY["digest"]


def test_closed_pr_is_observed_before_next_revision_discovery(monkeypatch):
    state = snapshot()
    state["coordination"]["can_discover"] = False
    state["missions"] = [
        {
            "id": "existing",
            "state": "awaiting_review",
            "publication": {"id": "claim"},
            "input": {"revision": "b" * 40, "opportunity": pilot.OPPORTUNITY},
            "policy_generation": 1,
            "evidence": {"submitted": {"number": 9}},
        }
    ]
    refreshed = copy.deepcopy(state)
    refreshed["coordination"]["can_discover"] = True
    events = []

    async def request(method, path, body=None):
        events.append((method, path, body))
        return refreshed

    async def revision():
        assert events[0][1].endswith("/pr-observation")
        assert events[0][2]["state"] == "closed"
        return "main", "a" * 40

    monkeypatch.setattr(runtime, "_next_discovery", 0.0)
    monkeypatch.setattr(runtime, "request", request)
    monkeypatch.setattr(
        runtime.revision_publisher,
        "observe",
        AsyncMock(
            return_value={
                "head": "c" * 40,
                "state": "closed",
                "open": False,
            }
        ),
    )
    monkeypatch.setattr(pilot, "revision", revision)
    monkeypatch.setattr(pilot, "capture", AsyncMock(return_value={}))
    monkeypatch.setattr(pilot, "applicable", lambda _: True)
    asyncio.run(runtime.discover_sdlc(state))
    assert [path for method, path, _ in events if method == "POST"] == [
        "/internal/v7/missions/existing/pr-observation",
        "/internal/v7/missions",
    ]


def test_provider_failure_does_not_starve_cancellation(monkeypatch, caplog):
    state = snapshot()
    state["missions"] = [{"id": "active", "state": "testing", "cancel_requested": True}]
    monkeypatch.setattr(runtime, "request", AsyncMock(return_value=state))
    monkeypatch.setattr(runtime, "discover_sdlc", AsyncMock(side_effect=RuntimeError("provider")))
    handle = SimpleNamespace(
        describe=AsyncMock(return_value=SimpleNamespace(status=WorkflowExecutionStatus.RUNNING)),
        cancel=AsyncMock(),
    )
    client = SimpleNamespace(get_workflow_handle=lambda _: handle)
    asyncio.run(runtime.reconcile_sdlc(client, "control"))
    handle.cancel.assert_awaited_once()
    assert "discovery unavailable (RuntimeError)" in caplog.text
