import asyncio
import os
import time

import httpx
from temporalio import activity
from temporalio.exceptions import ApplicationError

from .agent import CASES, build_manifest, review

WORKER_BUILDS = {variant: build_manifest(variant) for variant in ("baseline", "regressed")}

CORE = os.environ.get("STARBASE_CORE", "http://127.0.0.1:8787")


async def api(method: str, path: str, body: dict | None = None) -> dict:
    async with httpx.AsyncClient(timeout=3, trust_env=False) as client:
        response = await client.request(method, CORE + path, json=body)
        if response.status_code == 409:
            raise ApplicationError(response.text, non_retryable=True)
        response.raise_for_status()
        return response.json()


@activity.defn
async def prepare(input: dict) -> list:
    for build in [input["baseline"], input["candidate"]]:
        if build != WORKER_BUILDS.get(build["variant"]):
            raise ApplicationError(
                "Worker build differs from frozen mission; start compatible worker",
                non_retryable=True,
            )
    for _ in range(max(1, input["delay_seconds"])):
        try:
            await api(
                "POST",
                f"/v1/missions/{input['id']}/transition",
                {"state": "running", "detail": "Synthetic fixture preparation; no external work"},
            )
        except ApplicationError:
            current = await api("GET", f"/v1/missions/{input['id']}")
            if current["state"] in {"cancel_requested", "cancelled"}:
                # Wait for Temporal's cancellation token; raising CancelledError before
                # its request arrives is an activity failure, not an acknowledged stop.
                for _ in range(50):
                    activity.heartbeat("awaiting Temporal cancellation")
                    await asyncio.sleep(0.1)
                raise ApplicationError(
                    "Cancellation acknowledgement timed out", non_retryable=True
                ) from None
            raise
        activity.heartbeat("fixture preparation")
        await asyncio.sleep(1)
    return CASES


@activity.defn
async def run_trial(request: dict) -> dict:
    started = time.monotonic()
    output = await review(request["variant"], request["source"])
    return {
        "case_id": request["case_id"],
        "build_digest": request["digest"],
        "findings": output["findings"],
        "elapsed_ms": int((time.monotonic() - started) * 1000),
        "model": "function:surveyor-fixture-v1",
        "requests": 1,
    }


@activity.defn
async def retain(request: dict) -> dict:
    return await api(
        "POST", f"/v1/missions/{request['id']}/evidence", {"trials": request["trials"]}
    )
