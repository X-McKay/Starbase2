"""Exact-process cleanup must tolerate macOS filesystem aliases without broad kills."""

from scripts.check_world_export import native_pids


def test_native_pid_aliases_and_exact_boundary(tmp_path):
    real = tmp_path / "real"
    real.mkdir()
    alias = tmp_path / "alias"
    alias.symlink_to(real, target_is_directory=True)
    executable = alias / "Review App.app" / "Contents" / "MacOS" / "Review App"
    resolved = executable.resolve()
    listing = "\n".join(
        [
            f"10 {executable} --fixture=test",
            f"11 {resolved} --capture=test",
            f"12 {resolved}-other --capture=test",
            "13 /another/Review App --capture=test",
            f"14 python runner.py {resolved} --capture=test",
        ]
    )
    assert native_pids(executable, listing) == [10, 11]


def test_native_capture_background_launch_preserves_unicode_name(tmp_path):
    from unittest.mock import patch

    from scripts.check_world_export import native_capture

    executable = tmp_path / "Starbase2 · Aster Colony.app/Contents/MacOS/Starbase2 · Aster Colony"
    (tmp_path / "view.log").write_text("Godot Engine\n")
    (tmp_path / "view-stderr.log").write_text("")
    with (
        patch("scripts.check_world_export.subprocess.Popen") as launch,
        patch("scripts.check_world_export.run") as activate,
    ):
        launch.return_value.returncode = 0
        launch.return_value.communicate.return_value = ("", None)
        native_capture(executable, [], tmp_path, "view", tmp_path)
        command = launch.call_args.args[0]
        assert command[:4] == ["open", "-g", "-n", "-W"]
        assert str(executable.resolve().parents[2]) in command
        activate.assert_not_called()
        assert launch.return_value.communicate.call_args.kwargs["timeout"] <= 180


def test_background_timeout_cleans_up_only_exact_owned_process(tmp_path):
    import subprocess
    from unittest.mock import patch

    import pytest

    from scripts.check_world_export import native_capture

    executable = tmp_path / "Review.app/Contents/MacOS/Review"
    with (
        patch("scripts.check_world_export.subprocess.Popen") as launch,
        patch(
            "scripts.check_world_export.subprocess.check_output",
            return_value=f"101 {executable} --capture=x\n102 {executable}-other",
        ),
        patch("scripts.check_world_export.os.kill") as kill,
        patch("scripts.check_world_export.run") as activate,
    ):
        launch.return_value.poll.return_value = None
        launch.return_value.communicate.side_effect = [
            subprocess.TimeoutExpired("open", 180),
            ("", None),
        ]
        with pytest.raises(subprocess.TimeoutExpired):
            native_capture(executable, [], tmp_path, "view", tmp_path)
        launch.return_value.terminate.assert_called_once()
        assert [call.args[0] for call in kill.call_args_list] == [101]
        activate.assert_not_called()
