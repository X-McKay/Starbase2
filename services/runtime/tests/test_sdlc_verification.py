"""Verification orchestration controls; candidate execution and providers are mocked."""

import asyncio
import copy
from unittest.mock import AsyncMock

import pytest
from starbase_runtime import sdlc_pilot as p
from starbase_runtime import sdlc_verification as v

INPUT = {"mission_id": "pilot", "verification_id": "verify-test"}
SOURCE = (
    "class Store:\n    def get_conversation_history(self):\n"
    '        return "ORDER BY timestamp DESC"\n'
)
FILES = dict.fromkeys(p.FILES, "") | {p.SOURCE: SOURCE}


@pytest.fixture
def control(monkeypatch):
    child: dict = {
        "id": "verify-test",
        "input": {"head": "a" * 40},
        "state": "queued",
        "evidence": {},
        "effects": [],
    }
    parent = {"id": "pilot"}
    events = []

    async def records(_input, authorize=True):
        return parent, copy.deepcopy(child)

    async def event(_input, key, stage, data):
        events.append((key, stage, copy.deepcopy(data)))
        child["state"] = stage
        retained = copy.deepcopy(data)
        # Explicitly synthetic Core response; true grading is tested in Rust/HTTP.
        if stage == "verified":
            retained["outcome"] = (
                "infrastructure_blocked" if "infrastructure_error" in data else "passed"
            )
        if stage == "testing":
            retained["verdict"] = "ineligible" if data.get("validation_error") else "improved"
        child["evidence"][stage] = retained
        return copy.deepcopy(child)

    monkeypatch.setattr(v, "records", records)
    monkeypatch.setattr(v, "event", event)
    return child, events


def test_public_suite_uses_only_validated_sources_and_trusted_test(monkeypatch):
    execute = AsyncMock(return_value={"exit_code": 0})
    monkeypatch.setattr(v.sdlc_sandbox, "_execute", execute)
    asyncio.run(v.public_tests("control", FILES))
    assert execute.await_args is not None
    source = execute.await_args.args[1]
    assert v.sdlc_regression.PATH in source
    assert "unittest.defaultTestLoader.discover" in source
    with pytest.raises(ValueError):
        asyncio.run(v.public_tests("control", FILES | {"escape": "bad"}))
    assert execute.await_count == 1


def test_verified_result_is_reused_without_second_vm(control, monkeypatch):
    child, _ = control
    capture = AsyncMock(return_value=FILES)
    vm = AsyncMock(return_value={"exit_code": 0, "cases": []})
    public = AsyncMock(return_value={"exit_code": 0})
    monkeypatch.setattr(v, "capture", capture)
    monkeypatch.setattr(v.sdlc_sandbox, "run", vm)
    monkeypatch.setattr(v, "public_tests", public)
    first = asyncio.run(v.verification_execute(INPUT))
    second = asyncio.run(v.verification_execute(INPUT))
    assert first == second and first["sources"] == FILES
    capture.assert_awaited_once_with("a" * 40)
    vm.assert_awaited_once()
    public.assert_awaited_once()
    assert child["state"] == "verified"


def test_vm_infrastructure_error_cannot_trigger_code_repair(control, monkeypatch):
    child, _ = control
    monkeypatch.setattr(v, "capture", AsyncMock(return_value=FILES))
    monkeypatch.setattr(
        v.sdlc_sandbox, "run", AsyncMock(side_effect=RuntimeError("private provider text"))
    )
    model = AsyncMock()
    monkeypatch.setattr(p, "member", model)
    result = asyncio.run(v.verification_execute(INPUT))
    assert result["outcome"] == "infrastructure_blocked"
    assert result["infrastructure_error"] == "RuntimeError"
    assert "private provider text" not in str(result)
    with pytest.raises(Exception, match="observed code failure"):
        asyncio.run(v.verification_repair(INPUT | {"round": 0}))
    model.assert_not_awaited()
    assert child["state"] == "verified"


@pytest.mark.parametrize("round_number", [0, 2])
def test_invalid_patch_retained_and_bounded_without_vm_or_model_review(
    control, monkeypatch, round_number
):
    child, events = control
    child["state"] = "verified"
    child["evidence"]["repairing"] = {
        "lead": {"output": {"decision": "implement", "task": "control"}}
    }
    child["evidence"]["verified"] = {
        "outcome": "failed",
        "sources": FILES,
        "observations": {"exit_code": 0},
        "public": {"exit_code": 1},
    }
    proposal = {
        "role": "implementer",
        "output": {
            "rationale": "control",
            "edits": [{"line": 999, "new": "replacement"}],
        },
        "usage": {"input_tokens": 3},
    }
    model = AsyncMock(return_value=proposal)
    vm = AsyncMock()
    monkeypatch.setattr(p, "member", model)
    monkeypatch.setattr(v.sdlc_sandbox, "run", vm)
    tested = asyncio.run(v.verification_repair(INPUT | {"round": round_number}))
    assert tested["patch"] == proposal and tested["candidate"]["not_executed"]
    review = asyncio.run(v.verification_review(INPUT | {"round": round_number}))
    assert not review["accepted"] and review["continue"] == (round_number < 2)
    assert review["feedback"]["proposed_edits"] == proposal["output"]["edits"]
    assert model.await_count == 1
    vm.assert_not_awaited()
    assert events[-1][1] == ("reviewing" if round_number < 2 else "blocked")


def test_actual_candidate_review_uses_verification_and_public_evidence(control, monkeypatch):
    child, _ = control
    child["evidence"]["repairing"] = {
        "lead": {"output": {"decision": "implement", "task": "control"}}
    }
    child["evidence"]["verified"] = {
        "outcome": "failed",
        "sources": FILES,
        "observations": {"exit_code": 0},
        "public": {"exit_code": 1},
    }
    model = AsyncMock(
        side_effect=[
            {
                "role": "implementer",
                "output": {
                    "rationale": "fix tie",
                    "edits": [
                        {
                            "line": 3,
                            "new": 'return "ORDER BY timestamp DESC, id DESC"',
                        }
                    ],
                },
            },
            {
                "role": "reviewer",
                "output": {"status": "accept", "rationale": "independently reviewed"},
            },
        ]
    )
    monkeypatch.setattr(p, "member", model)
    monkeypatch.setattr(
        v.sdlc_sandbox, "run", AsyncMock(return_value={"exit_code": 0, "cases": []})
    )
    monkeypatch.setattr(v, "public_tests", AsyncMock(return_value={"exit_code": 0}))
    asyncio.run(v.verification_repair(INPUT | {"round": 0}))
    reviewed = asyncio.run(v.verification_review(INPUT | {"round": 0}))
    assert reviewed["accepted"] and child["state"] == "ready_to_update"
    assert model.await_args is not None
    context = model.await_args.args[1]
    assert context["public"]["exit_code"] == 0 and context["independent_verdict"] == "improved"
    assert ", id DESC" in context["after"]


def test_numbered_edits_are_frozen_scoped_and_single_line():
    from pydantic import ValidationError

    assert p.numbered_method(FILES)[-1]["line"] == 3
    edit = p.LinePatch(
        rationale="control",
        edits=[p.LineEdit(line=3, new='return "ORDER BY timestamp DESC, id DESC"')],
    )
    changed = p.apply_lines(FILES, edit)
    assert changed[p.SOURCE].startswith(
        "class Store:\n    def get_conversation_history(self):\n        return"
    )
    for line in [1, 2, 4]:
        with pytest.raises(ValueError, match="outside"):
            p.apply_lines(
                FILES, p.LinePatch(rationale="control", edits=[p.LineEdit(line=line, new="pass")])
            )
    with pytest.raises(ValueError, match="duplicated"):
        p.apply_lines(FILES, p.LinePatch(rationale="control", edits=[edit.edits[0], edit.edits[0]]))
    with pytest.raises(ValidationError):
        p.LineEdit(line=3, new="one\ntwo")
    with pytest.raises(SyntaxError):
        p.apply_lines(
            FILES, p.LinePatch(rationale="control", edits=[p.LineEdit(line=3, new="return (")])
        )


def test_loaded_build_is_stable_and_caller_cannot_mutate_it(monkeypatch):
    original = p.build()
    caller = p.build()
    caller["manifest"]["caller_poison"] = True

    def changed_checkout():
        raise AssertionError("A running worker must not relabel loaded code from changed files")

    monkeypatch.setattr(p, "_build_manifest", changed_checkout)
    assert p.build() == original and "caller_poison" not in p.build()["manifest"]


def test_model_failure_retains_usage_and_never_executes_candidate(control, monkeypatch):
    child, _ = control
    child["evidence"]["repairing"] = {
        "lead": {"output": {"decision": "implement", "task": "control"}}
    }
    child["evidence"]["verified"] = {
        "outcome": "failed",
        "sources": FILES,
        "observations": {"exit_code": 0, "cases": []},
        "public": {"exit_code": 1},
    }
    failure = {
        "role": "implementer",
        "error_type": "ValueError",
        "usage": {"input_tokens": 5, "output_tokens": 12},
        "response_excerpt": "truncated control",
    }
    monkeypatch.setattr(p, "member", AsyncMock(side_effect=p.MemberFailure(failure)))
    vm = AsyncMock()
    monkeypatch.setattr(v.sdlc_sandbox, "run", vm)
    result = asyncio.run(v.verification_repair(INPUT | {"round": 0}))
    assert result["aborted"] and child["state"] == "blocked"
    assert child["evidence"]["blocked"] == failure
    vm.assert_not_awaited()


def test_diagnostic_lead_handoff_is_retained_and_guides_numbered_implementation(
    control, monkeypatch
):
    child, _ = control
    child["evidence"]["verified"] = {
        "outcome": "failed",
        "sources": FILES,
        "observations": {"exit_code": 0, "cases": []},
        "public": {"exit_code": 1},
    }
    lead = {
        "role": "lead",
        "output": {
            "decision": "implement",
            "rationale": "control diagnosis",
            "task": "bounded control repair",
        },
    }
    patch = {
        "role": "implementer",
        "output": {
            "rationale": "control patch",
            "edits": [{"line": 3, "new": 'return "ORDER BY timestamp DESC, id DESC"'}],
        },
    }
    model = AsyncMock(side_effect=[lead, patch])
    monkeypatch.setattr(p, "member", model)
    monkeypatch.setattr(
        v.sdlc_sandbox, "run", AsyncMock(return_value={"exit_code": 0, "cases": []})
    )
    monkeypatch.setattr(v, "public_tests", AsyncMock(return_value={"exit_code": 0}))
    asyncio.run(v.verification_repair(INPUT | {"round": 0}))
    assert [c.args[0] for c in model.await_args_list] == ["lead", "implementer"]
    assert child["evidence"]["repairing"]["lead"] == lead
    assert model.await_args_list[1].args[1]["lead"] == lead["output"]
