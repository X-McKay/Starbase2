"""Prepare the selected sofa using the inspected static-prop preparation path; no API calls."""

import json
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import prepare_remaining_props as preparation  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ASSET = "habitat-lounge-sofa"


def main():
    preparation.require(bpy.app.background, "Use background Blender")
    preparation.require(bpy.app.version[:3] == (5, 2, 1), "Requires Blender 5.2.1")
    plan = json.loads((ROOT / "assets-production/batches/inhabited-polish/plan.json").read_text())
    ledger = json.loads((ROOT / "meshy_output/inhabited-polish-ledger.json").read_text())
    asset = next(item for item in plan["assets"] if item["id"] == ASSET)
    item = ledger["stages"][ASSET + "/mesh"]
    preparation.require(item.get("status") == "complete", "Finish the selected mesh first")
    source = Path(item["files"][0]).resolve()
    preparation.require(source.is_relative_to(ROOT / "meshy_output"), "Keep original inputs local")
    preparation.TARGETS[ASSET] = (3.45, 1.35, 1.35)
    preparation.prepare(asset, item, source)


if __name__ == "__main__":
    main()
