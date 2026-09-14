from pathlib import Path

import pytest

from scripts import check_world_web, install_godot_web_templates


def test_installer_rejects_nonlocal_destination(tmp_path: Path) -> None:
    with pytest.raises(RuntimeError, match="exactly"):
        install_godot_web_templates.install(tmp_path / "missing.tpz", tmp_path / "templates")


def test_installer_rejects_bad_checksum(tmp_path: Path) -> None:
    archive = tmp_path / "archive.tpz"
    archive.write_bytes(b"not the official template archive")
    with pytest.raises(RuntimeError, match="Expected"):
        install_godot_web_templates.verify_archive(archive)


def test_export_error_is_retained(tmp_path: Path) -> None:
    log = tmp_path / "export.log"
    with pytest.raises(RuntimeError, match="logged errors"):
        check_world_web.run(
            ["/bin/sh", "-c", "printf 'ERROR: broken\\n'"], cwd=tmp_path, env={}, log=log, timeout=1
        )
    assert "ERROR: broken" in log.read_text()


def test_engine_log_ignores_only_known_macos_certificate_warning(tmp_path: Path) -> None:
    log = tmp_path / "engine.log"
    log.write_text('ERROR: Condition "ret != noErr" is true.\nERROR: actual failure\n')
    assert check_world_web.error_lines(log) == ["ERROR: actual failure"]


def test_package_check_uses_fresh_empty_project_directory(tmp_path: Path) -> None:
    project = tmp_path / "empty-package-project"
    project.mkdir()
    command = check_world_web.package_command(
        godot="godot",
        project=project,
        pack=tmp_path / "export/index.pck",
        fixture=tmp_path / "fixture.json",
        engine_log=tmp_path / "engine.log",
    )
    assert list(project.iterdir()) == []
    assert command[command.index("--path") + 1] == str(project)
    assert "--main-pack" in command
    assert "--verify-package" in command
    assert "--api=http://127.0.0.1:1" in command


def test_source_identity_excludes_import_cache(tmp_path: Path) -> None:
    (tmp_path / "kept.gd").write_text("extends Node")
    (tmp_path / ".godot").mkdir()
    (tmp_path / ".godot" / "generated").write_text("mutable")
    assert set(check_world_web.tree_identity(tmp_path)) == {"kept.gd"}


def test_failure_manifest_retains_provenance(tmp_path: Path) -> None:
    output = tmp_path / "output"
    output.mkdir()
    stage = tmp_path / "stage"
    stage.mkdir()
    (output / "import-1.log").write_text("partial import")
    check_world_web.write_failure_manifest(
        output=output,
        version=check_world_web.ENGINE_VERSION,
        source={"main.tscn": {"bytes": 1, "sha256": "a"}},
        templates={"version.txt": "b"},
        text_resources=True,
        stable_node_ids=True,
        normalizer_hash="c",
        fixture=check_world_web.PACKAGE_FIXTURE,
        fixture_hash="d",
        stage=stage,
        error=RuntimeError("timed out"),
    )
    manifest = __import__("json").loads((output / "manifest.json").read_text())
    assert manifest["status"] == "failed"
    assert manifest["stage_retained"] is True
    assert manifest["logs"] == ["import-1.log"]
    assert manifest["package_fixture_sha256"] == "d"
