"""Local trusted coordinator. No candidate code loading or production identities."""

import argparse
import asyncio
import json
import os
import signal
import time
from datetime import timedelta
from pathlib import Path

from temporalio.client import Client, WorkflowExecutionStatus
from temporalio.common import WorkflowIDReusePolicy
from temporalio.exceptions import WorkflowAlreadyStartedError
from temporalio.service import RPCError, RPCStatusCode
from temporalio.worker import Worker

from .activities import api, prepare, retain, run_trial
from .agent import build_manifest
from .connection import connect
from .contract import Snapshot
from .dispatch import reconcile_operations, register
from .field import field_advice, field_analyze, field_capture, field_finish, field_tick
from .field_dispatch import reconcile_field, register_field
from .field_workflow import FieldDuty, FieldObservation
from .operations import (
    duty_tick,
    request,
    review_advice,
    review_analyze,
    review_prepare,
    review_retain,
)
from .operations_workflows import RecurringReview, RepositoryReview
from .repair import BUILD, repair_execute, repair_finish, repair_propose
from .repair_dispatch import reconcile_repairs
from .repair_workflow import IsolatedRepair
from .workflows import SurveyorCampaign

QUEUE = os.environ.get("STARBASE_TEMPORAL_QUEUE", "starbase2-local-v1")
REPAIRS_ENABLED = os.environ.get("STARBASE_REPAIRS_ENABLED", "true") == "true"
LEGACY_ENABLED = os.environ.get("STARBASE_LEGACY_ENABLED", "true") == "true"


async def reconcile(client: Client) -> None:
    snapshot = await api("GET", "/v1/snapshot")
    if snapshot.get("schema_version") != 1 or snapshot.get("simulation") is not True:
        raise ValueError("Unsupported or non-synthetic snapshot; no dispatch")
    Snapshot.model_validate(snapshot)
    for mission in snapshot["missions"]:
        if mission["state"] in {"completed", "failed", "cancelled"}:
            continue
        input = mission["input"]
        workflow_id = "starbase2-" + input["id"]
        if mission["state"] == "queued":
            try:
                await client.start_workflow(
                    SurveyorCampaign.run,
                    input,
                    id=workflow_id,
                    task_queue=QUEUE,
                    execution_timeout=timedelta(seconds=180),
                    id_reuse_policy=WorkflowIDReusePolicy.REJECT_DUPLICATE,
                )
            except WorkflowAlreadyStartedError:
                pass  # Ambiguous dispatch acknowledgement reconciles by stable workflow identity.
        handle = client.get_workflow_handle(workflow_id)
        try:
            desc = await handle.describe()
        except RPCError as error:
            # Cancel-before-dispatch requires a NOT_FOUND response, not a timeout.
            if error.status == RPCStatusCode.NOT_FOUND:
                if mission["state"] == "cancel_requested":
                    await api(
                        "POST",
                        f"/v1/missions/{input['id']}/transition",
                        {"state": "cancelled", "detail": "Cancelled before workflow dispatch"},
                    )
                    continue
            raise
        if desc.status is None:
            continue  # Unknown Temporal status cannot certify completion or cancellation.
        if mission["state"] == "cancel_requested":
            if desc.status == WorkflowExecutionStatus.RUNNING:
                await handle.cancel()
            else:
                await api(
                    "POST",
                    f"/v1/missions/{input['id']}/transition",
                    {
                        "state": "cancelled"
                        if desc.status == WorkflowExecutionStatus.CANCELED
                        else "failed",
                        "detail": f"Temporal {desc.status.name} after stop request",
                    },
                )
        elif desc.status != WorkflowExecutionStatus.RUNNING:
            await api(
                "POST",
                f"/v1/missions/{input['id']}/transition",
                {
                    "state": "failed",
                    "detail": f"Temporal {desc.status.name}; no retained completion",
                },
            )


async def reconcile_all(client: Client) -> bool:
    healthy = True
    # A legacy experiment outage must not suppress current operational dispatch.
    for version in (1, 2, 3, 4):
        if (version == 1 and not LEGACY_ENABLED) or (version == 3 and not REPAIRS_ENABLED):
            continue
        if version >= 2 and not os.environ.get("STARBASE_TOKEN_FILE"):
            continue
        try:
            if version == 1:
                await reconcile(client)
            elif version == 2:
                await reconcile_operations(client, QUEUE)
            elif version == 3:
                await reconcile_repairs(client, QUEUE)
            else:
                await reconcile_field(client, QUEUE)
        except Exception as exc:
            healthy = False
            print(f"v{version} reconciliation unavailable: {type(exc).__name__}: {exc}", flush=True)

    return healthy


async def run_worker() -> None:
    client = await connect()
    stop = asyncio.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        asyncio.get_running_loop().add_signal_handler(sig, stop.set)
    if os.environ.get("STARBASE_TOKEN_FILE"):
        await register()
        await register_field()
        if REPAIRS_ENABLED:
            await request("POST", "/internal/v3/builds", BUILD)
    async with Worker(
        client,
        task_queue=QUEUE,
        workflows=[RepositoryReview, RecurringReview, FieldObservation, FieldDuty]
        + ([SurveyorCampaign] if LEGACY_ENABLED else [])
        + ([IsolatedRepair] if REPAIRS_ENABLED else []),
        activities=[
            field_capture,
            field_analyze,
            field_advice,
            field_finish,
            field_tick,
            repair_propose,
            repair_execute,
            repair_finish,
            prepare,
            run_trial,
            retain,
            review_prepare,
            review_analyze,
            review_advice,
            review_retain,
            duty_tick,
        ],
        max_concurrent_activities=4,
        graceful_shutdown_timeout=timedelta(seconds=60),
    ):
        while not stop.is_set():
            if await reconcile_all(client):
                await asyncio.to_thread(
                    Path("/tmp/starbase2-worker-heartbeat").write_text, str(time.time())
                )
            try:
                await asyncio.wait_for(stop.wait(), timeout=1)
            except TimeoutError:
                pass


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["worker", "demo"])
    parser.add_argument("--id", default="first-survey")
    parser.add_argument("--delay", type=int, default=3)
    parser.add_argument("--integration", action="store_true")
    args = parser.parse_args()
    if args.command == "worker":
        await run_worker()
    else:
        from .contract import MissionInput

        input = MissionInput.model_validate(
            {
                "id": args.id,
                "baseline": build_manifest("baseline"),
                "candidate": build_manifest("regressed"),
                "delay_seconds": args.delay,
                "integration": args.integration,
            }
        )
        print(json.dumps(await api("POST", "/v1/missions", input.model_dump()), indent=2))


if __name__ == "__main__":
    asyncio.run(main())
