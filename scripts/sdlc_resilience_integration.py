"""Real Core and trusted adapters; synthetic GitHub/model/VM failure controls.

No live credentials, provider calls or repository code execution. Temporal is not
exercised here; its restart/replay control remains sdlc_integration.py.
"""

import asyncio
import json
import os
import runpy
import secrets
import signal
import socket
import subprocess
import time
from pathlib import Path
from unittest.mock import patch

import httpx
from temporalio.exceptions import ApplicationError

ROOT = Path(__file__).resolve().parents[1]
HARNESS = Path(__file__).read_bytes()


def start_core(env, log):
    return subprocess.Popen(
        [str(ROOT / "target/debug/starbase-core")],
        env=env,
        stdout=log,
        stderr=log,
        start_new_session=True,
    )


async def main():
    output = ROOT / ".local" / f"sdlc-resilience-integration-{time.time_ns()}"
    output.mkdir(mode=0o700)
    (output / "harness.py").write_bytes(HARNESS)
    token = output / "worker-token"
    token.write_text(secrets.token_hex(32))
    token.chmod(0o600)
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    env = {k: v for k, v in os.environ.items() if k in {"PATH", "LANG", "TMPDIR"}}
    env.update(
        STARBASE_PORT=str(port),
        STARBASE_CORE=f"http://127.0.0.1:{port}",
        STARBASE_DB=str(output / "core.sqlite"),
        STARBASE_TOKEN_FILE=str(token),
        STARBASE_SDLC_ENABLED="true",
        STARBASE_SDLC_VERIFICATION_ENABLED="true",
        STARBASE_SDLC_REPOSITORY="X-McKay/algent",
        STARBASE_SDLC_CONTROL_DIR=str(output),
    )
    events = []
    process = None
    log = (output / "core.log").open("w")

    def record(name, **data):
        events.append({"event": name, "synthetic_external_controls": True, **data})
        (output / "events.json").write_text(json.dumps(events, indent=2) + "\n")
        print(name, data, flush=True)

    try:
        with patch.dict(os.environ, env, clear=True):
            from starbase_runtime import sdlc_feedback as feedback
            from starbase_runtime import sdlc_pilot as pilot
            from starbase_runtime import sdlc_revision_publish as revision
            from starbase_runtime import sdlc_runtime as runtime
            from starbase_runtime import sdlc_sandbox
            from starbase_runtime.operations import request
            from starbase_runtime.review import digest
            from starbase_runtime.sdlc_publish import PublicationUnknown

            fixture = runpy.run_path(str(ROOT / "scripts/sdlc_worker_fixture.py"))
            (output / "worker-fixture.py").write_bytes(
                (ROOT / "scripts/sdlc_worker_fixture.py").read_bytes()
            )
            process = start_core(env, log)
            async with httpx.AsyncClient(
                base_url=env["STARBASE_CORE"], trust_env=False
            ) as operator:
                for _ in range(100):
                    try:
                        if (await operator.get("/")).status_code == 200:
                            break
                    except httpx.TransportError:
                        pass
                    await asyncio.sleep(0.1)
                else:
                    raise AssertionError("Core unavailable")

                async def command(path, body):
                    response = await operator.post(path, json=body)
                    assert response.status_code == 200, response.text
                    return response.json()

                await command(
                    "/v7/policy",
                    {
                        "repository": "X-McKay/algent",
                        "enabled": True,
                        "publish": True,
                        "generation": 0,
                        "max_missions": 3,
                        "expires_at": time.time() + 600,
                    },
                )
                with (
                    patch.multiple(
                        pilot,
                        build=fixture["build"],
                        capture=fixture["capture"],
                        member=fixture["member"],
                    ),
                    patch.object(sdlc_sandbox, "run", fixture["sandbox"]),
                ):
                    build = pilot.build()
                    mission_input = {
                        "id": "resilience-parent",
                        "repository": pilot.REPOSITORY,
                        "revision": fixture["REVISION"],
                        "opportunity": pilot.OPPORTUNITY,
                        "build": build,
                        "capability_digest": pilot.CAPABILITY["digest"],
                    }
                    await request("POST", "/internal/v7/missions", mission_input)
                    await runtime.sdlc_prepare(mission_input["id"])
                    lead = await runtime.sdlc_lead(mission_input["id"])
                    await runtime.sdlc_implement(
                        {"id": mission_input["id"], "round": 0, "lead": lead["lead"]}
                    )
                    assert (await runtime.sdlc_review({"id": mission_input["id"], "round": 0}))[
                        "accepted"
                    ]
                    parent = await request("GET", "/v7/missions/" + mission_input["id"])
                    receipt = await fixture["publish"](
                        parent, parent["evidence"]["testing"]["candidate_files"]
                    )
                    await runtime.event(parent["id"], "submitted", "submitted", receipt)
                    await runtime.sdlc_finish(
                        {"id": parent["id"], "ci": {"status": "passed", "synthetic": True}}
                    )
                    parent = await request("GET", "/v7/missions/" + parent["id"])
                    core = f"/internal/v7/missions/{parent['id']}"
                    head = receipt["head"]
                    provider: dict = {
                        "head": head,
                        "statuses": [],
                        "writes": 0,
                        "lose": False,
                        "drift": False,
                    }

                    def http(req):
                        path = req.url.path.removeprefix("/repos/x-mckay/algent")
                        assert path != req.url.path
                        if req.method == "GET":
                            if path == "":
                                value = {"default_branch": "main"}
                            elif path.startswith("/pulls/"):
                                value = {
                                    "number": receipt["number"],
                                    "state": "open",
                                    "merged": False,
                                    "head": {
                                        "sha": provider["head"],
                                        "ref": receipt["branch"],
                                        "repo": {"full_name": pilot.REPOSITORY},
                                    },
                                    "base": {
                                        "ref": "main",
                                        "repo": {"full_name": pilot.REPOSITORY},
                                    },
                                }
                            elif path.endswith("/statuses"):
                                value = provider["statuses"]
                            else:
                                raise AssertionError(path)
                            return httpx.Response(200, json=value)
                        assert req.method == "POST" and path == f"/statuses/{head}"
                        provider["writes"] += 1
                        value = json.loads(req.content) | {"id": provider["writes"]}
                        provider["statuses"].append(value)
                        if provider["lose"]:
                            provider["lose"] = False
                            raise httpx.ReadTimeout("Synthetic lost acknowledgement", request=req)
                        return httpx.Response(201, json=value)

                    async def finish_child(child):
                        await command(
                            f"/v7/missions/{parent['id']}/verifications/{child['id']}/cancel", {}
                        )
                        return await request(
                            "POST",
                            core + f"/verifications/{child['id']}/event",
                            {"key": "cancel", "stage": "cancelled", "data": {"synthetic": True}},
                        )

                    # Trusted classifier + Core admission with synthetic model proposals.
                    for state in ("stale", "conflicting", "current"):
                        captured = {
                            "head": head,
                            "lifecycle": "open",
                            "coverage": "complete",
                            "comments": [
                                {
                                    "id": "review:1",
                                    "kind": "review",
                                    "body": state,
                                    "updated_at": "2026-09-28T00:00:00Z",
                                    "state": "stale" if state == "stale" else "current",
                                    "head": "b" * 40 if state == "stale" else head,
                                    "path": pilot.SOURCE,
                                }
                            ],
                        }
                        captured["digest"] = digest(captured)
                        proposal = feedback.classify(
                            captured,
                            {
                                "state": state,
                                "rationale": "Synthetic control",
                                "comment_ids": ["review:1"],
                                "paths": [pilot.SOURCE] if state == "current" else [],
                                "task": "Repair observed regression" if state == "current" else "",
                            },
                            pilot.CAPABILITY,
                        )
                        await request(
                            "POST",
                            core + "/feedback",
                            {
                                "head": head,
                                "digest": captured["digest"],
                                "captured": captured,
                                "proposal": {"role": "feedback", "output": proposal},
                                "observed_at": time.time(),
                            },
                        )
                        body = {
                            "id": "verify-" + state,
                            "head": head,
                            "build": build,
                            "feedback_digest": captured["digest"],
                        }
                        if state != "current":
                            try:
                                await request("POST", core + "/verifications", body)
                            except ApplicationError as exc:
                                assert "not actionable" in str(exc)
                            else:
                                raise AssertionError("Non-actionable feedback admitted")
                        else:
                            child = await request("POST", core + "/verifications", body)
                            assert child["feedback"]["digest"] == captured["digest"]
                            await finish_child(child)
                        record("feedback-" + state, admitted=state == "current")

                    with patch.object(
                        pilot,
                        "client",
                        lambda: httpx.AsyncClient(
                            base_url="https://api.github.com", transport=httpx.MockTransport(http)
                        ),
                    ):
                        child = await request(
                            "POST",
                            core + "/verifications",
                            {"id": "verify-lost-ack", "head": head, "build": build},
                        )
                        provider["lose"] = True
                        try:
                            await revision.status(parent, child, True)
                        except PublicationUnknown:
                            pass
                        else:
                            raise AssertionError("Lost response was not uncertain")
                        result = await revision.status(parent, child, True)
                        assert result["id"] == 1 and provider["writes"] == 1
                        stopped = await finish_child(child)
                        assert len(stopped["effects"]) == 1 and stopped["cancel_requested"]
                        try:
                            await revision.status(parent, child, True)
                        except ApplicationError:
                            pass
                        else:
                            raise AssertionError("Cancelled effect was authorized")
                        assert provider["writes"] == 1
                        record(
                            "lost-ack-reconciled-and-cancel-fenced",
                            mutable_requests=1,
                            retained_claims=1,
                        )
                        child = await request(
                            "POST",
                            core + "/verifications",
                            {
                                "id": "verify-drift",
                                "head": head,
                                "build": build | {"digest": "d" * 64},
                            },
                        )

                        async def drift_request(method, path, body):
                            result = await request(method, path, body)
                            if path.endswith("/effect"):
                                provider["head"] = "e" * 40
                            return result

                        with patch.object(revision, "request", drift_request):
                            try:
                                await revision.status(parent, child, True)
                            except ValueError as exc:
                                assert "head changed" in str(exc)
                            else:
                                raise AssertionError("Head drift not fenced")
                        assert provider["writes"] == 1
                        await finish_child(child)
                        record("head-drift-after-claim-fenced", additional_mutable_requests=0)

                    # Cancel while runtime activities await model and sandbox adapters.
                    await request(
                        "POST",
                        core + "/pr-observation",
                        {
                            "number": receipt["number"],
                            "head": head,
                            "state": "closed",
                            "observed_at": time.time(),
                        },
                    )
                    for phase, revision_sha in (("model", "b" * 40), ("test", "c" * 40)):
                        second = mission_input | {
                            "id": "resilience-cancel-" + phase,
                            "revision": revision_sha,
                        }
                        await request("POST", "/internal/v7/missions", second)
                        started, release = asyncio.Event(), asyncio.Event()

                        async def captured(sha):
                            return await fixture["capture"](fixture["REVISION"])

                        async def delayed_member(role, context, started=started, release=release):
                            started.set()
                            await release.wait()
                            return await fixture["member"](role, context)

                        async def delayed_test(name, files, started=started, release=release):
                            started.set()
                            await release.wait()
                            return await fixture["sandbox"](name, files)

                        with patch.object(pilot, "capture", captured):
                            if phase == "model":
                                await runtime.sdlc_prepare(second["id"])
                            owner, name, delayed = (
                                (pilot, "member", delayed_member)
                                if phase == "model"
                                else (sdlc_sandbox, "run", delayed_test)
                            )
                            with patch.object(owner, name, delayed):
                                work = (
                                    runtime.sdlc_lead(second["id"])
                                    if phase == "model"
                                    else runtime.sdlc_prepare(second["id"])
                                )
                                task = asyncio.create_task(work)
                                await asyncio.wait_for(started.wait(), 10)
                                await command(f"/v7/missions/{second['id']}/cancel", {})
                                release.set()
                                try:
                                    await task
                                except ApplicationError:
                                    pass
                                else:
                                    raise AssertionError("Cancelled activity advanced")
                        await runtime.sdlc_abort(second["id"])
                        stopped = await request("GET", "/v7/missions/" + second["id"])
                        assert stopped["state"] == "cancelled" and not stopped.get("effects")
                        assert not stopped["evidence"].get("implementing")
                        if phase == "test":
                            assert not stopped["evidence"].get("investigating")
                        record("cancel-during-" + phase, later_dispatches=0)
                    snapshot = await request("GET", "/v7/snapshot")
                    (output / "snapshot.json").write_text(json.dumps(snapshot, indent=2))
                    record(
                        "complete",
                        external_effects=0,
                        synthetic_provider_writes=1,
                        temporal="not_exercised",
                        evidence=str(output),
                    )
    except Exception as exc:
        record("failed", error_type=type(exc).__name__, evidence=str(output))
        raise
    finally:
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            await asyncio.to_thread(process.wait, 15)
        log.close()
        print("Evidence:", output, flush=True)


if __name__ == "__main__":
    asyncio.run(main())
