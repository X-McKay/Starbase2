"""Packaged Shift Change proof uses the exact binary and retained native records."""

import json
from unittest.mock import patch

import pytest

from scripts.check_world_export import qualify_shift_change, verify_shift_report


def write_record(directory, mode):
    directory.mkdir(parents=True)
    names = [f"{mode}-occupied-habitat.png"]
    names += [f"{mode}-seated-{i:02d}.png" for i in range(4)]
    names += [f"{mode}-stand-{i:02d}.png" for i in range(5)]
    names += (
        ["domestic-fast-report.png"]
        if mode == "domestic"
        else [
            f"journey-{name}.png"
            for name in ("console-arrival", "report-ready", "home", "offline", "reconnected")
        ]
    )
    for name in names:
        (directory / name).write_bytes(b"\x89PNG\r\n\x1a\nfixture-image")
    record = {
        "mode": mode,
        "status": "passed",
        "fixture": True,
        "initial_positions_staged": True,
        "physics_after_staging": True,
        "failures": [],
        "wall_ms": 1000,
        "captures": names,
        "samples": [
            {"label": "seated", "clip": "social/seated"},
            {"label": "stand-0", "clip": "social/stand_up"},
            {"label": "working", "pose": "console"},
            {"label": "returned-home", "clip": "social/seated"},
            {"label": "report-ready", "evidence_ready": True},
            {"label": "offline", "goal": "hold", "pose": ""},
        ],
    }
    path = directory / f"{mode}-report.json"
    path.write_text(json.dumps(record))
    return path, record


def test_exact_packaged_binary_modes_fences_and_bound_artifacts(tmp_path):
    executable = tmp_path / "unpacked" / "App" / "binary"
    cwd = tmp_path / "unpacked"
    fixture = tmp_path / "world.json"
    board = tmp_path / "board.json"
    fixture.write_text("{}")
    board.write_text("{}")

    def capture(binary, arguments, output, name, working):
        assert binary == executable and working == cwd
        assert f"--fixture={fixture}" in arguments and f"--board-fixture={board}" in arguments
        mode = name.removeprefix("shift-")
        assert f"--shift-change-mode={mode}" in arguments
        write_record(output / name, mode)
        (output / f"{name}.log").write_text(f"SHIFT_CHANGE_CAPTURE_PASSED {mode}")

    with (
        patch("scripts.check_world_export.native_capture", side_effect=capture) as native,
        patch("scripts.check_world_export.run") as refusal,
    ):
        result = qualify_shift_change(executable, fixture, board, tmp_path, cwd)
    assert native.call_count == 2
    assert refusal.call_args.args[0][0] == str(executable)
    assert (
        refusal.call_args.kwargs["expected_refusal"]
        == "Package verification requires an offline fixture"
    )
    assert set(result["modes"]) == {"domestic", "journey"}
    assert len(result["modes"]["journey"]["captures"]) == 15
    assert len(result["board_fixture_sha256"]) == 64


@pytest.mark.parametrize(
    "mutation", ["failed", "missing-image", "not-fixture", "missing-offline", "incomplete-sequence"]
)
def test_incomplete_or_failed_native_proof_is_rejected(tmp_path, mutation):
    path, record = write_record(tmp_path / "journey", "journey")
    if mutation == "failed":
        record["failures"] = ["route blocked"]
    elif mutation == "missing-image":
        (path.parent / record["captures"][0]).unlink()
    elif mutation == "not-fixture":
        record["fixture"] = False
    elif mutation == "missing-offline":
        record["samples"] = [s for s in record["samples"] if s["label"] != "offline"]
    else:
        record["captures"].pop()
    path.write_text(json.dumps(record))
    with pytest.raises((RuntimeError, FileNotFoundError)):
        verify_shift_report(path.parent, "journey")
