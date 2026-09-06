"""Release tools must preserve failures even when Godot exits zero or hangs."""

import subprocess
from unittest.mock import patch

import pytest

from scripts.check_world_export import run


def test_zero_exit_with_logged_engine_error_fails(tmp_path):
    log = tmp_path / "export.log"
    result = subprocess.CompletedProcess(["godot"], 0, "ERROR: missing atlas\n")
    with patch("scripts.check_world_export.subprocess.run", return_value=result):
        with pytest.raises(RuntimeError, match="Export check failed"):
            run(["godot"], log, tmp_path)
    assert log.read_text() == "ERROR: missing atlas\n"


def test_timeout_retains_partial_evidence(tmp_path):
    log = tmp_path / "export.log"
    failure = subprocess.TimeoutExpired(["godot"], 1, output=b"started package check\n")
    with patch("scripts.check_world_export.subprocess.run", side_effect=failure):
        with pytest.raises(RuntimeError, match="timed out"):
            run(["godot"], log, tmp_path)
    assert log.read_text() == "started package check\n"


def test_nonzero_exit_without_engine_marker_fails(tmp_path):
    log = tmp_path / "export.log"
    result = subprocess.CompletedProcess(["godot"], 2, "load failed\n")
    with patch("scripts.check_world_export.subprocess.run", return_value=result):
        with pytest.raises(RuntimeError, match="Export check failed"):
            run(["godot"], log, tmp_path)
    assert log.read_text() == "load failed\n"


def test_expected_refusal_requires_one_clean_error(tmp_path):
    result = subprocess.CompletedProcess(["godot"], 1, "ERROR: fixture required\n")
    with patch("scripts.check_world_export.subprocess.run", return_value=result):
        assert (
            run(["godot"], tmp_path / "log", tmp_path, expected_refusal="fixture required")
            == result.stdout
        )


def test_expected_refusal_does_not_hide_secondary_errors(tmp_path):
    result = subprocess.CompletedProcess(
        ["godot"], 1, "ERROR: fixture required\nERROR: resource leaked\n"
    )
    with patch("scripts.check_world_export.subprocess.run", return_value=result):
        with pytest.raises(RuntimeError, match="Expected clean refusal"):
            run(["godot"], tmp_path / "log", tmp_path, expected_refusal="fixture required")
