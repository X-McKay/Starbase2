"""Durable timer command compatibility and deterministic fleet staggering."""

import asyncio

import pytest
from starbase_runtime import field_workflow


@pytest.mark.parametrize("patched", [False, True])
def test_repository_timer_retains_legacy_commands_without_patch(monkeypatch, patched):
    calls = []
    input = {"id": "repo-example", "generation": 7, "interval_seconds": 300}

    async def sleep(delay):
        calls.append(("sleep", delay.total_seconds()))

    async def activity(fn, payload, **kwargs):
        calls.append(("tick", payload))
        assert kwargs["retry_policy"].maximum_attempts == 2

    def patch(name):
        assert name == "repository-duty-stagger-v1"
        return patched

    monkeypatch.setattr(field_workflow.workflow, "patched", patch)
    monkeypatch.setattr(field_workflow.workflow, "time", lambda: 12345)
    monkeypatch.setattr(field_workflow.workflow, "sleep", sleep)
    monkeypatch.setattr(field_workflow.workflow, "execute_activity", activity)
    monkeypatch.setattr(
        field_workflow.workflow, "continue_as_new", lambda value: calls.append(("continue", value))
    )
    asyncio.run(field_workflow.FieldDuty().run(input))
    first = field_workflow.repository_initial_delay(input["id"], 300, 12345) if patched else 300
    assert calls[0] == ("sleep", first)
    assert len(calls) == 201
    assert all(calls[i] == ("sleep", 300) for i in range(2, 200, 2))
    assert all(
        calls[i] == ("tick", {"id": input["id"], "generation": 7, "tick": 12345})
        for i in range(1, 200, 2)
    )
    assert calls[-1] == ("continue", input)


def test_repository_phases_are_bounded_stable_and_spread():
    delay = field_workflow.repository_initial_delay
    phases = [delay(f"repo-{n}", 900, 1000) for n in range(256)]
    assert all(1 <= value <= 900 for value in phases)
    assert len(set(phases)) > 200
    assert phases == [delay(f"repo-{n}", 900, 1000 + 900) for n in range(256)]


def test_individual_duties_do_not_record_patch_marker(monkeypatch):
    async def noop(*args, **kwargs):
        return None

    def forbidden(*args):
        raise AssertionError("Legacy individual duties must keep their timer commands")

    monkeypatch.setattr(field_workflow.workflow, "patched", forbidden)
    monkeypatch.setattr(field_workflow.workflow, "sleep", noop)
    monkeypatch.setattr(field_workflow.workflow, "execute_activity", noop)
    monkeypatch.setattr(field_workflow.workflow, "time", lambda: 10)
    monkeypatch.setattr(field_workflow.workflow, "continue_as_new", lambda _: None)
    asyncio.run(
        field_workflow.FieldDuty().run({"id": "observe", "interval_seconds": 300, "generation": 0})
    )
