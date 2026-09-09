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


def test_native_activation_keeps_unicode_application_name(tmp_path):
    from unittest.mock import patch

    from scripts.check_world_export import native_capture

    executable = tmp_path / "Starbase2 · Aster Colony.app/Contents/MacOS/Starbase2 · Aster Colony"
    (tmp_path / "view.log").write_text("Godot Engine\n")
    (tmp_path / "view-stderr.log").write_text("")
    with (
        patch("scripts.check_world_export.subprocess.Popen") as launch,
        patch(
            "scripts.check_world_export.subprocess.check_output",
            return_value=f"101 {executable} --capture=x",
        ),
        patch("scripts.check_world_export.run") as activate,
    ):
        launch.return_value.poll.return_value = None
        launch.return_value.returncode = 0
        launch.return_value.communicate.return_value = ("", None)
        native_capture(executable, [], tmp_path, "view", tmp_path)
        expression = activate.call_args.args[0][2]
        assert " · " in expression
        assert "\\u00" not in expression


def test_pending_capture_reactivates_only_its_owned_app(tmp_path):
    import subprocess
    from unittest.mock import patch

    from scripts.check_world_export import native_capture

    executable = tmp_path / "Review.app/Contents/MacOS/Review"
    (tmp_path / "view.log").write_text("Godot Engine\n")
    (tmp_path / "view-stderr.log").write_text("")
    with (
        patch("scripts.check_world_export.subprocess.Popen") as launch,
        patch(
            "scripts.check_world_export.subprocess.check_output",
            return_value=f"101 {executable} --capture=x",
        ),
        patch("scripts.check_world_export.run") as activate,
    ):
        launch.return_value.poll.return_value = None
        launch.return_value.returncode = 0
        launch.return_value.communicate.side_effect = [
            subprocess.TimeoutExpired("open", 2),
            ("", None),
        ]
        native_capture(executable, [], tmp_path, "view", tmp_path)
        assert launch.call_count == 1
        assert activate.call_count == 2
        for call in activate.call_args_list:
            assert str(executable.resolve().parents[2]) in call.args[0][2]
