"""Public controls for the bounded V7 team and Core HTTP authority boundary."""

import asyncio
import copy
import json
import os
import socket
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from pydantic import ValidationError
from starbase_runtime import sdlc_pilot as pilot
from starbase_runtime import sdlc_runtime as runtime
from starbase_runtime import sdlc_workflow as workflow
from temporalio.client import WorkflowExecutionStatus
from temporalio.exceptions import ApplicationError

SOURCE = """class Persistence:
    def unrelated(self):
        return "retained"

    def get_conversation_history(self, context, limit=100):
        query = "ORDER BY timestamp DESC LIMIT ?"
        return query
"""
FILES = dict.fromkeys(pilot.FILES, "") | {pilot.SOURCE: SOURCE}
BUILD = {"digest": "b" * 64, "manifest": {"control": "fake-model"}}


def patch(old="timestamp DESC", new="timestamp DESC, id DESC"):
    return pilot.Patch(
        rationale="Break timestamp ties deterministically",
        edits=[pilot.Edit(path=pilot.SOURCE, old=old, new=new)],
    )


def mission():
    return {
        "id": "pilot",
        "input": {"build": BUILD, "revision": "a" * 40},
        "policy_generation": 1,
        "state": "queued",
        "evidence": {},
        "publication": None,
        "cancel_requested": False,
    }


class CoreControl:
    def __init__(self):
        self.run = mission()
        self.snapshot = {
            "enabled": True,
            "policy": {
                "enabled": True,
                "generation": 1,
                "expires_at": time.time() + 300,
                "max_missions": 1,
            },
            "missions": [self.run],
        }
        self.events = []
        self.posts = []

    async def request(self, method, path, body=None):
        if method == "GET":
            return copy.deepcopy(self.snapshot if path.endswith("snapshot") else self.run)
        assert isinstance(body, dict)
        self.posts.append((path, body))
        if path.endswith("/event"):
            self.events.append(body)
            self.run["state"] = body["stage"]
            data = copy.deepcopy(body["data"])
            if body["stage"] == "testing":
                # A stubbed Core response, never a claim about real grading.
                data["verdict"] = "improved"
            self.run["evidence"][body["stage"]] = data
            return copy.deepcopy(self.run)
        if path == "/internal/v7/missions":
            self.run = mission() | {"id": body["id"], "input": body}
            self.snapshot["missions"] = [self.run]
            return copy.deepcopy(self.run)
        raise AssertionError(path)


@pytest.fixture
def control(monkeypatch):
    core = CoreControl()
    monkeypatch.setattr(runtime, "request", core.request)
    monkeypatch.setattr(pilot, "build", lambda: BUILD)
    monkeypatch.setattr(runtime, "_next_discovery", 0.0)
    return core


def test_patch_fences_unrelated_ambiguous_noop_and_invalid_ast():
    assert pilot.applicable(FILES)
    assert "id DESC" in pilot.apply(FILES, patch())[pilot.SOURCE]
    for edit in [
        patch("retained", "changed"),
        patch("missing", "replacement"),
        patch("timestamp DESC", "timestamp DESC"),
        patch("return", "yield"),
        patch("return query", "return ("),
    ]:
        with pytest.raises((ValueError, SyntaxError)):
            pilot.apply(FILES, edit)
    with pytest.raises(ValidationError):
        pilot.Edit.model_validate(
            {"path": "tests/test_history.py", "old": "before", "new": "after"}
        )
    with pytest.raises(ValueError, match="unrelated"):
        pilot.apply(FILES, patch("limit=100", "limit=5"))


@pytest.mark.parametrize("fence", ["build", "cancel", "terminal", "disabled", "policy", "expiry"])
def test_mission_authority_fences(control, fence):
    if fence == "build":
        control.run["input"]["build"] = {"digest": "changed"}
    elif fence == "cancel":
        control.run["cancel_requested"] = True
    elif fence == "terminal":
        control.run["state"] = "awaiting_review"
    elif fence == "disabled":
        control.snapshot["enabled"] = False
    elif fence == "policy":
        control.snapshot["policy"]["generation"] = 2
    else:
        control.snapshot["policy"]["expires_at"] = 0
    with pytest.raises(ApplicationError):
        asyncio.run(runtime.mission("pilot"))


def test_fake_team_handoff_revision_and_acceptance(control, monkeypatch):
    outputs = {
        "lead": [{"decision": "implement", "rationale": "Observed tie issue", "task": "Fix ties"}],
        "implementer": [patch().model_dump(), patch().model_dump()],
        "reviewer": [
            {"status": "revise", "rationale": "Clarify ordering"},
            {"status": "accept", "rationale": "Bounded fix matches evidence"},
        ],
    }
    calls = []

    async def member(role, context):
        calls.append((role, context))
        return {"role": role, "output": outputs[role].pop(0)}

    monkeypatch.setattr(pilot, "capture", AsyncMock(return_value=FILES))
    monkeypatch.setattr(pilot, "member", member)
    monkeypatch.setattr(runtime.sdlc_sandbox, "run", AsyncMock(return_value={"exit_code": 0}))

    async def exercise():
        await runtime.sdlc_prepare("pilot")
        lead = await runtime.sdlc_lead("pilot")
        assert lead["continue"]
        await runtime.sdlc_implement({"id": "pilot", "round": 0, "lead": lead["lead"]})
        review = await runtime.sdlc_review({"id": "pilot", "round": 0})
        assert review["continue"] and not review["accepted"]
        await runtime.sdlc_implement(
            {"id": "pilot", "round": 1, "lead": lead["lead"], "feedback": review["feedback"]}
        )
        review = await runtime.sdlc_review({"id": "pilot", "round": 1})
        assert review["accepted"]

    asyncio.run(exercise())
    assert [role for role, _ in calls] == [
        "lead",
        "implementer",
        "reviewer",
        "implementer",
        "reviewer",
    ]
    assert calls[3][1]["feedback"]["status"] == "revise"
    assert calls[3][1]["source"] == SOURCE  # revisions start at the pinned baseline
    assert control.run["state"] == "ready_to_publish"
    assert [event["stage"] for event in control.events] == [
        "investigating",
        "implementing",
        "testing",
        "reviewing",
        "implementing",
        "testing",
        "reviewing",
        "ready_to_publish",
    ]


def test_lead_abstention_never_dispatches_implementation(control, monkeypatch):
    control.run["evidence"]["investigating"] = {
        "sources": FILES,
        "baseline": {},
        "opportunity": "unknown",
    }
    monkeypatch.setattr(
        pilot,
        "member",
        AsyncMock(
            return_value={
                "role": "lead",
                "output": {"decision": "abstain", "rationale": "No evidence", "task": "None"},
            }
        ),
    )
    assert asyncio.run(runtime.sdlc_lead("pilot")) == {"continue": False}
    assert control.run["state"] == "blocked"


def test_revocation_during_model_call_prevents_execution(control, monkeypatch):
    control.run["evidence"]["investigating"] = {"sources": FILES, "baseline": {}}

    async def member(*args):
        control.run["cancel_requested"] = True
        return {"role": "implementer", "output": patch().model_dump()}

    execute = AsyncMock()
    monkeypatch.setattr(pilot, "member", member)
    monkeypatch.setattr(runtime.sdlc_sandbox, "run", execute)
    with pytest.raises(ApplicationError):
        asyncio.run(runtime.sdlc_implement({"id": "pilot", "round": 0, "lead": {}}))
    execute.assert_not_awaited()


def test_discovery_deduplicates_revision_and_cancellation(control, monkeypatch):
    control.run["input"]["opportunity"] = pilot.OPPORTUNITY
    control.run["state"] = "awaiting_review"
    revision = AsyncMock(return_value=("main", "a" * 40))
    capture = AsyncMock()
    monkeypatch.setattr(pilot, "revision", revision)
    monkeypatch.setattr(pilot, "capture", capture)
    control.snapshot["policy"]["max_missions"] = 2
    client = SimpleNamespace(get_workflow_handle=lambda _: None)
    asyncio.run(runtime.reconcile_sdlc(client, "test"))
    capture.assert_not_awaited()
    assert not control.posts
    control.run["state"] = "testing"
    control.run["cancel_requested"] = True
    handle = SimpleNamespace(
        describe=AsyncMock(return_value=SimpleNamespace(status=WorkflowExecutionStatus.RUNNING)),
        cancel=AsyncMock(),
    )
    client.get_workflow_handle = lambda _: handle
    asyncio.run(runtime.reconcile_sdlc(client, "test"))
    handle.cancel.assert_awaited_once()


def test_workflow_bounds_revisions_and_does_not_retry_unknown_model_calls(monkeypatch):
    calls = []

    async def execute(fn, value, **options):
        calls.append((fn.__name__, options["retry_policy"].maximum_attempts))
        if fn is workflow.sdlc_lead:
            return {"continue": True, "lead": {}}
        if fn is workflow.sdlc_review:
            return {"accepted": False, "continue": value["round"] < 2, "feedback": {}}
        return {}

    monkeypatch.setattr(workflow.workflow, "execute_activity", execute)
    result = asyncio.run(workflow.RepositorySdlc().run("pilot"))
    assert result == {"status": "blocked"}
    assert [name for name, _ in calls].count("sdlc_implement") == 3
    assert [name for name, _ in calls].count("sdlc_review") == 3
    assert not any(name == "sdlc_publish" for name, _ in calls)
    assert all(
        attempts == 1
        for name, attempts in calls
        if name
        in {
            "sdlc_lead",
            "sdlc_implement",
            "sdlc_review",
        }
    )


def test_core_http_v7_worker_operator_separation(tmp_path):
    """Needs local socket permission; never talks to a provider or publishes."""
    binary = Path(__file__).resolve().parents[3] / "target/debug/starbase-core"
    assert binary.exists(), "Build Core before HTTP qualification"
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    token = tmp_path / "worker-token"
    token.write_text("local-test-worker")
    env = os.environ | {
        "STARBASE_DB": str(tmp_path / "core.sqlite"),
        "STARBASE_PORT": str(port),
        "STARBASE_TOKEN_FILE": str(token),
        "STARBASE_SDLC_ENABLED": "true",
        "STARBASE_SDLC_REPOSITORY": "X-McKay/algent",
        "STARBASE_ACCEPT_WORK": "true",
    }
    process = subprocess.Popen(
        [str(binary)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE
    )
    origin = f"http://127.0.0.1:{port}"

    def call(path, body=None, headers=None):
        request = urllib.request.Request(
            origin + path,
            data=None if body is None else json.dumps(body).encode(),
            headers={"Content-Type": "application/json"} | (headers or {}),
        )
        try:
            with urllib.request.urlopen(request, timeout=2) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as exc:
            return exc.code, exc.read().decode()

    try:
        for _ in range(100):
            if process.poll() is not None:
                assert process.stderr is not None
                raise AssertionError(process.stderr.read().decode())
            try:
                status, snapshot = call("/v7/snapshot")
                break
            except urllib.error.URLError:
                time.sleep(0.05)
        else:
            raise AssertionError("Core failed to become available")
        assert status == 200 and snapshot["enabled"] and not snapshot["policy"]["enabled"]
        assert call("/internal/v7/missions", {})[0] == 403
        assert call("/v7/policy", {})[0] == 403
        assert call("/v7/policy", {}, {"Authorization": "Bearer local-test-worker"})[0] == 403
        assert (
            call(
                "/internal/v7/missions",
                {},
                {
                    "Authorization": "Bearer local-test-worker",
                },
            )[0]
            == 422
        )
        with urllib.request.urlopen(origin + "/", timeout=2) as response:
            cookie = response.headers["Set-Cookie"].split(";", 1)[0]
        operator = {"Cookie": cookie, "Origin": origin}
        worker = {"Authorization": "Bearer local-test-worker"}
        policy = {
            "repository": "X-McKay/algent",
            "enabled": True,
            "publish": True,
            "generation": 0,
            "max_missions": 1,
            "expires_at": time.time() + 300,
        }
        assert call("/v7/policy", policy, operator)[0] == 200
        assert call("/v7/policy", policy, operator)[0] == 409
        candidate = {
            "id": "http-pilot",
            "repository": "X-McKay/algent",
            "revision": "a" * 40,
            "opportunity": "persistence-history",
            "build": BUILD,
        }
        assert (
            call("/internal/v7/missions", candidate | {"repository": "X-McKay/Starbase2"}, worker)[
                0
            ]
            == 409
        )
        status, retained = call("/internal/v7/missions", candidate, worker)
        assert status == 200 and retained["state"] == "queued"
        assert call("/internal/v7/missions", candidate, worker)[1] == retained
        assert (
            call(
                "/internal/v7/missions/http-pilot/publication",
                {
                    "revision": "a" * 40,
                    "artifact_digest": "c" * 64,
                },
                worker,
            )[0]
            == 409
        )
        assert call("/v7/missions/http-pilot/cancel", {}, operator)[1]["cancel_requested"]
        assert (
            call(
                "/internal/v7/missions/http-pilot/event",
                {
                    "key": "start",
                    "stage": "investigating",
                    "data": {},
                },
                worker,
            )[0]
            == 409
        )
        assert (
            call(
                "/internal/v7/missions/http-pilot/event",
                {
                    "key": "cancelled",
                    "stage": "cancelled",
                    "data": {},
                },
                worker,
            )[1]["state"]
            == "cancelled"
        )
        retry = {"id": "http-retry", "build": {"digest": "d" * 64}}
        retry_path = "/v7/missions/http-pilot/retry"
        assert call(retry_path, retry, worker)[0] == 403
        assert call(retry_path, retry, operator)[0] == 409  # original quota exhausted
        assert call("/v7/policy", policy | {"generation": 1, "max_missions": 3}, operator)[0] == 200
        status, child = call(retry_path, retry, operator)
        assert status == 200 and child["retry_of"] == "http-pilot"
        assert call(retry_path, retry, operator)[1] == child
        assert call("/v7/missions/http-pilot")[1]["state"] == "cancelled"
    finally:
        process.terminate()
        process.wait(timeout=5)


@pytest.mark.parametrize(
    ("status", "verdict", "round_number", "expected_stage"),
    [
        ("abstain", "improved", 0, "blocked"),
        ("revise", "improved", 2, "blocked"),
        ("accept", "ineligible", 0, "implementing"),
    ],
)
def test_review_cannot_certify_failed_verification(
    control,
    monkeypatch,
    status,
    verdict,
    round_number,
    expected_stage,
):
    control.run["state"] = "testing"
    control.run["evidence"] = {
        "investigating": {"sources": FILES},
        "testing": {
            "candidate_files": FILES,
            "diff": "test-control",
            "verdict": verdict,
            "baseline": {},
            "candidate": {},
            "patch": {"output": {"rationale": "control", "edits": []}},
        },
    }
    monkeypatch.setattr(
        pilot,
        "member",
        AsyncMock(
            return_value={
                "role": "reviewer",
                "output": {"status": status, "rationale": "Control decision"},
            }
        ),
    )
    result = asyncio.run(runtime.sdlc_review({"id": "pilot", "round": round_number}))
    assert not result["accepted"]
    assert control.run["state"] == expected_stage
    assert not any(event["stage"] == "ready_to_publish" for event in control.events)


def test_configuration_rejects_owner_escape_and_relative_secret_path(tmp_path, monkeypatch):
    config = tmp_path / "sdlc.json"
    monkeypatch.setenv("STARBASE_SDLC_CONFIG_FILE", str(config))
    for value in [
        {"repository": "X-McKay/Starbase2", "token_file": "/tmp/test-token"},
        {"repository": "X-McKay/algent", "token_file": "relative-token"},
        {"repository": "X-McKay/algent", "token_file": "/tmp/test-token", "merge": True},
    ]:
        config.write_text(json.dumps(value))
        with pytest.raises(ValueError):
            pilot.configuration()
    config.write_text(json.dumps({"repository": "X-McKay/algent", "token_file": "/tmp/test-token"}))
    assert pilot.configuration()["repository"] == "x-mckay/algent"


def test_revocation_during_capture_prevents_baseline_vm(control, monkeypatch):
    async def capture(_revision):
        control.run["cancel_requested"] = True
        return FILES

    execute = AsyncMock()
    monkeypatch.setattr(pilot, "capture", capture)
    monkeypatch.setattr(runtime.sdlc_sandbox, "run", execute)
    with pytest.raises(ApplicationError):
        asyncio.run(runtime.sdlc_prepare("pilot"))
    execute.assert_not_awaited()


@pytest.mark.parametrize("round_number", [0, 2])
def test_rejected_patch_is_retained_without_execution_and_sent_for_correction(
    control, monkeypatch, round_number
):
    control.run["state"] = "implementing"
    control.run["evidence"]["investigating"] = {"sources": FILES, "baseline": {"exit_code": 0}}
    rejected = patch("absent search", "replacement").model_dump()
    calls = []

    async def member(role, context):
        calls.append((role, context))
        return {
            "role": role,
            "output": rejected
            if role == "implementer"
            else {"status": "revise", "rationale": "Use an exact unique source span"},
        }

    real_request = control.request

    async def request(method, path, body=None):
        value = await real_request(method, path, body)
        if body and body.get("stage") == "testing":
            control.run["evidence"]["testing"]["verdict"] = "ineligible"
            value["evidence"]["testing"]["verdict"] = "ineligible"
        return value

    monkeypatch.setattr(runtime, "request", request)
    monkeypatch.setattr(pilot, "member", member)
    sandbox = AsyncMock()
    monkeypatch.setattr(runtime.sdlc_sandbox, "run", sandbox)

    async def exercise():
        tested = await runtime.sdlc_implement({"id": "pilot", "round": round_number, "lead": {}})
        assert tested["candidate"]["not_executed"]
        assert tested["patch"]["output"] == rejected
        result = await runtime.sdlc_review({"id": "pilot", "round": round_number})
        assert result["continue"] == (round_number < 2)
        assert not result["accepted"]
        assert result["feedback"]["validation_error"] == "Patch target is absent or ambiguous"
        assert result["feedback"]["proposed_edits"] == rejected["edits"]

    asyncio.run(exercise())
    sandbox.assert_not_awaited()
    assert [role for role, _ in calls] == ["implementer"]
    assert control.run["state"] == ("implementing" if round_number < 2 else "blocked")


def test_build_identity_survives_json_roundtrip(monkeypatch):
    monkeypatch.undo()
    value = pilot.build()
    assert json.loads(json.dumps(value)) == value
