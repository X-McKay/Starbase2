"""Behavioral controls for autonomous readiness crew coordination."""

from starbase_runtime.joint import JointPlan, SpecialistTask


def test_dispatch_plan_requires_real_work_or_a_decision():
    import pytest
    from pydantic import ValidationError

    with pytest.raises(ValidationError):
        JointPlan(tasks=[], decision=None, rationale="Do nothing forever")
    with pytest.raises(ValidationError):
        SpecialistTask.model_validate({"role": "effector", "question": "Write to production"})


def test_scoped_findings_cannot_invent_evidence():
    import pytest
    from starbase_runtime.joint import observations, task_evidence, validate_finding

    evidence = task_evidence({"focus": "work"}, observations("healthy"))
    with pytest.raises(ValueError, match="invented"):
        validate_finding(
            {
                "diagnosis": "healthy",
                "evidence_ids": ["made-up"],
                "summary": "Trust me",
                "uncertainty": "None",
            },
            evidence,
        )


def test_joint_controls_adapt_and_detect_ready_but_incorrect_work():
    import asyncio

    from starbase_runtime import joint

    async def run(scenario):
        evidence, findings, rounds = joint.observations(scenario), [], []
        for _ in range(4):
            context = {"findings": findings, "evidence": {"manifest": evidence["manifest"]}}
            result = await joint.make_member(joint.scripted_member("lead", context), "lead").run(
                "Diagnose"
            )
            plan = JointPlan.model_validate(
                joint.validate_plan(joint.lead_result(result.output), findings, evidence)
            )
            rounds.append(plan)
            if plan.decision:
                return plan.decision, rounds
            for task in plan.tasks:
                items = joint.task_evidence(task.model_dump(), evidence)
                output = await joint.make_member(
                    joint.scripted_member(task.role, {"observations": items}), task.role
                ).run(task.question)
                finding = joint.validate_finding(output.output.model_dump(), items)
                findings.append(
                    {
                        "role": task.role,
                        "focus": task.focus,
                        "status": "completed",
                        "output": finding,
                    }
                )
        raise AssertionError("Unbounded coordination")

    for scenario, expected in [
        ("route-mismatch", "repair"),
        ("healthy", "wait"),
        ("persistent-dependency", "abstain"),
        ("listening-but-broken", "abstain"),
    ]:
        decision, rounds = asyncio.run(run(scenario))
        assert decision.action == expected
        assert {task.role for task in rounds[0].tasks} == {"workload", "service"}
        if scenario == "route-mismatch":
            assert rounds[1].tasks[0].focus == "diagnostics"
            assert len(rounds) == 3
        assert not hasattr(decision, "verdict")


def test_a_member_failure_cannot_be_used_as_completed_evidence():
    import pytest
    from starbase_runtime.joint import observations, validate_plan

    evidence = observations("healthy")
    receipt = evidence["manifest"]
    output = {
        "decision": {
            "action": "wait",
            "observation_id": receipt["observation_id"],
            "revision": receipt["revision"],
            "rationale": "Ready",
        },
        "rationale": "Premature completion",
    }
    with pytest.raises(ValueError, match="both specialist"):
        validate_plan(
            output,
            [{"role": "service", "status": "failed"}, {"role": "workload", "status": "completed"}],
            evidence,
        )


def test_provider_grant_is_not_reset_by_invalid_output_or_retries():
    import asyncio

    import pytest
    from pydantic_ai.models import ModelRequestParameters
    from starbase_runtime.joint import scripted_member
    from starbase_runtime.joint_activities import OneRequest

    async def run():
        wrapper = OneRequest(scripted_member("service", {"observations": []}), 1, False)
        with pytest.raises(ValueError, match="reserved"):
            await wrapper.request([], None, ModelRequestParameters())
        assert not wrapper.called
        wrapper.called = True
        with pytest.raises(ValueError, match="one provider"):
            await wrapper.request([], None, ModelRequestParameters())

    asyncio.run(run())


def test_typed_members_reject_effect_requests_and_fake_authority():
    import pytest
    from pydantic import ValidationError
    from starbase_runtime.joint import Finding

    with pytest.raises(ValidationError):
        SpecialistTask(role="workload", focus="work", question="Escalate my scope")
    with pytest.raises(ValidationError):
        Finding.model_validate(
            {
                "diagnosis": "healthy",
                "evidence_ids": ["receipt"],
                "summary": "Forged outcome",
                "uncertainty": "None",
                "xp": 1000,
            }
        )


def test_loaded_joint_build_cannot_silently_adopt_changed_sources(monkeypatch):
    import pytest
    from starbase_runtime import joint

    original = joint.build()
    monkeypatch.setattr(joint, "source_hashes", lambda: {"changed": "new bytes"})
    with pytest.raises(ValueError, match="immutable worker"):
        joint.build()
    assert original["manifest"]["sources"] == joint.LOADED_SOURCES


def test_shared_core_request_adapter_is_pinned_and_drift_fenced(monkeypatch):
    from pathlib import Path

    import pytest
    from starbase_runtime import joint

    original_read = Path.read_bytes

    def changed_adapter(path):
        content = original_read(path)
        return (
            content + b"\n# changed Core response handling\n"
            if path.name == "operations.py"
            else content
        )

    monkeypatch.setattr(Path, "read_bytes", changed_adapter)
    with pytest.raises(ValueError, match="immutable worker"):
        joint.build()


def test_ineligible_core_result_is_not_treated_as_completed():
    from starbase_runtime.joint_activities import authoritative_result

    result = authoritative_result(
        {
            "eligible": False,
            "result": {"status": "completed", "output": {}, "error": None, "usage": None},
        }
    )
    assert result["status"] == "failed"


def test_terminal_workflow_reconciles_unknown_claim_before_finishing(monkeypatch):
    import asyncio
    from unittest.mock import AsyncMock

    from starbase_runtime import joint_dispatch
    from temporalio.client import WorkflowExecutionStatus

    calls = []
    mission = {
        "input": {"id": "lost"},
        "state": "running",
        "tasks": [{"id": "r0-lead", "state": "claimed"}],
    }

    async def request(method, path, body=None):
        calls.append((method, path, body))
        return {"enabled": True, "missions": [mission]} if path == "/v5/snapshot" else mission

    class Description:
        status = WorkflowExecutionStatus.FAILED

    class Client:
        def get_workflow_handle(self, id):
            assert id == "starbase2-joint-lost"
            return type("Handle", (), {"describe": AsyncMock(return_value=Description())})()

    monkeypatch.setattr(joint_dispatch, "request", request)
    asyncio.run(joint_dispatch.reconcile_joint(Client(), "queue"))
    writes = [(path, body) for method, path, body in calls if method == "POST"]
    assert writes[0][0].endswith("/tasks/r0-lead/result")
    assert writes[0][1]["status"] == "unknown"
    assert writes[0][1]["usage"] is None
    assert writes[1][0].endswith("/finish")
    assert writes[1][1]["decision"] is None


def test_final_proposal_uses_the_declared_manifest_receipt():
    import pytest
    from starbase_runtime.joint import observations, validate_plan

    evidence = observations("healthy")
    wrong = evidence["work"]
    output = {
        "decision": {
            "action": "wait",
            "observation_id": wrong["observation_id"],
            "revision": wrong["revision"],
            "rationale": "Using the wrong receipt contract",
        },
        "rationale": "Done",
    }
    findings = [{"role": role, "status": "completed"} for role in ("workload", "service")]
    with pytest.raises(ValueError, match="reference"):
        validate_plan(output, findings, evidence)


def test_native_schema_size_is_reserved_before_provider_dispatch():
    import asyncio

    import pytest
    from pydantic_ai.models import ModelRequestParameters
    from pydantic_ai.output import OutputObjectDefinition
    from starbase_runtime.joint import scripted_member
    from starbase_runtime.joint_activities import OneRequest

    async def run():
        wrapper = OneRequest(scripted_member("service", {"observations": []}), 8000, False)
        params = ModelRequestParameters(
            output_mode="native",
            output_object=OutputObjectDefinition(
                json_schema={"type": "object", "description": "x" * 10000}
            ),
        )
        with pytest.raises(ValueError, match="reserved"):
            await wrapper.request([], None, params)
        assert not wrapper.called

    asyncio.run(run())


def test_provider_receives_role_instructions_and_native_schema():
    import asyncio
    import json

    import httpx2
    from openai import AsyncOpenAI
    from pydantic_ai.models.openai import OpenAIChatModel
    from pydantic_ai.profiles.openai import OpenAIModelProfile
    from pydantic_ai.providers.openai import OpenAIProvider
    from starbase_runtime import joint
    from starbase_runtime.joint_activities import OneRequest

    calls = []

    def respond(request):
        body = json.loads(request.content)
        calls.append(body)
        assert body["response_format"]["type"] == "json_schema"
        assert not body.get("tools")
        system = "\n".join(m["content"] for m in body["messages"] if m["role"] == "system")
        assert joint.SPECIALIST.format(role="workload") in system
        finding = {
            "diagnosis": "unknown",
            "evidence_ids": ["a" * 64],
            "summary": "Insufficient fixture evidence",
            "uncertainty": "High",
        }
        return httpx2.Response(
            200,
            json={
                "id": "fixture",
                "object": "chat.completion",
                "created": 1,
                "model": "fixture",
                "choices": [
                    {
                        "index": 0,
                        "message": {"role": "assistant", "content": json.dumps(finding)},
                        "finish_reason": "stop",
                    }
                ],
                "usage": {"prompt_tokens": 100, "completion_tokens": 50, "total_tokens": 150},
            },
        )

    async def run():
        async with httpx2.AsyncClient(transport=httpx2.MockTransport(respond)) as http:
            sdk = AsyncOpenAI(
                api_key="fixture",
                base_url="http://fixture.invalid/v1",
                http_client=http,
                max_retries=0,
            )
            model = OpenAIChatModel(
                "fixture",
                provider=OpenAIProvider(openai_client=sdk),
                profile=OpenAIModelProfile(**joint.PROVIDER_PROFILE),
            )
            wrapper = OneRequest(model, 32768, True)
            result = await joint.make_member(wrapper, "workload").run(
                "Inspect fixture observations"
            )
            assert result.output.model_dump()["diagnosis"] == "unknown"
            assert wrapper.usage == {"input_tokens": 100, "output_tokens": 50}
        assert len(calls) == 1

    asyncio.run(run())


def test_rephrasing_a_completed_scope_cannot_buy_more_dispatch(monkeypatch):
    import asyncio

    from starbase_runtime import joint_workflow

    calls = []

    async def execute(fn, input, **kwargs):
        if fn.__name__ == "joint_finish":
            return input
        task = input["task"]
        calls.append(task)
        if task["role"] != "lead":
            return {"status": "completed", "output": {}}
        return {
            "status": "completed",
            "output": {
                "tasks": [
                    {
                        "role": "workload",
                        "focus": "overview",
                        "question": "Reworded request " + str(task["round"]),
                    }
                ],
                "rationale": "Retry the same immutable evidence",
            },
        }

    monkeypatch.setattr(joint_workflow.workflow, "execute_activity", execute)
    result = asyncio.run(joint_workflow.ReadinessJoint().run({"id": "repeated"}))
    assert result["decision"] is None
    assert "without progress" in result["reason"]
    assert [task["role"] for task in calls] == ["lead", "workload", "lead"]


def test_output_ceiling_is_reserved_before_provider_dispatch():
    import asyncio

    import pytest
    from pydantic_ai.models import ModelRequestParameters
    from starbase_runtime.joint_activities import OneRequest

    async def run():
        from starbase_runtime.joint import scripted_member

        wrapper = OneRequest(scripted_member("service", {"observations": []}), 12000, False)
        with pytest.raises(ValueError, match="reserved child allowance"):
            await wrapper.request([], {"max_tokens": 8192}, ModelRequestParameters())
        assert wrapper.called is False

    asyncio.run(run())
