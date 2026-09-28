"""Complete local practice cycles on real Core/Temporal; explicit --inference uses Qwen."""

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
from starbase_runtime import joint
from starbase_runtime.joint_workflow import ReadinessJoint
from starbase_runtime.learning_workflow import LearningPractice
from temporalio.client import Client
from temporalio.worker import Replayer

ROOT = Path(__file__).resolve().parents[1]


async def main():
    inference = "--inference" in sys.argv
    restart = "--restart" in sys.argv
    out = ROOT / ".local" / ("learning-inference-" if inference else "learning-integration-")
    out = out.with_name(out.name + str(time.time_ns()))
    out.mkdir()
    token = out / "worker-token"
    token.write_text(secrets.token_hex(32))
    token.chmod(0o600)
    env = {k: v for k, v in os.environ.items() if k in {"PATH", "LANG", "TMPDIR"}}
    env.update(
        PYTHONPATH=str(ROOT / "services/runtime"),
        STARBASE_PORT="18893",
        STARBASE_CORE="http://127.0.0.1:18893",
        STARBASE_TEMPORAL="127.0.0.1:17433",
        STARBASE_DB=str(out / "core.sqlite"),
        STARBASE_TOKEN_FILE=str(token),
        STARBASE_JOINT_ENABLED="true",
        STARBASE_LEARNING_ENABLED="true",
        STARBASE_REPAIRS_ENABLED="false",
        STARBASE_LEGACY_ENABLED="false",
    )
    if restart:
        env["STARBASE_LEARNING_CHECKPOINT"] = str(out / "checkpoint")
    processes, logs = [], []

    def save(name, value):
        (out / name).write_text(json.dumps(value, indent=2) + "\n")

    def start(name, argv):
        log = (out / (name + ".log")).open("a")
        logs.append(log)
        p = subprocess.Popen(
            argv, cwd=ROOT, env=env, stdout=log, stderr=log, start_new_session=True
        )
        processes.append(p)
        return p

    async def stop(p, kill=False):
        if p.poll() is None:
            os.killpg(p.pid, signal.SIGKILL if kill else signal.SIGTERM)
            await asyncio.to_thread(p.wait, 15)

    async def wait(fn, seconds=120):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if value := await fn():
                return value
            await asyncio.sleep(0.3)
        raise AssertionError("Timeout; retained evidence at " + str(out))

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
                "17433",
                "--headless",
                "--log-level",
                "error",
                "--db-filename",
                str(out / "temporal.sqlite"),
            ],
        )
        async with httpx.AsyncClient(base_url=env["STARBASE_CORE"], timeout=10) as http:

            async def call(method, path, body=None):
                headers = (
                    {"Authorization": "Bearer " + token.read_text()}
                    if path.startswith("/internal/")
                    else {}
                )
                r = await http.request(method, path, json=body, headers=headers)
                assert r.status_code == 200, (path, r.status_code, r.text)
                return r.json()

            async def ready():
                try:
                    return (await http.get("/")).status_code == 200
                except httpx.TransportError:
                    return False

            async def temporal_ready():
                try:
                    return await Client.connect(env["STARBASE_TEMPORAL"])
                except RuntimeError:
                    return None

            await wait(ready)
            client = await wait(temporal_ready)
            baseline = joint.build(inference)
            await call("POST", "/internal/v5/builds", baseline)
            seed_sources = []
            if inference:
                # Import exact historical public trial replies before starting any worker.
                # These are identified as earlier-build evidence, not fresh provider calls.
                directory = (
                    ROOT
                    / "evidence/autonomous-rpg-20260927/trials/joint-inference-1790552491181802000"
                )
                for scenario in ("healthy", "persistent-dependency", "listening-but-broken"):
                    path = directory / (scenario + ".json")
                    old = json.loads(path.read_text())
                    await call("POST", "/internal/v5/builds", old["build"])
                    mission_id = "historical-" + scenario
                    input = old["input"] | {"id": mission_id, "opportunity": "retained-" + scenario}
                    await call("POST", "/v5/missions", input)
                    for task in old["tasks"]:
                        base = f"/internal/v5/missions/{mission_id}"
                        await call("POST", base + "/reserve", task["reservation"])
                        await call("POST", base + f"/tasks/{task['id']}/claim", {})
                        await call("POST", base + f"/tasks/{task['id']}/result", task["result"])
                    await call("POST", base + "/finish", old["finish"])
                    seed_sources.append(
                        {
                            "path": str(path.relative_to(ROOT)),
                            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                            "replayed_id": mission_id,
                        }
                    )
            else:
                await call(
                    "POST",
                    "/v5/missions",
                    {
                        "id": "authored-failure",
                        "opportunity": "control-failure",
                        "build": baseline["digest"],
                        "scenario": "healthy",
                        "inference": False,
                        "budget": {"requests": 12, "tokens": 384000},
                    },
                )
                base = "/internal/v5/missions/authored-failure"
                await call(
                    "POST",
                    base + "/reserve",
                    {
                        "id": "r0-lead",
                        "role": "lead",
                        "focus": "overview",
                        "round": 0,
                        "question": "Authored malformed-response seed; not a model-quality result",
                        "tokens": 32768,
                    },
                )
                await call("POST", base + "/tasks/r0-lead/claim", {})
                await call(
                    "POST",
                    base + "/tasks/r0-lead/result",
                    {
                        "status": "failed",
                        "output": None,
                        "usage": {"input_tokens": 1, "output_tokens": 1},
                        "error": "UnexpectedModelBehavior",
                    },
                )
                await call(
                    "POST",
                    base + "/finish",
                    {
                        "decision": None,
                        "reason": "Authored integration failure seed; no provider call",
                    },
                )
            duty = {
                "id": "readiness-practice",
                "generation": 0,
                "enabled": True,
                "baseline": baseline["digest"],
                "max_cycles": 1,
                "cooldown_seconds": 60,
            }
            save(
                "declaration.json",
                {
                    "baseline": baseline,
                    "duty": duty,
                    "seeds": seed_sources,
                    "inference": inference,
                    "population": "four public paired cases; candidate proposed once before trials",
                    "scope": "exploratory practice adoption only; no held-out qualification, "
                    "XP or production authority",
                    "stopping_rule": "one bounded cycle once; no replacement of failed trials",
                    "restart_checkpoint": restart,
                    "primary_metric": "Core diagnostic pass count on four paired public cases",
                    "practice_margin": "4/4 candidate passes, baseline lower, no pair regression",
                    "hard_gates": "known usage; budget; identity; policy; complete valid trials",
                    "invalid_trials": "retained; unknown, infrastructure or cancellation "
                    "blocks adoption",
                    "uncertainty": "one trial per case; exploratory, no superiority inference",
                    "model_provenance": "configured local endpoint/model alias; served weight "
                    "digest and concurrent provider load unverified",
                    "output_ceiling": 8192,
                    "historical_limit": "source evidence used 2048 output tokens; historical "
                    "scores are not the comparison baseline",
                },
            )
            for name, digest in baseline["manifest"]["sources"].items():
                data = (ROOT / name).read_bytes()
                assert hashlib.sha256(data).hexdigest() == digest
                path = out / "frozen-sources" / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            provenance = {}
            for name in (
                "scripts/learning_integration.py",
                "scripts/learning_worker_fixture.py",
                "services/core/src/learning.rs",
                "services/core/src/joint.rs",
                "services/core/src/joint_opportunities.rs",
                "target/debug/starbase-core",
            ):
                data = (ROOT / name).read_bytes()
                provenance[name] = hashlib.sha256(data).hexdigest()
                if not name.startswith("target/"):
                    path = out / "frozen-sources" / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(data)
            save("harness-grader-provenance.json", provenance)
            await call("POST", "/v6/duty", duty)
            worker = start(
                "worker", [sys.executable, str(ROOT / "scripts/learning_worker_fixture.py")]
            )

            async def cycles():
                return (await call("GET", "/v6/snapshot"))["cycles"]

            admitted = (await wait(cycles))[0]
            save("cycle-declaration.json", admitted)
            print("Cycle admitted:", admitted["id"], flush=True)
            if restart:

                async def checkpoint():
                    return (out / "checkpoint").exists()

                await wait(checkpoint)
                await stop(worker, True)
                await stop(core)
                core = start("core", [str(ROOT / "target/debug/starbase-core")])
                await wait(ready)
                worker = start(
                    "worker", [sys.executable, str(ROOT / "scripts/learning_worker_fixture.py")]
                )

            async def terminal_cycle():
                c = await call("GET", "/v6/cycles/" + admitted["id"])
                save("cycle-latest.json", c)
                return c if c["state"] in {"completed", "failed", "cancelled"} else None

            result = await wait(terminal_cycle, 6900 if inference else 300)
            save("cycle.json", result)
            retained_trials = 0
            for trial in result["trials"]:
                r = await http.get("/v5/missions/" + trial["mission_id"])
                if r.status_code != 200:
                    continue
                retained_trials += 1
                save(trial["slot"] + ".json", r.json())
                history = await client.get_workflow_handle(
                    "starbase2-joint-" + trial["mission_id"]
                ).fetch_history()
                (out / (trial["slot"] + "-history.json")).write_text(history.to_json())
                await Replayer(workflows=[ReadinessJoint]).replay_workflow(history)
            handle = client.get_workflow_handle("starbase2-learning-" + admitted["id"])
            await handle.result()
            history = await handle.fetch_history()
            (out / "cycle-history.json").write_text(history.to_json())
            await Replayer(workflows=[LearningPractice]).replay_workflow(history)
            snapshot = await call("GET", "/v6/snapshot")
            save("snapshot.json", snapshot)
            tick = await call("POST", "/internal/v6/duty/0/tick", {})
            assert tick["outcome"] == "exhausted"
            assert len(snapshot["cycles"]) == 1
            if not inference:
                assert result["summary"]["outcome"] == "inconclusive", result
                assert result["summary"]["candidate_passes"] == 4
            if not inference:
                # Separate authored recovery case: cancellation after claim, before reply.
                # No model request is made; unknown accounting is intentionally conservative.
                await stop(worker)
                await call("POST", "/v6/duty", duty | {"generation": 1})
                cancelled = (await call("POST", "/internal/v6/duty/1/tick", {}))["cycle"]
                cancel_id = cancelled["id"]
                await call("POST", f"/internal/v6/cycles/{cancel_id}/proposal/claim", {})
                await client.start_workflow(
                    LearningPractice.run,
                    cancel_id,
                    id="starbase2-learning-" + cancel_id,
                    task_queue="learning-integration",
                )
                await call("POST", f"/v6/cycles/{cancel_id}/cancel", {})
                worker = start(
                    "worker", [sys.executable, str(ROOT / "scripts/learning_worker_fixture.py")]
                )

                async def accounted_cancellation():
                    c = await call("GET", "/v6/cycles/" + cancel_id)
                    return c if c["proposal"]["state"] == "unknown" else None

                cancelled = await wait(accounted_cancellation)
                assert cancelled["state"] == "cancelled"
                assert cancelled["candidate"] is None
                assert cancelled["proposal"]["accounted_tokens"] == 32768
                save("cancelled-claimed-proposal.json", cancelled)
                cancelled_history = await client.get_workflow_handle(
                    "starbase2-learning-" + cancel_id
                ).fetch_history()
                (out / "cancelled-history.json").write_text(cancelled_history.to_json())
                await Replayer(workflows=[LearningPractice]).replay_workflow(cancelled_history)
                print(
                    "Cancelled claimed proposal accounted; no candidate or redispatch.", flush=True
                )
            if not inference:
                # Stop with an admitted child but no parent/child workflow created.
                await stop(worker)
                await call("POST", "/v6/duty", duty | {"generation": 2})
                stranded = (await call("POST", "/internal/v6/duty/2/tick", {}))["cycle"]
                stranded_id = stranded["id"]
                await call("POST", f"/internal/v6/cycles/{stranded_id}/proposal/claim", {})
                await call(
                    "POST",
                    f"/internal/v6/cycles/{stranded_id}/proposal/result",
                    result["proposal"]["result"],
                )
                child = await call(
                    "POST",
                    f"/internal/v6/cycles/{stranded_id}/trials/"
                    + stranded["trial_order"][0]
                    + "/admit",
                    {},
                )
                await call("POST", "/v6/duty", duty | {"generation": 3, "enabled": False})
                await stop(core)
                env["STARBASE_JOINT_ENABLED"] = "false"
                core = start("core", [str(ROOT / "target/debug/starbase-core")])
                await wait(ready)
                worker = start(
                    "worker", [sys.executable, str(ROOT / "scripts/learning_worker_fixture.py")]
                )

                async def stopped_without_workflow():
                    c = await call("GET", "/v6/cycles/" + stranded_id)
                    return c if c["state"] == "cancelled" else None

                stopped = await wait(stopped_without_workflow)
                child = await call("GET", "/v5/missions/" + child["input"]["id"])
                assert child["state"] == "cancelled" and not child["tasks"]
                save("stopped-before-workflow.json", {"cycle": stopped, "child": child})
                print(
                    "Disabled queued cycle and child settled without workflow creation.", flush=True
                )
            print(json.dumps(result["summary"], indent=2), flush=True)
            print(
                f"Bounded attempt and replay finished; {retained_trials}/8 trials retained; "
                "no duplicate cycle after tick.",
                flush=True,
            )
    finally:
        for p in reversed(processes):
            await stop(p)
        for log in logs:
            log.close()
        print("Evidence:", out, flush=True)


if __name__ == "__main__":
    asyncio.run(main())
