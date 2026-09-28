"""Trainer call and immutable Procedure controls; Core owns comparison/adoption."""

import asyncio
import copy

import pytest
from pydantic import ValidationError
from starbase_runtime import joint, learning


def cycle():
    return {
        "id": "cycle-a",
        "baseline": joint.build(),
        "source_build": "earlier-build",
        "source_missions": [],
        "proposal": {"state": "reserved", "result": None},
    }


def test_procedure_changes_exact_build_without_authority_or_code_changes():
    baseline = joint.build()
    candidate = joint.build(procedure="Inspect useful work separately from probes.")
    assert candidate["digest"] != baseline["digest"]
    without = dict(candidate["manifest"])
    assert without.pop("procedure")
    assert without == baseline["manifest"]
    with pytest.raises(ValueError):
        joint.build(procedure="🛰" * 4000)
    with pytest.raises(ValidationError):
        learning.ProcedureProposal.model_validate(
            {"procedure": "x", "rationale": "x", "tools": ["shell"]}
        )


def test_saved_or_uncertain_proposal_never_reissues_provider_request(monkeypatch):
    calls = []
    record = cycle()

    async def request(method, path, body=None):
        calls.append((method, path, body))
        if method == "GET":
            return copy.deepcopy(record)
        if path.endswith("/claim"):
            return {"dispatch": False, "cycle": copy.deepcopy(record), "grant": {"tokens": 32768}}
        return {"retained": body}

    def no_model(*args, **kwargs):
        pytest.fail("Uncertain/saved proposal cannot invoke a model")

    monkeypatch.setattr(learning, "request", request)
    monkeypatch.setattr(learning, "OneRequest", no_model)
    result = asyncio.run(learning.learning_propose("cycle-a"))
    assert result["retained"]["status"] == "unknown"
    assert result["retained"]["usage"] is None
    record["proposal"]["result"] = {"status": "completed"}
    calls.clear()
    assert asyncio.run(learning.learning_propose("cycle-a"))["proposal"]["result"]
    assert len(calls) == 1


def test_scripted_proposal_is_retained_with_provenance_and_usage(monkeypatch):
    record = cycle()

    async def request(method, path, body=None):
        if method == "GET":
            return copy.deepcopy(record)
        if path.endswith("/claim"):
            return {"dispatch": True, "cycle": copy.deepcopy(record), "grant": {"tokens": 32768}}
        return body

    monkeypatch.setattr(learning, "request", request)
    result = asyncio.run(learning.learning_propose("cycle-a"))
    assert result["status"] == "completed"
    assert result["usage"] is not None
    assert result["trace"]["trainer"] == "authored-control"
    assert "not a learned improvement" in result["rationale"]
    assert learning.ProcedureProposal.model_validate(
        {k: result[k] for k in ("procedure", "rationale")}
    )


def test_trainer_context_is_bounded_and_excludes_trace_credentials_and_grader():
    record = cycle()
    mission = {
        "input": {"id": "a", "build": "old", "scenario": "healthy"},
        "outcome": "unresolved",
        "reason": "r" * 5000,
        "decision": None,
        "updated_at": 0,
        "tasks": [
            {
                "role": "lead",
                "focus": "overview",
                "state": "failed",
                "result": {
                    "output": "o" * 5000,
                    "error": "ValueError",
                    "trace": {"credential": "never-forward"},
                },
            }
        ],
        "grader": "never-forward",
    }
    record["source_missions"] = [dict(mission, updated_at=i) for i in range(10)]
    context = learning.trainer_context(record)
    assert len(context["failures"]) == 3
    assert context["coverage"]["total_source_missions"] == 10
    assert "never-forward" not in str(context)
    assert len(context["failures"][0]["members"][0]["output_excerpt"]) == 1200


def test_cancelled_workflow_accounts_claimed_proposal_without_redispatch(monkeypatch):
    record = cycle()
    record.update(state="cancelled", proposal={"state": "claimed", "result": None})
    calls = []

    async def request(method, path, body=None):
        calls.append((method, path, body))
        if method == "GET":
            if path == "/v6/snapshot":
                return {"enabled": True, "control": None, "cycles": [record]}
            return record
        return record if path.endswith("/reconcile-stop") else {}

    class Handle:
        async def describe(self):
            from types import SimpleNamespace

            return SimpleNamespace(status=learning.Status.CANCELED)

    class Client:
        def get_workflow_handle(self, name):
            assert name == "starbase2-learning-cycle-a"
            return Handle()

        async def start_workflow(self, *args, **kwargs):
            pytest.fail("Cancelled cycle cannot dispatch")

    monkeypatch.setattr(learning, "request", request)
    asyncio.run(learning.reconcile_learning(Client(), "test"))
    assert len(calls) == 4
    assert calls[3][1].endswith("/proposal/result")
    assert calls[3][2]["status"] == "unknown"
    assert calls[3][2]["usage"] is None


def test_procedure_validation_matches_core_utf8_bounds():
    with pytest.raises(ValidationError):
        learning.ProcedureProposal(procedure="🛰" * 3100, rationale="x")
    with pytest.raises(ValidationError):
        learning.ProcedureProposal(procedure="x", rationale="🛰" * 800)


def test_reconcile_refreshes_result_after_workflow_finishes(monkeypatch):
    record = cycle()
    record.update(state="cancelled", proposal={"state": "claimed", "result": None})
    retained = copy.deepcopy(record)
    retained["proposal"] = {"state": "completed", "result": {"status": "completed"}}
    calls = []

    async def request(method, path, body=None):
        calls.append(path)
        if path.endswith("/reconcile-stop"):
            return record
        assert method == "GET", "A saved reply must never be replaced with unknown"
        if path == "/v6/snapshot":
            return {"enabled": True, "control": None, "cycles": [record]}
        return retained

    class Handle:
        async def describe(self):
            from types import SimpleNamespace

            return SimpleNamespace(status=learning.Status.CANCELED)

    class Client:
        def get_workflow_handle(self, name):
            return Handle()

    monkeypatch.setattr(learning, "request", request)
    asyncio.run(learning.reconcile_learning(Client(), "test"))
    assert calls == [
        "/v6/snapshot",
        "/internal/v6/cycles/cycle-a/reconcile-stop",
        "/v6/cycles/cycle-a",
    ]


@pytest.mark.parametrize("enabled,generation", [(False, 0), (True, 1)])
def test_disabled_or_superseded_duty_cancels_workflow(monkeypatch, enabled, generation):
    record = cycle()
    record.update(state="evaluating", duty_generation=0)
    calls = []

    async def request(method, path, body=None):
        if method == "GET":
            return {
                "enabled": True,
                "control": {"duty": {"enabled": enabled, "generation": generation}},
                "cycles": [record],
            }
        if path.endswith("/reconcile-stop"):
            calls.append("ledger-stop")
            return record | {"state": "cancelled"}
        assert path.endswith("/tick")
        return {}

    class Handle:
        async def describe(self):
            from types import SimpleNamespace

            return SimpleNamespace(status=learning.Status.RUNNING)

        async def cancel(self):
            calls.append("cancel")

    class Client:
        def get_workflow_handle(self, name):
            return Handle()

        async def start_workflow(self, *args, **kwargs):
            pytest.fail("Disabled or superseded duty must not start workflows")

    monkeypatch.setattr(learning, "request", request)
    asyncio.run(learning.reconcile_learning(Client(), "test"))
    assert calls == ["ledger-stop", "cancel"]


def test_stopped_cycle_settles_even_without_a_workflow(monkeypatch):
    record = cycle() | {"state": "queued", "duty_generation": 0}
    calls = []

    async def request(method, path, body=None):
        calls.append(path)
        if path == "/v6/snapshot":
            return {"enabled": False, "control": None, "cycles": [record]}
        if path.endswith("/reconcile-stop"):
            record["state"] = "cancelled"
        return record

    class Handle:
        async def describe(self):
            raise learning.RPCError("No workflow", learning.RPCStatusCode.NOT_FOUND, b"")

    class Client:
        def get_workflow_handle(self, name):
            return Handle()

        async def start_workflow(self, *args, **kwargs):
            pytest.fail("Stopped cycle cannot start")

    monkeypatch.setattr(learning, "request", request)
    asyncio.run(learning.reconcile_learning(Client(), "test"))
    assert record["state"] == "cancelled"
    assert calls == [
        "/v6/snapshot",
        "/internal/v6/cycles/cycle-a/reconcile-stop",
        "/v6/cycles/cycle-a",
    ]
