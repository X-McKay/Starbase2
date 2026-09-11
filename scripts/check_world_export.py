"""Build and exercise the macOS release outside the checkout; retain artifact hashes."""

import argparse
import hashlib
import json
import os
import platform
import re
import signal
import subprocess
import tempfile
import time
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


def native_pids(executable: Path, listing: str) -> list[int]:
    # macOS may report /private/var for an executable launched through /var.
    prefixes = {str(executable) + " ", str(executable.resolve()) + " "}
    result = []
    for line in listing.splitlines():
        fields = line.strip().split(maxsplit=1)
        if len(fields) == 2 and any(fields[1].startswith(prefix) for prefix in prefixes):
            result.append(int(fields[0]))
    return result


def native_capture(
    executable: Path, arguments: list[str], output: Path, name: str, cwd: Path
) -> None:
    """Launch an exact owned GUI instance once within a bounded review."""
    stdout = output / f"{name}.log"
    stderr = output / f"{name}-stderr.log"
    app = str(executable.resolve().parents[2])
    command = [
        "open",
        "-n",
        "-W",
        "-a",
        app,
        "--stdout",
        str(stdout),
        "--stderr",
        str(stderr),
        "--args",
        "--max-fps",
        "60",
        "--",
        *arguments,
    ]
    deadline = time.monotonic() + 180
    launcher = subprocess.Popen(
        command, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    try:
        # One normal Launch Services launch; no repeated foreground activation.
        log, _ = launcher.communicate(timeout=max(0.1, deadline - time.monotonic()))
        (output / f"{name}-launch.log").write_text(log)
        if launcher.returncode:
            raise RuntimeError(f"Native launcher failed; inspect {name}-launch.log")
    except Exception:
        if launcher.poll() is None:
            launcher.terminate()
        log, _ = launcher.communicate(timeout=5)
        (output / f"{name}-launch.log").write_text(log)
        listing = subprocess.check_output(["ps", "-axo", "pid=,command="], text=True)
        for pid in native_pids(executable, listing):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        raise
    log = stdout.read_text() + stderr.read_text()
    if "Godot Engine" not in log or any(x in log for x in ("ERROR:", "Parse Error")):
        raise RuntimeError(f"Native capture failed; inspect {stdout} and {stderr}")


def verify_shift_report(directory: Path, mode: str) -> dict:
    report_path = directory / f"{mode}-report.json"
    record = json.loads(report_path.read_text())
    if (
        record.get("mode") != mode
        or record.get("status") != "passed"
        or record.get("fixture") is not True
        or record.get("initial_positions_staged") is not True
        or record.get("physics_after_staging") is not True
        or record.get("failures") != []
        or not 0 <= record.get("wall_ms", -1) < 180000
    ):
        raise RuntimeError(f"Shift Change {mode} report did not qualify")
    expected = [f"{mode}-occupied-habitat.png"]
    expected += [f"{mode}-seated-{i:02d}.png" for i in range(4)]
    expected += [f"{mode}-stand-{i:02d}.png" for i in range(5)]
    expected += (
        ["domestic-fast-report.png"]
        if mode == "domestic"
        else [
            f"journey-{name}.png"
            for name in ("console-arrival", "report-ready", "home", "offline", "reconnected")
        ]
    )
    if set(record.get("captures", [])) != set(expected):
        raise RuntimeError(f"Shift Change {mode} capture sequence incomplete")
    for name in expected:
        if not (directory / name).read_bytes().startswith(b"\x89PNG\r\n\x1a\n"):
            raise RuntimeError(f"Invalid Shift Change capture: {name}")
    samples = {s["label"]: s for s in record.get("samples", [])}
    if samples.get("seated", {}).get("clip") != "social/seated" or not any(
        s.get("clip") == "social/stand_up" for s in samples.values()
    ):
        raise RuntimeError("Shift Change social transition samples absent")
    if mode == "journey":
        if (
            samples.get("working", {}).get("pose") != "console"
            or samples.get("returned-home", {}).get("clip") != "social/seated"
            or samples.get("report-ready", {}).get("evidence_ready") is not True
            or samples.get("offline", {}).get("goal") != "hold"
            or samples.get("offline", {}).get("pose") != ""
        ):
            raise RuntimeError("Shift Change journey state samples incomplete")
    return {
        "report_sha256": digest(report_path),
        "captures": {name: digest(directory / name) for name in expected},
        "initial_positions_staged": True,
        "physics_after_staging": True,
        "visual_contact_acceptance": (
            "requires inspection of native captures; clip names are not pose proof"
        ),
    }


def qualify_shift_change(
    executable: Path, fixture: Path, board_fixture: Path, output: Path, cwd: Path
) -> dict:
    fixture_hashes = (digest(fixture), digest(board_fixture))
    run(
        [
            str(executable),
            "--headless",
            "--",
            "--shift-change-capture=" + str(output / "shift-refused"),
        ],
        output / "shift-fixture-refusal.log",
        cwd,
        expected_refusal="Package verification requires an offline fixture",
    )
    if (output / "shift-refused").exists():
        raise RuntimeError("Refused Shift Change run created output before its fixture fence")
    records = {}
    for mode in ("domestic", "journey"):
        directory = output / f"shift-{mode}"
        native_capture(
            executable,
            [
                "--fixture=" + str(fixture),
                "--board-fixture=" + str(board_fixture),
                "--shift-change-capture=" + str(directory),
                "--shift-change-mode=" + mode,
            ],
            output,
            "shift-" + mode,
            cwd,
        )
        if f"SHIFT_CHANGE_CAPTURE_PASSED {mode}" not in (output / f"shift-{mode}.log").read_text():
            raise RuntimeError(f"Shift Change {mode} did not finish")
        records[mode] = verify_shift_report(directory, mode)
    if fixture_hashes != (digest(fixture), digest(board_fixture)):
        raise RuntimeError("Shift Change fixtures changed during qualification")
    return {"board_fixture_sha256": fixture_hashes[1], "modes": records}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / ".local/world-release" / datetime.now(UTC).strftime("%Y%m%dT%H%M%S%fZ"),
    )
    parser.add_argument(
        "--live-api", help="Optional owned loopback Core for read-only native qualification"
    )
    args = parser.parse_args()
    if args.live_api:
        match = re.fullmatch(r"http://127\.0\.0\.1:([1-9][0-9]{0,4})", args.live_api)
        if not match or int(match[1]) > 65535:
            raise SystemExit("Live qualification requires a canonical private loopback origin.")
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
        run(
            [*common, "--headless", "--", "--capture-package=" + str(output)],
            output / "capture-fixture-refusal.log",
            isolated,
            expected_refusal="Package verification requires an offline fixture",
        )
        log = run(
            [
                *common,
                "--headless",
                "--",
                "--verify-package",
                "--fixture=" + str(fixture),
            ],
            output / "smoke.log",
            isolated,
        )
        if "EXPORTED WORLD PASSED" not in log:
            raise RuntimeError("Export smoke test did not finish; inspect smoke.log")
        for identity in ("repair", "review", "gym", "habitat", "greenhouse"):
            if f"EXPORTED_JOURNEY {identity}" not in log:
                raise RuntimeError(f"Missing actual exported physical journey: {identity}")
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
        native_capture(
            executable,
            ["--fixture=" + str(fixture), "--capture-package=" + str(output)],
            output,
            "structures",
            isolated,
        )
        structure_log = (output / "structures.log").read_text()
        if "EXPORTED_STRUCTURES_CAPTURE_PASSED" not in structure_log:
            raise RuntimeError("Native structure review did not finish; inspect structures.log")
        for identity in ("review", "gym", "habitat", "greenhouse"):
            if f"NATIVE_EXPORTED_JOURNEY {identity}" not in structure_log:
                raise RuntimeError(f"Missing native physical journey: {identity}")
            for view in ("exterior", "interior"):
                if not (output / f"{identity}-{view}.png").exists():
                    raise RuntimeError(f"Missing actual exported capture: {identity}-{view}")
        capture_report = output / "structure-captures.json"
        capture_data = json.loads(capture_report.read_text())
        if capture_data["failures"] or capture_data["motion_frames"] < 4:
            raise RuntimeError("Native physical motion evidence failed")
        if not capture_data.get("live_world_presentation", False):
            raise RuntimeError("Native review must exercise the live camera and HUD")
        for name in (
            "command-workspace",
            "command-workspace-compact",
            "habitat-guide",
            "greenhouse-guide",
            "living-commons",
            "living-colony",
            "inhabited-water",
            "inhabited-water-reduced",
            "operations-task-markers",
            "operations-review",
            "operations-comparison",
            "operations-duties",
            "operations-history",
            "operations-compact",
            "operations-disconnected",
            "operations-heartbeat",
        ):
            if not (output / f"{name}.png").exists():
                raise RuntimeError(f"Missing living-colony review capture: {name}")
        if not (output / "review-motion.png").exists():
            raise RuntimeError("Missing native physical motion strip")
        shift_record = qualify_shift_change(
            executable,
            fixture,
            ROOT / "evidence/command-district/board-fixture.json",
            output,
            isolated,
        )
        live_record = None
        if args.live_api:
            native_capture(
                executable,
                ["--api=" + args.live_api, "--live-capture=" + str(output)],
                output,
                "live",
                isolated,
            )
            live_record = json.loads((output / "live-review.json").read_text())
            if (
                live_record["failures"]
                or live_record["fixture"]
                or live_record["commands_dispatched"]
            ):
                raise RuntimeError("Live native qualification failed")
            if "LIVE_WORLD_CAPTURE_PASSED" not in (output / "live.log").read_text():
                raise RuntimeError("Live native qualification did not finish")
            for name in (
                "live-colony",
                "live-connection",
                "live-command",
                "live-repositories",
                "live-evidence",
                "live-compact",
                "live-disconnected",
                "live-reconnected",
            ):
                if not (output / (name + ".png")).exists():
                    raise RuntimeError("Missing live native capture: " + name)
        report = {
            "shift_change": shift_record,
            "live_backend": live_record,
            "native_input_mode": (
                "one normal Launch Services launch, no repeated activation; "
                "external input isolated in explicit capture mode; "
                "no manual OS input claim"
            ),
            "status": "local macOS export qualified; unsigned, not a Kubani release",
            "godot": version,
            "platform": platform.platform(),
            "archive_sha256": digest(archive),
            "pack_sha256": digest(pack),
            "executable_sha256": digest(executable),
            "fixture_sha256": digest(fixture),
            "qualification_script_sha256": runner_hash,
            "structure_capture_report_sha256": digest(capture_report),
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
