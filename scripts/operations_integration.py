"""Local v2 recovery, evidence, operator boundary, and recurring-work verification.

Retains failed attempts. No inference unless --inference is explicitly selected.
"""

import argparse
import asyncio
import json
import os
import secrets
import signal
import subprocess
import sys
import time
from pathlib import Path

import httpx
from starbase_runtime.operations_workflows import RecurringReview, RepositoryReview
from temporalio.client import Client
from temporalio.worker import Replayer

ROOT = Path(__file__).resolve().parents[1]


async def run(output: Path, inference: bool) -> None:
    output.mkdir(parents=True, exist_ok=False)
    output = output.resolve()
    token = secrets.token_hex(32)
    token_file = output / "runtime-token"
    token_file.write_text(token)
    token_file.chmod(0o600)
    env = {k: v for k, v in os.environ.items() if k in {"PATH", "LANG", "TMPDIR"}}
    env.update(
        PYTHONPATH=str(ROOT / "services/runtime"),
        STARBASE_PORT="18788",
        STARBASE_CORE="http://127.0.0.1:18788",
        STARBASE_TEMPORAL="127.0.0.1:17234",
        STARBASE_DB=str(output / "core.sqlite"),
        STARBASE_TOKEN_FILE=str(token_file),
    )
    processes, logs, events = [], [], []
    started = time.monotonic()

    def record(event, **facts):
        row = {"event": event, "seconds": round(time.monotonic() - started, 3), **facts}
        events.append(row)
        (output / "events.json").write_text(json.dumps(events, indent=2) + "\n")
        print(json.dumps(row), flush=True)

    def start(name, args):
        log = (output / f"{name}.log").open("a")
        logs.append(log)
        p = subprocess.Popen(
            args, cwd=ROOT, env=env, stdout=log, stderr=log, start_new_session=True
        )
        processes.append(p)
        return p

    def worker():
        return start("worker", [sys.executable, "-m", "starbase_runtime.worker", "worker"])

    async def wait(fn, seconds=75):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            value = await fn()
            if value:
                return value
            await asyncio.sleep(0.2)
        raise AssertionError(f"Condition not met in {seconds}s")

    async with httpx.AsyncClient(base_url=env["STARBASE_CORE"], timeout=5, trust_env=False) as http:

        async def post(path, body, internal=False):
            r = await http.post(
                path, json=body, headers={"Authorization": "Bearer " + token} if internal else {}
            )
            r.raise_for_status()
            return r.json()

        async def detail(id):
            r = await http.get("/v2/runs/" + id)
            r.raise_for_status()
            return r.json()

        async def completed(id):
            r = await detail(id)
            if r["state"] == "failed":
                raise AssertionError(r["detail"])
            return r if r["state"] == "completed" else None

        def input(id, kind="review", candidate=None, ai=False):
            return {
                "id": id,
                "kind": kind,
                "target": "sample",
                "profile": "surveyor-v1",
                "candidate": candidate,
                "inference": ai,
            }

        try:
            core = start("core", [str(ROOT / "target/debug/starbase-core")])
            temporal = start(
                "temporal",
                [
                    str(ROOT / ".local/tools/temporal"),
                    "server",
                    "start-dev",
                    "--ip",
                    "127.0.0.1",
                    "--port",
                    "17234",
                    "--headless",
                    "--log-level",
                    "error",
                    "--db-filename",
                    str(output / "temporal.sqlite"),
                ],
            )

            async def ready():
                try:
                    return (await http.get("/")).status_code == 200
                except httpx.TransportError:
                    return False

            await wait(ready, 15)
            # Operator cookie is issued by /. Worker identity cannot substitute for it.
            assert (
                await http.post(
                    "/v2/runs", json=input("foreign"), headers={"Origin": "https://evil.invalid"}
                )
            ).status_code == 403
            assert (await http.post("/internal/v2/heartbeat", json={})).status_code == 403
            async with httpx.AsyncClient(
                base_url=env["STARBASE_CORE"], trust_env=False
            ) as anonymous:
                assert (
                    await anonymous.post(
                        "/v2/runs",
                        json=input("anonymous"),
                        headers={"Authorization": "Bearer " + token},
                    )
                ).status_code == 403
            record("operator_and_worker_boundaries_passed")

            async def temporal_ready():
                try:
                    return await Client.connect(env["STARBASE_TEMPORAL"])
                except RuntimeError:
                    return None

            client = await wait(temporal_ready, 20)
            process = worker()

            async def registered():
                return (await http.get("/v2/snapshot")).json()["worker"]["available"]

            await wait(registered, 20)
            for name, candidate, outcome in [
                ("improve", "surveyor-v2", "improved"),
                ("regress", "surveyor-regressed", "regressed"),
            ]:
                await post("/v2/runs", input(name, "evaluation", candidate))
                result = await wait(lambda name=name: completed(name))
                assert result["report"]["summary"]["outcome"] == outcome
                assert len(result["report"]["evidence"]["trials"]) == 12
                handle = client.get_workflow_handle("starbase2-review-" + name)
                await handle.result()
                history = await handle.fetch_history()
                await Replayer(workflows=[RepositoryReview]).replay_workflow(history)
                (output / f"history-{name}.json").write_text(history.to_json())
                (output / f"{name}.json").write_text(json.dumps(result, indent=2) + "\n")
                record(
                    "paired_grading_and_replay_passed",
                    campaign=name,
                    summary=result["report"]["summary"],
                )
            await post("/v2/runs", input("review", ai=inference))
            result = await wait(lambda: completed("review"), 100)
            assert result["report"]["summary"]["finding_count"] == 1
            assert "example.invalid" not in json.dumps(result["snapshot"])
            evidence = result["report"]["evidence"]
            assert await post("/internal/v2/runs/review/report", evidence, True) == result["report"]
            evidence["review"]["elapsed_ms"] += 1
            assert (
                await http.post(
                    "/internal/v2/runs/review/report",
                    json=evidence,
                    headers={"Authorization": "Bearer " + token},
                )
            ).status_code == 409
            (output / "review.json").write_text(json.dumps(result, indent=2) + "\n")
            record(
                "real_analyzer_snapshot_and_immutable_report_passed",
                advisory=result["report"]["evidence"]["review"].get("advisory"),
            )
            # Stop before dispatch while worker is absent; prove stale health independently.
            process.kill()
            process.wait(timeout=5)
            await post("/v2/runs", input("cancel"))
            await post("/v2/runs/cancel/cancel", {})
            await asyncio.sleep(5.5)
            assert not (await http.get("/v2/snapshot")).json()["worker"]["available"]
            process = worker()

            async def cancelled():
                r = await detail("cancel")
                return r["state"] == "cancelled"

            await wait(cancelled)
            record("worker_loss_stale_and_cancel_before_dispatch_passed")
            duty = {
                "id": "watch",
                "target": "sample",
                "profile": "surveyor-v2",
                "interval_seconds": 30,
                "enabled": True,
                "generation": 0,
            }
            await post("/v2/duties", duty)

            async def timer_started():
                try:
                    return await client.get_workflow_handle("starbase2-duty-watch").describe()
                except Exception:
                    return None

            timer = await wait(timer_started, 15)
            process.kill()
            process.wait(timeout=5)
            temporal.terminate()
            temporal.wait(timeout=10)
            record("worker_and_temporal_restart_during_durable_timer", run_id=timer.run_id)
            temporal = start(
                "temporal",
                [
                    str(ROOT / ".local/tools/temporal"),
                    "server",
                    "start-dev",
                    "--ip",
                    "127.0.0.1",
                    "--port",
                    "17234",
                    "--headless",
                    "--log-level",
                    "error",
                    "--db-filename",
                    str(output / "temporal.sqlite"),
                ],
            )
            client = await wait(temporal_ready, 20)
            process = worker()

            async def duty_completed():
                s = (await http.get("/v2/snapshot")).json()
                return next(
                    (
                        r
                        for r in s["recent"]
                        if r["input"]["request"]["id"].startswith("duty-watch-")
                        and r["state"] == "completed"
                    ),
                    None,
                )

            recurring = await wait(duty_completed, 55)
            assert (
                await client.get_workflow_handle("starbase2-duty-watch").describe()
            ).run_id == timer.run_id
            duty["enabled"] = False
            await post("/v2/duties", duty)
            count = len((await http.get("/v2/snapshot")).json()["recent"])
            await post("/internal/v2/duties/watch/tick/99999999", {}, True)
            assert len((await http.get("/v2/snapshot")).json()["recent"]) == count
            history = await client.get_workflow_handle("starbase2-duty-watch").fetch_history()
            await Replayer(workflows=[RecurringReview]).replay_workflow(history)
            (output / "history-duty.json").write_text(history.to_json())
            record(
                "durable_timer_recovery_replay_and_pause_passed",
                run=recurring["input"]["request"]["id"],
            )
            before = await detail("review")
            core.terminate()
            core.wait(timeout=5)
            core = start("core", [str(ROOT / "target/debug/starbase-core")])
            await wait(ready, 15)
            assert await detail("review") == before
            record("core_restart_retained_evidence_and_history")
            record("passed")
        except BaseException as error:
            record("failed", error=f"{type(error).__name__}: {error}")
            raise
        finally:
            for p in reversed(processes):
                if p.poll() is None:
                    os.killpg(p.pid, signal.SIGTERM)
                    try:
                        p.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(p.pid, signal.SIGKILL)
                        p.wait(timeout=5)
            for log in logs:
                log.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path(f".local/operations-{time.time_ns()}"))
    parser.add_argument("--inference", action="store_true")
    args = parser.parse_args()
    asyncio.run(run(args.output, args.inference))
