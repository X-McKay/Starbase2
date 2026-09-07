"""One approved 60-credit batch, using the bundled Meshy task implementation.

Resumes known task IDs. Refuses to retry any uncertain submission.
"""

import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / ".agents/skills/meshy-3d-generation/scripts"))
from meshy_task import (  # noqa: E402 -- bundled skill is explicitly located above
    create_task,
    download,
    get_project_dir,
    poll_task,
    record_task,
    save_thumbnail,
)

plan = json.loads((Path(__file__).with_name("generation-plan.json")).read_text())
ledger = root / "meshy_output/approved-batch.json"
ledger.parent.mkdir(exist_ok=True)
for asset in plan["assets"]:
    assert len(asset["prompt"]) <= 600
tasks = json.loads(ledger.read_text())["tasks"] if ledger.exists() else []
assert all(not item["status"].startswith("submitting") for item in tasks), (
    "Reconcile uncertain submission first"
)
endpoint = "/openapi/v2/text-to-3d"


def save():
    ledger.write_text(json.dumps({"approved_cap": 80, "tasks": tasks}, indent=2) + "\n")


for asset in plan["assets"]:
    if any(item["asset"] == asset["id"] for item in tasks):
        continue
    prompt = asset["prompt"]
    assert len(prompt) <= 600
    item = {"asset": asset["id"], "status": "submitting_preview"}
    tasks.append(item)
    save()
    task = create_task(
        endpoint,
        {
            "mode": "preview",
            "prompt": prompt,
            "ai_model": "meshy-6",
            "topology": "triangle",
            "target_polycount": 30000,
            "should_remesh": True,
            "target_formats": ["glb"],
        },
    )
    item.update(
        preview=task, directory=get_project_dir(task, asset["id"]), status="preview_pending"
    )
    save()
    record_task(item["directory"], task, "text-to-3d", "preview", prompt=prompt)

for item in tasks:
    if "refine" in item:
        continue
    preview = poll_task(endpoint, item["preview"], timeout=900)
    Path(item["directory"], "preview-task.json").write_text(json.dumps(preview, indent=2))
    item["preview_credits"] = preview.get("consumed_credits")
    item["status"] = "submitting_texture"
    save()
    item["refine"] = create_task(
        endpoint,
        {
            "mode": "refine",
            "preview_task_id": item["preview"],
            "ai_model": "meshy-6",
            "enable_pbr": True,
            "texture_resolution": "2k",
            "remove_lighting": True,
            "texture_prompt": (
                "Ivory ceramic armor panels, dark graphite recessed mechanical seams, "
                "restrained cyan luminous accents, subtle industrial wear, realistic "
                "roughness and metal, clean readable surfaces."
            ),
            "target_formats": ["glb"],
        },
    )
    item["status"] = "texture_pending"
    save()
    record_task(item["directory"], item["refine"], "text-to-3d", "refine", prompt=item["asset"])

for item in tasks:
    if item["status"] == "downloaded":
        continue
    result = poll_task(endpoint, item["refine"], timeout=900)
    Path(item["directory"], "refined-task.json").write_text(json.dumps(result, indent=2))
    item["refine_credits"] = result.get("consumed_credits")
    download(result["model_urls"]["glb"], str(Path(item["directory"], "refined.glb")))
    if result.get("thumbnail_url"):
        save_thumbnail(item["directory"], result["thumbnail_url"])
    record_task(
        item["directory"], item["refine"], "text-to-3d", "downloaded", files=["refined.glb"]
    )
    item["status"] = "downloaded"
    save()
print("BATCH_COMPLETE", flush=True)
