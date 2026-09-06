"""Real local Temporal, subprocess SIGKILL, replay, cancellation and persisted evidence.

Each invocation keeps fresh databases/logs under its output directory. No containers,
provider keys, paid inference, or external operations. Exceptions are never retried
by the test harness to turn a failing experiment green.
"""

import argparse
import asyncio
import hashlib
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import httpx
from pydantic_ai.durable_exec.temporal import PydanticAIPlugin
from starbase_runtime.agent import build_manifest
from starbase_runtime.contract import Snapshot
from starbase_runtime.workflows import SurveyorCampaign
from temporalio.client import Client
from temporalio.worker import Replayer

ROOT = Path(__file__).resolve().parents[1]


async def run(output: Path) -> None:
    output.mkdir(parents=True, exist_ok=False)
    output = output.resolve()
    env = {k: v for k, v in os.environ.items() if k in {"PATH", "LANG", "TMPDIR", "SYSTEMROOT"}}
    env.update(
        PYTHONPATH=str(ROOT / "services/runtime"),
        STARBASE_PORT="18787",
        STARBASE_CORE="http://127.0.0.1:18787",
        STARBASE_TEMPORAL="127.0.0.1:17233",
        STARBASE_DB=str(output / "core.sqlite"),
    )
    processes = []
    logs = []
    events = []
    started = time.monotonic()

    def record(event: str, **facts) -> None:
        row = {"event": event, "elapsed_seconds": round(time.monotonic() - started, 3), **facts}
        events.append(row)
        (output / "events.json").write_text(json.dumps(events, indent=2) + "\n")
        print(json.dumps(row), flush=True)

    def start(name: str, args: list[str]) -> subprocess.Popen:
        log = (output / f"{name}.log").open("a")
        logs.append(log)
        proc = subprocess.Popen(
            args, cwd=ROOT, env=env, stdout=log, stderr=log, start_new_session=True
        )
        processes.append(proc)
        return proc

    def worker() -> subprocess.Popen:
        return start("worker", [sys.executable, "-m", "starbase_runtime.worker", "worker"])

    async def wait_until(fn, seconds=70):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            value = await fn()
            if value:
                return value
            await asyncio.sleep(0.2)
        raise AssertionError(f"Condition not met within {seconds}s")

    async with httpx.AsyncClient(base_url=env["STARBASE_CORE"], timeout=2, trust_env=False) as http:

        async def get(id: str) -> dict:
            response = await http.get(f"/v1/missions/{id}")
            response.raise_for_status()
            return response.json()

        async def state(id: str, desired: str):
            mission = await get(id)
            if mission["state"] == "failed" and desired != "failed":
                raise AssertionError(mission)
            return mission if mission["state"] == desired else None

        async def post(path: str, body: dict):
            response = await http.post(path, json=body)
            response.raise_for_status()
            return response.json()

        def mission(id: str, integration=False, delay=0):
            return {
                "id": id,
                "baseline": build_manifest("baseline"),
                "candidate": build_manifest("regressed"),
                "integration": integration,
                "delay_seconds": delay,
            }

        try:
            core = start("core", [str(ROOT / "target/debug/starbase-core")])
            start(
                "temporal",
                [
                    str(ROOT / ".local/tools/temporal"),
                    "server",
                    "start-dev",
                    "--ip",
                    "127.0.0.1",
                    "--port",
                    "17233",
                    "--headless",
                    "--log-level",
                    "error",
                    "--db-filename",
                    str(output / "temporal.sqlite"),
                ],
            )

            async def ready():
                try:
                    return (await http.get("/v1/snapshot")).status_code == 200
                except httpx.TransportError:
                    return False

            await wait_until(ready, 15)

            async def temporal_ready():
                try:
                    return await Client.connect(
                        env["STARBASE_TEMPORAL"], plugins=[PydanticAIPlugin()]
                    )
                except RuntimeError:
                    return None

            client = await wait_until(temporal_ready, 20)
            await post("/v1/missions", mission("cancel-before-dispatch"))
            await post("/v1/missions/cancel-before-dispatch/cancel", {})
            process = worker()
            await wait_until(lambda: state("cancel-before-dispatch", "cancelled"))
            record("cancel_before_dispatch_passed")

            for mode in ["direct", "integration"]:
                id = f"restart-{mode}"
                input = mission(id, integration=mode == "integration", delay=8)
                await post("/v1/missions", input)
                await wait_until(lambda id=id: state(id, "running"))
                handle = client.get_workflow_handle("starbase2-" + id)
                run_id = (await handle.describe()).run_id
                process.kill()
                process.wait(timeout=5)
                record("worker_sigkill", mode=mode, workflow_run_id=run_id)
                await asyncio.sleep(6)
                stale = await get(id)
                assert stale["stale"] and stale["state"] == "running" and stale["evidence"] is None
                (output / f"stale-{mode}.json").write_text(json.dumps(stale, indent=2))
                await post("/v1/missions", input)
                process = worker()
                complete = await wait_until(lambda id=id: state(id, "completed"))
                result = complete["evidence"]
                assert result["outcome"] == "regressed"
                assert result["baseline_passes"] == 3 and result["candidate_passes"] == 1
                assert len(result["trials"]) == 6 and result["hard_gate_failures"] == [0, 0]
                await handle.result()
                assert (await handle.describe()).run_id == run_id
                submission = {"trials": [row["trial"] for row in result["trials"]]}
                assert await post(f"/v1/missions/{id}/evidence", submission) == result
                submission["trials"][0]["elapsed_ms"] += 1
                assert (
                    await http.post(f"/v1/missions/{id}/evidence", json=submission)
                ).status_code == 409
                history = await handle.fetch_history()
                (output / f"history-{mode}.json").write_text(history.to_json())
                await Replayer(
                    workflows=[SurveyorCampaign], plugins=[PydanticAIPlugin()]
                ).replay_workflow(history)
                (output / f"comparison-{mode}.json").write_text(json.dumps(result, indent=2) + "\n")
                record(
                    "restart_duplicate_submission_replay_passed",
                    mode=mode,
                    history_events=len(history.events),
                    baseline=3,
                    candidate=1,
                )
                id = f"cancel-{mode}"
                await post("/v1/missions", mission(id, mode == "integration", 15))
                await wait_until(lambda id=id: state(id, "running"))
                await post(f"/v1/missions/{id}/cancel", {})
                cancelled = await wait_until(lambda id=id: state(id, "cancelled"))
                assert cancelled["evidence"] is None
                assert "CANCELED" in cancelled["detail"]
                record("cancellation_passed", mode=mode, detail=cancelled["detail"])

            drift = mission("wrong-build")
            drift["baseline"]["manifest"]["prompt"] = "unloaded prompt"
            drift["baseline"]["digest"] = hashlib.sha256(
                json.dumps(
                    drift["baseline"]["manifest"], sort_keys=True, separators=(",", ":")
                ).encode()
            ).hexdigest()
            await post("/v1/missions", drift)
            failed = await wait_until(lambda: state("wrong-build", "failed"))
            assert failed["evidence"] is None
            record("unloaded_build_rejected")
            snapshot = (await http.get("/v1/snapshot")).json()
            Snapshot.model_validate(snapshot)
            assert len(snapshot["missions"]) == 6
            process.terminate()
            process.wait(timeout=10)
            core.terminate()
            core.wait(timeout=5)
            start("core", [str(ROOT / "target/debug/starbase-core")])
            await wait_until(ready)
            restored = (await http.get("/v1/snapshot")).json()
            assert restored["missions"] == snapshot["missions"]
            (output / "snapshot.json").write_text(json.dumps(restored, indent=2) + "\n")
            record("core_restart_preserved_all_missions_and_evidence")
            record("passed", duration_seconds=round(time.monotonic() - started, 3))
        except BaseException as exc:
            record("failed", error=f"{type(exc).__name__}: {exc}")
            raise
        finally:
            for proc in reversed(processes):
                if proc.poll() is None:
                    os.killpg(proc.pid, signal.SIGTERM)
                    try:
                        proc.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(proc.pid, signal.SIGKILL)
                        proc.wait(timeout=5)
            for log in logs:
                log.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path(f".local/integration-{time.time_ns()}"))
    asyncio.run(run(parser.parse_args().output))
