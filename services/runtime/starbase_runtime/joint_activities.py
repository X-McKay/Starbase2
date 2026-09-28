"""Trusted activities reserve/claim once; candidates only receive sanitized data."""

import asyncio
import json
import time
from contextlib import AsyncExitStack

from pydantic_ai.messages import ModelMessagesTypeAdapter
from pydantic_ai.models.wrapper import WrapperModel
from pydantic_ai.usage import UsageLimits
from temporalio import activity
from temporalio.exceptions import ApplicationError

from . import joint
from .operations import request


class OneRequest(WrapperModel):
    """Persisted root grant bounds this call, including invalid structured replies."""

    def __init__(self, model, tokens: int, inference: bool):
        super().__init__(model)
        self.tokens, self.inference = tokens, inference
        self.called = False
        self.usage: dict | None = None
        self.response: list | None = None

    async def request(self, messages, model_settings, model_request_parameters):
        if self.called:
            raise ValueError("A child grant permits one provider request")
        payload_bytes = len(ModelMessagesTypeAdapter.dump_json(messages))
        schemas = [t.parameters_json_schema for t in model_request_parameters.output_tools]
        if model_request_parameters.output_object is not None:
            schemas.append(model_request_parameters.output_object.json_schema)
        instructions = "\n".join(
            p.content for p in model_request_parameters.instruction_parts or []
        )
        output_limit = (model_settings or joint.SETTINGS).get("max_tokens", 8192)
        if not isinstance(output_limit, int) or output_limit <= 0:
            raise ValueError("Explicit bounded output ceiling required")
        reservation = (
            payload_bytes
            + len(json.dumps(schemas).encode())
            + len(instructions.encode())
            + 4096
            + output_limit
        )
        if reservation > self.tokens:
            raise ValueError("Input and output exceed reserved child allowance")
        self.called = True
        response = await self.wrapped.request(messages, model_settings, model_request_parameters)
        self.usage = {
            "input_tokens": response.usage.input_tokens,
            "output_tokens": response.usage.output_tokens,
        }
        self.response = json.loads(ModelMessagesTypeAdapter.dump_json([response]))
        if self.inference and (
            response.usage.input_tokens <= 0 or response.usage.output_tokens <= 0
        ):
            self.usage = None
            raise ValueError("Provider usage is unknown")
        if response.usage.total_tokens > self.tokens or response.finish_reason == "length":
            raise ValueError("Provider exceeded allowance or truncated output")
        return response


def retained_findings(mission: dict) -> list[dict]:
    return [
        {
            "id": task["id"],
            "role": task["role"],
            "focus": task["focus"],
            "question": task["question"],
            **{key: task["result"][key] for key in ("status", "output", "error", "usage")},
        }
        for task in mission["tasks"]
        if task["role"] != "lead" and task.get("result") is not None
    ]


def authoritative_result(task: dict) -> dict:
    result = dict(task["result"])
    if not task["eligible"] and result["status"] == "completed":
        result["status"] = "failed"
        result["error"] = "Core rejected member eligibility"
    return result


@activity.defn
async def joint_member(input: dict) -> dict:
    mission_id, task = input["id"], input["task"]
    base = f"/internal/v5/missions/{mission_id}"
    mission = await request("GET", f"/v5/missions/{mission_id}")
    inference = mission["input"]["inference"]
    procedure = mission["build"]["manifest"].get("procedure", "")
    if mission["build"] != joint.build(inference, procedure):
        raise ApplicationError("Pinned crew build unavailable", non_retryable=True)
    reserved = await request("POST", base + "/reserve", task)
    if reserved.get("result") is not None:
        return authoritative_result(reserved)
    claim = await request("POST", base + f"/tasks/{task['id']}/claim", {})
    if claim["task"].get("result") is not None:
        return authoritative_result(claim["task"])
    result = {
        "status": "unknown",
        "output": None,
        "usage": None,
        "error": "A previous dispatch has no retained response",
    }
    if not claim["dispatch"]:
        await request("POST", base + f"/tasks/{task['id']}/result", result)
        return result
    evidence = joint.observations(mission["input"]["scenario"])
    findings = retained_findings(mission)
    context: dict = {
        "lead_question": task["question"],
        "task_contract": joint.TASK_CONTRACTS[task["focus"]],
        "observations": joint.task_evidence(task, evidence),
    }
    if task["role"] == "lead":
        context = {
            "round": task["round"],
            "capabilities": {
                "workload": {key: joint.TASK_CONTRACTS[key] for key in ("overview", "diagnostics")},
                "service": {"work": joint.TASK_CONTRACTS["work"]},
            },
            "findings": findings,
            "evidence": {"manifest": evidence["manifest"]},
            "remaining_budget": mission["budget"],
        }
    wrapper = None
    started = time.monotonic()
    try:
        async with AsyncExitStack() as stack:
            model = joint.scripted_member(task["role"], context)
            if inference:
                import httpx2
                from openai import AsyncOpenAI
                from pydantic_ai.models.openai import OpenAIChatModel
                from pydantic_ai.profiles.openai import OpenAIModelProfile
                from pydantic_ai.providers.openai import OpenAIProvider

                config = joint.configuration()
                http = await stack.enter_async_context(
                    httpx2.AsyncClient(timeout=60, trust_env=False, follow_redirects=False)
                )
                sdk = AsyncOpenAI(
                    api_key="local-no-credential",
                    base_url=config["endpoint"],
                    http_client=http,
                    max_retries=0,
                )
                model = OpenAIChatModel(
                    config["model"],
                    provider=OpenAIProvider(openai_client=sdk),
                    profile=OpenAIModelProfile(**joint.PROVIDER_PROFILE),
                )
            wrapper = OneRequest(model, task["tokens"], inference)
            async with asyncio.timeout(65):
                run = await joint.make_member(wrapper, task["role"], procedure).run(
                    json.dumps(context),
                    usage_limits=UsageLimits(request_limit=1, total_tokens_limit=task["tokens"]),
                )
            output = run.output.model_dump(mode="json")
            if task["role"] == "lead":
                output = joint.validate_plan(joint.lead_result(run.output), findings, evidence)
            else:
                output = joint.validate_finding(output, context["observations"])
            result = {
                "status": "completed",
                "output": output,
                "usage": wrapper.usage,
                "error": None,
            }
    except Exception as exc:
        result = {
            "status": "failed" if wrapper is not None and wrapper.usage is not None else "unknown",
            "output": None,
            "usage": wrapper.usage if wrapper else None,
            "error": type(exc).__name__,
        }
    # Trace contains sanitized input/output, exact raw model reply and measured latency.
    # The candidate cannot select or edit the root ledger's state/usage fields.
    result["trace"] = {
        "context": context,
        "response": wrapper.response if wrapper else None,
        "elapsed_ms": round((time.monotonic() - started) * 1000),
    }
    retained = await request("POST", base + f"/tasks/{task['id']}/result", result)
    return authoritative_result(retained)


@activity.defn
async def joint_finish(input: dict) -> dict:
    return await request(
        "POST",
        f"/internal/v5/missions/{input['id']}/finish",
        {"decision": input.get("decision"), "reason": input["reason"]},
    )
