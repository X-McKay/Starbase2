"""Snapshot this batch's local provenance without API calls or ledger writes.

Run once outputs are ready; pending generations/preparation are reported honestly.
Provider result files are referenced by path/hash only, never copied into output.
"""

import hashlib
import json
import math
import os
import re
import tempfile
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BATCH = Path(__file__).resolve().parent
CAP = 1250
ROOMS = {"command": "review", "training": "gym", "habitat": "habitat", "botanical": "greenhouse"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def amount(value):
    require(
        type(value) in (int, float) and math.isfinite(value) and value >= 0,
        "Invalid ledger credit amount",
    )
    return value


def snapshot(raw_path):
    root = ROOT.resolve()
    path = Path(raw_path)
    path = (root / path).resolve() if not path.is_absolute() else path.resolve()
    require(path.is_relative_to(root), "Snapshot input must be inside project")
    relative = str(path.relative_to(root))
    if not path.is_file():
        return {"path": relative, "status": "missing"}
    before = path.stat()
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    after = path.stat()
    require(
        (before.st_size, before.st_mtime_ns) == (after.st_size, after.st_mtime_ns),
        "An artifact changed during snapshot; rerun after production stops",
    )
    return {
        "path": relative,
        "status": "present",
        "sha256": digest.hexdigest(),
        "bytes": after.st_size,
    }


def collect():
    plan_path = BATCH / "plan.json"
    ledger_path = ROOT / "meshy_output/remaining-structures-ledger.json"
    plan = json.loads(plan_path.read_text())
    ledger = json.loads(ledger_path.read_text())
    require(
        plan.get("approved_credit_cap") == CAP and plan.get("prior_generation_credits") == 0,
        "Unexpected batch authorization",
    )
    require(
        ledger.get("approved_credit_cap") == CAP and ledger.get("prior_generation_credits") == 0,
        "Unexpected ledger authorization",
    )
    assets = [asset["id"] for asset in plan["assets"]]
    require(
        len(assets) == len(set(assets))
        and all(re.fullmatch(r"[a-z0-9-]+", asset) for asset in assets),
        "Invalid or duplicate plan asset IDs",
    )
    expected = {f"{asset}/{stage}" for asset in assets for stage in ("image", "mesh")}
    entries = ledger["stages"]
    stages = {}
    actual = 0
    pending = 0
    unfinished = []
    for key in sorted(expected | entries.keys()):
        require(re.fullmatch(r"[a-z0-9-]+/(image|mesh)", key), "Invalid ledger stage key")
        item = entries.get(key)
        if item is None:
            stages[key] = {"status": "not_submitted", "original_files": []}
            unfinished.append(key)
            continue
        status = item.get("status", "unknown")
        require(re.fullmatch(r"[a-z_]+", status), "Invalid ledger status")
        row = {"status": status, "reserved_credits": amount(item["reserved_credits"])}
        if "task_id" in item:
            require(re.fullmatch(r"[a-zA-Z0-9_-]+", item["task_id"]), "Invalid task identifier")
            row["task_id"] = item["task_id"]
        if "consumed_credits" in item:
            row["actual_credits"] = amount(item["consumed_credits"])
            actual += row["actual_credits"]
        else:
            pending += row["reserved_credits"]
            row["actual_credits"] = None
        paths = list(item.get("files", []))
        if item.get("result_file"):
            paths.append(item["result_file"])
        row["original_files"] = [snapshot(path) for path in sorted(set(paths))]
        if status != "complete" or "actual_credits" not in row or row["actual_credits"] is None:
            unfinished.append(key)
        stages[key] = row
    artifacts = {}
    production = []
    for asset in assets:
        if asset.endswith("-hull"):
            family = asset.removesuffix("-hull")
            require(family in ROOMS, "Unknown structure family in plan")
            category = "structures"
            name = family
            provenance_names = ("provenance.json", "hull-provenance.json")
        else:
            category, name = "props", asset
            provenance_names = ("provenance.json",)
        source_dir = ROOT / "assets-production" / category / name
        runtime_dir = ROOT / "apps/world/assets" / category / name
        references = [snapshot(source_dir / filename) for filename in provenance_names]
        # Preserve exact current source/runtime hashes without trusting arbitrary
        # provider fields or copying free-form nested provenance into this file.
        # Godot may extract textures and store import choices beside the GLB.
        # Include every selected runtime dependency, including .import sidecars.
        paths = list((source_dir / "blender").glob("*.blend")) + [
            path for path in runtime_dir.rglob("*") if path.is_file() and path.name != ".DS_Store"
        ]
        if category == "structures":
            paths.append(source_dir / "layout.json")
            room = ROOMS[name]
            paths.extend(
                [
                    ROOT / f"apps/world/structures/{folder}/{room}-continuous.tscn"
                    for folder in ("exteriors", "interiors")
                ]
            )
            paths.append(ROOT / f"apps/world/structures/definitions/{room}.tres")
        if (
            not paths
            or not any(path.suffix == ".blend" for path in paths)
            or not any(path.suffix == ".glb" for path in paths)
        ):
            state = "unfinished"
        else:
            state = "present"
        for path in paths:
            record = snapshot(path)
            artifacts[record["path"]] = record
            if record["status"] == "missing":
                state = "unfinished"
        if any(record["status"] != "present" for record in references):
            state = "unfinished"
        production.append({"asset_id": asset, "status": state, "provenance_records": references})
    for asset in plan["assets"]:
        if asset.get("reference_image_path"):
            record = snapshot(asset["reference_image_path"])
            artifacts[record["path"]] = record
    missing = sorted(
        {record["path"] for record in artifacts.values() if record["status"] == "missing"}
    )
    preparation_unfinished = [row["asset_id"] for row in production if row["status"] != "present"]
    originals_missing = [
        record["path"]
        for row in stages.values()
        for record in row["original_files"]
        if record["status"] != "present"
    ]
    return {
        "schema_version": 1,
        "recorded_at_utc": datetime.now(UTC).isoformat(),
        "scope": "Remaining structures: generation and local files; visual acceptance is separate",
        "status": "unfinished"
        if unfinished or preparation_unfinished or missing or originals_missing
        else "locally_complete",
        "plan": snapshot(plan_path),
        "ledger_snapshot_sha256": snapshot(ledger_path)["sha256"],
        "planned_asset_count": len(assets),
        "planned_stage_count": len(expected),
        "recorded_stage_count": len(entries),
        "unplanned_recorded_stages": sorted(entries.keys() - expected),
        "budget": {
            "approved_credit_cap": CAP,
            "prior_generation_credits": 0,
            "actual_credits": actual,
            "pending_reservations": pending,
            "remaining_authorized_credits": CAP - actual - pending,
            "provider_balance": "not queried",
        },
        "unfinished_stages": unfinished,
        "unfinished_preparation": preparation_unfinished,
        "missing_artifacts": sorted(set(missing + originals_missing)),
        "stages": stages,
        "production": production,
        "artifact_snapshot": artifacts,
        "limitations": (
            "Hashes record local files at invocation. Referenced provider metadata stays local. "
            "Native QA and owner visual acceptance are separate evidence. "
            "Unsubmitted stages reserve no credits."
        ),
    }


def main():
    report = collect()
    destination = BATCH / "provenance.json"
    fd, temporary = tempfile.mkstemp(prefix="provenance-", suffix=".tmp", dir=BATCH)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(report, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(
        json.dumps(
            {
                key: report[key]
                for key in (
                    "status",
                    "planned_asset_count",
                    "planned_stage_count",
                    "budget",
                    "unfinished_stages",
                    "unfinished_preparation",
                    "missing_artifacts",
                )
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
