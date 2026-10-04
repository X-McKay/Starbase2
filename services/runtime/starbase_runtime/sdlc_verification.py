"""Exact-head external verification and bounded repair of the authorized pilot PR."""

import base64
import difflib
import re
import time
from datetime import timedelta

from temporalio import activity
from temporalio.client import WorkflowExecutionStatus
from temporalio.common import WorkflowIDReusePolicy
from temporalio.exceptions import ApplicationError, WorkflowAlreadyStartedError
from temporalio.service import RPCError, RPCStatusCode

from . import sdlc_families, sdlc_regression, sdlc_sandbox, sdlc_tool_bridge
from . import sdlc_pilot as pilot
from . import sdlc_revision_publish as publisher
from .field_sources import get_json
from .operations import request
from .review import digest

TERMINAL = {"completed", "blocked", "cancelled"}
_next_poll = 0.0
PUBLIC_HARNESS = """
import os, tempfile, unittest, sys
from pathlib import Path
with tempfile.TemporaryDirectory(prefix="starbase-public-") as work:
    os.chdir(work)
    for name, contents in SOURCE_FILES.items():
        p=Path(name); p.parent.mkdir(parents=True, exist_ok=True); p.write_text(contents)
    sys.path.insert(0, work)
    suite=unittest.defaultTestLoader.discover("tests", pattern="test_persistence_history.py")
    result=unittest.TextTestRunner(verbosity=2).run(suite)
    sys.exit(not result.wasSuccessful())
"""


def capability(parent: dict) -> dict:
    return pilot.contract(parent | {"input": parent.get("input", {})})


def public_artifact(opportunity: str) -> tuple[str, str]:
    if opportunity == pilot.OPPORTUNITY:
        return sdlc_regression.PATH, sdlc_regression.SOURCE
    return sdlc_families.public_artifact(opportunity)


async def observations(name: str, files: dict, opportunity: str) -> dict:
    if opportunity == pilot.OPPORTUNITY:
        return await sdlc_sandbox.run(name, files)
    return await sdlc_families.run(name, files, opportunity)


def path(input: dict) -> str:
    return f"/internal/v7/missions/{input['mission_id']}/verifications/{input['verification_id']}"


async def records(input: dict, *, authorize: bool = True) -> tuple[dict, dict]:
    parent = await request("GET", "/v7/missions/" + input["mission_id"])
    child = next(v for v in parent.get("verifications", []) if v["id"] == input["verification_id"])
    if authorize:
        if child["input"]["build"] != pilot.run_build(parent):
            raise ApplicationError("Pinned verification build unavailable", non_retryable=True)
        child = await request("POST", path(input) + "/authorize", {})
    return parent, child


async def event(input: dict, key: str, stage: str, data: dict) -> dict:
    return await request("POST", path(input) + "/event", {"key": key, "stage": stage, "data": data})


async def public_tests(
    name: str, files: dict[str, str], opportunity: str = pilot.OPPORTUNITY
) -> dict:
    # Same validated sources, trusted test artifact, identical pinned VM boundary.
    sdlc_sandbox.program(files)
    test_path, test_source = public_artifact(opportunity)
    source = "SOURCE_FILES=" + repr(files | {test_path: test_source}) + "\n"
    harness = PUBLIC_HARNESS.replace("test_persistence_history.py", test_path.rsplit("/", 1)[-1])
    return await sdlc_sandbox._execute(name, source + harness)


async def capture(head: str, opportunity: str = pilot.OPPORTUNITY) -> dict[str, str]:
    test_path, test_source = public_artifact(opportunity)
    files = await pilot.capture(head)
    async with pilot.client() as http:
        value = await get_json(
            http,
            f"/repos/{pilot.REPOSITORY}/contents/{test_path}?ref={head}",
        )
    if (
        value.get("type") != "file"
        or value.get("encoding") != "base64"
        or value.get("size") != len(test_source.encode())
        or base64.b64decode(value.get("content", "")) != test_source.encode()
    ):
        raise ValueError("Public verification configuration changed; operator review required")
    return files


@activity.defn
async def verification_pending(input: dict) -> dict:
    parent, child = await records(input)
    return await publisher.status(parent, child, pending=True)


@activity.defn
async def verification_execute(input: dict) -> dict:
    parent, child = await records(input)
    cap = capability(parent)
    opportunity = cap["opportunity"]
    family_args = () if opportunity == pilot.OPPORTUNITY else (opportunity,)
    if "verified" in child["evidence"]:
        return child["evidence"]["verified"]
    head = child["input"]["head"]
    await event(input, "verification-started", "verifying", {"head": head})
    try:
        files = await capture(head, *family_args)
        await records(input)
        observed = await observations("sb-check-" + child["id"], files, opportunity)
        await records(input)
        public = await public_tests("sb-public-" + child["id"], files, *family_args)
        data = {
            "sources": files,
            "source_digest": digest(files),
            "observations": observed,
            "public": public,
            "head": head,
            "scope": cap["verification"]["scope"],
        }
    except ApplicationError:
        raise
    except Exception as exc:
        # Provider/VM/configuration errors are not evidence of a code defect.
        data = {"head": head, "infrastructure_error": type(exc).__name__}
    retained = await event(input, "verification-result", "verified", data)
    return retained["evidence"]["verified"]


@activity.defn
async def verification_status(input: dict) -> dict:
    parent, child = await records(input)
    return await publisher.status(parent, child, pending=False)


async def repair_member(input: dict, parent: dict, child: dict, role: str, context: dict) -> dict:
    if sdlc_tool_bridge.enabled(child.get("input", {}).get("build", {})):

        async def guard():
            await records(input)

        context = await sdlc_tool_bridge.attach(
            context,
            child["evidence"]["verified"]["sources"],
            capability(parent),
            guard,
            "sb-tools-" + child["id"],
            child["evidence"]["testing"]["candidate_files"] if role == "reviewer" else None,
        )
    return await pilot.member(role, context)


@activity.defn
async def verification_repair(input: dict) -> dict:
    parent, child = await records(input)
    cap = capability(parent)
    opportunity = cap["opportunity"]
    source_path = cap["editable_paths"][0]
    family_args = () if opportunity == pilot.OPPORTUNITY else (opportunity,)
    round_number = input["round"]
    verified = child["evidence"]["verified"]
    if verified["outcome"] != "failed":
        raise ApplicationError("Only an observed code failure permits repair", non_retryable=True)
    lead = child["evidence"].get("repairing", {}).get("lead")
    if lead is None:
        try:
            lead = await repair_member(
                input,
                parent,
                child,
                "lead",
                {
                    "source": verified["sources"][source_path],
                    "pr_feedback": child.get("feedback"),
                    "observations": {
                        key: verified["observations"].get(key) for key in ("exit_code", "cases")
                    },
                    "capability": cap,
                    "opportunity": cap["objective"],
                },
            )
        except pilot.MemberFailure as exc:
            await event(input, "lead-failed", "blocked", exc.evidence)
            return {"aborted": True}
        if lead["output"]["decision"] != "implement":
            await event(input, "lead-abstained", "blocked", lead)
            return {"aborted": True}
    await event(
        input,
        f"repair-{round_number}",
        "repairing",
        {"role": "implementer", "round": round_number, "lead": lead},
    )
    schema = re.search(
        r"CREATE TABLE IF NOT EXISTS conversation_history\s*\(.*?\);",
        verified["sources"][source_path],
        re.S,
    )
    context = {
        "edit_format": "numbered-lines",
        "lead": lead["output"],
        "source": (
            pilot.numbered_method(verified["sources"])
            if opportunity == pilot.OPPORTUNITY
            else verified["sources"][source_path]
        ),
        "database_schema": schema.group(0) if schema else "Unknown; do not invent columns",
        "task": "Repair chronological history, selecting the latest limit messages with "
        "insertion-order timestamp ties. Preserve all other behavior and tests.",
        "baseline": {key: verified["observations"].get(key) for key in ("exit_code", "cases")},
        "public_test_exit_code": verified["public"].get("exit_code"),
        "feedback": input.get("feedback"),
    }
    if opportunity != pilot.OPPORTUNITY:
        context["edit_format"] = "line-blocks"
        context.pop("database_schema")
        context["source"] = pilot.numbered_symbol(verified["sources"], cap)
        context["task"] = cap["objective"]
    context["capability"] = cap
    if opportunity != pilot.OPPORTUNITY:
        context["public_regression"] = sdlc_families.public_artifact(opportunity)[1]
    try:
        result = await repair_member(input, parent, child, "implementer", context)
    except pilot.MemberFailure as exc:
        await event(input, f"model-failed-{round_number}", "blocked", exc.evidence)
        return {"aborted": True}
    if result["output"].get("status") == "abstain":
        await event(input, f"implement-abstain-{round_number}", "blocked", result)
        return {"aborted": True}
    error = None
    try:
        files = (
            sdlc_tool_bridge.candidate_files(result, verified["sources"], cap)
            if "candidate_files" in result
            else (
                pilot.apply_lines(
                    verified["sources"], pilot.LinePatch.model_validate(result["output"])
                )
                if opportunity == pilot.OPPORTUNITY
                else pilot.apply_blocks(
                    verified["sources"], pilot.BlockPatch.model_validate(result["output"]), cap
                )
            )
        )
    except (ValueError, SyntaxError) as exc:
        files = verified["sources"]
        error = "Invalid candidate syntax" if isinstance(exc, SyntaxError) else str(exc)
    await records(input)
    candidate = {"exit_code": None, "cases": [], "not_executed": True}
    public = {"exit_code": None, "not_executed": True}
    if not error:
        candidate = await observations(
            f"sb-repair-{child['id']}-{round_number}", files, opportunity
        )
        await records(input)
        public = await public_tests(
            f"sb-repair-public-{child['id']}-{round_number}", files, *family_args
        )
    data = {
        "baseline": verified["observations"],
        "candidate": candidate,
        "public": public,
        "candidate_files": files,
        "patch": result,
        "validation_error": error,
        "artifact_digest": digest(files),
        "diff": "".join(
            difflib.unified_diff(
                verified["sources"][source_path].splitlines(True),
                files[source_path].splitlines(True),
                fromfile=source_path,
                tofile=source_path,
            )
        ),
    }
    retained = await event(input, f"testing-{round_number}", "testing", data)
    return retained["evidence"]["testing"]


@activity.defn
async def verification_review(input: dict) -> dict:
    parent, child = await records(input)
    cap = capability(parent)
    source_path = cap["editable_paths"][0]
    round_number = input["round"]
    test = child["evidence"]["testing"]
    if test.get("validation_error"):
        review = {
            "role": "patch-validator",
            "status": "revise",
            "rationale": (
                "Use original method-body line numbers and single replacement lines."
                if cap["opportunity"] == pilot.OPPORTUNITY
                else "Use unique exact search/replace edits inside the permitted function body."
            ),
            "validation_error": test["validation_error"],
            "proposed_edits": test["patch"]["output"]["edits"],
        }
    else:
        result = await repair_member(
            input,
            parent,
            child,
            "reviewer",
            {
                "capability": cap,
                "before": child["evidence"]["verified"]["sources"][source_path],
                "after": test["candidate_files"][source_path],
                "diff": test["diff"],
                "independent_verdict": test["verdict"],
                "baseline": test["baseline"],
                "candidate": test["candidate"],
                "public": test["public"],
                "implementation_rationale": test["patch"]["output"]["rationale"],
            },
        )
        review = result | result["output"]
    await event(input, f"review-{round_number}", "reviewing", review)
    accepted = review["status"] == "accept" and test["verdict"] == "improved"
    continuing = not accepted and round_number < 2 and review["status"] != "abstain"
    if accepted:
        await event(input, "ready-to-update", "ready_to_update", {})
    elif not continuing:
        await event(input, "repair-blocked", "blocked", review)
    return {
        "accepted": accepted,
        "continue": continuing,
        "feedback": review | {"verdict": test["verdict"]},
    }


@activity.defn
async def verification_update(input: dict) -> dict:
    parent, child = await records(input)
    return await publisher.update(parent, child, child["evidence"]["testing"]["candidate_files"])


@activity.defn
async def verification_finish(input: dict) -> dict:
    _, child = await records(input, authorize=False)
    if child["state"] == "completed":
        return child
    return await event(
        input,
        "completed",
        "completed",
        {
            "head": child["input"]["head"],
            "outcome": child["evidence"]["verified"]["outcome"],
            "status_receipt": input["status_receipt"],
            "update": input.get("update"),
            "verified_merge": False,
            "xp_awarded": 0,
        },
    )


@activity.defn
async def verification_abort(input: dict) -> dict:
    _, child = await records(input, authorize=False)
    if child["state"] in TERMINAL:
        return child
    return await event(
        input,
        "workflow-ended",
        "cancelled" if child.get("cancel_requested") else "blocked",
        {
            "reason": "Bounded verification activity stopped or has uncertain outcome; "
            "reconcile before retry",
            "external_effect_may_have_started": bool(child.get("effects")),
        },
    )


async def reconcile_verifications(client, queue: str) -> None:
    global _next_poll
    from .sdlc_verification_workflow import RepositoryVerification

    snapshot = await request("GET", "/internal/v7/snapshot")
    policy = snapshot["policy"]
    if (
        snapshot["enabled"]
        and snapshot.get("verification_enabled", False)
        and policy["enabled"]
        and policy["publish"]
        and policy["expires_at"] > time.time()
        and time.monotonic() >= _next_poll
    ):
        _next_poll = time.monotonic() + 30
        children = [v for m in snapshot["missions"] for v in m.get("verifications", [])]
        if not any(v["state"] not in TERMINAL for v in children):
            for parent in snapshot["missions"]:
                if (
                    parent["state"] != "awaiting_review"
                    or len(parent.get("verifications", [])) >= 16
                ):
                    continue
                observed = await publisher.observe(parent)
                if not observed["open"]:
                    continue
                build = pilot.run_build(parent)
                latest_feedback = next(
                    (
                        r
                        for r in reversed(parent.get("feedback", []))
                        if r["head"] == observed["head"]
                    ),
                    None,
                )
                feedback = (
                    latest_feedback
                    if latest_feedback
                    and latest_feedback["proposal"]["output"]["state"] == "current"
                    else None
                )
                feedback_digest = feedback["digest"] if feedback else None
                if any(
                    v["input"]["head"] == observed["head"]
                    and v["input"]["build"]["digest"] == build["digest"]
                    and v["input"].get("feedback_digest") == feedback_digest
                    for v in parent.get("verifications", [])
                ):
                    continue
                identity = (
                    "verify-"
                    + digest(
                        [parent["id"], observed["head"], build["digest"]]
                        + ([feedback_digest] if feedback_digest else [])
                    )[:24]
                )
                await request(
                    "POST",
                    f"/internal/v7/missions/{parent['id']}/verifications",
                    {
                        "id": identity,
                        "head": observed["head"],
                        "build": build,
                        **({"feedback_digest": feedback_digest} if feedback_digest else {}),
                    },
                )
                snapshot = await request("GET", "/internal/v7/snapshot")
                break
    for parent in snapshot["missions"]:
        for child in parent.get("verifications", []):
            if child["state"] in TERMINAL:
                continue
            input = {"mission_id": parent["id"], "verification_id": child["id"]}
            handle = client.get_workflow_handle("starbase2-" + child["id"])
            if child["state"] == "queued" and not child.get("cancel_requested"):
                try:
                    await client.start_workflow(
                        RepositoryVerification.run,
                        input,
                        id="starbase2-" + child["id"],
                        task_queue=queue,
                        execution_timeout=timedelta(minutes=20),
                        id_reuse_policy=WorkflowIDReusePolicy.REJECT_DUPLICATE,
                    )
                except WorkflowAlreadyStartedError:
                    pass
            try:
                status = (await handle.describe()).status
            except RPCError as exc:
                if exc.status != RPCStatusCode.NOT_FOUND:
                    raise
                if child.get("cancel_requested"):
                    await verification_abort(input)
                continue
            if child.get("cancel_requested") and status == WorkflowExecutionStatus.RUNNING:
                await handle.cancel()
            elif status is not None and status != WorkflowExecutionStatus.RUNNING:
                await verification_abort(input)
