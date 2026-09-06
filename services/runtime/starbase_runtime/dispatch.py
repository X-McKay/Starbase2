"""Idempotent dispatch and cancellation reconciliation for local operations."""

from datetime import timedelta

from temporalio.client import Client, WorkflowExecutionStatus
from temporalio.common import WorkflowIDReusePolicy
from temporalio.exceptions import WorkflowAlreadyStartedError
from temporalio.service import RPCError, RPCStatusCode

from .operations import BUILDS, request
from .operations_contract import OperationsSnapshot
from .operations_workflows import RecurringReview, RepositoryReview


async def reconcile_operations(client: Client, queue: str) -> None:
    snapshot = await request("GET", "/v2/snapshot")
    if snapshot.get("schema_version") != 2:
        raise ValueError("Unsupported operations contract")
    OperationsSnapshot.model_validate(snapshot)
    for run in snapshot["active"]:
        run_id = run["input"]["request"]["id"]
        workflow_id = "starbase2-review-" + run_id
        if run["state"] == "queued":
            try:
                await client.start_workflow(
                    RepositoryReview.run,
                    run_id,
                    id=workflow_id,
                    task_queue=queue,
                    execution_timeout=timedelta(minutes=8),
                    id_reuse_policy=WorkflowIDReusePolicy.REJECT_DUPLICATE,
                )
            except WorkflowAlreadyStartedError:
                pass
        handle = client.get_workflow_handle(workflow_id)
        try:
            description = await handle.describe()
        except RPCError as error:
            if error.status == RPCStatusCode.NOT_FOUND and run["state"] == "cancel_requested":
                await request(
                    "POST",
                    f"/internal/v2/runs/{run_id}/transition",
                    {"state": "cancelled", "detail": "Cancelled before dispatch"},
                )
                continue
            raise
        status = description.status
        if status is None:
            continue
        if run["state"] == "cancel_requested" and status == WorkflowExecutionStatus.RUNNING:
            await handle.cancel()
        elif status != WorkflowExecutionStatus.RUNNING:
            latest = await request("GET", f"/v2/runs/{run_id}")
            if latest["state"] in {"completed", "failed", "cancelled"}:
                continue
            state = (
                "cancelled"
                if status == WorkflowExecutionStatus.CANCELED
                and latest["state"] == "cancel_requested"
                else "failed"
            )
            await request(
                "POST",
                f"/internal/v2/runs/{run_id}/transition",
                {"state": state, "detail": f"Temporal {status.name}; retained completion absent"},
            )
    for duty in snapshot["duties"]:
        workflow_id = f"starbase2-duty-{duty['id']}"
        handle = client.get_workflow_handle(workflow_id)
        try:
            description = await handle.describe()
        except RPCError as error:
            if error.status != RPCStatusCode.NOT_FOUND:
                raise
            description = None
        if description is not None and description.status == WorkflowExecutionStatus.RUNNING:
            # Configuration change cancels the old durable timer; next reconciliation
            # creates the new generation. Tick dispatch still checks current policy.
            memo = await description.memo()
            if not duty["enabled"] or memo.get("generation") != duty["generation"]:
                await handle.cancel()
            continue
        if duty["enabled"]:
            try:
                await client.start_workflow(
                    RecurringReview.run,
                    duty,
                    id=workflow_id,
                    task_queue=queue,
                    memo={"generation": duty["generation"]},
                    id_reuse_policy=WorkflowIDReusePolicy.ALLOW_DUPLICATE,
                )
            except WorkflowAlreadyStartedError:
                pass
    await request("POST", "/internal/v2/heartbeat", {})


async def register() -> None:
    for build in BUILDS.values():
        await request("POST", "/internal/v2/builds", build)
