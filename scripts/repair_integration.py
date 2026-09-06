"""Real Temporal + microsandbox repair checks. --inference opts into 3 model calls."""

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
from starbase_runtime.repair_workflow import IsolatedRepair
from temporalio.client import Client
from temporalio.worker import Replayer

ROOT = Path(__file__).resolve().parents[1]


async def main(output: Path, inference: bool) -> None:
    output.mkdir(parents=True, exist_ok=False)
    output = output.resolve()
    token = secrets.token_hex(32)
    token_file = output / "runtime-token"
    token_file.write_text(token)
    token_file.chmod(0o600)
    env = {k: v for k, v in os.environ.items() if k in {"PATH", "LANG", "TMPDIR"}}
    env.update(
        PYTHONPATH=str(ROOT / "services/runtime"),
        STARBASE_PORT="18789",
        STARBASE_CORE="http://127.0.0.1:18789",
        STARBASE_TEMPORAL="127.0.0.1:17235",
        STARBASE_DB=str(output / "core.sqlite"),
        STARBASE_TOKEN_FILE=str(token_file),
    )
    processes = []
    logs = []
    events = []
    started = time.monotonic()

    def event(name, **facts):
        item = {"event": name, "seconds": round(time.monotonic() - started, 3), **facts}
        events.append(item)
        (output / "events.json").write_text(json.dumps(events, indent=2) + "\n")
        print(json.dumps(item), flush=True)

    def launch(name, args):
        log = (output / (name + ".log")).open("a")
        logs.append(log)
        p = subprocess.Popen(
            args, cwd=ROOT, env=env, stdout=log, stderr=log, start_new_session=True
        )
        processes.append(p)
        return p

    def worker():
        return launch("worker", [sys.executable, "-m", "starbase_runtime.worker", "worker"])

    def server():
        return launch(
            "temporal",
            [
                str(ROOT / ".local/tools/temporal"),
                "server",
                "start-dev",
                "--ip",
                "127.0.0.1",
                "--port",
                "17235",
                "--headless",
                "--log-level",
                "error",
                "--db-filename",
                str(output / "temporal.sqlite"),
            ],
        )

    async def wait(fn, seconds=100):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            try:
                result = await fn()
                if result:
                    return result
            except httpx.ConnectError:
                pass
            await asyncio.sleep(0.03)
        raise AssertionError("Condition timed out")

    async with httpx.AsyncClient(base_url=env["STARBASE_CORE"], timeout=5, trust_env=False) as http:

        async def get(path):
            r = await http.get(path)
            r.raise_for_status()
            return r.json()

        async def post(path, body, internal=False):
            r = await http.post(
                path, json=body, headers={"Authorization": "Bearer " + token} if internal else {}
            )
            r.raise_for_status()
            return r.json()

        async def detail(id):
            return await get("/v3/repairs/" + id)

        async def done(id):
            r = await detail(id)
            if r["state"] == "failed":
                raise AssertionError(r["detail"])
            return r if r["state"] in {"completed", "cancelled"} else None

        async def create(id, mode="control-good", scenario="clamp-v1"):
            return await post("/v3/repairs", {"id": id, "mode": mode, "scenario": scenario})

        try:
            core = launch("core", [str(ROOT / "target/debug/starbase-core")])
            temporal = server()
            await wait(lambda: get("/v3/repairs"))
            denied = await http.post(
                "/v3/repairs", json={"id": "deny", "mode": "inference", "scenario": "clamp-v1"}
            )
            assert denied.status_code == 403
            await http.get("/")
            runtime = worker()

            async def ready():
                return (await get("/v2/snapshot"))["worker"]["available"]

            await wait(ready)
            await create("recover")

            async def executing():
                r = await detail("recover")
                return r if r["actions"] and r["actions"][0]["observation"] is None else None

            await wait(executing)
            client = await Client.connect(env["STARBASE_TEMPORAL"])
            handle = client.get_workflow_handle("starbase2-repair-recover")
            run_id = (await handle.describe()).run_id
            os.killpg(runtime.pid, signal.SIGKILL)
            runtime.wait()
            os.killpg(temporal.pid, signal.SIGTERM)
            temporal.wait(timeout=10)
            event("worker_and_temporal_interrupted", workflow_run_id=run_id)
            temporal = server()
            await asyncio.sleep(2)
            runtime = worker()
            recovered = await wait(lambda: done("recover"))
            assert recovered["summary"]["outcome"] == "improved"
            assert recovered["actions"][0]["attempts"] == 2
            client = await Client.connect(env["STARBASE_TEMPORAL"])
            handle = client.get_workflow_handle("starbase2-repair-recover")
            assert (await handle.describe()).run_id == run_id
            history = await handle.fetch_history()
            await Replayer(workflows=[IsolatedRepair]).replay_workflow(history)
            (output / "history-recover.json").write_text(history.to_json())
            (output / "recover.json").write_text(json.dumps(recovered, indent=2) + "\n")
            event("recovered_and_replayed", outcome="improved", baseline_attempts=2)
            for id, mode, outcome in [
                ("regression", "control-bad", "regressed"),
                ("unchanged", "control-unchanged", "no_change"),
            ]:
                await create(id, mode)
                r = await wait(lambda id=id: done(id))
                assert r["summary"]["outcome"] == outcome
                (output / (id + ".json")).write_text(json.dumps(r, indent=2) + "\n")
                event(id, outcome=outcome)
            await create("cancel")

            async def cancelling():
                r = await detail("cancel")
                return r if r["state"] == "executing" else None

            await wait(cancelling)
            await post("/v3/repairs/cancel/cancel", {})
            cancelled = await wait(lambda: done("cancel"))
            assert cancelled["state"] == "cancelled" and cancelled["summary"] is None
            (output / "cancel.json").write_text(json.dumps(cancelled, indent=2) + "\n")
            event("cancelled_without_credit", state=cancelled["state"])
            assert (await get("/v3/repairs"))["crew"]["xp"] == 0
            if inference:
                for id, scenario, xp in [
                    ("ai-clamp", "clamp-v1", 25),
                    ("ai-dedupe", "dedupe-v1", 25),
                    ("ai-repeat", "clamp-v1", 0),
                ]:
                    await create(id, "inference", scenario)
                    r = await wait(lambda id=id: done(id))
                    (output / (id + ".json")).write_text(json.dumps(r, indent=2) + "\n")
                    assert r["summary"]["outcome"] == "improved", r["summary"]
                    assert r["summary"]["xp_awarded"] == xp
                    diff = await http.get(f"/v3/repairs/{id}/patch")
                    diff.raise_for_status()
                    (output / (id + ".patch")).write_text(diff.text)
                    event(id, outcome="improved", xp=xp)
                p = (await get("/v3/repairs"))["crew"]
                assert p["xp"] == 50 and p["level"] == 2 and len(p["credits"]) == 2
                (output / "progression.json").write_text(json.dumps(p, indent=2) + "\n")
            os.killpg(core.pid, signal.SIGTERM)
            core.wait(timeout=10)
            core = launch("core", [str(ROOT / "target/debug/starbase-core")])
            final = await wait(lambda: get("/v3/repairs"))
            assert final["crew"]["xp"] == (50 if inference else 0)
            event("core_restart_retained_ledger", xp=final["crew"]["xp"])
        except BaseException as exc:
            event("failed", error=type(exc).__name__, detail=str(exc))
            raise
        finally:
            for p in reversed(processes):
                if p.poll() is None:
                    os.killpg(p.pid, signal.SIGTERM)
                    try:
                        p.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(p.pid, signal.SIGKILL)
                        p.wait()
            for log in logs:
                log.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--inference", action="store_true")
    parser.add_argument("--output", type=Path, default=Path(".local") / f"repairs-{time.time_ns()}")
    args = parser.parse_args()
    asyncio.run(main(args.output, args.inference))
