"""Bounded, synthetic autonomy wiring controls; never agent qualification."""

import argparse
import hashlib
import json
import math
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CONTROLS = (
    "sdlc_integration",
    "verification_integration",
    "sdlc_coordination_integration",
    "sdlc_resilience_integration",
)
COVERAGE = {
    "discovery_to_pr": ("sdlc_integration", "Synthetic known persistence opportunity only"),
    "restart_replay": ("sdlc_integration", "Core/worker restart and Temporal replay"),
    "duplicate_effects": ("verification_integration", "Lost status acknowledgement reconciliation"),
    "published_head_reverification": (
        "verification_integration",
        "Separate failed and passed heads",
    ),
    "healthy_no_change": (
        "sdlc_coordination_integration",
        "Corrected source rules produce no missions",
    ),
    "pr_feedback": (
        "sdlc_resilience_integration",
        "Core admission for current/stale/conflicting captures; synthetic provider/model",
    ),
    "provider_interruption": (
        "sdlc_coordination_integration",
        "Discovery outage/recovery; not interrupted publication",
    ),
    "concurrent_head_drift": (
        "sdlc_resilience_integration",
        "Trusted adapter head change after claim fences provider write",
    ),
    "cancellation": (
        "sdlc_resilience_integration",
        "Cancellation during model/test adapter waits; not process termination",
    ),
    "multi_family_discovery": (
        "sdlc_coordination_integration",
        "Three families; synthetic VM observations graded by Core",
    ),
    "bounded_reassignment": (
        "sdlc_coordination_integration",
        "Rejected memory proposal reassigns Rivet to Moss once",
    ),
}


def dump(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def fingerprints(root=ROOT):
    paths = [
        root / "uv.lock",
        root / "Cargo.lock",
        root / "target/debug/starbase-core",
        root / "pyproject.toml",
        root / "Cargo.toml",
        root / ".local/tools/temporal",
    ]
    for pattern in (
        "scripts/*integration.py",
        "scripts/*worker_fixture.py",
        "scripts/autonomy_trial.py",
        "services/runtime/starbase_runtime/**/*.py",
        "services/runtime/starbase_runtime/agents/**/*.md",
        "services/core/src/**/*.rs",
        "services/core/migrations/**/*",
        "services/core/*.sql",
        "services/core/Cargo.toml",
        "contracts/*.json",
        ".local/algent-inspection/src/__init__.py",
        ".local/algent-inspection/src/utils/__init__.py",
        ".local/algent-inspection/src/utils/logging.py",
        ".local/algent-inspection/src/utils/persistence.py",
    ):
        paths.extend(root.glob(pattern))
    return {
        str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(set(paths))
        if path.is_file() and "__pycache__" not in path.parts
    }


def manifest(duration, profile, digests):
    return {
        "version": 1,
        "profile": profile,
        "duration_seconds": duration,
        "question": "Do the declared synthetic integration controls still pass?",
        "scope": "local synthetic wiring regression; no real provider/model/sandbox calls",
        "model_qualification": "not_attempted",
        "baseline_candidate_comparison": "not_attempted",
        "source_digests": digests,
        "python": sys.version,
        "controls": list(CONTROLS),
        "coverage": {
            key: {"control": control, "scope": scope} for key, (control, scope) in COVERAGE.items()
        },
        "stopping_rule": "one complete cycle"
        if profile == "iteration"
        else "repeat until deadline",
        "hard_gates": ["all declared controls pass", "no source drift", "no forced cleanup"],
        "failure_rule": "stop on first failure; retain all results; never retry until green",
        "authority": "synthetic adapters only; no live monitor configuration or external mutations",
        "limits": "missing gates remain not_covered; successful controls do not qualify autonomy",
    }


def validate_evidence(control, log):
    matches = re.findall(r"^Evidence: (.+)$", log, re.MULTILINE)
    if len(matches) != 1:
        return {"status": "evidence_missing"}
    path = Path(matches[0]).resolve()
    expected_prefix = control.replace("_", "-") + "-"
    if path.parent != (ROOT / ".local").resolve() or not path.name.startswith(expected_prefix):
        return {"status": "evidence_invalid"}
    try:
        events = json.loads((path / "events.json").read_text())
        assert isinstance(events, list) and events
        assert all(
            isinstance(event, dict) and event.get("synthetic_external_controls") is True
            for event in events
        )
        assert not any(event.get("event") == "failed" for event in events)
        complete = events[-1]
        assert complete["event"] == "complete"
        if control not in {"sdlc_coordination_integration", "sdlc_resilience_integration"}:
            assert complete["replay"] == "passed"
        if control == "sdlc_integration":
            assert complete["effects"] == 3 and complete["duplicate_missions"] == 0
            assert complete["state"] == "awaiting_review" and complete["verdict"] == "improved"
        elif control == "sdlc_resilience_integration":
            assert complete.get("temporal") == "not_exercised"
        elif control == "sdlc_coordination_integration":
            assert complete["families"] == ["persistence-history", "memory-key", "logging-level"]
            assert complete["priority_order"] == complete["families"]
            assert complete["reassignment"] is True
            assert complete["no_change_dispatches"] == 0
            assert complete["unavailable_dispatches"] == 0
            assert complete["duplicate_missions"] == 0
            assert complete["external_effects"] == 0
            assert complete["operator_cancellations"] == 3
            assert complete["verified_not_published"] == 3
        else:
            assert complete["outcomes"] == ["failed", "passed"]
            assert complete["statuses"] == 4
            assert complete["branch_updates"] == 1 and complete["reviews"] == 1
        return {"status": "passed", "evidence": str(path), "completion": complete}
    except (OSError, ValueError, AssertionError, KeyError, TypeError):
        return {"status": "evidence_invalid", "evidence": str(path)}


def run_control(control, output, seconds):
    """SIGINT permits asyncio harness finally blocks to stop their owned services."""
    started = time.monotonic()
    log_path = output / f"{control}.log"
    environment = {
        key: value for key, value in os.environ.items() if key in {"PATH", "LANG", "TMPDIR"}
    }
    environment["PYTHONPATH"] = str(ROOT / "services/runtime")
    status = None
    forced_cleanup = False
    with log_path.open("w") as log:
        process = subprocess.Popen(
            [sys.executable, str(ROOT / "scripts" / f"{control}.py")],
            cwd=ROOT,
            env=environment,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            process.wait(timeout=seconds)
        except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
            status = (
                "deadline_exceeded" if isinstance(error, subprocess.TimeoutExpired) else "cancelled"
            )
            process.send_signal(signal.SIGINT)
            try:
                process.wait(timeout=45)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
                forced_cleanup = True
    result = {
        "status": status or "failed",
        "exit_code": process.returncode,
        "elapsed_seconds": time.monotonic() - started,
        "log": str(log_path),
        "cleanup": "requires_inspection" if forced_cleanup else "harness_exited",
    }
    if status is None and process.returncode == 0:
        result.update(validate_evidence(control, log_path.read_text()))
    return result


def summarize(results, drift=False):
    completed = {row["control"] for row in results if row["status"] == "passed"}
    failed = any(row["status"] != "passed" for row in results)
    wiring = (
        "contaminated"
        if drift
        else ("failed" if failed else "passed" if completed == set(CONTROLS) else "incomplete")
    )
    return {
        "wiring_result": wiring,
        "autonomy_qualification": "not_qualified",
        "model_qualification": "not_attempted",
        "source_drift": drift,
        "results": results,
        "coverage": {
            key: {
                "status": "passed_synthetic"
                if control in completed and wiring == "passed"
                else "not_covered",
                "scope": scope,
            }
            for key, (control, scope) in COVERAGE.items()
        },
    }


def run(output, duration=900, profile="iteration", execute=run_control):
    if not math.isfinite(duration) or duration <= 0 or duration > 7200:
        raise ValueError("duration must be finite, positive and at most 7200 seconds")
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    initial = fingerprints()
    dump(output / "manifest.json", manifest(duration, profile, initial))
    results = []
    deadline = time.monotonic() + duration
    cycle = 0
    while True:
        cycle += 1
        folder = output / f"cycle-{cycle}"
        folder.mkdir(mode=0o700)
        for control in CONTROLS:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                results.append({"control": control, "cycle": cycle, "status": "budget_exhausted"})
                break
            result: dict[str, Any]
            try:
                result = execute(control, folder, remaining)
            except Exception as error:
                result = {"status": "infrastructure_error", "error_type": type(error).__name__}
            result |= {"control": control, "cycle": cycle}
            results.append(result)
            dump(output / "results.json", summarize(results))
            if result["status"] != "passed":
                break
        if (
            profile == "iteration"
            or time.monotonic() >= deadline
            or any(row["status"] != "passed" for row in results)
        ):
            break
    result = summarize(results, fingerprints() != initial)
    dump(output / "results.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=("iteration", "soak"), default="iteration")
    parser.add_argument("--duration-seconds", type=float, default=None)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    duration = (
        args.duration_seconds
        if args.duration_seconds is not None
        else (7200 if args.profile == "soak" else 900)
    )
    output = args.output or ROOT / ".local" / f"autonomy-trial-{time.time_ns()}"
    result = run(output, duration, args.profile)
    print(
        json.dumps(
            {
                "evidence": str(output),
                "wiring_result": result["wiring_result"],
                "autonomy_qualification": result["autonomy_qualification"],
            }
        )
    )
    return 0 if result["wiring_result"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
