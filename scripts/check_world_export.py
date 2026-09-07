"""Build and exercise the macOS release outside the checkout; retain artifact hashes."""

import argparse
import hashlib
import json
import os
import platform
import signal
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


def native_capture(
    executable: Path, arguments: list[str], output: Path, name: str, cwd: Path
) -> None:
    """Launch a fresh GUI instance through macOS; direct second launches can stall."""
    stdout = output / f"{name}.log"
    stderr = output / f"{name}-stderr.log"
    try:
        run(
            [
                "open",
                "-n",
                "-W",
                "-a",
                str(executable.parents[2]),
                "--stdout",
                str(stdout),
                "--stderr",
                str(stderr),
                "--args",
                "--max-fps",
                "60",
                "--",
                *arguments,
            ],
            output / f"{name}-launch.log",
            cwd,
        )
    except Exception:
        # open -W is not the app process. A timed-out launch must not leave the
        # isolated review running. Match this exact temporary executable only.
        processes = subprocess.check_output(["ps", "-axo", "pid=,command="], text=True)
        for line in processes.splitlines():
            fields = line.strip().split(maxsplit=1)
            if len(fields) == 2 and fields[1].startswith(str(executable) + " "):
                try:
                    os.kill(int(fields[0]), signal.SIGTERM)
                except ProcessLookupError:
                    pass
        raise
    log = stdout.read_text() + stderr.read_text()
    if "Godot Engine" not in log or any(x in log for x in ("ERROR:", "Parse Error")):
        raise RuntimeError(f"Native capture failed; inspect {stdout} and {stderr}")


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
            native_capture(
                executable,
                [
                    "--fixture=" + str(fixture),
                    "--frames=600",
                    "--capture=" + str(capture),
                    *options,
                ],
                output,
                name,
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
