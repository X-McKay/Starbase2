"""Reconcile Core intent with stable V5 workflow identity; no implicit activation."""

from datetime import timedelta

from temporalio.client import WorkflowExecutionStatus as Status
from temporalio.common import WorkflowIDReusePolicy
from temporalio.exceptions import WorkflowAlreadyStartedError
from temporalio.service import RPCError, RPCStatusCode

from .joint import build
from .joint_workflow import ReadinessJoint
from .operations import request


async def register_joint():
    for inference in (False, True):
        await request("POST", "/internal/v5/builds", build(inference))


async def reconcile_joint(client, queue: str):
    snapshot = await request("GET", "/v5/snapshot")
    for mission in snapshot["missions"]:
        state, input = mission["state"], mission["input"]
        handle = client.get_workflow_handle("starbase2-joint-" + input["id"])
        if state in {"completed", "failed"}:
            continue
        if state == "queued" and snapshot["enabled"]:
            try:
                await client.start_workflow(
                    ReadinessJoint.run,
                    input,
                    id="starbase2-joint-" + input["id"],
                    task_queue=queue,
                    execution_timeout=timedelta(seconds=600),
                    id_reuse_policy=WorkflowIDReusePolicy.REJECT_DUPLICATE,
                )
            except WorkflowAlreadyStartedError:
                pass
        try:
            status = (await handle.describe()).status
        except RPCError as exc:
            if exc.status == RPCStatusCode.NOT_FOUND:
                continue
            raise
        if status == Status.RUNNING and (state == "cancelled" or not snapshot["enabled"]):
            await handle.cancel()
        elif status is not None and status != Status.RUNNING:
            latest = await request("GET", f"/v5/missions/{input['id']}")
            for task in latest["tasks"]:
                if task["state"] == "claimed":
                    await request(
                        "POST",
                        f"/internal/v5/missions/{input['id']}/tasks/{task['id']}/result",
                        {
                            "status": "unknown",
                            "output": None,
                            "usage": None,
                            "error": "Workflow ended without a retained member response",
                        },
                    )
            if latest["state"] not in {"completed", "failed", "cancelled"}:
                await request(
                    "POST",
                    f"/internal/v5/missions/{input['id']}/finish",
                    {
                        "decision": None,
                        "reason": "Workflow terminated without a retained final decision",
                    },
                )
