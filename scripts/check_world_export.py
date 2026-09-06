"""Build and exercise the macOS release outside the checkout; retain artifact hashes."""

import argparse
import hashlib
import json
import platform
import subprocess
import tempfile
import tomllib
import zipfile
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "apps/world"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_files() -> dict[str, str]:
    return {
        str(p.relative_to(PROJECT)): digest(p)
        for p in sorted(PROJECT.rglob("*"))
        if p.is_file() and not any(part.startswith(".") for part in p.relative_to(PROJECT).parts)
    }


def run(
    command: list[str],
    log: Path,
    cwd: Path,
    timeout: int = 180,
    expected_refusal: str | None = None,
) -> str:
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as error:
        partial = error.stdout or b""
        log.write_text(partial.decode(errors="replace") if isinstance(partial, bytes) else partial)
        raise RuntimeError(f"Export check timed out; retained {log}") from error
    log.write_text(result.stdout)
    if expected_refusal is not None:
        if (
            result.returncode != 1
            or expected_refusal not in result.stdout
            or result.stdout.count("ERROR:") != 1
            or "leaked" in result.stdout
        ):
            raise RuntimeError(f"Expected clean refusal; retained {log}")
        return result.stdout
    if result.returncode or any(x in result.stdout for x in ("ERROR:", "Parse Error")):
        raise RuntimeError(f"Export check failed; retained {log}")
    return result.stdout


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / ".local/world-release" / datetime.now(UTC).strftime("%Y%m%dT%H%M%S%fZ"),
    )
    args = parser.parse_args()
    if platform.system() != "Darwin":
        raise SystemExit("This qualification runs the actual macOS executable; use a macOS host.")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise SystemExit(
            "Use a fresh output directory; earlier qualification evidence is preserved."
        )
    pinned = tomllib.loads((ROOT / "mise.toml").read_text())["tools"]["godot"]
    version = run(["godot", "--version"], output / "version.log", ROOT).strip()
    if not version.startswith(pinned + ".stable."):
        raise SystemExit(f"Godot {pinned}.stable required; got {version}")
    archive = output / "Starbase2-macOS.zip"
    run(
        ["godot", "--headless", "--path", str(PROJECT), "--editor", "--import"],
        output / "import.log",
        ROOT,
    )
    sources = source_files()
    runner_hash = digest(Path(__file__))
    run(
        ["godot", "--headless", "--path", str(PROJECT), "--export-release", "macOS", str(archive)],
        output / "export.log",
        ROOT,
    )
    fixture = ROOT / "evidence/command-district/world-fixture.json"
    with tempfile.TemporaryDirectory(prefix="starbase2-export-") as directory:
        isolated = Path(directory)
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(isolated)
        executable = next(isolated.glob("*.app/Contents/MacOS/*"))
        executable.chmod(0o755)
        pack = next(isolated.glob("*.app/Contents/Resources/*.pck"))
        common = [str(executable), "--max-fps", "60"]
        run(
            [*common, "--headless", "--quit-after", "60", "--", "--verify-package"],
            output / "fixture-refusal.log",
            isolated,
            expected_refusal="Package verification requires an offline fixture",
        )
        log = run(
            [
                *common,
                "--headless",
                "--quit-after",
                "900",
                "--",
                "--verify-package",
                "--fixture=" + str(fixture),
            ],
            output / "smoke.log",
            isolated,
        )
        if "EXPORTED WORLD PASSED" not in log:
            raise RuntimeError("Export smoke test did not finish; inspect smoke.log")
        for name, options in [
            ("colony", ["--walk-test"]),
            ("interior", ["--room=review", "--compact", "--reduced-motion"]),
        ]:
            capture = output / (name + ".png")
            run(
                [
                    *common,
                    "--quit-after",
                    "720",
                    "--",
                    "--fixture=" + str(fixture),
                    "--frames=600",
                    "--capture=" + str(capture),
                    *options,
                ],
                output / (name + ".log"),
                isolated,
            )
            if not capture.exists() or not capture.with_suffix(".png.json").exists():
                raise RuntimeError(f"Missing actual exported capture: {name}")
        report = {
            "status": "local macOS export qualified; unsigned, not a Kubani release",
            "godot": version,
            "platform": platform.platform(),
            "archive_sha256": digest(archive),
            "pack_sha256": digest(pack),
            "executable_sha256": digest(executable),
            "fixture_sha256": digest(fixture),
            "qualification_script_sha256": runner_hash,
            "source_files": sources,
            "source_tree_sha256": hashlib.sha256(
                json.dumps(sources, sort_keys=True).encode()
            ).hexdigest(),
            "checks": {p.name: digest(p) for p in sorted(output.glob("*.log"))},
            "captures": {p.name: digest(p) for p in sorted(output.glob("*.png*"))},
        }
    if sources != source_files() or runner_hash != digest(Path(__file__)):
        raise RuntimeError("World sources changed during qualification; build a new candidate.")
    (output / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Export qualified. Artifact, captures, logs and provenance: {output}")


if __name__ == "__main__":
    main()
