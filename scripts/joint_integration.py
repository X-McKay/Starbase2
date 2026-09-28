"""Real Core/Temporal readiness coordination, retained evidence, restart and replay."""

import asyncio
import hashlib
import json
import os
import secrets
import signal
import subprocess
import sys
import time
from pathlib import Path

import httpx
from starbase_runtime.joint_workflow import ReadinessJoint
from temporalio.client import Client
from temporalio.worker import Replayer

ROOT = Path(__file__).resolve().parents[1]
HARNESS = Path(__file__).read_bytes()


async def main():
    inference = "--inference" in sys.argv
    scenarios = (
        ("route-mismatch",)
        if "--one-case" in sys.argv
        else ("route-mismatch", "healthy", "persistent-dependency", "listening-but-broken")
    )
    if "--remaining-cases" in sys.argv:
        scenarios = ("healthy", "persistent-dependency", "listening-but-broken")
    core_port = os.environ.get("STARBASE_JOINT_TEST_CORE_PORT", "18891")
    temporal_port = os.environ.get("STARBASE_JOINT_TEST_TEMPORAL_PORT", "17431")
    output = ROOT / ".local" / ("joint-inference-" if inference else "joint-integration-")
    output = output.with_name(output.name + str(time.time_ns()))
    output.mkdir()
    token = output / "worker-token"
    token.write_text(secrets.token_hex(32))
    token.chmod(0o600)
    env = {k: v for k, v in os.environ.items() if k in {"PATH", "LANG", "TMPDIR"}}
    env.update(
        PYTHONPATH=str(ROOT / "services/runtime"),
        STARBASE_PORT=core_port,
        STARBASE_CORE=f"http://127.0.0.1:{core_port}",
        STARBASE_TEMPORAL=f"127.0.0.1:{temporal_port}",
        STARBASE_DB=str(output / "core.sqlite"),
        STARBASE_TOKEN_FILE=str(token),
        STARBASE_JOINT_ENABLED="true",
        STARBASE_JOINT_CHECKPOINT=str(output / "checkpoint"),
        STARBASE_REPAIRS_ENABLED="false",
        STARBASE_LEGACY_ENABLED="false",
    )
    processes, logs, events = [], [], []

    def record(name, **facts):
        events.append({"event": name, **facts})
        (output / "events.json").write_text(json.dumps(events, indent=2) + "\n")
        print(
            name, {k: v.get("digest") if k == "build" else v for k, v in facts.items()}, flush=True
        )

    def start(name, args):
        log = (output / (name + ".log")).open("a")
        logs.append(log)
        p = subprocess.Popen(
            args, cwd=ROOT, env=env, stdout=log, stderr=log, start_new_session=True
        )
        processes.append(p)
        return p

    async def stop(p, kill=False):
        if p.poll() is None:
            os.killpg(p.pid, signal.SIGKILL if kill else signal.SIGTERM)
            await asyncio.to_thread(p.wait, 15)

    async def wait(fn, seconds=60):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            result = await fn()
            if result:
                return result
            await asyncio.sleep(0.2)
        raise AssertionError("Timed out; evidence at " + str(output))

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
                temporal_port,
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
            worker = start(
                "worker", [sys.executable, str(ROOT / "scripts/joint_worker_fixture.py")]
            )

            async def registered():
                return (await http.get("/v5/snapshot")).json()["builds"]

            builds = await wait(registered)
            selected = next(b for b in builds if b["manifest"]["inference"] == inference)
            for name, expected in selected["manifest"]["sources"].items():
                content = (ROOT / name).read_bytes()
                assert hashlib.sha256(content).hexdigest() == expected
                target = output / "frozen-sources" / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(content)
            (output / "harness.py").write_bytes(HARNESS)
            (output / "grader.json").write_text(
                json.dumps(
                    {
                        "harness": hashlib.sha256(HARNESS).hexdigest(),
                        "source": hashlib.sha256(
                            (ROOT / "services/core/src/joint.rs").read_bytes()
                        ).hexdigest(),
                        "binary": hashlib.sha256(
                            (ROOT / "target/debug/starbase-core").read_bytes()
                        ).hexdigest(),
                    },
                    indent=2,
                )
                + "\n"
            )
            record(
                "declaration",
                build=selected,
                scenarios=list(scenarios),
                trials_per_case=1,
                total_request_limit=12 * len(scenarios),
                total_token_limit=384000 * len(scenarios),
                inference=inference,
                purpose="Public coordination smoke; no qualification or superiority claim",
            )

            async def create(id, scenario="route-mismatch", requests=12):
                body = {
                    "id": id,
                    "opportunity": "observation-" + id,
                    "build": selected["digest"],
                    "scenario": scenario,
                    "inference": inference,
                    "budget": {"requests": requests, "tokens": 384000},
                }
                response = await http.post("/v5/missions", json=body)
                assert response.status_code == 200, response.text
                return body

            async def finished(id):
                m = (await http.get("/v5/missions/" + id)).json()
                return m if m["state"] in {"completed", "failed", "cancelled"} else None

            for scenario in scenarios:
                body = await create(scenario, scenario)
                duplicate = await http.post("/v5/missions", json=body)
                assert duplicate.status_code == 200
                conflict = await http.post(
                    "/v5/missions", json=body | {"budget": {"requests": 1, "tokens": 1}}
                )
                assert conflict.status_code == 409
                m = await wait(
                    lambda scenario=scenario: finished(scenario), seconds=650 if inference else 60
                )
                if not inference:
                    assert m["outcome"] == "diagnostic-pass", m
                assert m["xp"] == 0 and m["simulation"] is True
                (output / (scenario + ".json")).write_text(json.dumps(m, indent=2) + "\n")
                handle = client.get_workflow_handle("starbase2-joint-" + scenario)
                await handle.result()
                history = await handle.fetch_history()
                (output / (scenario + "-history.json")).write_text(history.to_json())
                await Replayer(workflows=[ReadinessJoint]).replay_workflow(history)
                record(
                    "diagnostic-and-replay",
                    scenario=scenario,
                    tasks=len(m["tasks"]),
                    outcome=m["outcome"],
                )

            if inference:
                record("inference-smoke-complete", evidence=str(output))
                return

            await create("budget", requests=1)
            m = await wait(lambda: finished("budget"))
            assert m["outcome"] == "unresolved" and m["budget"]["requests_reserved"] == 1
            record("root-budget-fenced", outcome=m["outcome"])
            snapshot = (await http.get("/v5/snapshot")).json()
            opportunities = snapshot["opportunities"]
            assert len(opportunities) == 1
            assert opportunities[0]["category"] == "budget-stop"
            assert opportunities[0]["source_mission_ids"] == ["budget"]
            assert opportunities[0]["status"] == "proposed-review"
            assert opportunities[0]["observed_count"] == 1
            repeated = (await http.get("/v5/snapshot")).json()["opportunities"]
            assert repeated == opportunities
            record("trainer-review-stable", opportunity=opportunities[0]["id"])

            await create("restart")

            async def checkpoint():
                return (output / "checkpoint").exists()

            await wait(checkpoint)
            await stop(worker, kill=True)
            await stop(core)
            core = start("core", [str(ROOT / "target/debug/starbase-core")])
            await wait(ready)
            recovered = (await http.get("/v5/snapshot")).json()["opportunities"]
            assert recovered == opportunities
            worker = start(
                "worker", [sys.executable, str(ROOT / "scripts/joint_worker_fixture.py")]
            )
            m = await wait(lambda: finished("restart"), seconds=150)
            assert m["outcome"] == "diagnostic-pass" and len(m["tasks"]) == 6, m
            assert m["budget"]["requests_reserved"] == 6
            history = await client.get_workflow_handle("starbase2-joint-restart").fetch_history()
            (output / "restart-history.json").write_text(history.to_json())
            await Replayer(workflows=[ReadinessJoint]).replay_workflow(history)
            (output / "restart.json").write_text(json.dumps(m, indent=2) + "\n")
            record(
                "core-worker-restart-replay",
                tasks=len(m["tasks"]),
                requests=m["budget"]["requests_reserved"],
            )

            await stop(worker)
            await create("cancel")
            cancelled = await http.post("/v5/missions/cancel/cancel", json={})
            assert cancelled.status_code == 200
            worker = start(
                "worker", [sys.executable, str(ROOT / "scripts/joint_worker_fixture.py")]
            )
            await asyncio.sleep(0.5)
            m = await finished("cancel")
            assert m["state"] == "cancelled" and not m["tasks"]
            record("cancel-before-dispatch", tasks=0)
            snapshot = (await http.get("/v5/snapshot")).json()
            (output / "snapshot.json").write_text(json.dumps(snapshot, indent=2) + "\n")
            assert {s for o in snapshot["opportunities"] for s in o["source_mission_ids"]} == {
                "budget",
                "cancel",
            }
            record("complete", evidence=str(output))
    finally:
        for process in reversed(processes):
            await stop(process)
        for log in logs:
            log.close()
        print("Evidence:", output, flush=True)


if __name__ == "__main__":
    asyncio.run(main())
