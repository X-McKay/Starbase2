"""Credential-free local field-agent/Graphiti integration, recovery and replay."""

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
from redislite.falkordb_client import FalkorDB
from starbase_runtime.field_workflow import FieldDuty, FieldObservation
from temporalio.client import Client
from temporalio.worker import Replayer

ROOT = Path(__file__).resolve().parents[1]


async def main():
    output = ROOT / ".local" / ("field-integration-" + str(time.time_ns()))
    output.mkdir()
    token_file = output / "token"
    token_file.write_text(secrets.token_hex(32))
    token_file.chmod(0o600)
    env = {k: v for k, v in os.environ.items() if k in {"PATH", "LANG", "TMPDIR"}}
    env.update(
        PYTHONPATH=str(ROOT / "services/runtime"),
        STARBASE_PORT="18791",
        STARBASE_CORE="http://127.0.0.1:18791",
        STARBASE_TEMPORAL="127.0.0.1:17241",
        STARBASE_DB=str(output / "core.sqlite"),
        STARBASE_TOKEN_FILE=str(token_file),
        STARBASE_FALKOR_PORT="16389",
        STARBASE_MEMORY_ENABLED="true",
        STARBASE_REPAIRS_ENABLED="false",
        STARBASE_LEGACY_ENABLED="false",
    )
    processes, logs, events = [], [], []
    worker_args = (
        [sys.executable, str(ROOT / "scripts/repository_worker_fixture.py")]
        if "--repositories" in sys.argv
        else [sys.executable, "-m", "starbase_runtime.worker", "worker"]
    )

    def event(name, **facts):
        events.append({"event": name, **facts})
        (output / "events.json").write_text(json.dumps(events, indent=2) + "\n")
        print(name, facts, flush=True)

    def start(name, args):
        log = (output / (name + ".log")).open("a")
        logs.append(log)
        p = subprocess.Popen(
            args, cwd=ROOT, env=env, stdout=log, stderr=log, start_new_session=True
        )
        processes.append(p)
        return p

    async def stop(p):
        if p.poll() is None:
            os.killpg(p.pid, signal.SIGTERM)
            await asyncio.to_thread(p.wait, 20)

    async def wait(fn, deadline_seconds=60):
        until = time.monotonic() + deadline_seconds
        while time.monotonic() < until:
            result = await fn()
            if result:
                return result
            await asyncio.sleep(0.2)
        raise AssertionError("Timed out; see retained evidence " + str(output))

    db = await asyncio.to_thread(
        FalkorDB, str(output / "memory.rdb"), serverconfig={"port": "16389", "bind": "127.0.0.1"}
    )
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
                "17241",
                "--headless",
                "--log-level",
                "error",
                "--db-filename",
                str(output / "temporal.sqlite"),
            ],
        )
        async with httpx.AsyncClient(base_url=env["STARBASE_CORE"], timeout=5) as http:

            async def ready():
                try:
                    return (await http.get("/")).status_code == 200
                except httpx.TransportError:
                    return False

            await wait(ready)

            async def temporal_ready():
                try:
                    return await Client.connect(env["STARBASE_TEMPORAL"])
                except RuntimeError:
                    return None

            client = await wait(temporal_ready)
            worker = start("worker", worker_args)

            async def registered():
                return (await http.get("/v4/snapshot")).json()["builds"]

            await wait(registered)

            async def post(path, data):
                r = await http.post(path, json=data)
                r.raise_for_status()
                return r.json()

            async def submit(id, agent="watchkeeper", target="cluster-fixture", inference=False):
                return await post(
                    "/v4/runs", {"id": id, "agent": agent, "target": target, "inference": inference}
                )

            async def completed(id):
                r = (await http.get("/v4/runs/" + id)).json()
                if r["state"] == "failed":
                    raise AssertionError(r)
                return r if r["state"] == "completed" else None

            async with httpx.AsyncClient(base_url=env["STARBASE_CORE"]) as anonymous:
                assert (
                    await anonymous.post(
                        "/v4/runs",
                        json={
                            "id": "denied",
                            "agent": "watchkeeper",
                            "target": "cluster-fixture",
                            "inference": False,
                        },
                    )
                ).status_code == 403
            await submit("cluster-first")
            first = await wait(lambda: completed("cluster-first"))
            assert len(first["report"]["findings"]) == 2
            assert first["report"]["memory"]["status"] == "empty"
            await submit("pr-first", "reviewer", "pr-fixture")
            pr = await wait(lambda: completed("pr-first"))
            assert len(pr["report"]["findings"]) == 1
            event("cluster_and_changed_line_pr", cluster=first["report"], pr=pr["report"])
            m = (await http.get("/v4/snapshot")).json()["memory"]
            approved = next(x for x in m if x["agent"] == "watchkeeper")
            await post(
                "/v4/memory/review", {"id": approved["id"], "revision": 0, "decision": "approve"}
            )
            await submit("cluster-recall")
            recalled = await wait(lambda: completed("cluster-recall"))
            assert recalled["report"]["memory"]["status"] == "available", recalled
            assert len(recalled["report"]["memory"]["recurring_keys"]) == 1
            event("graphiti_falkor_recall", memory=recalled["report"]["memory"])
            history = await client.get_workflow_handle(
                "starbase2-field-cluster-recall"
            ).fetch_history()
            await Replayer(workflows=[FieldObservation]).replay_workflow(history)
            (output / "history.json").write_text(history.to_json())
            await stop(worker)
            await stop(core)
            await asyncio.to_thread(db.close)
            db = await asyncio.to_thread(
                FalkorDB,
                str(output / "memory.rdb"),
                serverconfig={"port": "16389", "bind": "127.0.0.1"},
            )
            core = start("core", [str(ROOT / "target/debug/starbase-core")])
            await wait(ready)
            await submit("cancelled")
            await post("/v4/runs/cancelled/cancel", {})
            worker = start("worker", worker_args)
            await submit("after-restart")
            after = await wait(lambda: completed("after-restart"))
            assert after["report"]["memory"]["status"] == "available"
            assert after["report"]["memory"]["records"] == recalled["report"]["memory"]["records"]
            await post(
                "/v4/memory/review", {"id": approved["id"], "revision": 1, "decision": "revoke"}
            )
            await submit("after-revoke")
            revoked = await wait(lambda: completed("after-revoke"))
            assert revoked["report"]["memory"]["records"] == []
            assert (await http.get("/v4/runs/cancelled")).json()["state"] == "cancelled"
            event("replay_restart_persistence_revocation_cancellation")
            duty = {
                "id": "cluster-watch",
                "agent": "watchkeeper",
                "target": "cluster-fixture",
                "interval_seconds": 30,
                "generation": 0,
                "enabled": True,
            }
            await post("/v4/duties", duty)

            async def duty_sleeping():
                try:
                    return (
                        await client.get_workflow_handle(
                            "starbase2-field-duty-cluster-watch"
                        ).describe()
                    ).status
                except Exception:
                    return None

            await wait(duty_sleeping)
            await stop(worker)
            worker = start("worker", worker_args)

            async def duty_done():
                runs = (await http.get("/v4/snapshot")).json()["runs"]
                return next(
                    (
                        r
                        for r in runs
                        if r["input"]["id"].startswith("duty-cluster-watch-")
                        and r["state"] == "completed"
                    ),
                    None,
                )

            await wait(duty_done, 75)
            await post("/v4/duties", duty | {"enabled": False, "generation": 1})

            async def duty_stopped():
                from temporalio.client import WorkflowExecutionStatus

                return (
                    await client.get_workflow_handle(
                        "starbase2-field-duty-cluster-watch"
                    ).describe()
                ).status == WorkflowExecutionStatus.CANCELED

            await wait(duty_stopped)
            duty_history = await client.get_workflow_handle(
                "starbase2-field-duty-cluster-watch"
            ).fetch_history()
            await Replayer(workflows=[FieldDuty]).replay_workflow(duty_history)
            event("durable_duty_worker_restart_pause_replay")
            if "--repositories" in sys.argv:
                watch_config = {
                    "repository": "fixture/command",
                    "interval_seconds": 30,
                    "enabled": True,
                    "removed": False,
                    "generation": 0,
                }
                watch = await post("/v4/repositories", watch_config)
                watch_id = watch["id"]

                async def watch_sleeping():
                    try:
                        return (
                            await client.get_workflow_handle(
                                "starbase2-field-duty-" + watch_id
                            ).describe()
                        ).status
                    except Exception:
                        return None

                await wait(watch_sleeping)
                await stop(worker)
                worker = start("worker", worker_args)

                async def watch_done():
                    runs = (await http.get("/v4/snapshot")).json()["runs"]
                    return next(
                        (
                            r
                            for r in runs
                            if r["input"]["target"] == watch_id and r["state"] == "completed"
                        ),
                        None,
                    )

                result = await wait(watch_done, 75)
                detail = (await http.get("/v4/runs/" + result["input"]["id"])).json()
                assert detail["snapshot"]["data"]["simulation"]
                assert len(detail["report"]["findings"]) == 1
                assert "fixture/command#7" in detail["report"]["findings"][0]["subject"]
                await post(
                    "/v4/repositories",
                    watch_config | {"enabled": False, "removed": True, "generation": 1},
                )

                async def watch_stopped():
                    from temporalio.client import WorkflowExecutionStatus

                    return (
                        await client.get_workflow_handle(
                            "starbase2-field-duty-" + watch_id
                        ).describe()
                    ).status == WorkflowExecutionStatus.CANCELED

                await wait(watch_stopped)
                history = await client.get_workflow_handle(
                    "starbase2-field-duty-" + watch_id
                ).fetch_history()
                await Replayer(workflows=[FieldDuty]).replay_workflow(history)
                assert (await http.get("/v4/runs/" + result["input"]["id"])).json() == detail
                # A new explicit interval must not change the retained prior run.
                event("repository_watch_restart_capture_remove_replay", report=detail["report"])
                (ROOT / "evidence/command-district/integration.json").write_text(
                    json.dumps(events, indent=2) + "\n"
                )
                snapshot = (await http.get("/v4/snapshot")).json()
                details = {}
                for row in snapshot["runs"]:
                    details[row["input"]["id"]] = (
                        await http.get("/v4/runs/" + row["input"]["id"])
                    ).json()
                (ROOT / "evidence/command-district/board-fixture.json").write_text(
                    json.dumps({"snapshot": snapshot, "details": details}, indent=2) + "\n"
                )
            if "--inference" in sys.argv:
                await submit("pr-advisory", "reviewer", "pr-fixture", True)
                advised = await wait(lambda: completed("pr-advisory"), 90)
                event("optional_model_advice", advisory=advised["report"]["advisory"])
                assert advised["report"]["advisory"]["status"] == "unverified", advised
            evidence = (
                ROOT
                / "evidence/field-agents"
                / (
                    "integration-inference.json"
                    if "--inference" in sys.argv
                    else "integration.json"
                )
            )
            evidence.write_text(json.dumps(events, indent=2) + "\n")
            event("passed", output=str(output))
    finally:
        for p in reversed(processes):
            await stop(p)
        for log in logs:
            log.close()
        await asyncio.to_thread(db.close)


if __name__ == "__main__":
    asyncio.run(main())
