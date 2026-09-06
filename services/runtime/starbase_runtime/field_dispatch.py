"""Reconcile field runs by stable workflow identity; no duplicate dispatch."""

from datetime import timedelta

from temporalio.client import WorkflowExecutionStatus as Status
from temporalio.common import WorkflowIDReusePolicy
from temporalio.exceptions import WorkflowAlreadyStartedError
from temporalio.service import RPCError, RPCStatusCode

from .field import builds
from .field_workflow import FieldDuty, FieldObservation
from .operations import request


async def register_field() -> None:
    watches = (await request("GET", "/v4/repositories"))["repositories"]
    for build in builds([w for w in watches if not w["config"]["removed"]]).values():
        await request("POST", "/internal/v4/builds", build)


async def reconcile_field(client, queue: str) -> None:
    await register_field()
    snapshot = await request("GET", "/v4/snapshot")
    for run in snapshot["runs"]:
        state, input = run["state"], run["input"]
        if state in {"completed", "failed", "cancelled"}:
            continue
        if state == "queued" and not snapshot["enabled"]:
            continue
        workflow_id = "starbase2-field-" + input["id"]
        if state == "queued" and snapshot["enabled"]:
            try:
                await client.start_workflow(
                    FieldObservation.run,
                    input,
                    id=workflow_id,
                    task_queue=queue,
                    execution_timeout=timedelta(minutes=8),
                    id_reuse_policy=WorkflowIDReusePolicy.REJECT_DUPLICATE,
                )
            except WorkflowAlreadyStartedError:
                pass
        handle = client.get_workflow_handle(workflow_id)
        try:
            status = (await handle.describe()).status
        except RPCError as exc:
            if exc.status == RPCStatusCode.NOT_FOUND and state == "cancel_requested":
                await request("POST", f"/internal/v4/runs/{input['id']}/cancelled", {})
                continue
            raise
        if state == "cancel_requested" and status == Status.RUNNING:
            await handle.cancel()
        elif status is not None and status != Status.RUNNING:
            latest = await request("GET", "/v4/runs/" + input["id"])
            if latest["state"] in {"completed", "failed", "cancelled"}:
                continue
            result = (
                "cancelled"
                if status == Status.CANCELED and state == "cancel_requested"
                else "failed"
            )
            await request("POST", f"/internal/v4/runs/{input['id']}/{result}", {})

    for duty in snapshot["duties"]:
        handle = client.get_workflow_handle("starbase2-field-duty-" + duty["id"])
        try:
            info = await handle.describe()
        except RPCError as exc:
            if exc.status != RPCStatusCode.NOT_FOUND:
                raise
            info = None
        if info is not None and info.status == Status.RUNNING:
            if (
                not snapshot["enabled"]
                or not duty["enabled"]
                or (await info.memo()).get("generation") != duty["generation"]
            ):
                await handle.cancel()
        elif duty["enabled"] and snapshot["enabled"]:
            try:
                await client.start_workflow(
                    FieldDuty.run,
                    duty,
                    id="starbase2-field-duty-" + duty["id"],
                    task_queue=queue,
                    memo={"generation": duty["generation"]},
                    id_reuse_policy=WorkflowIDReusePolicy.ALLOW_DUPLICATE,
                )
            except WorkflowAlreadyStartedError:
                pass
