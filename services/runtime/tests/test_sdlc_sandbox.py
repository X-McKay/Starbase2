import asyncio
import json
from unittest.mock import AsyncMock

import pytest
from starbase_runtime import sdlc_regression
from starbase_runtime import sdlc_sandbox as sandbox


def files():
    return dict.fromkeys(sandbox.FILES, "")


def output():
    return sandbox.PREFIX + json.dumps(
        {"cases": [{"id": key, "actual": []} for key in sandbox.CASE_IDS]}
    )


@pytest.mark.parametrize(
    "bad",
    [
        {},
        {"../x": ""},
        {**files(), "extra": ""},
        {**files(), "src/__init__.py": b""},
        {**files(), "src/__init__.py": "\x00"},
        {**files(), "src/__init__.py": "x" * 24001},
    ],
)
def test_source_boundary(bad):
    with pytest.raises(ValueError):
        sandbox.program(bad)


def test_harness_has_no_expected_answers():
    source = sandbox.program(files())
    assert "assertEqual" not in source
    assert "[0, 1, 2, 3, 4]" not in source
    assert "SOURCE_FILES" in source
    assert "assertEqual" in sdlc_regression.SOURCE


@pytest.mark.parametrize(
    "value",
    [
        "",
        output() + "\n" + output(),
        sandbox.PREFIX + "{}",
        sandbox.PREFIX + '{"cases":[]}',
        sandbox.PREFIX + '{"cases":true}',
    ],
)
def test_reject_malformed_observations(value):
    with pytest.raises(ValueError):
        sandbox.observations(value)


def test_logger_noise_and_case_identity():
    assert len(sandbox.observations("logger message\n" + output())) == 7
    with pytest.raises(ValueError):
        sandbox.observations(output().replace("history_all", "history_unknown"))
    with pytest.raises(ValueError):
        sandbox.observations(output().replace("[]", "[true]", 1))


def test_exit_failure_never_grades(monkeypatch):
    execute = AsyncMock(return_value={"exit_code": 1, "stdout": output()})
    monkeypatch.setattr(sandbox, "_execute", execute)
    assert (asyncio.run(sandbox.run("sb-unit", files())))["cases"] == []


def test_pinned_vm_no_host_execution(monkeypatch):
    import asyncio

    class Process:
        returncode = 0
        stdout = type("Stream", (), {"read": AsyncMock(side_effect=[output().encode(), b""])})()
        stderr = type("Stream", (), {"read": AsyncMock(return_value=b"")})()

        async def wait(self):
            return 0

    spawn = AsyncMock(return_value=Process())
    monkeypatch.setattr(sandbox, "command", AsyncMock(return_value=(0, b"msb 0.6.14", b"")))
    remove_mock = AsyncMock()
    monkeypatch.setattr(sandbox, "remove", remove_mock)
    monkeypatch.setattr(sandbox, "executable", lambda: "/trusted/msb")
    monkeypatch.setattr(sandbox.asyncio, "create_subprocess_exec", spawn)
    result = asyncio.run(sandbox.run("sb-unit", files()))
    args = spawn.call_args.args
    assert args[0] == "/trusted/msb"
    assert args[args.index("--net") + 1] == "none"
    assert args[args.index("--pull") + 1] == "never"
    assert args[args.index("--max-duration") + 1] == "30s"
    assert "--mount" not in args and "--env" not in args
    assert sandbox.IMAGE in args
    assert "TOKEN" not in str(spawn.call_args.kwargs["env"])
    assert len(result["cases"]) == 7
    assert remove_mock.await_count == 2


def test_public_regression_is_valid_python_and_separate_from_observations():
    import ast

    tree = ast.parse(sdlc_regression.SOURCE)
    cases = [
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef) and node.name.startswith("test_")
    ]
    assert len(cases) == 7
    assert sdlc_regression.PATH not in sandbox.FILES
    assert "unittest" not in sandbox.program(files())
