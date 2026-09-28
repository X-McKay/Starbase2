"""Real Core/Temporal SDLC lifecycle with explicitly synthetic external controls."""

import asyncio
import json
import os
import secrets
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

import httpx
from pydantic_ai.durable_exec.temporal import PydanticAIPlugin
from starbase_runtime.sdlc_workflow import RepositorySdlc
from temporalio.api.enums.v1 import EventType
from temporalio.client import Client
from temporalio.worker import Replayer

ROOT = Path(__file__).resolve().parents[1]
HARNESS = Path(__file__).read_bytes()
FIXTURE = (ROOT / "scripts/sdlc_worker_fixture.py").read_bytes()


async def main():
    output = ROOT / ".local" / ("sdlc-integration-" + str(time.time_ns()))
    output.mkdir()
    (output / "harness.py").write_bytes(HARNESS)
    (output / "worker-fixture.py").write_bytes(FIXTURE)
    token = output / "worker-token"
    token.write_text(secrets.token_hex(32))
    token.chmod(0o600)
    core_port, temporal_port = "18917", "17447"
    for port in (core_port, temporal_port):
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", int(port)))
    env = {k: v for k, v in os.environ.items() if k in {"PATH", "LANG", "TMPDIR"}}
    env.update(
        PYTHONPATH=str(ROOT / "services/runtime"),
        STARBASE_PORT=core_port,
        STARBASE_CORE=f"http://127.0.0.1:{core_port}",
        STARBASE_TEMPORAL=f"127.0.0.1:{temporal_port}",
        STARBASE_TEMPORAL_QUEUE="sdlc-control",
        STARBASE_DB=str(output / "core.sqlite"),
        STARBASE_TOKEN_FILE=str(token),
        STARBASE_SDLC_ENABLED="true",
        STARBASE_SDLC_REPOSITORY="X-McKay/algent",
        STARBASE_SDLC_CONTROL_DIR=str(output),
        STARBASE_FIELD_ENABLED="false",
        STARBASE_LEGACY_ENABLED="false",
        STARBASE_REPAIRS_ENABLED="false",
        STARBASE_JOINT_ENABLED="false",
        STARBASE_LEARNING_ENABLED="false",
    )
    processes, logs, events = [], [], []

    def record(name, **data):
        events.append({"event": name, "synthetic_external_controls": True, **data})
        (output / "events.json").write_text(json.dumps(events, indent=2) + "\n")
        print(name, data, flush=True)

    def start(name, args):
        log = (output / (name + ".log")).open("a")
        logs.append(log)
        process = subprocess.Popen(
            args, cwd=ROOT, env=env, stdout=log, stderr=log, start_new_session=True
        )
        processes.append(process)
        return process

    async def stop(process, kill=False):
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL if kill else signal.SIGTERM)
            await asyncio.to_thread(process.wait, 15)

    async def wait(fn, seconds=60):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            value = await fn()
            if value:
                return value
            await asyncio.sleep(0.2)
        raise AssertionError("Timed out; retained evidence: " + str(output))

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
                    return await Client.connect(
                        env["STARBASE_TEMPORAL"], plugins=[PydanticAIPlugin()]
                    )
                except RuntimeError:
                    return None

            client = await wait(temporal_ready)
            response = await http.post(
                "/v7/policy",
                json={
                    "repository": "X-McKay/algent",
                    "enabled": True,
                    "publish": True,
                    "generation": 0,
                    "max_missions": 3,
                    "expires_at": time.time() + 600,
                },
            )
            assert response.status_code == 200, response.text
            worker = start("worker", [sys.executable, str(ROOT / "scripts/sdlc_worker_fixture.py")])

            async def checkpoint():
                snapshot = (await http.get("/v7/snapshot")).json()
                if not snapshot["missions"]:
                    return False
                m = snapshot["missions"][0]
                if m["state"] in {"blocked", "failed"}:
                    raise AssertionError(m)
                if m["state"] != "submitted":
                    return False
                handle = client.get_workflow_handle("starbase2-sdlc-" + m["id"])
                history = await handle.fetch_history()
                return (
                    m
                    if any(
                        e.event_type == EventType.EVENT_TYPE_TIMER_STARTED for e in history.events
                    )
                    else False
                )

            mission = await wait(checkpoint)
            record("durable-ci-timer", mission=mission["id"])
            await stop(worker, kill=True)
            await stop(core)
            core = start("core", [str(ROOT / "target/debug/starbase-core")])
            await wait(ready)
            worker = start("worker", [sys.executable, str(ROOT / "scripts/sdlc_worker_fixture.py")])

            async def finished():
                value = (await http.get("/v7/missions/" + mission["id"])).json()
                return (
                    value if value["state"] in {"awaiting_review", "blocked", "failed"} else False
                )

            final = await wait(finished, 45)
            assert final["state"] == "awaiting_review", final
            assert final["input"]["capability_digest"] == final["capability"]["digest"]
            assert [task["crew"] for task in final["coordination"]["assignments"]] == [
                "moss",
                "rivet",
                "prism",
            ]
            for stage in ("implementing", "reviewing"):
                assert (
                    final["evidence"][stage]["capability_digest"] == final["capability"]["digest"]
                )
            assert final["evidence"]["testing"]["patch"]["assignment"]["role"] == "implementer"
            held = (await http.get("/v7/snapshot")).json()
            assert held["coordination"]["admission"] == "ready"
            assert held["coordination"]["reserved_opportunities"] == ["persistence-history"]
            observation_path = f"/internal/v7/missions/{mission['id']}/pr-observation"
            observation = {
                "number": final["evidence"]["submitted"]["number"],
                "head": final["evidence"]["submitted"]["head"],
                "state": "closed",
                "observed_at": time.time(),
            }
            assert (await http.post(observation_path, json=observation)).status_code == 403
            worker_headers = {"Authorization": "Bearer " + token.read_text().strip()}
            conflicting = await http.post(
                "/internal/v7/missions",
                json=final["input"] | {"id": "sdlc-held-control", "revision": "b" * 40},
                headers=worker_headers,
            )
            assert conflicting.status_code in {409, 422}, conflicting.text
            assert "reserves the capability" in conflicting.text
            observed = await http.post(observation_path, json=observation, headers=worker_headers)
            assert observed.status_code == 200, observed.text
            released = (await http.get("/v7/snapshot")).json()
            assert released["coordination"]["admission"] == "ready"
            assert released["coordination"]["reserved_opportunities"] == []
            observation = observation | {"state": "open", "observed_at": time.time()}
            assert (
                await http.post(observation_path, json=observation, headers=worker_headers)
            ).status_code == 200
            held = (await http.get("/v7/snapshot")).json()
            assert held["coordination"]["admission"] == "ready"
            assert held["coordination"]["reserved_opportunities"] == ["persistence-history"]
            final = (await http.get("/v7/missions/" + mission["id"])).json()
            record(
                "contract-and-lifecycle",
                bound_contract=final["capability"]["digest"],
                crew=["moss", "rivet", "prism"],
                closed_released=True,
                reopened_held=True,
            )
            assert final["evidence"]["testing"]["verdict"] == "improved"
            assert final["evidence"]["awaiting_review"]["ci"]["status"] == "passed"
            roles = [
                json.loads(line)["role"]
                for line in (output / "model-controls.jsonl").read_text().splitlines()
            ]
            assert roles == ["lead", "implementer", "reviewer"], roles
            assert len(final["effects"]) == 3
            await asyncio.sleep(2)
            assert len((await http.get("/v7/snapshot")).json()["missions"]) == 1
            handle = client.get_workflow_handle("starbase2-sdlc-" + mission["id"])
            await handle.result()
            history = await handle.fetch_history()
            (output / "history.json").write_text(history.to_json())
            await Replayer(
                workflows=[RepositorySdlc], plugins=[PydanticAIPlugin()]
            ).replay_workflow(history)
            (output / "mission.json").write_text(json.dumps(final, indent=2) + "\n")
            record(
                "complete",
                roles=roles,
                effects=3,
                duplicate_missions=0,
                verdict="improved",
                state=final["state"],
                history_events=len(history.events),
                replay="passed",
                evidence=str(output),
            )
    except Exception as error:
        record("failed", error_type=type(error).__name__, evidence=str(output))
        raise
    finally:
        for process in reversed(processes):
            await stop(process)
        for log in logs:
            log.close()
        print("Evidence:", output, flush=True)


if __name__ == "__main__":
    asyncio.run(main())
