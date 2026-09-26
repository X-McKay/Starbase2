"""Independent readiness gates, including false-positive and stale-evidence controls."""

import copy
import hashlib
import io
import json
import tarfile

import pytest

from scripts.readiness.contract import Observation, grade, manifest, repair, scope_errors

IMAGE = "localhost/readiness@sha256:" + "a" * 64
REVISION = "b" * 40


def healthy():
    return [
        Observation(
            elapsed_seconds=t,
            revision=REVISION,
            flux_current=True,
            workload_current=True,
            ready=True,
            pod_uid="one-pod",
            restarts=0,
            functional=True,
        )
        for t in (0.0, 2.0, 4.0)
    ]


def test_route_repair_preserves_scope_and_needs_independent_work():
    seed = manifest("route-mismatch", IMAGE)
    fixed = repair(seed, "route-mismatch")
    assert scope_errors(seed, fixed) == []
    assert grade(seed, fixed, REVISION, healthy(), "repair")["verdict"] == "verified-repair"
    samples = healthy()
    samples[-1].functional = False
    assert grade(seed, fixed, REVISION, samples, "repair")["verdict"] == "failed"


def test_python_repair_changes_interpreter_not_assertion():
    seed = manifest("python-environment", IMAGE)
    fixed = repair(seed, "python-environment")
    before = seed["spec"]["template"]["spec"]["containers"][0]
    after = fixed["spec"]["template"]["spec"]["containers"][0]
    assert (
        before["readinessProbe"]["exec"]["command"][1:]
        == after["readinessProbe"]["exec"]["command"][1:]
    )
    assert scope_errors(seed, fixed) == []


def test_weakened_probe_and_unrelated_mutation_are_ineligible():
    seed = manifest("route-mismatch", IMAGE)
    for field, value in (("readinessProbe", {"tcpSocket": {"port": "http"}}), ("image", "other")):
        changed = copy.deepcopy(seed)
        changed["spec"]["template"]["spec"]["containers"][0][field] = value
        assert grade(seed, changed, REVISION, healthy(), "repair")["verdict"] == "ineligible"
    removed = copy.deepcopy(seed)
    del removed["spec"]["template"]["spec"]["containers"][0]["livenessProbe"]
    assert scope_errors(seed, removed)


def test_stale_revision_and_generation_cannot_certify_repair():
    seed = manifest("route-mismatch", IMAGE)
    for field, value in (
        ("revision", "c" * 40),
        ("flux_current", False),
        ("workload_current", False),
    ):
        samples = healthy()
        setattr(samples[-1], field, value)
        assert (
            grade(seed, repair(seed, "route-mismatch"), REVISION, samples, "repair")["verdict"]
            == "invalid"
        )


def test_wait_control_requires_stability_and_no_change():
    seed = manifest("transient-dependency", IMAGE)
    assert grade(seed, seed, REVISION, healthy(), "wait")["verdict"] == "verified-no-change"
    assert grade(seed, seed, REVISION, healthy()[:1], "wait")["verdict"] == "invalid"
    samples = healthy()
    samples[-1].pod_uid = "replacement"
    assert grade(seed, seed, REVISION, samples, "wait")["verdict"] == "failed"


def test_persistent_failure_is_blocked_not_success():
    seed = manifest("persistent-dependency", IMAGE)
    samples = healthy()
    for sample in samples:
        sample.ready = sample.functional = False
        sample.elapsed_seconds += 30
    assert grade(seed, seed, REVISION, samples, "escalate")["verdict"] == "blocked"
    assert grade(seed, seed, REVISION, samples, "wait")["verdict"] == "failed"
    assert grade(seed, seed, REVISION, healthy(), "escalate")["verdict"] == "invalid"
    samples = healthy()
    for sample in samples:
        sample.elapsed_seconds += 30
    assert grade(seed, seed, REVISION, samples, "escalate")["verdict"] == "failed"


def test_liveness_is_not_a_readiness_replacement():
    seed = manifest("route-mismatch", IMAGE)
    proposed = repair(seed, "route-mismatch")
    proposed["spec"]["template"]["spec"]["containers"][0]["readinessProbe"]["httpGet"]["path"] = (
        "/live"
    )
    assert grade(seed, proposed, REVISION, healthy(), "repair")["verdict"] == "ineligible"


def test_repair_claim_without_change_and_unknown_evidence_fail_closed():
    seed = manifest("healthy", IMAGE)
    assert grade(seed, seed, REVISION, healthy(), "repair")["verdict"] == "failed"
    assert grade(seed, seed, REVISION, [], "wait")["verdict"] == "invalid"
    samples = healthy()
    samples[-1].functional = None
    assert grade(seed, seed, REVISION, samples, "wait")["verdict"] == "invalid"


def test_functional_grader_rejects_wrong_json_numeric_types():
    from scripts.readiness.run import functional

    answers: list[dict] = [
        {"status": 200, "body": {"value": value, "result": result}}
        for value, result in ((-3, 10), (0, 1), (7, 50))
    ]
    assert functional(answers)
    for result in (True, 1.0, "1"):
        changed = copy.deepcopy(answers)
        changed[1]["body"]["result"] = result
        assert not functional(changed)


def test_imported_image_must_match_digest_before_aliasing():
    from scripts.readiness.run import verify_imported_image

    header = "REF TYPE DIGEST SIZE PLATFORMS LABELS\n"
    row = (
        "localhost/fixture:test application/vnd.oci.image.manifest.v1+json "
        "sha256:abc 1MiB linux/arm64 -\n"
    )
    verify_imported_image(header + row, "localhost/fixture:test", "sha256:abc")
    for listing in (header, header + row + row, header + row.replace("sha256:abc", "sha256:other")):
        with pytest.raises(RuntimeError, match="differs"):
            verify_imported_image(listing, "localhost/fixture:test", "sha256:abc")


def test_export_is_bound_to_built_config_and_checksums(tmp_path):
    from scripts.readiness.run import archive_digest

    config = json.dumps(
        {"os": "linux", "architecture": "arm64", "rootfs": {"diff_ids": []}}
    ).encode()
    config_digest = "sha256:" + hashlib.sha256(config).hexdigest()
    image = json.dumps({"config": {"digest": config_digest}, "layers": []}).encode()
    image_digest = "sha256:" + hashlib.sha256(image).hexdigest()
    index = json.dumps(
        {
            "manifests": [
                {
                    "digest": image_digest,
                    "annotations": {
                        "org.opencontainers.image.ref.name": "localhost/fixture:test",
                    },
                }
            ]
        }
    ).encode()
    archive = tmp_path / "image.tar"
    with tarfile.open(archive, "w") as bundle:
        for name, payload in (
            ("index.json", index),
            ("blobs/sha256/" + image_digest.split(":")[1], image),
            ("blobs/sha256/" + config_digest.split(":")[1], config),
        ):
            member = tarfile.TarInfo(name)
            member.size = len(payload)
            bundle.addfile(member, io.BytesIO(payload))
    assert archive_digest(archive, "localhost/fixture:test", config_digest) == image_digest
    with pytest.raises(RuntimeError, match="config differs"):
        archive_digest(archive, "localhost/fixture:test", "sha256:" + "0" * 64)
    with pytest.raises(RuntimeError, match="reference differs"):
        archive_digest(archive, "localhost/other:test", config_digest)
    with tarfile.open(archive, "a") as bundle:
        member = tarfile.TarInfo("blobs/sha256/" + config_digest.split(":")[1])
        member.size = 2
        bundle.addfile(member, io.BytesIO(b"{}"))
    with pytest.raises(RuntimeError, match="checksum mismatch"):
        archive_digest(archive, "localhost/fixture:test", config_digest)


def test_rollout_waits_for_target_process_without_requiring_readiness(tmp_path, monkeypatch):
    from scripts.readiness.run import Lab

    lab = Lab(tmp_path / "run")
    old: dict = {
        "metadata": {"uid": "old", "annotations": {"lab.starbase2/manifest": "old"}},
        "status": {
            "phase": "Running",
            "containerStatuses": [
                {"name": "worker", "ready": True, "state": {"running": {}}},
            ],
        },
    }
    new = copy.deepcopy(old)
    new["metadata"] = {"uid": "new", "annotations": {"lab.starbase2/manifest": "target"}}
    new["status"]["containerStatuses"][0]["ready"] = False
    deliveries = iter(({"items": [old]}, {"items": [old, new]}))
    monkeypatch.setattr(lab, "get", lambda resource: next(deliveries))
    monkeypatch.setattr("scripts.readiness.run.time.sleep", lambda seconds: None)
    assert lab.wait_workload("target")["pod_uid"] == "new"


def test_sampler_does_not_stop_with_stale_flux_inside_success_window(tmp_path, monkeypatch):
    from dataclasses import asdict

    from scripts.readiness.run import Lab

    lab = Lab(tmp_path / "run")
    observations = []
    for index in range(5):
        sample = healthy()[0]
        sample.elapsed_seconds = index * 2.0
        sample.flux_current = index != 1
        observations.append((sample, {"observation": asdict(sample)}))
    deliveries = iter(observations)
    monkeypatch.setattr(lab, "observe", lambda *args: next(deliveries))
    monkeypatch.setattr("scripts.readiness.run.time.sleep", lambda seconds: None)
    samples = lab.sample(REVISION, "target", 45, True)
    assert len(samples) == 5
    assert all(item["observation"]["flux_current"] for item in samples[-3:])
