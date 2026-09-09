"""Record local living-colony source/output hashes; no network or generation."""

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def snapshot(path: Path) -> dict:
    return {
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "bytes": path.stat().st_size,
    }


def main() -> None:
    files = set()
    for asset in ("command", "training", "habitat", "botanical"):
        source = ROOT / "assets-production/structures" / asset
        files.update((source / "blender").glob("*-polished.blend"))
        files.update(source.glob("*provenance.json"))
        files.add(source / "layout.json")
        files.update((ROOT / "apps/world/assets/structures" / asset).rglob("*"))
    files.update((ROOT / "assets-production/environment/living-commons").rglob("*"))
    files.update((ROOT / "apps/world/assets/environment/living-commons").rglob("*"))
    files.update((HERE / "concepts").glob("*"))
    for name in (
        "build_remaining_structures.py",
        "build_living_commons.py",
        "connect_remaining_structures.py",
    ):
        files.add(ROOT / "assets-production/scripts" / name)
    for name in (
        "world.gd",
        "hud.gd",
        "command_board.gd",
        "station.gd",
        "living_commons.gd",
        "living_foliage.gdshader",
        "room_ambience.gd",
        "navigation.gd",
        "surface_layout.gd",
        "colony_paths.gd",
        "colony_paving.gd",
        "paving_lights.gd",
        "paving_glow.gdshader",
        "foundation_surface.gdshader",
        "structures/materials.gd",
        "structures/colony.tscn",
        "structures/cutaway.gdshader",
    ):
        files.add(ROOT / "apps/world" / name)
    files.add(Path(__file__).resolve())
    files.add(ROOT / "justfile")
    files.add(ROOT / "assets-production/batches/remaining-structures/provenance.json")
    files.update((ROOT / "apps/world/assets/props").rglob("*"))
    baseline = json.loads(
        (ROOT / "evidence/world/remaining-structures/baseline/preserved-assets.json").read_text()
    )
    changed = [
        name for name, digest in baseline.items() if snapshot(ROOT / name)["sha256"] != digest
    ]
    report = {
        "milestone": "living-colony",
        "baseline_commit": "9dc417b2be790b58ecf49c1490edbc248d2ffb82",
        "image_generation": {
            "method": "built-in imagegen",
            "concept": "concepts/command-arrival.png",
            "exact_prompt": "concepts/prompt.txt",
        },
        "new_meshy_credits": 0,
        "meshy_reuse": {
            "models": 13,
            "prior_actual_credits": 507,
            "pending_credits": 0,
            "unused_prior_allowance": 743,
            "source_batch": "assets-production/batches/remaining-structures/provenance.json",
        },
        "rebuild": "mise exec -- just world-living-build",
        "preservation": {"files_checked": len(baseline), "changed": changed},
        "files": {
            str(path.relative_to(ROOT)): snapshot(path)
            for path in sorted(files)
            if path.is_file() and not path.name.endswith((".blend1", ".blend2"))
        },
        "qualification": (
            "Selected production and integration inputs; the qualified export manifest "
            "binds the full world source tree. See evidence/world/living-colony; "
            "this snapshot alone "
            "does not certify a build or owner art approval."
        ),
    }
    (HERE / "provenance.json").write_text(json.dumps(report, indent=2) + "\n")
    print(
        f"LIVING_PROVENANCE: {len(report['files'])} files; "
        f"{len(baseline)} preservation checks; changed={changed}; new Meshy credits=0"
    )
    if changed:
        raise SystemExit("Preserved Engineering/character assets changed")


if __name__ == "__main__":
    main()
