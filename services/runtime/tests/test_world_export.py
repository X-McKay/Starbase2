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


def test_native_launcher_success_does_not_hide_app_errors(tmp_path):
    from scripts.check_world_export import native_capture

    executable = tmp_path / "Review.app/Contents/MacOS/Review"
    (tmp_path / "interior.log").write_text("Godot Engine\n")
    (tmp_path / "interior-stderr.log").write_text("ERROR: missing texture\n")
    with patch("scripts.check_world_export.subprocess.Popen") as launch:
        launch.return_value.poll.return_value = 0
        launch.return_value.returncode = 0
        launch.return_value.communicate.return_value = ("", None)
        with pytest.raises(RuntimeError, match="Native capture failed"):
            native_capture(executable, [], tmp_path, "interior", tmp_path)


def test_native_timeout_stops_only_exact_isolated_executable(tmp_path):
    import signal

    from scripts.check_world_export import native_capture

    executable = tmp_path / "Review.app/Contents/MacOS/Review"
    processes = (
        f"101 {executable} -- --capture=interior.png\n"
        "102 /other/Review.app/Contents/MacOS/Review -- --capture=interior.png\n"
        f"103 {executable}-other -- --capture=interior.png\n"
    )
    with (
        patch("scripts.check_world_export.subprocess.Popen") as launch,
        patch("scripts.check_world_export.run", side_effect=RuntimeError("timed out")),
        patch("scripts.check_world_export.subprocess.check_output", return_value=processes),
        patch("scripts.check_world_export.os.kill") as kill,
    ):
        launch.return_value.poll.return_value = None
        launch.return_value.communicate.return_value = ("", None)
        with pytest.raises(RuntimeError, match="timed out"):
            native_capture(executable, [], tmp_path, "interior", tmp_path)
        launch.return_value.terminate.assert_called_once()
        kill.assert_called_once_with(101, signal.SIGTERM)


def test_native_communication_timeout_cleans_up_and_preserves_failure(tmp_path):
    import signal

    from scripts.check_world_export import native_capture

    executable = tmp_path / "Review.app/Contents/MacOS/Review"
    with (
        patch("scripts.check_world_export.subprocess.Popen") as launch,
        patch("scripts.check_world_export.run"),
        patch("scripts.check_world_export.time.monotonic", side_effect=[0, 1, 181]),
        patch(
            "scripts.check_world_export.subprocess.check_output",
            return_value=f"101 {executable} --capture=x",
        ),
        patch("scripts.check_world_export.os.kill") as kill,
    ):
        launch.return_value.poll.return_value = None
        launch.return_value.communicate.side_effect = [
            subprocess.TimeoutExpired("open", 180),
            ("partial launcher output", None),
        ]
        with pytest.raises(subprocess.TimeoutExpired):
            native_capture(executable, [], tmp_path, "interior", tmp_path)
        kill.assert_called_once_with(101, signal.SIGTERM)
        assert (tmp_path / "interior-launch.log").read_text() == "partial launcher output"
