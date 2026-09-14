"""Build two clean Godot Web probe exports and require byte-identical artifacts."""

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
PROBE = ROOT / "fixtures/world-web-probe"
MARKER = "starbase-web-probe-ready"
REQUIRED_SUFFIXES = (".html", ".js", ".wasm", ".pck")
ENGINE_VERSION = "4.7.2.stable.official.ed1daf0bf"
SOURCE_FILES = (
    Path("project.godot"),
    Path("export_presets.cfg"),
    Path("probe.tscn"),
    Path("probe.gd"),
    Path("probe.gd.uid"),
)


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def files(directory: Path) -> dict[str, dict[str, int | str]]:
    return {
        path.relative_to(directory).as_posix(): {
            "bytes": path.stat().st_size,
            "sha256": digest(path),
        }
        for path in sorted(item for item in directory.rglob("*") if item.is_file())
    }


def source_identity() -> dict[str, str]:
    return {
        (PROBE / path).relative_to(ROOT).as_posix(): digest(PROBE / path) for path in SOURCE_FILES
    } | {"mise.toml": digest(ROOT / "mise.toml")}


def run_export(godot: str, home: Path, project: Path, output: Path, log: Path) -> None:
    with log.open("w") as stream:
        process = subprocess.Popen(
            [
                godot,
                "--headless",
                "--path",
                str(project),
                "--export-release",
                "Web",
                str(output / "index.html"),
            ],
            cwd=ROOT,
            env=os.environ | {"HOME": str(home)},
            stdout=stream,
            stderr=subprocess.STDOUT,
            text=True,
        )
        try:
            status = process.wait(timeout=120)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            raise RuntimeError(f"Web probe export timed out; retained partial log: {log}") from None
    if status:
        raise RuntimeError(f"Web probe export failed ({status}); inspect {log}")
    result = log.read_text()
    errors = [
        line
        for line in result.splitlines()
        if "ERROR:" in line and 'Condition "ret != noErr"' not in line
    ]
    if errors:
        raise RuntimeError(f"Web probe export logged errors; inspect {log}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".local/world-web-probe")
    parser.add_argument("--godot", default="godot")
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        raise SystemExit(f"Use a fresh output directory; retained output exists: {output}")
    version = subprocess.check_output([args.godot, "--version"], text=True, timeout=20).strip()
    pinned = tomllib.loads((ROOT / "mise.toml").read_text())["tools"]["godot"]
    if pinned != "4.7.2" or version != ENGINE_VERSION:
        raise SystemExit(f"Godot {ENGINE_VERSION} required; got {version}")
    template_dir = (
        ROOT
        / ".local/godot-home/Library/Application Support/Godot/export_templates"
        / f"{pinned}.stable"
    )
    missing = [
        name
        for name in ("version.txt", "web_nothreads_debug.zip", "web_nothreads_release.zip")
        if not (template_dir / name).is_file()
    ]
    if missing:
        raise SystemExit(
            "Missing checkout-local Web templates; run just world-web-templates: "
            + ", ".join(missing)
        )
    output.mkdir(parents=True)
    with tempfile.TemporaryDirectory(
        prefix="starbase2-web-export-", dir=ROOT / ".local"
    ) as home_root:
        home = Path(home_root) / "home"
        home.mkdir()
        installed = home / "Library/Application Support/Godot/export_templates" / f"{pinned}.stable"
        installed.parent.mkdir(parents=True)
        shutil.copytree(template_dir, installed)
        for number in (1, 2):
            export = output / f"export-{number}"
            export.mkdir()
            project = Path(home_root) / f"project-{number}"
            project.mkdir()
            for source in SOURCE_FILES:
                shutil.copy2(PROBE / source, project / source)
            run_export(args.godot, home, project, export, output / f"export-{number}.log")
    first, second = files(output / "export-1"), files(output / "export-2")
    expected = {f"index{suffix}" for suffix in REQUIRED_SUFFIXES}
    if not expected.issubset(first):
        raise RuntimeError(
            f"Probe export is incomplete: expected {sorted(expected)}, got {sorted(first)}"
        )
    identical = first == second
    manifest = {
        "status": "passed" if identical else "nondeterministic",
        "scope": "isolated Web export probe; main world preset unchanged",
        "godot": version,
        "templates": {
            name: digest(template_dir / name)
            for name in sorted(path.name for path in template_dir.iterdir() if path.is_file())
        },
        "source": source_identity(),
        "exports_identical": identical,
        "export_1": first,
        "export_2": second,
        "total_bytes": sum(int(item["bytes"]) for item in first.values()),
        "browser_marker": MARKER,
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    if not identical:
        raise RuntimeError("Clean Web exports differ; inspect the retained manifest and exports")
    print(f"Web probe exports are deterministic: {output}")


if __name__ == "__main__":
    main()
