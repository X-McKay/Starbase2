"""Snapshot retained inputs and world sources without network or ledger writes."""

import hashlib
import json
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
ALLOWED_CHANGES = {
    "apps/world/characters/model_visual.gd",
    "apps/world/characters/definitions/operator.tres",
}


def snapshot(path: Path) -> dict:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return {"sha256": digest.hexdigest(), "bytes": path.stat().st_size}


def local_path(value: str) -> Path:
    path = Path(value)
    path = (path if path.is_absolute() else ROOT / path).resolve()
    if not path.is_relative_to(ROOT) or not path.is_file():
        raise ValueError("Required retained input missing or outside repository")
    return path


def collect(directory: Path) -> set[Path]:
    return {
        path
        for path in directory.rglob("*")
        if path.is_file()
        and not any(part in {".godot", "__pycache__", ".git"} for part in path.parts)
        and not path.name.endswith((".blend1", ".blend2", ".pyc"))
    }


def main() -> None:
    ledger = json.loads((ROOT / "meshy_output/inhabited-polish-ledger.json").read_text())
    if ledger["approved_credit_cap"] != 1000 or ledger["prior_generation_credits"] != 0:
        raise ValueError("Unexpected milestone budget")
    stages = {}
    files = set()
    actual = pending = 0
    for name, stage in ledger["stages"].items():
        charge = stage.get("consumed_credits")
        if stage["status"] == "complete" and charge is None:
            raise ValueError("Completed stage missing actual charge")
        if charge is not None:
            if not isinstance(charge, int) or charge < 0:
                raise ValueError("Invalid actual charge")
            actual += charge
        reservation = stage["reserved_credits"] if charge is None else 0
        pending += reservation
        originals = [local_path(value) for value in stage.get("files", [])]
        files.update(originals)
        stages[name] = {
            "status": stage["status"],
            "task_id": stage.get("task_id"),
            "actual_credits": charge,
            "pending_reservation": reservation,
            "payload_sha256": stage.get("payload_sha256"),
            "retained_originals": [str(path.relative_to(ROOT)) for path in originals],
        }
    if actual + pending > 1000:
        raise ValueError("Budget exceeded")
    for directory in (
        HERE,
        ROOT / "assets-production/scripts",
        ROOT / "assets-production/structures",
        ROOT / "assets-production/props",
        ROOT / "assets-production/environment",
        ROOT / "assets-production/characters/cybercat-vanguard",
        ROOT / "assets-production/characters/cybercat-vanguard-secondary",
    ):
        files.update(collect(directory))
    files.discard(HERE / "provenance.json")
    for relative in (
        "justfile",
        "assets-production/batches/remaining-structures/plan.json",
        "assets-production/batches/remaining-structures/provenance.json",
        "assets-production/batches/living-colony/provenance.json",
        "evidence/world/inhabited-polish/baseline/source-hashes.json",
        "evidence/world/remaining-structures/baseline/preserved-assets.json",
    ):
        files.add(local_path(relative))
    baseline = json.loads(
        (ROOT / "evidence/world/remaining-structures/baseline/preserved-assets.json").read_text()
    )
    changed = sorted(
        name
        for name, digest in baseline.items()
        if not (ROOT / name).is_file() or snapshot(ROOT / name)["sha256"] != digest
    )
    unexpected = sorted(set(changed) - ALLOWED_CHANGES)
    previous = json.loads(
        (ROOT / "evidence/world/inhabited-polish/baseline/source-hashes.json").read_text()
    )
    world = {
        str(path.relative_to(ROOT / "apps/world")): snapshot(path)
        for path in sorted(collect(ROOT / "apps/world"))
    }
    before = previous["world_files"]
    qualification = {
        "status": "Pending frozen-source standalone qualification; snapshot is not certification."
    }
    manifest_path = ROOT / "evidence/world/inhabited-polish/final/package-01/manifest.json"
    if manifest_path.is_file():
        manifest = json.loads(manifest_path.read_text())
        if manifest["source_files"] != {name: record["sha256"] for name, record in world.items()}:
            raise ValueError("Current world differs from qualified package source manifest")
        files.add(manifest_path)
        qualification = {
            "status": manifest["status"],
            "manifest": str(manifest_path.relative_to(ROOT)),
            "manifest_sha256": snapshot(manifest_path)["sha256"],
            "archive_sha256": manifest["archive_sha256"],
            "pack_sha256": manifest["pack_sha256"],
            "executable_sha256": manifest["executable_sha256"],
            "world_source_match": True,
            "limits": (
                "Local unsigned review only; owner art acceptance and human audio audition open."
            ),
        }
    report = {
        "milestone": "inhabited-polish",
        "captured_at": datetime.now(UTC).isoformat(),
        "qualification": qualification,
        "rebuild": "mise exec -- just world-inhabited-build",
        "imagegen": {"concept": "concepts/habitat-living.png", "prompt": "concepts/prompt.txt"},
        "budget": {
            "cap": 1000,
            "prior_charges_in_this_allowance": 0,
            "historical_charges_excluded": 507,
            "actual": actual,
            "pending_reservations": pending,
            "remaining_after_reservations": 1000 - actual - pending,
            "unfinished_stages": [
                name for name, stage in stages.items() if stage["status"] != "complete"
            ],
        },
        "stages": stages,
        "preservation": {
            "checked": len(baseline),
            "unchanged": len(baseline) - len(changed),
            "intentional_changes": sorted(set(changed) & ALLOWED_CHANGES),
            "unexpected_changes": unexpected,
        },
        "previous_qualified_world": {
            "manifest": previous["qualified_manifest"],
            "manifest_sha256": previous["qualified_manifest_sha256"],
            "file_count": len(before),
            "changed": sorted(
                name
                for name in before.keys() & world.keys()
                if before[name] != world[name]["sha256"]
            ),
            "added": sorted(world.keys() - before.keys()),
            "missing": sorted(before.keys() - world.keys()),
        },
        "production_files": {str(path.relative_to(ROOT)): snapshot(path) for path in sorted(files)},
        "world_files": world,
        "scope": (
            "World source and media/import sidecars included; generated .godot cache excluded. "
            "Selected production trees and retained sofa originals included. Raw provider task "
            "responses and ledger contents are not copied. "
            "Earlier milestone reports remain historical."
        ),
    }
    destination = HERE / "provenance.json"
    temporary = HERE / ".provenance.tmp"
    temporary.write_text(json.dumps(report, indent=2) + "\n")
    temporary.replace(destination)
    print(
        json.dumps(
            {
                "world_files": len(world),
                "production_files": len(files),
                "budget": report["budget"],
                "preservation": report["preservation"],
            }
        )
    )
    if unexpected:
        raise SystemExit("Unexpected preservation changes; see report")


if __name__ == "__main__":
    main()
