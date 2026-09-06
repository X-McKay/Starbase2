"""Stable dispatch identities and reconciliation for v3 repair missions."""

from datetime import timedelta

from temporalio.client import Client, WorkflowExecutionStatus
from temporalio.common import WorkflowIDReusePolicy
from temporalio.exceptions import WorkflowAlreadyStartedError
from temporalio.service import RPCError, RPCStatusCode

from .operations import request
from .repair import transition
from .repair_workflow import IsolatedRepair


async def reconcile_repairs(client: Client, queue: str) -> None:
    snapshot = await request("GET", "/v3/repairs")
    for r in snapshot["repairs"]:
        if r["state"] in {"completed", "failed", "cancelled"}:
            continue
        run_id = r["input"]["id"]
        wid = "starbase2-repair-" + run_id
        handle = client.get_workflow_handle(wid)
        if r["state"] == "queued":
            try:
                await client.start_workflow(
                    IsolatedRepair.run,
                    run_id,
                    id=wid,
                    task_queue=queue,
                    execution_timeout=timedelta(minutes=10),
                    id_reuse_policy=WorkflowIDReusePolicy.REJECT_DUPLICATE,
                )
            except WorkflowAlreadyStartedError:
                pass
        try:
            status = (await handle.describe()).status
        except RPCError as error:
            if error.status == RPCStatusCode.NOT_FOUND and r["state"] == "cancel_requested":
                await transition(
                    run_id, "cancelled", "Cancelled before dispatch; no sandbox created"
                )
                continue
            raise
        if status == WorkflowExecutionStatus.RUNNING:
            if r["state"] == "cancel_requested":
                await handle.cancel()
        elif status is not None:
            latest = await request("GET", f"/v3/repairs/{run_id}")
            if latest["state"] in {"completed", "failed", "cancelled"}:
                continue
            # A lost worker can leave a VM alive for its bounded lifetime. Explicit
            # removal reconciles this before declaring the mission stopped/failed.
            import hashlib

            from .sandbox import remove

            for stage in ("baseline", "candidate"):
                await remove("sb-" + hashlib.sha256((run_id + stage).encode()).hexdigest()[:32])
            final = "cancelled" if latest["state"] == "cancel_requested" else "failed"
            await transition(
                run_id, final, f"Temporal {status.name}; sandboxes removed; no verified completion"
            )
