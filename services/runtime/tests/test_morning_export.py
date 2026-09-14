"""A saved screenshot set must not substitute for the bounded physical morning."""

import json
from unittest.mock import patch

import pytest

from scripts.check_world_export import qualify_morning, verify_morning_report


def morning_files(directory):
    captures = ["01-inhabited-habitat.png"]
    captures += [f"02-standing-{frame:02d}.png" for frame in (8, 24, 40)]
    captures += [f"minute-{second:02d}.png" for second in (15, 30, 45, 60)]
    captures += [
        "03-workstation.png",
        "04-result-ready.png",
        "05-morning-briefing.png",
        "06-retained-evidence.png",
        "07-home-again.png",
        "08-stale-briefing.png",
        "09-reduced-large-text.png",
        "10-station-records.png",
        "11-station-compact.png",
    ]
    for name in captures:
        (directory / name).write_bytes(b"\x89PNG\r\n\x1a\n")
    record = {
        "mode": "morning",
        "status": "passed",
        "fixture": True,
        "initial_positions_staged": True,
        "physics_after_staging": True,
        "failures": [],
        "wall_ms": 108000,
        "captures": captures,
        "samples": [
            {"label": "home", "clip": "social/seated"},
            {"label": "departure", "clip": "social/stand_up"},
            {"label": "working", "pose": "console", "clip": "work/field_slate"},
            {"label": "result-ready", "evidence_ready": True},
            {"label": "home-again", "clip": "social/seated"},
            {"label": "offline", "pose": "", "goal": "hold"},
            {"label": "reconnected", "evidence_ready": True},
        ],
    }
    minute = {
        "fixture": True,
        "world_fixture": True,
        "board_fixture": True,
        "commands_dispatched": False,
        "http_idle": True,
        "fixture_memory_status": "disabled",
        "initial_setup_only_teleports": True,
        "moving_frames": 300,
        "samples": [{"wall_ms": second * 1000} for second in range(108)],
    }
    (directory / "morning-report.json").write_text(json.dumps(record))
    (directory / "minute-samples.json").write_text(json.dumps(minute))
    return record, minute


def test_morning_manifest_binds_report_minute_and_native_frames(tmp_path):
    morning_files(tmp_path)
    result = verify_morning_report(tmp_path)
    assert len(result["captures"]) == 17
    assert len(result["minute_samples_sha256"]) == 64
    assert result["commands_dispatched"] is False
    assert "not production" in result["visual_acceptance"]


@pytest.mark.parametrize(
    "defect",
    [
        "short",
        "teleport",
        "command",
        "no-board",
        "memory",
        "no-motion",
        "duplicate-time",
        "still-working",
        "missing-frame",
    ],
)
def test_morning_rejects_incomplete_or_unsafe_evidence(tmp_path, defect):
    record, minute = morning_files(tmp_path)
    if defect == "short":
        minute["samples"] = minute["samples"][:55]
    elif defect == "teleport":
        minute["initial_setup_only_teleports"] = False
    elif defect == "command":
        minute["commands_dispatched"] = True
    elif defect == "no-board":
        minute["board_fixture"] = False
    elif defect == "memory":
        minute["fixture_memory_status"] = "enabled"
    elif defect == "no-motion":
        minute["moving_frames"] = 2
    elif defect == "duplicate-time":
        minute["samples"][50]["wall_ms"] = 0
    elif defect == "still-working":
        record["samples"][5]["pose"] = "console"
    elif defect == "missing-frame":
        record["captures"].pop()
    (tmp_path / "morning-report.json").write_text(json.dumps(record))
    (tmp_path / "minute-samples.json").write_text(json.dumps(minute))
    with pytest.raises(RuntimeError):
        verify_morning_report(tmp_path)


def test_morning_qualification_refuses_unfenced_modes_before_native_launch(tmp_path):
    fixture = tmp_path / "world.json"
    board = tmp_path / "board.json"
    fixture.write_text("{}")
    board.write_text("{}")
    with (
        patch("scripts.check_world_export.run") as run,
        patch("scripts.check_world_export.native_capture") as native,
    ):

        def refuse(*args, **kwargs):
            (tmp_path / "morning-refused").mkdir()

        run.side_effect = refuse
        with pytest.raises(RuntimeError, match="before its fixture fence"):
            qualify_morning(tmp_path / "app", fixture, board, tmp_path, tmp_path)
        native.assert_not_called()
