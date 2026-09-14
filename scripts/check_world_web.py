"""Cleanly export the current world Web preset twice and retain provenance.

This tool never edits the checked-out world project. It intentionally does not
make browser, serving, or runtime-transport claims; it verifies export inputs
and artifacts only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORLD = ROOT / "apps/world"
LOCAL_HOME = ROOT / ".local/godot-home"
ENGINE_VERSION = "4.7.2.stable.official.ed1daf0bf"
NORMALIZER = ROOT / "scripts/world_web_normalize.gd"
PACKAGE_FIXTURE = ROOT / "fixtures/world/stale.json"


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def tree_identity(root: Path) -> dict[str, dict[str, int | str]]:
    return {
        path.relative_to(root).as_posix(): {"bytes": path.stat().st_size, "sha256": digest(path)}
        for path in sorted(root.rglob("*"))
        if path.is_file() and ".godot" not in path.relative_to(root).parts
    }


def artifacts(root: Path) -> dict[str, dict[str, int | str]]:
    return {
        path.relative_to(root).as_posix(): {"bytes": path.stat().st_size, "sha256": digest(path)}
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def error_lines(log: Path) -> list[str]:
    """Return engine errors except the known macOS certificate-store warning."""
    return [
        line
        for line in log.read_text().splitlines()
        if "ERROR:" in line and 'Condition "ret != noErr"' not in line
    ]


def run(command: list[str], *, cwd: Path, env: dict[str, str], log: Path, timeout: int) -> str:
    with log.open("w") as stream:
        process = subprocess.Popen(
            command, cwd=cwd, env=env, text=True, stdout=stream, stderr=subprocess.STDOUT
        )
        try:
            status = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            raise RuntimeError(f"Command timed out; retained partial log: {log}") from None
    if status:
        raise RuntimeError(f"Command failed ({status}); inspect {log}")
    result = log.read_text()
    if error_lines(log):
        raise RuntimeError(f"Command logged errors; inspect {log}")
    return result


def package_command(
    *, godot: str, project: Path, pack: Path, fixture: Path, engine_log: Path
) -> list[str]:
    """Run only the PCK from a deliberately empty project directory."""
    return [
        godot,
        "--headless",
        "--path",
        str(project),
        "--main-pack",
        str(pack),
        "--fixed-fps",
        "60",
        "--log-file",
        str(engine_log),
        "--",
        "--verify-package",
        f"--fixture={fixture}",
        "--api=http://127.0.0.1:1",
    ]


def stage_export(
    *,
    number: int,
    stage_root: Path,
    output: Path,
    godot: str,
    home: Path,
    text_resources: bool,
    stable_node_ids: bool,
    normalizer: Path | None,
    fixture: Path,
) -> dict[str, dict[str, int | str]]:
    project = stage_root / f"world-{number}"
    shutil.copytree(WORLD, project, ignore=shutil.ignore_patterns(".godot"))
    if text_resources:
        with (project / "project.godot").open("a") as config:
            config.write("\n[editor]\nexport/convert_text_resources_to_binary=false\n")
    export = output / f"export-{number}"
    export.mkdir()
    environment = os.environ | {"HOME": str(home)}
    run(
        [godot, "--headless", "--path", str(project), "--editor", "--import"],
        cwd=ROOT,
        env=environment,
        log=output / f"import-{number}.log",
        timeout=600,
    )
    if stable_node_ids:
        assert normalizer is not None
        run(
            [
                godot,
                "--headless",
                "--path",
                str(project),
                "--script",
                str(normalizer),
                "--",
                str(output / f"normalize-{number}.json"),
            ],
            cwd=ROOT,
            env=environment,
            log=output / f"normalize-{number}.log",
            timeout=120,
        )
    run(
        [
            godot,
            "--headless",
            "--path",
            str(project),
            "--export-release",
            "Web",
            str(export / "index.html"),
        ],
        cwd=ROOT,
        env=environment,
        log=output / f"export-{number}.log",
        timeout=900,
    )
    package_log = output / f"package-{number}.log"
    package_engine_log = output / f"package-engine-{number}.log"
    package_project = stage_root / f"package-gate-{number}"
    package_project.mkdir()
    package_output = run(
        package_command(
            godot=godot,
            project=package_project,
            pack=export / "index.pck",
            fixture=fixture,
            engine_log=package_engine_log,
        ),
        cwd=ROOT,
        env=environment,
        log=package_log,
        timeout=120,
    )
    if "EXPORTED WORLD PASSED" not in package_output:
        raise RuntimeError(f"Package journey did not finish; inspect {package_log}")
    if not package_engine_log.is_file():
        raise RuntimeError(f"Package engine log was not written: {package_engine_log}")
    if error_lines(package_engine_log):
        raise RuntimeError(f"Package journey logged engine errors; inspect {package_engine_log}")
    required = {"index.html", "index.js", "index.wasm", "index.pck"}
    record = artifacts(export)
    if not required.issubset(record):
        raise RuntimeError(f"Web export {number} missing files: {sorted(required - set(record))}")
    return record


def write_failure_manifest(
    *,
    output: Path,
    version: str,
    source: dict[str, dict[str, int | str]],
    templates: dict[str, str],
    text_resources: bool,
    stable_node_ids: bool,
    normalizer_hash: str | None,
    fixture: Path,
    fixture_hash: str,
    stage: Path,
    error: Exception,
) -> None:
    manifest = {
        "status": "failed",
        "scope": "clean full-world Web export only; no browser acceptance claim",
        "godot": version,
        "source": source,
        "templates": templates,
        "stage_text_resources": text_resources,
        "stable_node_ids": stable_node_ids,
        "normalizer_sha256": normalizer_hash,
        "package_fixture": str(fixture),
        "package_fixture_sha256": fixture_hash,
        "stage": str(stage),
        "stage_retained": stage.is_dir(),
        "logs": [path.name for path in sorted(output.glob("*.log"))],
        "error": str(error),
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--godot", default="godot")
    parser.add_argument(
        "--text-resources",
        action="store_true",
        help="Stage-only determinism probe; retain scenes/resources as text.",
    )
    parser.add_argument(
        "--stable-node-ids",
        action="store_true",
        help="Normalize imported GLB PackedScene node IDs in the isolated stage.",
    )
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        raise SystemExit(f"Use a fresh output directory; retained output exists: {output}")
    pinned = tomllib.loads((ROOT / "mise.toml").read_text())["tools"]["godot"]
    version = subprocess.check_output([args.godot, "--version"], text=True, timeout=20).strip()
    if pinned != "4.7.2" or version != ENGINE_VERSION:
        raise SystemExit(f"Godot {ENGINE_VERSION} required; got {version}")
    templates = (
        LOCAL_HOME / "Library/Application Support/Godot/export_templates" / f"{pinned}.stable"
    )
    needed = ("version.txt", "web_nothreads_debug.zip", "web_nothreads_release.zip")
    if any(not (templates / name).is_file() for name in needed):
        raise SystemExit("Missing checkout-local Web templates; run just world-web-templates")
    baseline = tree_identity(WORLD)
    templates_before = {name: digest(templates / name) for name in needed}
    normalizer = NORMALIZER if args.stable_node_ids else None
    if normalizer is not None and not normalizer.is_file():
        raise SystemExit(f"Missing staged node-ID normalizer: {normalizer}")
    normalizer_hash = digest(normalizer) if normalizer is not None else None
    if not PACKAGE_FIXTURE.is_file():
        raise SystemExit(f"Missing offline package fixture: {PACKAGE_FIXTURE}")
    fixture_hash = digest(PACKAGE_FIXTURE)
    output.mkdir(parents=True)
    temporary_root = Path(tempfile.mkdtemp(prefix="starbase2-world-web-", dir=ROOT / ".local"))
    try:
        home = temporary_root / "home"
        installed = home / "Library/Application Support/Godot/export_templates" / f"{pinned}.stable"
        installed.parent.mkdir(parents=True)
        home.mkdir(parents=True, exist_ok=True)
        shutil.copytree(templates, installed)
        first = stage_export(
            number=1,
            stage_root=temporary_root,
            output=output,
            godot=args.godot,
            home=home,
            text_resources=args.text_resources,
            stable_node_ids=args.stable_node_ids,
            normalizer=normalizer,
            fixture=PACKAGE_FIXTURE,
        )
        if (
            tree_identity(WORLD) != baseline
            or {name: digest(templates / name) for name in needed} != templates_before
            or digest(PACKAGE_FIXTURE) != fixture_hash
            or (normalizer is not None and digest(normalizer) != normalizer_hash)
        ):
            raise RuntimeError(
                "World source changed during first export; retained output is not a candidate"
            )
        second = stage_export(
            number=2,
            stage_root=temporary_root,
            output=output,
            godot=args.godot,
            home=home,
            text_resources=args.text_resources,
            stable_node_ids=args.stable_node_ids,
            normalizer=normalizer,
            fixture=PACKAGE_FIXTURE,
        )
        unchanged = tree_identity(WORLD) == baseline
        templates_unchanged = {
            name: digest(templates / name) for name in needed
        } == templates_before
        normalizer_unchanged = normalizer is None or digest(normalizer) == normalizer_hash
        fixture_unchanged = digest(PACKAGE_FIXTURE) == fixture_hash
        if (
            not unchanged
            or not templates_unchanged
            or not normalizer_unchanged
            or not fixture_unchanged
        ):
            raise RuntimeError("An immutable export input changed during export")
    except Exception as error:
        write_failure_manifest(
            output=output,
            version=version,
            source=baseline,
            templates=templates_before,
            text_resources=args.text_resources,
            stable_node_ids=args.stable_node_ids,
            normalizer_hash=normalizer_hash,
            fixture=PACKAGE_FIXTURE,
            fixture_hash=fixture_hash,
            stage=temporary_root,
            error=error,
        )
        raise
    shutil.rmtree(temporary_root)
    identical = first == second
    manifest = {
        "status": "passed"
        if unchanged
        and templates_unchanged
        and normalizer_unchanged
        and fixture_unchanged
        and identical
        else "failed",
        "scope": "clean full-world Web export only; no browser acceptance claim",
        "godot": version,
        "source": baseline,
        "source_unchanged": unchanged,
        "stage_text_resources": args.text_resources,
        "stable_node_ids": args.stable_node_ids,
        "normalizer_sha256": normalizer_hash,
        "normalizer_unchanged": normalizer_unchanged,
        "package_fixture": str(PACKAGE_FIXTURE),
        "package_fixture_sha256": fixture_hash,
        "package_fixture_unchanged": fixture_unchanged,
        "templates": templates_before,
        "templates_unchanged": templates_unchanged,
        "exports_identical": identical,
        "export_1": first,
        "export_2": second,
        "total_bytes": sum(int(entry["bytes"]) for entry in first.values()),
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    if not identical:
        raise RuntimeError("Clean full-world exports differ; inspect retained manifest")
    print(f"Clean full-world Web exports are deterministic: {output}")


if __name__ == "__main__":
    main()
