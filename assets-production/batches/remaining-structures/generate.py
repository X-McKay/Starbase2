"""Task-scoped Meshy stages; no dispatch occurs on import.

Populate plan assets with id, description, optional polycount (default 18000).
Optional reference_image_path is a project-relative PNG/JPEG concept used for
image-to-image. texture_resolution defaults to 2k; 4k/8k are also supported.
Submit concepts with --stage image --submit-only, then --stage image --finish.
Inspect design-0.png and set reviewed_image_task_id to its exact task ID in the
asset plan before --stage mesh --submit-only. Finish mesh with --finish.
--status is offline. --finish never submits. An uncertain POST blocks all new
submissions; reconcile provider state and its reserved ledger entry manually.
No automatic submission retries are performed, including definite rejections.
"""

import argparse
import base64
import contextlib
import fcntl
import hashlib
import io
import json
import math
import os
import re
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[3]
PLAN = Path(__file__).with_name("plan.json")
LEDGER = ROOT / "meshy_output/remaining-structures-ledger.json"
sys.path.insert(0, str(ROOT / ".agents/skills/meshy-3d-generation/scripts"))
import meshy_task as meshy  # noqa: E402

ENDPOINTS = {"image": "/openapi/v1/text-to-image", "mesh": "/openapi/v1/image-to-3d"}
COSTS = {"image": 9, "mesh": 30}


class SafeStop(Exception):
    """Only locally authored, nonsecret messages may be printed."""


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def quiet(function, *args, **kwargs):
    # Bundled CLI helpers can emit key prefixes and errors containing signed URLs.
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        return function(*args, **kwargs)


def require(condition, message):
    if not condition:
        raise SafeStop(message)


def reference_image_data(relative_path):
    require(isinstance(relative_path, str), "Reference image path must be a string")
    path = Path(relative_path)
    require(not path.is_absolute(), "Reference image path must be project relative")
    resolved = (ROOT / path).resolve()
    require(resolved.is_relative_to(ROOT.resolve()), "Reference image must remain inside project")
    require(resolved.is_file(), "Reference image is missing")
    require(
        resolved.suffix.lower() in (".png", ".jpg", ".jpeg"), "Reference image must be PNG or JPEG"
    )
    data = resolved.read_bytes()
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        mime = "image/png"
    elif data.startswith(b"\xff\xd8\xff"):
        mime = "image/jpeg"
    else:
        raise SafeStop("Reference image does not have a PNG or JPEG signature")
    return f"data:{mime};base64," + base64.b64encode(data).decode("ascii")


def summary(ledger):
    entries = ledger["stages"]
    actual = sum(item.get("consumed_credits", 0) for item in entries.values())
    pending = sum(
        item["reserved_credits"] for item in entries.values() if "consumed_credits" not in item
    )
    return {
        "actual_credits": actual,
        "pending_reservations": pending,
        "remaining_authorized": 1250 - actual - pending,
        "stages": {
            key: {
                field: item[field]
                for field in ("status", "task_id", "directory", "files", "consumed_credits")
                if field in item
            }
            for key, item in entries.items()
        },
    }


def run(args):
    os.chdir(ROOT)
    LEDGER.parent.mkdir(parents=True, exist_ok=True)
    with LEDGER.with_suffix(".lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SafeStop("Another remaining-structures writer is active") from None
        plan = json.loads(PLAN.read_text())
        ledger = (
            json.loads(LEDGER.read_text())
            if LEDGER.exists()
            else {
                "version": 1,
                "approved_credit_cap": 1250,
                "prior_generation_credits": 0,
                "stages": {},
            }
        )
        if args.status:
            print(json.dumps(summary(ledger), indent=2))
            return
        require(args.asset and args.stage, "--asset and --stage are required")
        matches = [asset for asset in plan["assets"] if asset["id"] == args.asset]
        require(len(matches) == 1, "Asset must occur exactly once in the plan")
        asset = matches[0]
        require(re.fullmatch(r"[a-z0-9][a-z0-9-]*", args.asset), "Invalid asset ID")
        # Environment detection uses the bundled helper without exposing its key prefix.
        try:
            quiet(meshy._cmd_check_env, SimpleNamespace())
        except SystemExit as result:
            require(result.code == 0, "Meshy environment check failed")
        key = args.asset + "/" + args.stage
        stages = ledger["stages"]
        endpoint = ENDPOINTS[args.stage]
        if key not in stages:
            require(not args.finish, "No existing task to finish; submit explicitly first")
            require(args.submit_only, "New tasks require --submit-only")
            require(
                plan.get("status") == "approved"
                and plan.get("approved_credit_cap") == 1250
                and plan.get("prior_generation_credits") == 0,
                "This batch requires the separate approved 1250-credit cap",
            )
            require(
                all(item.get("task_id") for item in stages.values()),
                "Reconcile uncertain submission before any new POST",
            )
            require(
                summary(ledger)["remaining_authorized"] >= COSTS[args.stage],
                "Next reservation exceeds approved cap",
            )
            if args.stage == "image":
                payload = {
                    "ai_model": "nano-banana-pro",
                    "aspect_ratio": "1:1",
                    "prompt": asset["description"] + " " + plan["material_direction"],
                }
                if "reference_image_path" in asset:
                    payload["reference_image_urls"] = [
                        reference_image_data(asset["reference_image_path"])
                    ]
                    endpoint = "/openapi/v1/image-to-image"
            else:
                source = stages.get(args.asset + "/image", {})
                require(source.get("status") == "complete", "Complete and inspect image first")
                require(
                    asset.get("reviewed_image_task_id") == source.get("task_id"),
                    "Record the inspected concept task ID in reviewed_image_task_id",
                )
                result = json.loads(Path(source["result_file"]).read_text())
                index = asset.get("selected_image_index", 0)
                require(
                    index == source.get("selected_image_index", 0),
                    "Selected image differs from the downloaded concept",
                )
                resolution = asset.get("texture_resolution", "2k")
                require(resolution in ("2k", "4k", "8k"), "Unsupported texture resolution")
                polycount = asset.get("polycount", 18000)
                require(
                    type(polycount) is int and 100 <= polycount <= 300000,
                    "Polycount must be an integer from 100 to 300000",
                )
                payload = {
                    "image_url": result["image_urls"][index],
                    "ai_model": "meshy-6",
                    "should_texture": True,
                    "enable_pbr": True,
                    "texture_resolution": resolution,
                    "should_remesh": True,
                    "topology": "triangle",
                    "target_polycount": polycount,
                    "remove_lighting": True,
                    "multi_view_thumbnails": True,
                }
            item = {
                "status": "submitting",
                "reserved_credits": COSTS[args.stage],
                "endpoint": endpoint,
                "payload_sha256": hashlib.sha256(
                    json.dumps(payload, sort_keys=True).encode()
                ).hexdigest(),
            }
            stages[key] = item
            atomic_json(LEDGER, ledger)  # durable reservation precedes POST
            try:
                task_id = quiet(meshy.create_task, endpoint, payload)
            except BaseException:
                item["status"] = "uncertain_submission"
                atomic_json(LEDGER, ledger)
                raise SafeStop(
                    "Submission unconfirmed; reservation retained; reconcile before new POST"
                ) from None
            item.update(task_id=task_id, status="pending")
            atomic_json(LEDGER, ledger)  # persist ID before directory/metadata work
        item = stages[key]
        require(item.get("task_id"), "Uncertain submission must be reconciled, never retried")
        # Resume from the actual dispatch endpoint, even if the plan later changes.
        # Pre-endpoint ledger entries used text-to-image / image-to-3d exclusively.
        endpoint = item.get("endpoint", ENDPOINTS[args.stage])
        allowed = (
            (ENDPOINTS["image"], "/openapi/v1/image-to-image")
            if args.stage == "image"
            else (ENDPOINTS["mesh"],)
        )
        require(endpoint in allowed, "Recorded endpoint does not match the requested stage")
        if "directory" not in item:
            item["directory"] = (
                meshy.get_project_dir(item["task_id"], args.asset)
                if args.stage == "image"
                else stages[args.asset + "/image"]["directory"]
            )
            atomic_json(LEDGER, ledger)
        if args.submit_only or item["status"] == "complete":
            print(json.dumps(summary(ledger), indent=2))
            return
        directory = Path(item["directory"])
        result_path = directory / (args.stage + "-task.json")
        # Bundled GET saves every status, including FAILED/CANCELED, for exact charges.
        quiet(
            meshy._cmd_get,
            SimpleNamespace(endpoint=endpoint, task_id=item["task_id"], save=str(result_path)),
        )
        result = json.loads(result_path.read_text())
        item["result_file"] = str(result_path)
        status = result["status"]
        item["status"] = status.lower()
        if status not in ("SUCCEEDED", "FAILED", "CANCELED"):
            atomic_json(LEDGER, ledger)
            print(json.dumps(summary(ledger), indent=2))
            return
        actual = result.get("consumed_credits")
        require(
            type(actual) in (int, float) and math.isfinite(actual) and actual >= 0,
            "Terminal task lacks actual consumed_credits; reservation remains held",
        )
        item["consumed_credits"] = actual
        atomic_json(LEDGER, ledger)  # charge survives a download failure
        if status != "SUCCEEDED":
            print(json.dumps(summary(ledger), indent=2))
            return
        files = []
        if args.stage == "image":
            index = asset.get("selected_image_index", 0)
            targets = [(result["image_urls"][index], directory / f"design-{index}.png")]
            item["selected_image_index"] = index
        else:
            targets = [(result["model_urls"]["glb"], directory / "mesh.glb")]
        for url, path in targets:
            quiet(meshy.download, url, str(path) + ".partial")
            os.replace(str(path) + ".partial", path)
            files.append(str(path))
        if result.get("thumbnail_url"):
            quiet(meshy.save_thumbnail, str(directory), result["thumbnail_url"])
        quiet(
            meshy.record_task,
            str(directory),
            item["task_id"],
            endpoint.rsplit("/", 1)[-1],
            args.stage,
            prompt=asset["description"],
            files=files,
        )
        item.update(status="complete", files=files)
        atomic_json(LEDGER, ledger)
        print(json.dumps(summary(ledger), indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset")
    parser.add_argument("--stage", choices=ENDPOINTS)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--submit-only", action="store_true")
    mode.add_argument(
        "--finish",
        action="store_true",
        help="One status check and download if complete; never POST",
    )
    mode.add_argument("--status", action="store_true")
    try:
        run(parser.parse_args())
    except SafeStop as error:
        print(f"STOP: {error}", file=sys.stderr)
        return 1
    except BaseException as error:
        # Never echo provider exception text: it may contain credentials or signed URLs.
        print(
            f"STOP: {type(error).__name__}; retained ledger permits known-task resume",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
