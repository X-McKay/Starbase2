"""Run one reviewed Meshy stage, preserving IDs and refusing uncertain retries.

Use --stage image, mesh, remesh, texture, rig or animation and --asset ID.
The plan must contain an explicit approved_credit_cap before any dispatch.
"""

import argparse
import base64
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".agents/skills/meshy-3d-generation/scripts"))
from meshy_task import (  # noqa: E402
    create_task,
    download,
    get_project_dir,
    poll_task,
    record_task,
)

parser = argparse.ArgumentParser()
parser.add_argument("--asset", required=True)
parser.add_argument("--submit-only", action="store_true")
parser.add_argument(
    "--stage", choices=["image", "mesh", "remesh", "texture", "rig", "animation"], required=True
)
args = parser.parse_args()
plan = json.loads(Path(__file__).with_name("plan.json").read_text())
asset = next(item for item in plan["assets"] if item["id"] == args.asset)
ledger_path = ROOT / "meshy_output/engineering-polish-ledger.json"
ledger = json.loads(ledger_path.read_text()) if ledger_path.exists() else {"stages": {}}
stages = ledger["stages"]
key = args.asset + "/" + args.stage
costs = {"image": 9, "mesh": 20, "remesh": 5, "texture": 10, "rig": 5, "animation": 3}
endpoints = {
    "image": "image-to-image",
    "mesh": "image-to-3d",
    "remesh": "remesh",
    "texture": "retexture",
    "rig": "rigging",
    "animation": "animations",
}
endpoint = "/openapi/v1/" + endpoints[args.stage]


def save():
    ledger_path.parent.mkdir(exist_ok=True)
    ledger_path.write_text(json.dumps(ledger, indent=2) + "\n")


def previous(stage):
    item = stages[args.asset + "/" + stage]
    assert item["status"] == "complete", "Complete and inspect the prior stage first"
    return item, json.loads(Path(item["result_file"]).read_text())


if key not in stages:
    cap = plan.get("approved_credit_cap", 0)
    assert plan["status"] == "approved" and cap > 0, "Explicit batch credit approval required"
    assert all(item["status"] != "submitting" for item in stages.values()), (
        "Reconcile uncertain submission before further effects"
    )
    reserved = sum(
        item.get("consumed_credits", item["reserved_credits"]) for item in stages.values()
    )
    assert plan.get("prior_generation_credits", 0) + reserved + costs[args.stage] <= cap, (
        "Approved credit cap would be exceeded"
    )
    if args.stage == "image":
        payload = {
            "ai_model": "nano-banana-pro",
            "aspect_ratio": "1:1",
            "prompt": asset["description"]
            + " "
            + plan["material_direction"]
            + " Single isolated complete object centered on neutral light gray background, "
            "even studio illumination, readable three-dimensional form, "
            "no text, no collage, no ground plane.",
        }
        concept = Path(__file__).with_name("concept-v1.png").read_bytes()
        payload["reference_image_urls"] = [
            "data:image/png;base64," + base64.b64encode(concept).decode()
        ]
        payload["prompt"] += (
            " Use the attached concept only for design and materials; "
            "show only this isolated asset, not the surrounding building or two-panel composition."
        )
    elif args.stage == "mesh":
        source, _ = previous("image")
        payload = {
            "input_task_id": source["task_id"],
            "ai_model": "meshy-6",
            "should_texture": False,
            "should_remesh": False,
            "multi_view_thumbnails": True,
        }
        if asset["rig"]:
            payload["pose_mode"] = "t-pose"
    elif args.stage == "remesh":
        source, _ = previous("mesh")
        payload = {
            "input_task_id": source["task_id"],
            "target_polycount": asset["polycount"],
            "topology": "triangle",
            "target_formats": ["glb"],
            "resize_height": asset["height_m"],
            "origin_at": "bottom",
        }
    elif args.stage == "texture":
        _, result = previous("remesh")
        payload = {
            "model_url": result["model_urls"]["glb"],
            "ai_model": "meshy-6",
            "text_style_prompt": plan["material_direction"],
            "enable_pbr": True,
            "texture_resolution": "2k" if asset["rig"] else "4k",
            "remove_lighting": True,
            "target_formats": ["glb"],
        }
    elif args.stage == "rig":
        assert asset["rig"] and asset["polycount"] <= 300000
        source, result = previous(asset.get("source_stage", "texture"))
        payload = {"height_meters": asset["height_m"]}
        if asset.get("rig_model_url"):
            payload["model_url"] = result["model_urls"]["glb"]
        else:
            payload["input_task_id"] = source["task_id"]
    else:
        source, _ = previous("rig")
        assert "reviewed_action_id" in plan["character_extra"], (
            "Select an actual catalog animation first"
        )
        payload = {
            "rig_task_id": source["task_id"],
            "action_id": plan["character_extra"]["reviewed_action_id"],
        }
    item = {
        "status": "submitting",
        "reserved_credits": costs[args.stage],
        "payload": {k: v for k, v in payload.items() if k != "reference_image_urls"},
        "concept_sha256": hashlib.sha256(
            Path(__file__).with_name("concept-v1.png").read_bytes()
        ).hexdigest(),
    }
    stages[key] = item
    save()
    item["task_id"] = create_task(endpoint, payload)
    item["directory"] = (
        get_project_dir(item["task_id"], args.asset)
        if args.stage == "image"
        else stages[args.asset + ("/source" if asset.get("source_stage") else "/image")][
            "directory"
        ]
    )
    item["status"] = "pending"
    save()
    record_task(
        item["directory"],
        item["task_id"],
        endpoints[args.stage],
        args.stage,
        prompt=asset["description"],
    )
if args.submit_only:
    print("Submitted", key)
    sys.exit(0)
item = stages[key]
assert "task_id" in item, "Uncertain submission must be reconciled, not retried"
if item["status"] != "complete":
    result = poll_task(endpoint, item["task_id"], timeout=900)
    result_path = Path(item["directory"]) / (args.stage + "-task.json")
    result_path.write_text(json.dumps(result, indent=2) + "\n")
    item["result_file"] = str(result_path)
    item["consumed_credits"] = result.get("consumed_credits", item["reserved_credits"])
    files = []
    if args.stage == "image":
        for index, url in enumerate(result["image_urls"]):
            path = Path(item["directory"]) / f"design-{index}.png"
            download(url, str(path))
            files.append(str(path))
    elif result.get("model_urls", {}).get("glb"):
        path = Path(item["directory"]) / (args.stage + ".glb")
        download(result["model_urls"]["glb"], str(path))
        files.append(str(path))
    if args.stage in ["rig", "animation"]:
        body = result.get("result", result)
        urls = {
            "rigged-character": body.get("rigged_character_glb_url"),
            "idle": body.get("animation_glb_url"),
        }
        for motion in ["walking", "running"]:
            urls[motion] = body.get("basic_animations", {}).get(motion + "_glb_url")
        for name, url in urls.items():
            if url:
                path = Path(item["directory"]) / (name + ".glb")
                download(url, str(path))
                files.append(str(path))
    item["files"] = files
    item["status"] = "complete"
    save()
print(
    json.dumps(
        {
            "asset": args.asset,
            "stage": args.stage,
            "status": item["status"],
            "files": item.get("files", []),
        }
    )
)
