"""Trusted assembly of mission-specific tool sessions. No new provider effects."""

import ast

from . import sdlc_pilot as pilot
from .agents.sdlc import definition
from .sdlc_workspace import Limits, Workspace


def enabled(build: dict) -> bool:
    return build.get("manifest", {}).get("agent", {}).get("profile") in {"tools", "tools-thinking"}


async def attach(
    context: dict, files: dict, capability: dict, guard, name: str, candidate: dict | None = None
) -> dict:
    from .sdlc_verification import public_tests

    async def tester(current):
        family = capability["opportunity"]
        args = () if family == pilot.OPPORTUNITY else (family,)
        result = await public_tests(name, current, *args)
        return {
            "passed": result.get("exit_code") == 0,
            "scope": "trusted public regression only; independent Core grading is separate",
            **result,
        }

    workspace = Workspace(
        files,
        capability,
        tester,
        guard,
        limits=Limits(calls=definition.LIMITS["tool_calls"], seconds=definition.LIMITS["seconds"]),
    )
    if candidate is not None and candidate != files:
        path = capability["editable_paths"][0]
        result = await workspace.apply_patch(
            path, workspace.source_digest, files[path], candidate[path]
        )
        if not result["ok"]:
            raise ValueError("Retained review candidate violates workspace scope")
    return {key: value for key, value in context.items() if key != "edit_format"} | {
        "_workspace": workspace,
        "_guard": guard,
    }


def candidate_files(result: dict, original: dict, capability: dict) -> dict:
    proposed = result["candidate_files"]
    path = capability["editable_paths"][0]
    if set(proposed) != set(original) or any(
        proposed[p] != original[p] for p in original if p != path
    ):
        raise ValueError("Workspace candidate changed unrelated files")

    def symbol(source):
        nodes = [
            n
            for n in ast.walk(ast.parse(source))
            if isinstance(n, ast.FunctionDef) and n.name == capability["editable_symbol"]
        ]
        if len(nodes) != 1:
            raise ValueError("Candidate symbol is absent or ambiguous")
        return ast.get_source_segment(source, nodes[0])

    value = pilot.apply(
        original,
        pilot.Patch(
            rationale=result["output"]["rationale"],
            edits=[pilot.Edit(path=path, old=symbol(original[path]), new=symbol(proposed[path]))],
        ),
        capability,
    )
    if value != proposed:
        raise ValueError("Workspace candidate changed text outside the installed symbol")
    return value
