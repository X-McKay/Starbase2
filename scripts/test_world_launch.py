"""A failed import must never open a misleading partial game."""

import subprocess
from unittest.mock import patch

import pytest

from scripts import world


@pytest.mark.parametrize("code, output", [(1, "failed"), (0, "ERROR: missing scene")])
def test_import_failure_prevents_launch(code: int, output: str) -> None:
    with (
        patch.object(
            world.subprocess, "run", return_value=subprocess.CompletedProcess([], code, output)
        ),
        patch.object(world.subprocess, "call") as launch,
        pytest.raises(SystemExit, match="World import failed"),
    ):
        world.main()
    launch.assert_not_called()


def test_import_precedes_launch_and_preserves_arguments() -> None:
    with (
        patch.object(
            world.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "Imported\n")
        ) as imported,
        patch.object(world.subprocess, "call", return_value=0) as launch,
        patch.object(world.sys, "argv", ["world.py", "--", "--fixture=test.json"]),
        pytest.raises(SystemExit) as stopped,
    ):
        world.main()
    assert stopped.value.code == 0
    assert "--import" in imported.call_args.args[0]
    assert launch.call_args.args[0][-2:] == ["--", "--fixture=test.json"]
