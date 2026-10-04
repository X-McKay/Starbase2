"""Trusted V7 activities and recurring admission for the single authorized SDLC pilot."""

import asyncio
import difflib
import logging
import time

from temporalio import activity
from temporalio.client import WorkflowExecutionStatus
from temporalio.common import WorkflowIDReusePolicy
from temporalio.exceptions import ApplicationError, WorkflowAlreadyStartedError
from temporalio.service import RPCError, RPCStatusCode

from . import (
    sdlc_capabilities,
    sdlc_families,
    sdlc_feedback_runtime,
    sdlc_sandbox,
    sdlc_tool_bridge,
)
from . import sdlc_pilot as pilot
from . import sdlc_publish as publisher
from . import sdlc_revision_publish as revision_publisher
from .operations import request
from .review import ROOT, digest

TERMINAL = {"awaiting_review", "failed", "blocked", "cancelled"}
_next_discovery = 0.0
_feedback_cursor = 0
_next_improvement_report = 0.0


async def mission(identity: str) -> dict:
    value = await request("GET", "/v7/missions/" + identity)
    if value["input"]["build"] != pilot.run_build(value):
        raise ApplicationError("Pinned SDLC build unavailable", non_retryable=True)
    if value["input"].get("capability_digest") and (
        value.get("capability") != pilot.contract(value)
        or value["input"]["capability_digest"] != pilot.contract(value)["digest"]
    ):
        raise ApplicationError("Pinned repository capability unavailable", non_retryable=True)
    if value["state"] in TERMINAL or value.get("cancel_requested"):
        raise ApplicationError("SDLC mission fenced", non_retryable=True)
    snapshot = await request("GET", "/v7/snapshot")
    policy = snapshot["policy"]
    if (
        not snapshot["enabled"]
        or not policy["enabled"]
        or policy["generation"] != value["policy_generation"]
        or policy["expires_at"] <= time.time()
    ):
        raise ApplicationError("SDLC policy expired or revoked", non_retryable=True)
    return value


async def event(identity: str, key: str, stage: str, data: dict) -> dict:
    return await request(
        "POST",
        f"/internal/v7/missions/{identity}/event",
        {"key": key, "stage": stage, "data": data},
    )


async def assigned_member(run: dict, role: str, context: dict) -> dict:
    cap = pilot.contract(run)
    task = sdlc_capabilities.assignment(run, role, cap)
    if task is not None:
        context = context | {"assignment": task, "objective": cap["objective"], "capability": cap}
        if cap["opportunity"] != pilot.OPPORTUNITY:
            context["public_regression"] = sdlc_families.public_artifact(cap["opportunity"])[1]
    if sdlc_tool_bridge.enabled(run["input"]["build"]):

        async def guard():
            await mission(run["id"])

        context = await sdlc_tool_bridge.attach(
            context,
            run["evidence"]["investigating"]["sources"],
            cap,
            guard,
            "sb-tools-" + run["id"],
            run["evidence"]["testing"]["candidate_files"] if role == "reviewer" else None,
        )
    try:
        result = await pilot.member(role, context)
    except pilot.MemberFailure as error:
        await event(run["id"], role + "-model-failed", "blocked", error.evidence)
        raise
    return (
        result
        if task is None
        else result
        | {
            "assignment": task,
            "capability_digest": cap["digest"],
            "build_digest": run["input"]["build"]["digest"],
        }
    )


async def sandbox_run(name: str, files: dict, run: dict) -> dict:
    opportunity = run["input"].get("opportunity", pilot.OPPORTUNITY)
    if opportunity == pilot.OPPORTUNITY:
        return await sdlc_sandbox.run(name, files)
    return await sdlc_families.run(name, files, opportunity)


@activity.defn
async def sdlc_prepare(identity: str) -> dict:
    run = await mission(identity)
    existing = run["evidence"].get("investigating")
    if existing:
        return existing
    files = await pilot.capture(run["input"]["revision"])
    if not pilot.applicable(files, pilot.contract(run)):
        raise ApplicationError("Opportunity no longer applies to pinned source", non_retryable=True)
    await mission(identity)  # Network capture may outlive a policy change or stop.
    baseline = await sandbox_run("sb-sdlc-" + identity + "-baseline", files, run)
    data = {
        "sources": files,
        "source_digest": digest(files),
        "baseline": baseline,
        "opportunity": pilot.contract(run)["objective"],
        "scope": pilot.contract(run)["verification"]["scope"],
    }
    await event(identity, "source-baseline", "investigating", data)
    return data


@activity.defn
async def sdlc_lead(identity: str) -> dict:
    run = await mission(identity)
    evidence = run["evidence"]["investigating"]
    result = await assigned_member(
        run,
        "lead",
        {
            "source": evidence["sources"][pilot.contract(run)["editable_paths"][0]],
            "observations": evidence["baseline"],
            "opportunity": evidence["opportunity"],
        },
    )
    if result["output"]["decision"] != "implement":
        await event(identity, "lead-abstain", "blocked", result)
        return {"continue": False}
    await event(identity, "lead-handoff", "implementing", result)
    return {"continue": True, "lead": result}


@activity.defn
async def sdlc_implement(input: dict) -> dict:
    identity, round_number = input["id"], input["round"]
    run = await mission(identity)
    original = run["evidence"]["investigating"]
    context = {
        "source": original["sources"][pilot.contract(run)["editable_paths"][0]],
        "lead": input["lead"],
        "feedback": input.get("feedback"),
        "baseline": original["baseline"],
    }
    cap = pilot.contract(run)
    blocks = cap["opportunity"] != pilot.OPPORTUNITY
    if blocks:
        context["edit_format"] = "line-blocks"
        context["source"] = pilot.numbered_symbol(original["sources"], cap)
    result = await assigned_member(run, "implementer", context)
    if result["output"].get("status") == "abstain":
        await event(identity, f"implement-abstain-{round_number}", "blocked", result)
        raise ApplicationError("Implementer abstained with retained evidence", non_retryable=True)
    validation_error = None
    try:
        if "candidate_files" in result:
            files = sdlc_tool_bridge.candidate_files(result, original["sources"], cap)
        else:
            files = (
                pilot.apply_blocks(
                    original["sources"], pilot.BlockPatch.model_validate(result["output"]), cap
                )
                if blocks
                else pilot.apply(
                    original["sources"], pilot.Patch.model_validate(result["output"]), cap
                )
            )
    except (ValueError, SyntaxError) as exc:
        # Keep rejected proposals and their usage; feed validation back through
        # the existing bounded review/revision loop without executing them.
        validation_error = (
            "Candidate syntax is invalid" if isinstance(exc, SyntaxError) else str(exc)
        )
        files = original["sources"]
    # Recheck authority after the model reply, before candidate execution.
    await mission(identity)
    candidate = (
        {"exit_code": None, "cases": [], "not_executed": True}
        if validation_error
        else await sandbox_run(f"sb-sdlc-{identity}-r{round_number}", files, run)
    )
    diff = "".join(
        difflib.unified_diff(
            original["sources"][pilot.contract(run)["editable_paths"][0]].splitlines(True),
            files[pilot.contract(run)["editable_paths"][0]].splitlines(True),
            fromfile=pilot.contract(run)["editable_paths"][0],
            tofile=pilot.contract(run)["editable_paths"][0],
        )
    )
    data = {
        "baseline": original["baseline"],
        "candidate": candidate,
        "candidate_files": files,
        "patch": result,
        "diff": diff,
        "artifact_digest": digest(publisher.artifacts(files, pilot.contract(run))),
        "validation_error": validation_error,
    }
    retained = await event(identity, f"testing-{round_number}", "testing", data)
    return retained["evidence"]["testing"]


@activity.defn
async def sdlc_review(input: dict) -> dict:
    identity, round_number = input["id"], input["round"]
    run = await mission(identity)
    test = run["evidence"]["testing"]
    if test.get("validation_error"):
        feedback = {
            "role": "patch-validator",
            "status": "revise",
            "validation_error": test["validation_error"],
            "proposed_edits": test["patch"]["output"].get("edits", []),
            "verdict": test["verdict"],
            "rationale": (
                "No candidate was executed. Use an exact unique substring from the original "
                "source. Prefer a short single-line span; do not collapse newlines or spaces. "
                "Preserve the capability objective and unrelated behavior."
                if pilot.contract(run)["opportunity"] == pilot.OPPORTUNITY
                else "No candidate was executed. Replace an original numbered body line with "
                "a valid block; each list item is one line. Preserve relative indentation "
                "within the block. Preserve the capability objective and unrelated behavior."
            ),
        }
        await event(identity, f"review-{round_number}", "reviewing", feedback)
        continuing = round_number < 2
        await event(
            identity,
            f"validation-revise-{round_number}" if continuing else "validation-blocked",
            "implementing" if continuing else "blocked",
            feedback,
        )
        return {"accepted": False, "continue": continuing, "feedback": feedback}
    result = await assigned_member(
        run,
        "reviewer",
        {
            "before": run["evidence"]["investigating"]["sources"][
                pilot.contract(run)["editable_paths"][0]
            ],
            "after": test["candidate_files"][pilot.contract(run)["editable_paths"][0]],
            "diff": test["diff"],
            "independent_verdict": test["verdict"],
            "baseline": test["baseline"],
            "candidate": test["candidate"],
            "implementation_rationale": test["patch"]["output"]["rationale"],
            "validation_error": test.get("validation_error"),
            "proposed_edits": test["patch"]["output"].get("edits", []),
        },
    )
    data = result | result["output"]
    await event(identity, f"review-{round_number}", "reviewing", data)
    accepted = data["status"] == "accept" and test["verdict"] == "improved"
    if accepted:
        await event(identity, "ready", "ready_to_publish", {})
    elif round_number < 2 and data["status"] != "abstain":
        # Return actual evidence to the implementer; every revision restarts at the base.
        await event(
            identity,
            f"revise-{round_number}",
            "implementing",
            {"role": "reviewer", "feedback": data, "verdict": test["verdict"]},
        )
    else:
        await event(identity, "review-blocked", "blocked", data)
    return {
        "accepted": accepted,
        "feedback": data
        | {
            "verdict": test["verdict"],
            "validation_error": test.get("validation_error"),
            "proposed_edits": test["patch"]["output"].get("edits", []),
        },
        "continue": accepted or (round_number < 2 and data["status"] != "abstain"),
    }


@activity.defn
async def sdlc_publish(identity: str) -> dict:
    run = await request("GET", "/v7/missions/" + identity)
    if run["state"] in {"submitted", "awaiting_review"}:
        return run["evidence"]["submitted"]
    run = await mission(identity)
    receipt = await publisher.publish(run, run["evidence"]["testing"]["candidate_files"])
    await event(identity, "submitted", "submitted", receipt)
    return receipt


@activity.defn
async def sdlc_follow(input: dict) -> dict:
    await mission(input["id"])
    return await publisher.followup(input["receipt"])


@activity.defn
async def sdlc_finish(input: dict) -> dict:
    return await event(
        input["id"],
        "awaiting-review",
        "awaiting_review",
        {
            "ci": input["ci"],
            "status": "PR submitted; human merge decision remains",
            "verified_merge": False,
            "xp_awarded": 0,
        },
    )


@activity.defn
async def sdlc_abort(identity: str) -> dict:
    run = await request("GET", "/v7/missions/" + identity)
    if run["state"] in TERMINAL:
        return run
    stage = "cancelled" if run.get("cancel_requested") else "blocked"
    return await event(
        identity,
        "workflow-ended",
        stage,
        {
            "reason": (
                "A bounded activity failed, was interrupted, or has unknown outcome; "
                "inspect retained evidence before retry"
            ),
            "external_effect_may_have_started": run.get("publication") is not None,
        },
    )


async def discover_catalog(snapshot: dict) -> dict:
    """Capture one exact revision once; retain every installed family's decision."""
    sha = None
    files = None
    error = None
    try:
        _, sha = await pilot.revision()
        files = await pilot.capture(sha)
    except Exception as exc:
        error = type(exc).__name__
    for cap in sdlc_capabilities.catalog()["capabilities"]:
        if not sdlc_capabilities.compatible_contract(snapshot, cap):
            continue
        outcome, reason = "unavailable", error or "No captured source"
        if files is not None:
            try:
                applies = pilot.applicable(files, cap)
                outcome = "candidate" if applies else "no_change"
                reason = (
                    "Installed source rule matched"
                    if applies
                    else "Installed source rule did not match; not a health certification"
                )
            except (ValueError, SyntaxError, KeyError) as exc:
                reason = type(exc).__name__
        build = (
            pilot.build()
            if cap["opportunity"] == pilot.OPPORTUNITY
            else pilot.build(cap["opportunity"])
        )
        await request(
            "POST",
            "/internal/v7/discoveries",
            {
                "repository": cap["repository"],
                "revision": sha,
                "opportunity": cap["opportunity"],
                "build": build,
                "capability_digest": cap["digest"],
                "source_digest": digest(files) if files is not None else None,
                "outcome": outcome,
                "reason": reason,
                "observed_at": time.time(),
            },
        )
    snapshot = await request("GET", "/internal/v7/snapshot")
    if any(
        m["state"] not in TERMINAL
        or any(
            v["state"] not in {"completed", "blocked", "cancelled"}
            for v in m.get("verifications", [])
        )
        for m in snapshot["missions"]
    ):
        return snapshot
    from .sdlc_readiness import assess

    if assess(snapshot, now=time.time())["circuit_open"]:
        return snapshot
    candidates = sorted(
        snapshot["discoveries"], key=lambda d: (-d["priority"], d["created_at"], d["id"])
    )
    for finding in candidates:
        if finding["outcome"] != "candidate" or finding.get("status") == "admitted":
            continue
        family = finding["opportunity"]
        same_family = [m for m in snapshot["missions"] if m["input"]["opportunity"] == family]
        if any(m["input"]["revision"] == finding["revision"] for m in same_family):
            continue  # Existing failures are evidence, not invitations to replay.
        if any(
            m.get("publication")
            and (
                m.get("pr_observation", {}).get("state") not in {"closed", "merged"}
                or time.time() - m.get("pr_observation", {}).get("observed_at", 0) > 60
            )
            for m in same_family
        ):
            continue
        await request("POST", f"/internal/v7/discoveries/{finding['id']}/admit", {})
        return await request("GET", "/internal/v7/snapshot")
    return snapshot


async def discover_sdlc(snapshot: dict) -> dict:
    global _next_discovery, _feedback_cursor

    if (
        snapshot["enabled"]
        and snapshot["policy"]["enabled"]
        and snapshot["policy"]["expires_at"] > time.time()
        and time.monotonic() >= _next_discovery
    ):
        _next_discovery = time.monotonic() + 60
        # Reconcile retained PR lifecycle before releasing reservations. Failed
        # provider reads propagate without admitting new work or inventing closure.
        feedback_parents = [
            m
            for m in snapshot["missions"]
            if m["state"] == "awaiting_review" and m.get("publication")
        ]
        feedback_target = (
            feedback_parents[_feedback_cursor % len(feedback_parents)]["id"]
            if feedback_parents
            else None
        )
        _feedback_cursor += 1
        for retained in snapshot["missions"]:
            if retained["state"] == "awaiting_review" and retained.get("publication"):
                observed = await revision_publisher.observe(retained)
                await request(
                    "POST",
                    f"/internal/v7/missions/{retained['id']}/pr-observation",
                    {
                        "number": retained["evidence"]["submitted"]["number"],
                        "head": observed["head"],
                        "state": observed["state"],
                        "observed_at": time.time(),
                    },
                )
                if retained["id"] == feedback_target and observed["state"] == "open":
                    try:
                        await sdlc_feedback_runtime.poll_feedback(retained)
                    except Exception as exc:
                        logging.getLogger(__name__).warning(
                            "PR feedback unavailable (%s)", type(exc).__name__
                        )
                snapshot = await request("GET", "/internal/v7/snapshot")
        if "discoveries" in snapshot:
            return await discover_catalog(snapshot)
        # Legacy Core controls retain their original single-family admission path.
        # A frozen candidate opportunity is discovered once per exact source revision.
        if snapshot.get("coordination", {}).get("can_discover", True) and not any(
            m["state"] not in TERMINAL for m in snapshot["missions"]
        ):
            policy = snapshot["policy"]
            admitted = sum(
                m["policy_generation"] == policy["generation"] for m in snapshot["missions"]
            )
            if admitted < policy["max_missions"] and policy["expires_at"] > time.time():
                _, sha = await pilot.revision()
                exists = any(
                    m["input"]["revision"] == sha and m["input"]["opportunity"] == pilot.OPPORTUNITY
                    for m in snapshot["missions"]
                )
                if not exists:
                    files = await pilot.capture(sha)
                    if pilot.applicable(files) and sdlc_capabilities.compatible_contract(
                        snapshot, pilot.CAPABILITY
                    ):
                        identity = (
                            "sdlc-"
                            + digest(
                                {
                                    "repository": pilot.REPOSITORY,
                                    "revision": sha,
                                    "opportunity": pilot.OPPORTUNITY,
                                }
                            )[:24]
                        )
                        await request(
                            "POST",
                            "/internal/v7/missions",
                            {
                                "id": identity,
                                "repository": pilot.REPOSITORY,
                                "revision": sha,
                                "opportunity": pilot.OPPORTUNITY,
                                "build": pilot.build(),
                                "capability_digest": pilot.CAPABILITY["digest"],
                            },
                        )
                        snapshot = await request("GET", "/internal/v7/snapshot")
    return snapshot


async def record_improvement(snapshot: dict) -> None:
    """Derive local advisory experiments periodically; never changes Core authority."""
    global _next_improvement_report
    if not snapshot.get("enabled") or time.monotonic() < _next_improvement_report:
        return
    _next_improvement_report = time.monotonic() + 60
    from .sdlc_improvement import derive_report, write_report

    directory = ROOT / ".local" / "sdlc-improvement"
    try:
        if directory.exists() and len(list(directory.glob("trainer-*.json"))) >= 256:
            logging.getLogger(__name__).warning("Trainer report retention full; reports preserved")
            return
        await asyncio.to_thread(write_report, directory, derive_report(snapshot))
    except (ValueError, OSError, TypeError) as error:
        logging.getLogger(__name__).warning("Trainer report unavailable (%s)", type(error).__name__)


async def reconcile_sdlc(client, queue: str) -> None:
    from datetime import timedelta

    from .sdlc_workflow import RepositorySdlc

    snapshot = await request("GET", "/internal/v7/snapshot")
    await record_improvement(snapshot)
    try:
        async with asyncio.timeout(30):
            snapshot = await discover_sdlc(snapshot)
    except Exception as exc:
        logging.getLogger(__name__).warning(
            "SDLC discovery unavailable (%s); existing work still reconciles", type(exc).__name__
        )
    for run in snapshot["missions"]:
        if run["state"] in TERMINAL:
            continue
        identity = run["id"]
        workflow_id = "starbase2-sdlc-" + identity
        handle = client.get_workflow_handle(workflow_id)
        if run["state"] == "queued" and snapshot["enabled"] and not run.get("cancel_requested"):
            try:
                await client.start_workflow(
                    RepositorySdlc.run,
                    identity,
                    id=workflow_id,
                    task_queue=queue,
                    execution_timeout=timedelta(minutes=25),
                    id_reuse_policy=WorkflowIDReusePolicy.REJECT_DUPLICATE,
                )
            except WorkflowAlreadyStartedError:
                pass
        try:
            status = (await handle.describe()).status
        except RPCError as exc:
            if exc.status != RPCStatusCode.NOT_FOUND:
                raise
            if run.get("cancel_requested"):
                await sdlc_abort(identity)
            continue
        if run.get("cancel_requested") and status == WorkflowExecutionStatus.RUNNING:
            await handle.cancel()
        elif status is not None and status != WorkflowExecutionStatus.RUNNING:
            await sdlc_abort(identity)
