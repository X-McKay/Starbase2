"""Real Core/runtime coordination with synthetic model, provider and VM adapters.

Repository source is read as data, never executed on the host. No GitHub effects.
"""

import asyncio
import json
import os
import secrets
import signal
import socket
import subprocess
import time
from pathlib import Path
from unittest.mock import patch

import httpx

ROOT = Path(__file__).resolve().parents[1]
HARNESS = Path(__file__).read_bytes()
FAMILIES = ["persistence-history", "memory-key", "logging-level"]
VALUES = {
    "persistence-history": {
        "history_all": [0, 1, 2, 3, 4],
        "history_last3": [2, 3, 4],
        "history_last1": [4],
        "history_zero": [],
        "history_empty": [],
        "history_context": [9],
        "history_mixed": [0, 1, 2, 3, 4],
    },
    "memory-key": {
        "memory_empty_key": [7],
        "memory_named": [9],
        "memory_missing": [],
        "memory_other_agent": [11],
        "memory_all": [7, 9],
        "memory_zero": [0],
    },
    "logging-level": {
        "logging_initial": [10],
        "logging_update": [20],
        "logging_error": [40],
        "logging_handlers": [1],
        "logging_omitted": [40],
        "logging_other": [30],
    },
}


async def main():
    output = ROOT / ".local" / ("sdlc-coordination-integration-" + str(time.time_ns()))
    output.mkdir(mode=0o700)
    (output / "harness.py").write_bytes(HARNESS)
    token = output / "worker-token"
    token.write_text(secrets.token_hex(32))
    token.chmod(0o600)
    port = 18919
    processes, logs, events, roles = [], [], [], []

    def record(name, **data):
        events.append({"event": name, "synthetic_external_controls": True, **data})
        (output / "events.json").write_text(json.dumps(events, indent=2) + "\n")
        print(name, data, flush=True)

    environment = {k: v for k, v in os.environ.items() if k in {"PATH", "LANG", "TMPDIR"}}
    environment.update(
        PYTHONPATH=str(ROOT / "services/runtime"),
        STARBASE_PORT=str(port),
        STARBASE_CORE=f"http://127.0.0.1:{port}",
        STARBASE_TOKEN_FILE=str(token),
        STARBASE_DB=str(output / "core.sqlite"),
        STARBASE_SDLC_ENABLED="true",
        STARBASE_SDLC_REPOSITORY="X-McKay/algent",
        STARBASE_FIELD_ENABLED="false",
        STARBASE_LEGACY_ENABLED="false",
        STARBASE_REPAIRS_ENABLED="false",
        STARBASE_JOINT_ENABLED="false",
        STARBASE_LEARNING_ENABLED="false",
    )

    def start_core():
        log = (output / "core.log").open("a")
        logs.append(log)
        process = subprocess.Popen(
            [str(ROOT / "target/debug/starbase-core")],
            cwd=ROOT,
            env=environment,
            stdout=log,
            stderr=log,
            start_new_session=True,
        )
        processes.append(process)
        return process

    async def stop(process):
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            await asyncio.to_thread(process.wait, 15)

    async def ready():
        async with httpx.AsyncClient(trust_env=False, timeout=1) as client:
            for _ in range(100):
                try:
                    response = await client.get(environment["STARBASE_CORE"] + "/")
                    if response.status_code == 200:
                        return
                except httpx.TransportError:
                    pass
                await asyncio.sleep(0.1)
        raise AssertionError("Core startup timed out")

    async def operator_post(path, body):
        async with httpx.AsyncClient(
            base_url=environment["STARBASE_CORE"], trust_env=False
        ) as client:
            await client.get("/")
            response = await client.post(path, json=body)
            assert response.status_code == 200, response.text
            return response.json()

    try:
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", port))
        with patch.dict(os.environ, environment, clear=True):
            from starbase_runtime import sdlc_pilot as pilot
            from starbase_runtime import sdlc_runtime as runtime
            from starbase_runtime.operations import request
            from starbase_runtime.review import digest

            original = {
                path: (ROOT / ".local/algent-inspection" / path).read_text() for path in pilot.FILES
            }
            state: dict = {"revision": "a" * 40, "files": original, "provider_down": False}
            attempts = {}
            real_build = pilot.build

            def build(opportunity=pilot.OPPORTUNITY):
                value = real_build(opportunity)
                value["manifest"]["synthetic_coordination_fixture"] = digest(
                    Path(__file__).read_text()
                )
                value["digest"] = digest(value["manifest"])
                return value

            async def revision():
                if state["provider_down"]:
                    raise ConnectionError("Synthetic bounded provider interruption")
                return "main", state["revision"]

            async def capture(sha):
                assert sha == state["revision"]
                return dict(state["files"])

            def edit(family):
                if family == "persistence-history":
                    return {
                        "path": pilot.SOURCE,
                        "old": "ORDER BY timestamp DESC",
                        "new": "ORDER BY timestamp DESC, id DESC",
                    }
                if family == "memory-key":
                    return {
                        "path": pilot.SOURCE,
                        "old": "if memory_key:",
                        "new": "if memory_key is not None:",
                    }
                return {
                    "path": "src/utils/logging.py",
                    "old": "    return logger",
                    "new": (
                        "    if level is not None:\n"
                        "        logger.setLevel(getattr(logging, level))\n    return logger"
                    ),
                }

            async def member(role, context):
                family = context["capability"]["opportunity"]
                roles.append(
                    {"family": family, "role": role, "crew": context["assignment"]["crew"]}
                )
                (output / "roles.json").write_text(json.dumps(roles, indent=2))
                if role == "lead":
                    value = {
                        "decision": "implement",
                        "rationale": "Synthetic control",
                        "task": family,
                    }
                elif role == "implementer":
                    attempts[family] = attempts.get(family, 0) + 1
                    if family == "persistence-history":
                        change = edit(family)
                    else:
                        assert context["edit_format"] == "line-blocks"
                        target = "if memory_key:" if family == "memory-key" else "return logger"
                        matches = [
                            row for row in context["source"] if row["text"].strip() == target
                        ]
                        assert len(matches) == 1
                        lines = (
                            ["if memory_key is not None:"]
                            if family == "memory-key"
                            else [
                                "if level is not None:",
                                "    logger.setLevel(getattr(logging, level))",
                                "return logger",
                            ]
                        )
                        line = matches[0]["line"]
                        if family == "memory-key" and attempts[family] == 1:
                            line = 9999
                        change = {"line": line, "lines": lines}
                    value = {"rationale": "Synthetic control", "edits": [change]}
                else:
                    value = {"status": "accept", "rationale": "Synthetic independent reviewer"}
                return {
                    "role": role,
                    "output": value,
                    "usage": {},
                    "elapsed_ms": 0,
                    "model": "synthetic",
                }

            async def sandbox(name, files, run):
                family = run["input"]["opportunity"]
                values = dict(VALUES[family])
                change = edit(family)
                if change["new"] not in files[change["path"]]:
                    values[next(iter(values))] = [-1]
                return {
                    "exit_code": 0,
                    "cases": [{"id": k, "actual": v} for k, v in values.items()],
                    "synthetic": True,
                }

            core = start_core()
            await ready()
            await operator_post(
                "/v7/policy",
                {
                    "repository": "X-McKay/algent",
                    "enabled": True,
                    "publish": False,
                    "generation": 0,
                    "max_missions": 3,
                    "expires_at": time.time() + 900,
                },
            )
            with (
                patch.multiple(
                    pilot, revision=revision, capture=capture, member=member, build=build
                ),
                patch.object(runtime, "sandbox_run", sandbox),
            ):
                accepted = []
                for index, family in enumerate(FAMILIES):
                    snapshot = await runtime.discover_catalog(
                        await request("GET", "/internal/v7/snapshot")
                    )
                    active = [m for m in snapshot["missions"] if m["state"] not in runtime.TERMINAL]
                    assert len(active) == 1 and active[0]["input"]["opportunity"] == family
                    run = active[0]
                    identity = run["id"]
                    duplicate = await runtime.discover_catalog(snapshot)
                    assert len(duplicate["missions"]) == index + 1
                    assert len(duplicate["discoveries"]) == 3
                    if index == 0:
                        await stop(core)
                        core = start_core()
                        await ready()
                        restored = await request("GET", "/v7/missions/" + identity)
                        assert restored["input"] == run["input"] and restored["state"] == "queued"
                        record("core-restart-queued-input-preserved", mission=identity)
                    await runtime.sdlc_prepare(identity)
                    lead = await runtime.sdlc_lead(identity)
                    assert lead["continue"]
                    implementation = {"id": identity, "round": 0, "lead": lead["lead"]}
                    test = await runtime.sdlc_implement(implementation)
                    review = await runtime.sdlc_review({"id": identity, "round": 0})
                    if family == "memory-key":
                        assert test["verdict"] == "ineligible" and test["candidate"]["not_executed"]
                        assert not review["accepted"] and review["continue"]
                        reassigned = await request("GET", "/v7/missions/" + identity)
                        assert reassigned["coordination"]["assignments"][1]["crew"] == "moss"
                        test = await runtime.sdlc_implement(
                            implementation | {"round": 1, "feedback": review["feedback"]}
                        )
                        review = await runtime.sdlc_review({"id": identity, "round": 1})
                    assert review["accepted"] and test["verdict"] == "improved"
                    verified = await request("GET", "/v7/missions/" + identity)
                    assert (
                        verified["state"] == "ready_to_publish" and verified["publication"] is None
                    )
                    accepted.append(family)
                    (output / f"{family}-verified.json").write_text(json.dumps(verified, indent=2))
                    # Declared operator intervention: terminate before publication; not completion.
                    await operator_post(f"/v7/missions/{identity}/cancel", {})
                    stopped = await runtime.sdlc_abort(identity)
                    assert stopped["state"] == "cancelled" and stopped["publication"] is None
                    record("verified-then-operator-cancelled", family=family, mission=identity)
                corrected = dict(original)
                for family in FAMILIES:
                    change = edit(family)
                    corrected[change["path"]] = corrected[change["path"]].replace(
                        change["old"], change["new"], 1
                    )
                state.update(revision="b" * 40, files=corrected)
                healthy = await runtime.discover_catalog(
                    await request("GET", "/internal/v7/snapshot")
                )
                assert len(healthy["missions"]) == 3
                assert sum(d["outcome"] == "no_change" for d in healthy["discoveries"]) == 3
                state["provider_down"] = True
                outage = await runtime.discover_catalog(healthy)
                assert len(outage["missions"]) == 3
                assert sum(d["outcome"] == "unavailable" for d in outage["discoveries"]) == 3
                state["provider_down"] = False
                recovered = await runtime.discover_catalog(outage)
                assert len(recovered["missions"]) == 3 and len(recovered["discoveries"]) == 9
                assert all(
                    m["state"] == "cancelled" and m["publication"] is None
                    for m in recovered["missions"]
                )
                (output / "snapshot.json").write_text(json.dumps(recovered, indent=2))
                assert [
                    r["crew"]
                    for r in roles
                    if r["family"] == "memory-key" and r["role"] == "implementer"
                ] == ["rivet", "moss"]
                record(
                    "complete",
                    families=accepted,
                    priority_order=FAMILIES,
                    reassignment=True,
                    no_change_dispatches=0,
                    unavailable_dispatches=0,
                    duplicate_missions=0,
                    external_effects=0,
                    operator_cancellations=3,
                    verified_not_published=3,
                    temporal="not_exercised",
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
