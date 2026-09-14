"""Release image names stay in the Starbase2 registry namespace."""

import json
import sys

import pytest

from scripts.deployment import build


def inputs(tmp_path, registry):
    data = {"platform": "linux/amd64", "registry": registry}
    data.update(
        {name: "registry.test/base@sha256:" + "a" * 64 for name in ("rust", "base", "python", "uv")}
    )
    path = tmp_path / "build.json"
    path.write_text(json.dumps(data))
    return path


@pytest.mark.parametrize(
    "registry",
    [
        "registry.test/starbase",
        "registry.test",
        "registry.test/starbase2/nested",
        "registry.test/starbase2/",
        "registry.test/not-starbase2",
    ],
)
def test_rejects_images_outside_starbase2_before_build(tmp_path, monkeypatch, registry):
    monkeypatch.setattr(sys, "argv", ["build", str(inputs(tmp_path, registry)), "--execute"])
    monkeypatch.setattr(
        build.subprocess,
        "check_output",
        lambda *a, **k: pytest.fail("Git must not run for invalid image namespace"),
    )
    monkeypatch.setattr(
        build.subprocess,
        "run",
        lambda *a, **k: pytest.fail("Build must not run for invalid image namespace"),
    )
    with pytest.raises(ValueError, match="starbase2"):
        build.main()


@pytest.mark.parametrize(
    "registry", ["registry.test/starbase2", "registry.test:5000/team/starbase2"]
)
def test_scoped_build_plan_keeps_both_components_under_starbase2(
    tmp_path, monkeypatch, capsys, registry
):
    monkeypatch.setattr(sys, "argv", ["build", str(inputs(tmp_path, registry))])
    monkeypatch.setattr(
        build.subprocess,
        "check_output",
        lambda args, **kw: "b" * 40 if args[1] == "rev-parse" else b"",
    )
    monkeypatch.setattr(
        build.subprocess, "run", lambda *a, **k: pytest.fail("Plan must not execute")
    )
    build.main()
    output = capsys.readouterr().out
    for component in ("core", "runtime"):
        assert f"--tag {registry}/{component}:" + "b" * 40 in output
