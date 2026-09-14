"""Install checksum-pinned Godot Web templates into this checkout's cache."""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import tempfile
import tomllib
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCAL_HOME = ROOT / ".local/godot-home"
ARCHIVE_NAME = "Godot_v4.7.2-stable_export_templates.tpz"
ARCHIVE_URL = (
    "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/" + ARCHIVE_NAME
)
ARCHIVE_SIZE = 1_281_349_702
ARCHIVE_SHA256 = "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011"
REQUIRED = (
    "templates/version.txt",
    "templates/web_nothreads_debug.zip",
    "templates/web_nothreads_release.zip",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def pinned_version() -> str:
    return tomllib.loads((ROOT / "mise.toml").read_text())["tools"]["godot"] + ".stable"


def verify_archive(path: Path) -> None:
    if not path.is_file() or path.stat().st_size != ARCHIVE_SIZE:
        raise RuntimeError(f"Expected {ARCHIVE_NAME} to be {ARCHIVE_SIZE} bytes")
    if sha256(path) != ARCHIVE_SHA256:
        raise RuntimeError(f"SHA-256 mismatch for {ARCHIVE_NAME}")


def download(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
        temporary_path = Path(temporary.name)
        try:
            with urllib.request.urlopen(ARCHIVE_URL, timeout=60) as response:
                shutil.copyfileobj(response, temporary)
            temporary.flush()
            os.fsync(temporary.fileno())
        except BaseException:
            temporary_path.unlink(missing_ok=True)
            raise
    temporary_path.replace(path)


def install(archive: Path, destination: Path) -> None:
    expected = LOCAL_HOME / "Library/Application Support/Godot/export_templates" / pinned_version()
    if destination != expected:
        raise RuntimeError(f"Template destination must be exactly {expected}")
    with zipfile.ZipFile(archive) as package:
        missing = set(REQUIRED) - set(package.namelist())
        if missing:
            raise RuntimeError(f"Pinned template archive misses: {sorted(missing)}")
        if package.read("templates/version.txt").decode().strip() != pinned_version():
            raise RuntimeError("Template archive version does not match mise.toml")
        stage = destination.with_name(destination.name + ".staging")
        shutil.rmtree(stage, ignore_errors=True)
        stage.mkdir(parents=True)
        for member in REQUIRED:
            with package.open(member) as source, (stage / Path(member).name).open("wb") as output:
                shutil.copyfileobj(source, output)
    shutil.rmtree(destination, ignore_errors=True)
    stage.replace(destination)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, default=ROOT / ".local/cache/godot" / ARCHIVE_NAME)
    parser.add_argument(
        "--template-dir",
        type=Path,
        default=LOCAL_HOME
        / "Library/Application Support/Godot/export_templates"
        / pinned_version(),
    )
    parser.add_argument("--offline", action="store_true", help="Refuse network download.")
    args = parser.parse_args()
    archive = args.archive.resolve()
    if not archive.exists():
        cache = (ROOT / ".local/cache/godot").resolve()
        if cache not in archive.parents:
            raise SystemExit(f"Missing archive download destination must stay below {cache}")
        if args.offline:
            raise SystemExit(f"Missing cached template archive: {archive}")
        print(f"Downloading pinned {ARCHIVE_NAME} to {archive}")
        download(archive)
    verify_archive(archive)
    install(archive, args.template_dir.resolve())
    print(f"Installed verified Godot Web templates in {args.template_dir.resolve()}")


if __name__ == "__main__":
    main()
