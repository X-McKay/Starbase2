"""Offline effect-boundary checks for the task-scoped Meshy batch."""

import importlib.util
import json
import sys
from collections.abc import Callable
from pathlib import Path
from types import ModuleType, SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[3]


class FakeMeshy(ModuleType):
    _cmd_check_env: Callable[..., None]
    record_task: Callable[..., None]
    save_thumbnail: Callable[..., None]
    create_task: Callable[..., str]
    get_project_dir: Callable[..., str]
    _cmd_get: Callable[..., None]
    download: Callable[..., int]


@pytest.fixture
def batch(tmp_path, monkeypatch):
    fake = FakeMeshy("meshy_task")
    calls = []
    fake._cmd_check_env = lambda args: None
    fake.record_task = lambda *args, **kwargs: None
    fake.save_thumbnail = lambda *args: None
    monkeypatch.setitem(sys.modules, "meshy_task", fake)
    previous_path = sys.path[:]
    spec = importlib.util.spec_from_file_location(
        "remaining_generation", ROOT / "assets-production/batches/remaining-structures/generate.py"
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    monkeypatch.setattr(sys, "path", previous_path)
    monkeypatch.setattr(module, "ROOT", tmp_path)
    monkeypatch.setattr(module, "PLAN", tmp_path / "plan.json")
    monkeypatch.setattr(
        module, "LEDGER", tmp_path / "meshy_output/remaining-structures-ledger.json"
    )
    monkeypatch.chdir(tmp_path)
    module.PLAN.write_text(
        json.dumps(
            {
                "status": "approved",
                "approved_credit_cap": 1250,
                "prior_generation_credits": 0,
                "material_direction": "Synthetic test material",
                "assets": [{"id": name, "description": "Synthetic prop"} for name in ("a", "b")],
            }
        )
    )

    def create(endpoint, payload):
        # Observe the durable reservation at the precise dispatch boundary.
        ledger = json.loads(module.LEDGER.read_text())
        assert any(item["status"] == "submitting" for item in ledger["stages"].values())
        calls.append(endpoint)
        return "synthetic-task"

    def directory(*args):
        path = tmp_path / "meshy_output/synthetic-project"
        path.mkdir(parents=True, exist_ok=True)
        return str(path)

    def get(args):
        Path(args.save).write_text(
            json.dumps(
                {
                    "status": "SUCCEEDED",
                    "consumed_credits": 9,
                    "image_urls": ["synthetic-download-reference"],
                }
            )
        )

    fake.create_task = create
    fake.get_project_dir = directory
    fake._cmd_get = get
    fake.download = lambda url, path: Path(path).write_bytes(b"synthetic image")
    return module, fake, calls


def options(asset="a", stage="image", mode="submit_only"):
    return SimpleNamespace(
        asset=asset,
        stage=stage,
        submit_only=mode == "submit_only",
        finish=mode == "finish",
        status=mode == "status",
    )


def test_dispatch_persists_reservation_and_resume_never_resubmits(batch):
    module, _, calls = batch
    module.run(options())
    module.run(options())
    assert len(calls) == 1
    assert json.loads(module.LEDGER.read_text())["stages"]["a/image"]["task_id"] == "synthetic-task"


def test_finish_unknown_task_never_dispatches(batch):
    module, _, calls = batch
    with pytest.raises(module.SafeStop, match="No existing task"):
        module.run(options(mode="finish"))
    assert not calls


def test_concept_review_gates_mesh_dispatch(batch):
    module, _, calls = batch
    module.run(options())
    module.run(options(mode="finish"))
    with pytest.raises(module.SafeStop, match="inspected concept"):
        module.run(options(stage="mesh"))
    assert len(calls) == 1


def test_uncertain_submission_retains_reservation_and_blocks_later_post(batch):
    module, fake, calls = batch

    def uncertain(endpoint, payload):
        calls.append(endpoint)
        raise TimeoutError("Synthetic uncertain POST")

    fake.create_task = uncertain
    with pytest.raises(module.SafeStop, match="Submission unconfirmed"):
        module.run(options())
    with pytest.raises(module.SafeStop, match="Reconcile uncertain"):
        module.run(options(asset="b"))
    ledger = json.loads(module.LEDGER.read_text())
    assert module.summary(ledger)["pending_reservations"] == 9
    assert len(calls) == 1


def test_pending_reservations_enforce_cap(batch):
    module, _, calls = batch
    module.atomic_json(
        module.LEDGER,
        {
            "stages": {
                "prior/image": {"status": "pending", "task_id": "known", "reserved_credits": 1242}
            }
        },
    )
    with pytest.raises(module.SafeStop, match="exceeds approved cap"):
        module.run(options())
    assert not calls


def test_actual_charge_replaces_estimate(batch):
    module, fake, _ = batch
    module.run(options())

    def failed(args):
        Path(args.save).write_text(json.dumps({"status": "FAILED", "consumed_credits": 0}))

    fake._cmd_get = failed
    module.run(options(mode="finish"))
    result = module.summary(json.loads(module.LEDGER.read_text()))
    assert result["actual_credits"] == 0
    assert result["pending_reservations"] == 0
    assert result["remaining_authorized"] == 1250


def test_missing_actual_charge_keeps_reservation(batch):
    module, fake, _ = batch
    module.run(options())
    fake._cmd_get = lambda args: Path(args.save).write_text(json.dumps({"status": "FAILED"}))
    with pytest.raises(module.SafeStop, match="lacks actual consumed_credits"):
        module.run(options(mode="finish"))
    assert module.summary(json.loads(module.LEDGER.read_text()))["pending_reservations"] == 9


def test_single_writer_lock_blocks_dispatch(batch):
    module, _, calls = batch
    module.LEDGER.parent.mkdir(parents=True)
    with module.LEDGER.with_suffix(".lock").open("a") as lock:
        module.fcntl.flock(lock, module.fcntl.LOCK_EX | module.fcntl.LOCK_NB)
        with pytest.raises(module.SafeStop, match="writer is active"):
            module.run(options())
    assert not calls


def test_returned_id_survives_local_directory_failure(batch):
    module, fake, calls = batch
    original_directory = fake.get_project_dir

    def fail_directory(*args):
        raise OSError("Synthetic local storage failure")

    fake.get_project_dir = fail_directory
    with pytest.raises(OSError):
        module.run(options())
    fake.get_project_dir = original_directory
    module.run(options())
    assert len(calls) == 1
    assert json.loads(module.LEDGER.read_text())["stages"]["a/image"]["task_id"] == "synthetic-task"


def test_known_task_can_finish_while_other_submission_is_uncertain(batch):
    module, _, calls = batch
    module.run(options())
    ledger = json.loads(module.LEDGER.read_text())
    ledger["stages"]["b/image"] = {"status": "uncertain_submission", "reserved_credits": 9}
    module.atomic_json(module.LEDGER, ledger)
    module.run(options(mode="finish"))
    ledger = json.loads(module.LEDGER.read_text())
    assert ledger["stages"]["a/image"]["status"] == "complete"
    assert ledger["stages"]["b/image"]["status"] == "uncertain_submission"
    assert len(calls) == 1


def test_reference_concept_uses_image_edit_and_resumes_recorded_endpoint(batch):
    module, fake, calls = batch
    concept = module.ROOT / "concept.png"
    concept.write_bytes(b"\x89PNG\r\n\x1a\nsynthetic image bytes")
    plan = json.loads(module.PLAN.read_text())
    plan["assets"][0]["reference_image_path"] = "concept.png"
    module.PLAN.write_text(json.dumps(plan))
    original_create = fake.create_task
    submitted = {}

    def create(endpoint, payload):
        submitted.update(payload)
        return original_create(endpoint, payload)

    fake.create_task = create
    module.run(options())
    assert calls == ["/openapi/v1/image-to-image"]
    assert submitted["reference_image_urls"][0].startswith("data:image/png;base64,")
    assert "reference_image_urls" not in module.LEDGER.read_text()
    assert "base64" not in module.LEDGER.read_text()
    # A later plan change cannot redirect retrieval of the existing paid task.
    del plan["assets"][0]["reference_image_path"]
    module.PLAN.write_text(json.dumps(plan))
    original_get = fake._cmd_get
    retrieved = []

    def get(args):
        retrieved.append(args.endpoint)
        return original_get(args)

    fake._cmd_get = get
    module.run(options(mode="finish"))
    assert retrieved == ["/openapi/v1/image-to-image"]
    assert len(calls) == 1


@pytest.mark.parametrize("reference", ["../outside.png", "/tmp/outside.png", "missing.png"])
def test_invalid_reference_never_reserves_or_dispatches(batch, reference):
    module, _, calls = batch
    plan = json.loads(module.PLAN.read_text())
    plan["assets"][0]["reference_image_path"] = reference
    module.PLAN.write_text(json.dumps(plan))
    with pytest.raises(module.SafeStop):
        module.run(options())
    assert not calls
    assert not module.LEDGER.exists()


def test_reviewed_hull_uses_selected_topology_and_texture_settings(batch):
    module, fake, calls = batch
    module.run(options())
    module.run(options(mode="finish"))
    plan = json.loads(module.PLAN.read_text())
    plan["assets"][0].update(
        reviewed_image_task_id="synthetic-task", polycount=50000, texture_resolution="4k"
    )
    module.PLAN.write_text(json.dumps(plan))
    original_create = fake.create_task
    submitted = {}

    def create(endpoint, payload):
        submitted.update(payload)
        return original_create(endpoint, payload)

    fake.create_task = create
    module.run(options(stage="mesh"))
    assert calls[-1] == "/openapi/v1/image-to-3d"
    assert submitted["target_polycount"] == 50000
    assert submitted["texture_resolution"] == "4k"
    assert submitted["enable_pbr"] is True
    ledger = json.loads(module.LEDGER.read_text())
    assert ledger["stages"]["a/mesh"]["reserved_credits"] == 30
