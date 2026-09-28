"""Synthetic provider/model/VM controls around the actual V7 product worker.

Never imported by production. No GitHub, inference or candidate execution occurs.
"""

import asyncio
import json
import os
from pathlib import Path
from unittest.mock import patch

from starbase_runtime import sdlc_capabilities, sdlc_sandbox, worker
from starbase_runtime import sdlc_pilot as pilot
from starbase_runtime import sdlc_publish as publisher
from starbase_runtime.operations import request
from starbase_runtime.review import digest

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(os.environ["STARBASE_SDLC_CONTROL_DIR"])
REVISION = "2f8e9fef0b8b4b16c8641a0409eb532c22fab8b4"
product_build = pilot.build
product_catalog = sdlc_capabilities.catalog


def history_catalog() -> dict:
    catalog = product_catalog()
    catalog["capabilities"] = [
        cap for cap in catalog["capabilities"] if cap["opportunity"] == pilot.OPPORTUNITY
    ]
    return catalog


def build() -> dict:
    value = product_build()
    value["manifest"]["synthetic_control_fixture"] = digest(Path(__file__).read_text())
    value["digest"] = digest(value["manifest"])
    return value


async def revision() -> tuple[str, str]:
    return "main", REVISION


async def capture(sha: str) -> dict[str, str]:
    assert sha == REVISION
    root = ROOT / ".local/algent-inspection"
    return {path: (root / path).read_text() for path in pilot.FILES}


async def member(role: str, context: dict) -> dict:
    with (OUT / "model-controls.jsonl").open("a") as output:
        output.write(json.dumps({"role": role, "synthetic": True}) + "\n")
    if role == "lead":
        value = {"decision": "implement", "rationale": "Synthetic control", "task": "Stable ties"}
    elif role == "implementer":
        value = {
            "rationale": "Synthetic control",
            "edits": [
                {
                    "path": pilot.SOURCE,
                    "old": "ORDER BY timestamp DESC",
                    "new": "ORDER BY timestamp DESC, id DESC",
                }
            ],
        }
    else:
        value = {"status": "accept", "rationale": "Synthetic control; not model qualification"}
    return {"role": role, "output": value, "usage": {}, "elapsed_ms": 0, "model": "synthetic"}


async def sandbox(name: str, files: dict[str, str]) -> dict:
    values = {
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
            values[key] = [-1]
    return {
        "exit_code": 0,
        "cases": [{"id": key, "actual": v} for key, v in values.items()],
        "synthetic": True,
    }


async def publish(mission: dict, files: dict) -> dict:
    core = f"/internal/v7/missions/{mission['id']}"
    await request(
        "POST",
        core + "/publication",
        {
            "artifact_digest": digest(publisher.artifacts(files)),
            "revision": REVISION,
        },
    )
    for kind in ("branch", "pr", "review"):
        effect = {"key": kind, "kind": kind, "data": {"synthetic": True}}
        claimed = await request("POST", core + "/effect", effect)
        duplicate = await request("POST", core + "/effect", effect)
        assert claimed["claimed"] is True and duplicate["claimed"] is False
    return {
        "url": "https://github.com/X-McKay/algent/pull/987654321",
        "number": 987654321,
        "head": "a" * 40,
        "branch": "starbase/" + mission["id"],
        "review_id": 987654321,
        "synthetic": True,
    }


async def followup(receipt: dict) -> dict:
    marker = OUT / "ci-checkpoint"
    if not marker.exists():
        marker.write_text("Synthetic pending CI; wait for Temporal timer before restart.\n")
        return {"status": "pending", "synthetic": True}
    return {"status": "passed", "synthetic": True}


if __name__ == "__main__":
    with (
        patch.multiple(pilot, revision=revision, build=build, capture=capture, member=member),
        patch.object(sdlc_sandbox, "run", sandbox),
        # This fixture provides only the history model/VM adapter. The separate
        # coordination control covers the installed multi-family catalog.
        patch.object(sdlc_capabilities, "catalog", history_catalog),
        patch.multiple(publisher, publish=publish, followup=followup),
        # Keep heartbeat isolated from the running local installation.
        patch.object(
            worker,
            "Path",
            lambda path: (
                OUT / "worker-heartbeat"
                if str(path) == "/tmp/starbase2-worker-heartbeat"
                else Path(path)
            ),
        ),
    ):
        asyncio.run(worker.run_worker())
