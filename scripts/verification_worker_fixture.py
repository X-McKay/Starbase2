"""Synthetic external controls for the actual verification product worker."""

import asyncio
import json
import os
from datetime import timedelta
from pathlib import Path
from unittest.mock import patch

from starbase_runtime import sdlc_pilot as pilot
from starbase_runtime import sdlc_revision_publish as publisher
from starbase_runtime import sdlc_sandbox, sdlc_verification, worker
from starbase_runtime.operations import request
from starbase_runtime.review import digest
from temporalio.exceptions import ApplicationError

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(os.environ["STARBASE_VERIFICATION_CONTROL_DIR"])
HEAD1, HEAD2 = "a" * 40, "b" * 40
product_build = pilot.build


def build() -> dict:
    value = product_build()
    value["manifest"]["synthetic_verification_fixture"] = digest(Path(__file__).read_text())
    value["digest"] = digest(value["manifest"])
    return value


async def revision() -> tuple[str, str]:
    return "main", HEAD1


async def capture(head: str) -> dict[str, str]:
    assert head in {HEAD1, HEAD2}
    files = {path: (ROOT / ".local/algent-inspection" / path).read_text() for path in pilot.FILES}
    if head == HEAD2:
        files[pilot.SOURCE] = files[pilot.SOURCE].replace(
            "ORDER BY timestamp DESC", "ORDER BY timestamp DESC, id DESC"
        )
    return files


async def member(role: str, context: dict) -> dict:
    with (OUT / "roles.jsonl").open("a") as output:
        output.write(json.dumps({"role": role, "synthetic": True}) + "\n")
    if role == "lead":
        value = {
            "decision": "implement",
            "rationale": "Synthetic diagnostic lead control",
            "task": "Add a descending insertion-id tie breaker to the timestamp query.",
        }
    elif role == "implementer":
        assert context["edit_format"] == "numbered-lines"
        target = next(
            line for line in context["source"] if "ORDER BY timestamp DESC" in line["text"]
        )
        value = {
            "rationale": "Synthetic correction control",
            "edits": [
                {
                    "line": target["line"],
                    "new": "ORDER BY timestamp DESC, id DESC",
                }
            ],
        }
    else:
        assert role == "reviewer"
        value = {"status": "accept", "rationale": "Synthetic review; no model qualification"}
    return {"role": role, "output": value, "model": "synthetic", "usage": {}, "elapsed_ms": 0}


async def sandbox(name: str, files: dict[str, str]) -> dict:
    cases = {
        "history_all": [0, 1, 2, 3, 4],
        "history_last3": [2, 3, 4],
        "history_last1": [4],
        "history_zero": [],
        "history_empty": [],
        "history_context": [9],
        "history_mixed": [0, 1, 2, 3, 4],
    }
    if "ORDER BY timestamp DESC, id DESC" not in files[pilot.SOURCE]:
        for key in ("history_all", "history_last3", "history_last1", "history_mixed"):
            cases[key] = [-1]
    return {
        "exit_code": 0,
        "cases": [{"id": key, "actual": value} for key, value in cases.items()],
        "synthetic": True,
    }


async def public_tests(name: str, files: dict[str, str]) -> dict:
    return {
        "exit_code": 0 if "ORDER BY timestamp DESC, id DESC" in files[pilot.SOURCE] else 1,
        "synthetic": True,
    }


async def observe(mission: dict) -> dict:
    return {
        "head": (OUT / "head").read_text(),
        "open": True,
        "state": "open",
        "branch": mission["evidence"]["submitted"]["branch"],
    }


def core_path(mission, verification):
    return f"/internal/v7/missions/{mission['id']}/verifications/{verification['id']}"


async def effect(core, kind, data):
    await request("POST", core + "/authorize", {})
    body = {"key": kind, "kind": kind, "data": data}
    claim = await request("POST", core + "/effect", body)
    assert (await request("POST", core + "/effect", body))["claimed"] is False
    key = core + "/" + kind
    path = OUT / "effects.json"
    values = json.loads(path.read_text()) if path.exists() else {}
    if key not in values:
        assert claim["claimed"] is True
        await request("POST", core + "/authorize", {})
        values[key] = data
        path.write_text(json.dumps(values, indent=2))
    return values[key]


async def status(mission: dict, verification: dict, pending: bool) -> dict:
    core = core_path(mission, verification)
    current = await request("POST", core + "/authorize", {})
    state = (
        "pending"
        if pending
        else {"passed": "success", "failed": "failure", "infrastructure_blocked": "error"}[
            current["evidence"]["verified"]["outcome"]
        ]
    )
    kind = "status_pending" if pending else "status_result"
    receipt = await effect(
        core,
        kind,
        {
            "head": verification["input"]["head"],
            "state": state,
            "context": "starbase/persistence-regression",
        },
    )
    marker = OUT / "retry-checkpoint"
    if not pending and verification["input"]["head"] == HEAD1 and not marker.exists():
        marker.write_text(verification["id"])
        raise ApplicationError(
            "Synthetic lost status acknowledgement", next_retry_delay=timedelta(seconds=10)
        )
    return receipt | {"synthetic": True}


async def update(mission: dict, verification: dict, files: dict) -> dict:
    core = core_path(mission, verification)
    await effect(
        core,
        "branch_update",
        {"expected_head": HEAD1, "candidate_head": HEAD2, "artifact_digest": digest(files)},
    )
    (OUT / "head").write_text(HEAD2)
    await effect(core, "review", {"candidate_head": HEAD2})
    return {
        "head": HEAD2,
        "previous_head": HEAD1,
        "branch": "starbase/control-parent",
        "number": 987654321,
        "url": "https://github.com/X-McKay/algent/pull/987654321",
        "review_id": 987654321,
        "synthetic": True,
    }


if __name__ == "__main__":
    with (
        patch.multiple(pilot, revision=revision, build=build, capture=capture, member=member),
        patch.object(sdlc_sandbox, "run", sandbox),
        patch.multiple(sdlc_verification, capture=capture, public_tests=public_tests),
        patch.multiple(publisher, observe=observe, status=status, update=update),
        patch.object(
            worker,
            "Path",
            lambda path: (
                OUT / "heartbeat" if str(path) == "/tmp/starbase2-worker-heartbeat" else Path(path)
            ),
        ),
    ):
        asyncio.run(worker.run_worker())
