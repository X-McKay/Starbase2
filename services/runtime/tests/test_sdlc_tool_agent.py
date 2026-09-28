"""Model/tool integration controls; final claims cannot bypass artifact evidence."""

import asyncio
from unittest.mock import AsyncMock

from pydantic_ai.messages import ModelResponse, ToolCallPart
from pydantic_ai.models.function import FunctionModel
from starbase_runtime.agents.sdlc.factory import make_agent
from starbase_runtime.sdlc_tool_bridge import candidate_files
from starbase_runtime.sdlc_workspace import Workspace
from test_sdlc_families import contract, sources


def test_tool_agent_repairs_tests_inspects_and_submits_exact_artifact():
    async def exercise():
        cap = contract("memory-key")
        ws = Workspace(
            sources("memory-key"), cap, AsyncMock(return_value={"passed": True}), AsyncMock()
        )
        step = 0

        def model(messages, info):
            nonlocal step
            step += 1
            name, args = {
                1: (
                    "apply_patch",
                    {
                        "path": cap["editable_paths"][0],
                        "source_digest": ws.source_digest,
                        "old": "if memory_key:",
                        "new": "if memory_key is not None:",
                    },
                ),
                2: ("inspect_diff", {}),
                3: ("run_public_tests", {}),
            }.get(
                step,
                (
                    info.output_tools[0].name,
                    {
                        "status": "submit",
                        "rationale": "Public regression passed for inspected scoped repair",
                        "artifact_digest": ws.candidate_digest,
                    },
                ),
            )
            return ModelResponse(parts=[ToolCallPart(name, args)])

        result = await make_agent(FunctionModel(model), "implementer", ws).run(
            "Repair empty key lookup"
        )
        assert result.output.status == "submit"
        assert ws.finish(result.output.artifact_digest) == sources("memory-key", corrected=True)
        assert [r["tool"] for r in ws.receipts] == [
            "apply_patch",
            "inspect_diff",
            "run_public_tests",
        ]

    asyncio.run(exercise())


def test_unverified_submit_is_returned_to_agent_as_feedback():
    async def exercise():
        cap = contract("memory-key")
        ws = Workspace(sources("memory-key"), cap, AsyncMock(), AsyncMock())
        calls = 0

        def model(messages, info):
            nonlocal calls
            calls += 1
            output = (
                {
                    "status": "submit",
                    "rationale": "Unverified claim",
                    "artifact_digest": ws.candidate_digest,
                }
                if calls == 1
                else {"status": "abstain", "rationale": "No verified artifact available"}
            )
            return ModelResponse(parts=[ToolCallPart(info.output_tools[0].name, output)])

        result = await make_agent(FunctionModel(model), "implementer", ws).run("Repair")
        assert calls == 2 and result.output.status == "abstain"

    asyncio.run(exercise())


def test_readonly_roles_never_receive_mutation_tools():
    async def exercise(role):
        ws = Workspace(sources("memory-key"), contract("memory-key"), AsyncMock(), AsyncMock())

        def model(messages, info):
            assert not {"apply_patch", "replace_symbol"}.intersection(
                t.name for t in info.function_tools
            )
            output = (
                {"decision": "abstain", "rationale": "Missing evidence", "task": "Investigate"}
                if role == "lead"
                else {
                    "status": "abstain",
                    "rationale": "Missing evidence",
                    "missing_evidence": "No independent verification supplied",
                }
            )
            return ModelResponse(parts=[ToolCallPart(info.output_tools[0].name, output)])

        await make_agent(FunctionModel(model), role, ws).run("Inspect")

    for role in ("lead", "reviewer"):
        asyncio.run(exercise(role))


def test_trusted_candidate_bridge_preserves_complete_file():
    original, corrected = sources("memory-key"), sources("memory-key", corrected=True)
    assert (
        candidate_files(
            {"candidate_files": corrected, "output": {"rationale": "Scoped fix"}},
            original,
            contract("memory-key"),
        )
        == corrected
    )
