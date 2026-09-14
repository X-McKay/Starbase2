"""Owned loopback review backend: real GET-only GitHub duty, no inference or memory.

Use --gh-credential only when reuse of the local gh identity is authorized. Its
scope is not asserted to be narrow; the existing adapter binds reads to one repo.
The private working directory contains databases/logs; public evidence is summary
only. Stop with SIGTERM or create the owned directory's STOP file. All children
and the copied credential are cleaned up. No Godot process is launched here.
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
from temporalio.client import Client, WorkflowExecutionStatus

ROOT = Path(__file__).resolve().parents[1]


async def main(args):
    output = args.output.resolve()
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    events = []
    children = []
    logs = []
    closing = asyncio.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        asyncio.get_running_loop().add_signal_handler(sig, closing.set)

    def record(name, **facts):
        events.append({"event": name, "at": time.time(), **facts})
        (evidence / "events.json").write_text(json.dumps(events, indent=2) + "\n")
        print(name, flush=True)

    token = output / "runtime-token"
    token.write_text(secrets.token_hex(32))
    token.chmod(0o600)
    credential = output / "github-token"
    env = {k: v for k, v in os.environ.items() if k in {"PATH", "LANG", "TMPDIR"}}
    env.update(
        PYTHONPATH=str(ROOT / "services/runtime"),
        STARBASE_PORT=str(args.port),
        STARBASE_CORE=f"http://127.0.0.1:{args.port}",
        STARBASE_TEMPORAL=f"127.0.0.1:{args.temporal_port}",
        STARBASE_DB=str(output / "core.sqlite"),
        STARBASE_TOKEN_FILE=str(token),
        STARBASE_FIELD_ENABLED="true",
        STARBASE_MEMORY_ENABLED="false",
        STARBASE_INFERENCE_ENABLED="false",
        STARBASE_REPAIRS_ENABLED="false",
        STARBASE_LEGACY_ENABLED="false",
        STARBASE_FIELD_TARGETS_FILE=str(output / "targets.json"),
    )

    def start(name, command):
        log = (output / (name + ".log")).open("a")
        logs.append(log)
        child = subprocess.Popen(
            command, cwd=ROOT, env=env, stdout=log, stderr=log, start_new_session=True
        )
        children.append(child)
        (output / "processes.json").write_text(
            json.dumps(
                {
                    "harness_pid": os.getpid(),
                    "core_url": env["STARBASE_CORE"],
                    "children": [{"pid": p.pid, "argv": p.args} for p in children],
                },
                indent=2,
            )
        )
        return child

    async def stop(child):
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                await asyncio.to_thread(child.wait, 20)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                await asyncio.to_thread(child.wait, 5)

    async def wait(fn, seconds=90):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline and not closing.is_set():
            result = await fn()
            if result:
                return result
            await asyncio.sleep(0.2)
        raise RuntimeError("Bounded live review wait failed; inspect owned logs")

    try:
        target = {
            "id": "live-starbase2",
            "agent": "reviewer",
            "kind": "github_repository",
            "repository": "X-McKay/Starbase2",
            "allow_inference": False,
        }
        if args.gh_credential:
            with credential.open("xb") as private:
                credential.chmod(0o600)
                result = await asyncio.to_thread(
                    subprocess.run,
                    ["gh", "auth", "token"],
                    stdout=private,
                    stderr=subprocess.DEVNULL,
                    timeout=15,
                )
            if result.returncode or not credential.stat().st_size:
                raise RuntimeError("Existing gh credential unavailable")
            target["token_file"] = str(credential)
        (output / "targets.json").write_text(json.dumps([target]))
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
                str(args.temporal_port),
                "--headless",
                "--log-level",
                "error",
                "--db-filename",
                str(output / "temporal.sqlite"),
            ],
        )
        async with httpx.AsyncClient(
            base_url=env["STARBASE_CORE"], timeout=10, trust_env=False
        ) as http:

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
            worker_args = [sys.executable, "-m", "starbase_runtime.worker", "worker"]
            worker = start("worker", worker_args)

            async def registered():
                return (await http.get("/v4/snapshot")).json()["builds"]

            await wait(registered)

            async def post(path, body):
                response = await http.post(path, json=body)
                response.raise_for_status()
                return response.json()

            config = {
                "repository": "X-McKay/Starbase2",
                "interval_seconds": 30,
                "enabled": True,
                "removed": False,
                "generation": 0,
            }
            watch = await post("/v4/repositories", config)
            watch_id = watch["id"]
            record(
                "repository_duty_created_without_godot",
                repository=config["repository"],
                watch_id=watch_id,
                core_url=env["STARBASE_CORE"],
                memory=False,
                inference=False,
                credential="existing gh identity; scope not asserted"
                if args.gh_credential
                else "anonymous",
            )

            async def sleeping():
                try:
                    return (
                        await client.get_workflow_handle(
                            "starbase2-field-duty-" + watch_id
                        ).describe()
                    ).status == WorkflowExecutionStatus.RUNNING
                except Exception:
                    return False

            await wait(sleeping)
            await stop(worker)
            worker = start("worker", worker_args)

            async def done():
                runs = (await http.get("/v4/snapshot")).json()["runs"]
                terminal = next(
                    (
                        r
                        for r in runs
                        if r["input"]["target"] == watch_id
                        and r["state"] in {"completed", "failed"}
                    ),
                    None,
                )
                if terminal and terminal["state"] == "failed":
                    raise RuntimeError("Real repository observation failed; inspect private logs")
                return terminal

            run = await wait(done, 150)
            run_id = run["input"]["id"]
            detail = (await http.get("/v4/runs/" + run_id)).json()
            assert not detail["snapshot"]["data"]["simulation"]
            assert detail["report"]["advisory"] is None
            assert detail["report"]["memory"]["records"] == []
            duplicate = await post("/v4/runs", detail["input"])
            assert duplicate == detail
            conflict = await http.post("/v4/runs", json=detail["input"] | {"inference": True})
            assert conflict.status_code in {400, 409}
            # Hold dispatch while creating and cancelling a fresh queued identity.
            await stop(worker)
            cancelled_input = {
                "id": "live-cancel-before-dispatch",
                "agent": "reviewer",
                "target": watch_id,
                "inference": False,
            }
            await post("/v4/runs", cancelled_input)
            await post("/v4/runs/live-cancel-before-dispatch/cancel", {})
            worker = start("worker", worker_args)

            async def cancelled():
                value = (await http.get("/v4/runs/live-cancel-before-dispatch")).json()
                return value if value["state"] == "cancelled" else None

            cancelled_record = await wait(cancelled)
            assert cancelled_record["snapshot"] is None and cancelled_record["report"] is None
            record(
                "cancel_before_dispatch_no_capture",
                state="cancelled",
                snapshot_absent=True,
                report_absent=True,
            )
            await post("/v4/repositories", config | {"enabled": False, "generation": 1})

            async def paused():
                return (
                    await client.get_workflow_handle("starbase2-field-duty-" + watch_id).describe()
                ).status == WorkflowExecutionStatus.CANCELED

            await wait(paused)
            await stop(core)
            core = start("core", [str(ROOT / "target/debug/starbase-core")])
            await wait(ready)
            assert (await http.get("/v4/runs/" + run_id)).json() == detail
            record(
                "real_observation_retained_after_worker_and_core_restart",
                run_id=run_id,
                state=detail["state"],
                snapshot_digest=detail["snapshot"]["digest"],
                findings=len(detail["report"]["findings"]),
                coverage=detail["report"]["coverage"],
                paused=True,
                duplicate_same_record=True,
                changed_duplicate_status=conflict.status_code,
            )
            record(
                "ready_for_native_review",
                core_url=env["STARBASE_CORE"],
                private_output=str(output),
                hold_seconds=args.hold_seconds,
            )
            deadline = time.monotonic() + args.hold_seconds
            while (
                time.monotonic() < deadline
                and not closing.is_set()
                and not (output / "STOP").exists()
            ):
                try:
                    await asyncio.wait_for(closing.wait(), timeout=1)
                except TimeoutError:
                    pass
    finally:
        for child in reversed(children):
            await stop(child)
        for log in logs:
            log.close()
        credential.unlink(missing_ok=True)
        token.unlink(missing_ok=True)
        record("owned_processes_stopped_credentials_removed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--port", type=int, default=18801)
    parser.add_argument("--temporal-port", type=int, default=17251)
    parser.add_argument("--hold-seconds", type=int, default=1800)
    parser.add_argument("--gh-credential", action="store_true")
    asyncio.run(main(parser.parse_args()))
