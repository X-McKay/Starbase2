"""Local Qwen/microVM development probes; Core grades, and no provider write is made."""

import argparse
import asyncio
import json
import os
import secrets
import socket
import time
from pathlib import Path
from unittest.mock import patch

import httpx
from starbase_runtime import sdlc_pilot as pilot
from starbase_runtime import sdlc_runtime as runtime
from starbase_runtime import sdlc_verification as verification

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = Path(__file__).read_bytes()


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--family", choices=["persistence-history", "memory-key", "logging-level"])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    families = [args.family] if args.family else ["memory-key", "logging-level"]
    output = args.output or ROOT / ".local" / ("sdlc-family-probe-" + str(time.time_ns()))
    output.mkdir()
    (output / "probe.py").write_bytes(SCRIPT)
    token = output / "worker-token"
    token.write_text(secrets.token_hex(32))
    token.chmod(0o600)
    with socket.socket() as port_probe:
        port_probe.bind(("127.0.0.1", 0))
        port = port_probe.getsockname()[1]
    origin = f"http://127.0.0.1:{port}"
    env = os.environ | {
        "STARBASE_PORT": str(port),
        "STARBASE_DB": str(output / "core.sqlite"),
        "STARBASE_TOKEN_FILE": str(token),
        "STARBASE_SDLC_ENABLED": "true",
        "STARBASE_SDLC_REPOSITORY": pilot.REPOSITORY,
        "STARBASE_ACCEPT_WORK": "true",
    }
    os.environ.update(STARBASE_TOKEN_FILE=str(token), STARBASE_CORE=origin)
    files = {name: (ROOT / ".local/algent-inspection" / name).read_text() for name in pilot.FILES}

    # Only capture is replaced by a retained source checkout; Qwen, sandbox,
    # Core admission/grading and runtime activities execute normally.
    async def capture(_sha):
        return dict(files)

    rows = []
    with (output / "core.log").open("w") as log:
        process = await asyncio.create_subprocess_exec(
            str(ROOT / "target/debug/starbase-core"), env=env, stdout=log, stderr=log
        )
        try:
            async with httpx.AsyncClient(base_url=origin, timeout=5) as http:
                for _ in range(100):
                    try:
                        response = await http.get("/")
                        response.raise_for_status()
                        break
                    except httpx.HTTPError:
                        await asyncio.sleep(0.05)
                else:
                    raise RuntimeError("Probe Core unavailable")
                response = await http.post(
                    "/v7/policy",
                    json={
                        "repository": pilot.REPOSITORY,
                        "enabled": True,
                        "publish": False,
                        "generation": 0,
                        "max_missions": 3,
                        "expires_at": time.time() + 1800,
                    },
                )
                response.raise_for_status()
                with patch.object(pilot, "capture", capture):
                    for family in families:
                        identity = "probe-" + family
                        cap = pilot.sdlc_capabilities.contract_for(pilot.REPOSITORY, family)
                        await runtime.request(
                            "POST",
                            "/internal/v7/missions",
                            {
                                "id": identity,
                                "repository": pilot.REPOSITORY,
                                "revision": "2f8e9fef0b8b4b16c8641a0409eb532c22fab8b4",
                                "opportunity": family,
                                "build": pilot.build(family),
                                "capability_digest": cap["digest"],
                            },
                        )
                        outcome = {
                            "family": family,
                            "real_model": True,
                            "real_microvm": True,
                            "publication": False,
                            "qualification": "development probe, not held-out reliability",
                        }
                        try:
                            async with asyncio.timeout(800):
                                await runtime.sdlc_prepare(identity)
                                lead = await runtime.sdlc_lead(identity)
                                feedback = None
                                accepted = False
                                if lead["continue"]:
                                    for number in range(3):
                                        tested = await runtime.sdlc_implement(
                                            {
                                                "id": identity,
                                                "round": number,
                                                "lead": lead["lead"],
                                                "feedback": feedback,
                                            }
                                        )
                                        reviewed = await runtime.sdlc_review(
                                            {"id": identity, "round": number}
                                        )
                                        if reviewed["accepted"]:
                                            public = await verification.public_tests(
                                                "sb-probe-public-" + family,
                                                tested["candidate_files"],
                                                family,
                                            )
                                            accepted = public["exit_code"] == 0
                                            outcome["public"] = public
                                            break
                                        if not reviewed["continue"]:
                                            break
                                        feedback = reviewed["feedback"]
                                outcome["candidate_verified"] = accepted
                        except Exception as error:
                            outcome["error_type"] = type(error).__name__
                            if isinstance(error, pilot.MemberFailure):
                                await runtime.event(
                                    identity, "model-failed", "blocked", error.evidence
                                )
                        value = await runtime.request("GET", "/v7/missions/" + identity)
                        outcome["mission"] = value
                        rows.append(outcome)
                        (output / "results.json").write_text(json.dumps(rows, indent=2) + "\n")
                        print(
                            family,
                            "candidate_verified",
                            outcome.get("candidate_verified", False),
                            flush=True,
                        )
                        # End local mission explicitly before any publication; keep all evidence.
                        if value["state"] not in runtime.TERMINAL:
                            (
                                await http.post(f"/v7/missions/{identity}/cancel", json={})
                            ).raise_for_status()
                            await runtime.sdlc_abort(identity)
        finally:
            process.terminate()
            await asyncio.wait_for(process.wait(), 10)
    print("Evidence:", output, flush=True)
    if not all(row.get("candidate_verified") for row in rows) or len(rows) != len(families):
        raise SystemExit("At least one development probe failed; all attempts retained")


if __name__ == "__main__":
    asyncio.run(main())
