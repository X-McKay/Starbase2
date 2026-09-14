"""Create and export a minimal Web transport command fixture from pinned inputs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tomllib
from pathlib import Path

from check_world_web import run

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "fixtures/world-web-probe"
WORLD = ROOT / "apps/world"
TEMPLATE_HOME = ROOT / ".local/godot-home"
PROBE_FILES = ("project.godot", "export_presets.cfg", "probe.tscn", "command-check.gd")
WORLD_FILES = (
    "commands.gd",
    "commands.gd.uid",
    "transport.gd",
    "transport.gd.uid",
    "web_request.gd",
    "web_request.gd.uid",
    "web_request.js",
)
ENGINE_VERSION = "4.7.2.stable.official.ed1daf0bf"


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--godot", default="godot")
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        raise SystemExit(f"Use a fresh output directory: {output}")
    pinned = tomllib.loads((ROOT / "mise.toml").read_text())["tools"]["godot"]
    version = subprocess.check_output([args.godot, "--version"], text=True, timeout=20).strip()
    if pinned != "4.7.2" or version != ENGINE_VERSION:
        raise SystemExit(f"Godot {ENGINE_VERSION} required; got {version}")
    templates = (
        TEMPLATE_HOME / "Library/Application Support/Godot/export_templates" / f"{pinned}.stable"
    )
    required_templates = ("version.txt", "web_nothreads_debug.zip", "web_nothreads_release.zip")
    if any(not (templates / item).is_file() for item in required_templates):
        raise SystemExit("Missing checkout-local Web templates; run just world-web-templates")
    source = {f"fixtures/world-web-probe/{name}": digest(PROBE / name) for name in PROBE_FILES}
    source |= {f"apps/world/{name}": digest(WORLD / name) for name in WORLD_FILES}
    source["mise.toml"] = digest(ROOT / "mise.toml")
    output.mkdir(parents=True)
    project = output / "project"
    project.mkdir()
    for name in ("project.godot", "export_presets.cfg", "command-check.gd"):
        shutil.copy2(PROBE / name, project / name)
    scene = (PROBE / "probe.tscn").read_text().replace("res://probe.gd", "res://command-check.gd")
    (project / "probe.tscn").write_text(scene)
    for name in WORLD_FILES:
        shutil.copy2(WORLD / name, project / name)
    preset = project / "export_presets.cfg"
    preset.write_text(
        preset.read_text().replace('include_filter=""', 'include_filter="web_request.js"')
    )
    home = output / "godot-home"
    installed = home / "Library/Application Support/Godot/export_templates" / f"{pinned}.stable"
    installed.parent.mkdir(parents=True)
    shutil.copytree(templates, installed)
    env = os.environ | {"HOME": str(home)}
    export = output / "export"
    export.mkdir()
    run(
        [
            args.godot,
            "--headless",
            "--path",
            str(project),
            "--export-release",
            "Web",
            str(export / "index.html"),
        ],
        cwd=ROOT,
        env=env,
        log=output / "export.log",
        timeout=180,
    )
    files = {
        item.name: {"bytes": item.stat().st_size, "sha256": digest(item)}
        for item in sorted(export.iterdir())
        if item.is_file()
    }
    if not {"index.html", "index.js", "index.wasm", "index.pck"}.issubset(files):
        raise SystemExit("Transport fixture export is incomplete")
    (output / "manifest.json").write_text(
        json.dumps(
            {
                "scope": "minimal Web transport command fixture",
                "godot": version,
                "source": source,
                "templates": {name: digest(templates / name) for name in required_templates},
                "artifacts": files,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )
    print(f"Prepared Web transport fixture: {output}")


if __name__ == "__main__":
    main()
