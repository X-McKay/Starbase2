"""Real durable verification/repair loop with synthetic external effects only."""

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
from starbase_runtime.sdlc_verification_workflow import RepositoryVerification
from temporalio.client import Client
from temporalio.worker import Replayer

ROOT = Path(__file__).resolve().parents[1]
HARNESS = Path(__file__).read_bytes()
FIXTURE = (ROOT / "scripts/verification_worker_fixture.py").read_bytes()
HEAD1, HEAD2 = "a" * 40, "b" * 40


async def main():
    output = ROOT / ".local" / ("verification-integration-" + str(time.time_ns()))
    output.mkdir()
    (output / "harness.py").write_bytes(HARNESS)
    (output / "fixture.py").write_bytes(FIXTURE)
    (output / "head").write_text(HEAD1)
    token = output / "worker-token"
    token.write_text(secrets.token_hex(32))
    token.chmod(0o600)
    core_port, temporal_port = "18918", "17448"
    for port in (core_port, temporal_port):
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", int(port)))
    env = {k: v for k, v in os.environ.items() if k in {"PATH", "LANG", "TMPDIR"}}
    env.update(
        PYTHONPATH=str(ROOT / "services/runtime"),
        STARBASE_PORT=core_port,
        STARBASE_CORE=f"http://127.0.0.1:{core_port}",
        STARBASE_TEMPORAL=f"127.0.0.1:{temporal_port}",
        STARBASE_TEMPORAL_QUEUE="verification-control",
        STARBASE_DB=str(output / "core.sqlite"),
        STARBASE_TOKEN_FILE=str(token),
        STARBASE_SDLC_ENABLED="true",
        STARBASE_SDLC_REPOSITORY="X-McKay/algent",
        STARBASE_SDLC_VERIFICATION_ENABLED="true",
        STARBASE_VERIFICATION_CONTROL_DIR=str(output),
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

            async def post(path, body):
                headers = (
                    {"Authorization": "Bearer " + token.read_text()}
                    if path.startswith("/internal/")
                    else {}
                )
                response = await http.post(path, json=body, headers=headers)
                assert response.status_code == 200, (path, response.text)
                return response.json()

            async def temporal_ready():
                try:
                    return await Client.connect(
                        env["STARBASE_TEMPORAL"], plugins=[PydanticAIPlugin()]
                    )
                except RuntimeError:
                    return None

            client = await wait(temporal_ready)
            await post(
                "/v7/policy",
                {
                    "repository": "X-McKay/algent",
                    "enabled": True,
                    "publish": True,
                    "generation": 0,
                    "max_missions": 1,
                    "expires_at": time.time() + 900,
                },
            )
            assert (await http.get("/v7/snapshot")).json()["verification_enabled"]
            # Seed an explicitly synthetic submitted parent through the real state machine.
            prefix = "/internal/v7/missions/control-parent"
            await post(
                "/internal/v7/missions",
                {
                    "id": "control-parent",
                    "repository": "x-mckay/algent",
                    "revision": HEAD1,
                    "opportunity": "persistence-history",
                    "build": {"digest": "c" * 64},
                },
            )
            cases = {
                "history_all": [0, 1, 2, 3, 4],
                "history_last3": [2, 3, 4],
                "history_last1": [4],
                "history_zero": [],
                "history_empty": [],
                "history_context": [9],
                "history_mixed": [0, 1, 2, 3, 4],
            }
            candidate = {
                "exit_code": 0,
                "cases": [{"id": key, "actual": value} for key, value in cases.items()],
            }
            baseline = {"exit_code": 0, "cases": [{"id": key, "actual": []} for key in cases]}
            for stage, data in [
                ("investigating", {"synthetic": True}),
                ("implementing", {"synthetic": True}),
                (
                    "testing",
                    {"baseline": baseline, "candidate": candidate, "artifact_digest": "d" * 64},
                ),
                ("reviewing", {"status": "accept", "synthetic": True}),
                ("ready_to_publish", {}),
            ]:
                await post(prefix + "/event", {"key": stage, "stage": stage, "data": data})
            await post(prefix + "/publication", {"artifact_digest": "d" * 64, "revision": HEAD1})
            for kind in ("branch", "pr", "review"):
                await post(
                    prefix + "/effect", {"key": kind, "kind": kind, "data": {"synthetic": True}}
                )
            await post(
                prefix + "/event",
                {
                    "key": "submitted",
                    "stage": "submitted",
                    "data": {
                        "number": 987654321,
                        "url": "https://github.com/X-McKay/algent/pull/987654321",
                        "head": HEAD1,
                        "branch": "starbase/control-parent",
                        "synthetic": True,
                    },
                },
            )
            await post(
                prefix + "/event",
                {"key": "awaiting", "stage": "awaiting_review", "data": {"synthetic": True}},
            )
            worker = start(
                "worker", [sys.executable, str(ROOT / "scripts/verification_worker_fixture.py")]
            )

            async def checkpoint():
                marker = output / "retry-checkpoint"
                if not marker.exists():
                    return False
                vid = marker.read_text()
                description = await client.get_workflow_handle("starbase2-" + vid).describe()
                pending = description.raw_description.pending_activities
                return vid if any(p.attempt >= 2 for p in pending) else False

            vid = await wait(checkpoint)
            record("status-effect-retained-retry-scheduled", verification=vid)
            await stop(worker, kill=True)
            await stop(core)
            core = start("core", [str(ROOT / "target/debug/starbase-core")])
            await wait(ready)
            worker = start(
                "worker", [sys.executable, str(ROOT / "scripts/verification_worker_fixture.py")]
            )

            async def finished():
                parent = (await http.get("/v7/missions/control-parent")).json()
                children = parent.get("verifications", [])
                if any(v["state"] in {"blocked", "cancelled"} for v in children):
                    (output / "failed-parent.json").write_text(json.dumps(parent, indent=2))
                    raise AssertionError("Verification blocked; inspect failed-parent.json")
                return (
                    parent
                    if len(children) == 2 and all(v["state"] == "completed" for v in children)
                    else False
                )

            parent = await wait(finished, 90)
            children = sorted(parent["verifications"], key=lambda v: v["created_at"])
            assert [v["input"]["head"] for v in children] == [HEAD1, HEAD2]
            assert [v["evidence"]["verified"]["outcome"] for v in children] == ["failed", "passed"]
            assert children[0]["evidence"]["testing"]["verdict"] == "improved"
            effects = json.loads((output / "effects.json").read_text())
            assert len(effects) == 6, effects
            assert sum(key.endswith("/branch_update") for key in effects) == 1
            assert sum(key.endswith("/review") for key in effects) == 1
            roles = [
                json.loads(line)["role"]
                for line in (output / "roles.jsonl").read_text().splitlines()
            ]
            assert roles == ["lead", "implementer", "reviewer"], roles
            histories = []
            for child in children:
                handle = client.get_workflow_handle("starbase2-" + child["id"])
                await handle.result()
                history = await handle.fetch_history()
                (output / (child["id"] + "-history.json")).write_text(history.to_json())
                await Replayer(
                    workflows=[RepositoryVerification], plugins=[PydanticAIPlugin()]
                ).replay_workflow(history)
                histories.append(len(history.events))
            (output / "parent.json").write_text(json.dumps(parent, indent=2) + "\n")
            record(
                "complete",
                heads=[HEAD1, HEAD2],
                outcomes=["failed", "passed"],
                model_calls=roles,
                statuses=4,
                branch_updates=1,
                reviews=1,
                history_events=histories,
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
