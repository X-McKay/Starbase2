"""Predeclared paired public development campaign, never held-out qualification.

Each profile/family runs once in a new process. Failed attempts remain in the
report; source drift stops dispatch. All children use the same Core binary and
source checkout and disable publication through the development probe.
"""

import argparse
import hashlib
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
PROFILES = ("legacy", "tools", "tools-thinking")
FAMILIES = ("persistence-history", "memory-key", "logging-level")
ENVIRONMENT_KEYS = ("STARBASE_MODEL", "STARBASE_INFERENCE_URL", "STARBASE_INFERENCE_ENABLED")


def plan() -> list[dict]:
    """Latin-square profile order: each arm occupies each within-family position."""
    return [
        {
            "sequence": i * len(PROFILES) + j + 1,
            "family": family,
            "profile": PROFILES[(i + j) % len(PROFILES)],
        }
        for i, family in enumerate(FAMILIES)
        for j in range(len(PROFILES))
    ]


def fingerprints(root: Path = ROOT) -> dict[str, str]:
    paths = [
        root / name
        for name in (
            "uv.lock",
            "Cargo.lock",
            "pyproject.toml",
            "Cargo.toml",
            "target/debug/starbase-core",
        )
    ]
    for pattern in (
        "scripts/sdlc_family_probe.py",
        "scripts/sdlc_tools_campaign.py",
        "services/runtime/starbase_runtime/**/*.py",
        "services/runtime/starbase_runtime/agents/**/*",
        "services/core/src/**/*.rs",
        "services/core/*.sql",
        "contracts/*.json",
        ".local/algent-inspection/src/**/*.py",
    ):
        paths.extend(root.glob(pattern))
    return {
        str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(set(paths))
        if p.is_file() and "__pycache__" not in p.parts
    }


def configuration_fingerprint() -> dict[str, str | None]:
    # Never write tokens, credential paths or endpoint authentication into a manifest.
    return {
        key: hashlib.sha256(os.environ[key].encode()).hexdigest() if key in os.environ else None
        for key in ENVIRONMENT_KEYS
    }


def write(path: Path, data: Any) -> None:
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


def usage_of(value: Any) -> dict[str, int]:
    totals = {"input_tokens": 0, "output_tokens": 0, "records": 0}
    if isinstance(value, dict):
        usage = value.get("usage")
        if isinstance(usage, dict) and all(
            type(usage.get(k)) is int for k in totals if k != "records"
        ):
            totals.update(
                input_tokens=usage["input_tokens"], output_tokens=usage["output_tokens"], records=1
            )
        for key, child in value.items():
            if key != "usage":
                nested = usage_of(child)
                for name in totals:
                    totals[name] += nested[name]
    elif isinstance(value, list):
        for child in value:
            nested = usage_of(child)
            for name in totals:
                totals[name] += nested[name]
    return totals


def classify(row: dict | None, exit_code: int | None, timed_out: bool = False) -> str:
    if timed_out:
        return "timeout"
    if row is None or not isinstance(row.get("mission"), dict):
        return "infrastructure_failure"
    error = row.get("error_type")
    if error in {"MemberFailure", "ModelAPIError", "ModelHTTPError", "UnexpectedModelBehavior"}:
        return "model_or_provider_failure"
    if error:
        return "execution_failure"
    if row.get("candidate_verified") is True and exit_code == 0:
        return "accepted"
    if row.get("candidate_verified") is False and exit_code in (0, 1):
        return "candidate_failed"
    return "infrastructure_failure"


def execute(trial: dict, folder: Path, seconds: float) -> dict:
    output = folder / "probe"
    env = os.environ | {"STARBASE_SDLC_AGENT_PROFILE": trial["profile"]}
    started = time.monotonic()
    timed_out = False
    with (folder / "process.log").open("w") as log:
        process = subprocess.Popen(
            [
                sys.executable,
                str(ROOT / "scripts/sdlc_family_probe.py"),
                "--family",
                trial["family"],
                "--output",
                str(output),
            ],
            cwd=ROOT,
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            process.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGINT)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
    result_path = output / "results.json"
    row = None
    if result_path.is_file():
        try:
            data = json.loads(result_path.read_text())
            if (
                isinstance(data, list)
                and len(data) == 1
                and data[0].get("family") == trial["family"]
            ):
                row = data[0]
        except (ValueError, AttributeError):
            pass
    # Mission event payloads are authoritative member receipts. Do not count the
    # same receipts again from convenience projections at the mission root.
    events = (row or {}).get("mission", {}).get("events", [])
    usage = usage_of(events)
    return {
        **trial,
        "status": classify(row, process.returncode, timed_out),
        "exit_code": process.returncode,
        "elapsed_seconds": time.monotonic() - started,
        "usage": usage if usage["records"] else None,
        "evidence": str(output.relative_to(folder)),
        "candidate_verified": bool(row and row.get("candidate_verified")),
        "error_type": (row or {}).get("error_type"),
    }


def summarize(rows: list[dict], *, drift: bool = False) -> dict:
    expected = plan()
    identities = [(r.get("sequence"), r.get("family"), r.get("profile")) for r in rows]
    wanted = [(r["sequence"], r["family"], r["profile"]) for r in expected]
    complete = identities == wanted
    arms = {}
    for profile in PROFILES:
        trials = [r for r in rows if r.get("profile") == profile]
        counts = {
            state: sum(r["status"] == state for r in trials)
            for state in (
                "accepted",
                "candidate_failed",
                "model_or_provider_failure",
                "execution_failure",
                "infrastructure_failure",
                "timeout",
            )
        }
        arms[profile] = {
            "planned": len(FAMILIES),
            "attempted": len(trials),
            **counts,
            "elapsed_seconds": sum(r.get("elapsed_seconds", 0) for r in trials),
            "known_input_tokens": sum(
                (r.get("usage") or {}).get("input_tokens", 0) for r in trials
            ),
            "known_output_tokens": sum(
                (r.get("usage") or {}).get("output_tokens", 0) for r in trials
            ),
            "trials_missing_usage": sum(r.get("usage") is None for r in trials),
        }
    return {
        "campaign_validity": "contaminated" if drift else "complete" if complete else "incomplete",
        "qualification": "not_qualified",
        "comparison": "inconclusive",
        "limitations": [
            "One public trial per family and arm; no confidence estimate",
            "No held-out cases or automatic promotion",
            "Model/provider and infrastructure failures remain in the denominator",
            "Healthy, out-of-scope and adversarial cases require separate controls",
        ],
        "arms": arms,
        "trials": rows,
    }


def run(output: Path, seconds: float = 900, executor=execute) -> dict:
    if not 0 < seconds <= 1800:
        raise ValueError("Trial deadline must be in (0, 1800] seconds")
    output.mkdir(parents=True, exist_ok=False)
    frozen, configuration = fingerprints(), configuration_fingerprint()
    manifest = {
        "plan": plan(),
        "source_digests": frozen,
        "configuration_digests": configuration,
        "seconds_per_trial": seconds,
        "retries": 0,
        "publication": False,
        "qualification": "public development only",
    }
    write(output / "manifest.json", manifest)
    rows, drift = [], False
    for trial in manifest["plan"]:
        if fingerprints() != frozen or configuration_fingerprint() != configuration:
            drift = True
            break
        folder = output / f"{trial['sequence']:02d}-{trial['family']}-{trial['profile']}"
        folder.mkdir()
        try:
            row = executor(trial, folder, seconds)
        except Exception as exc:
            row = {
                **trial,
                "status": "infrastructure_failure",
                "error_type": type(exc).__name__,
                "usage": None,
            }
        rows.append(row)
        write(folder / "result.json", row)
        drift = fingerprints() != frozen or configuration_fingerprint() != configuration
        write(output / "results.json", summarize(rows, drift=drift))
        if drift:
            break
    result = summarize(rows, drift=drift)
    write(output / "results.json", result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--seconds-per-trial", type=float, default=900)
    args = parser.parse_args()
    output = args.output or ROOT / ".local" / f"sdlc-tools-campaign-{time.time_ns()}"
    result = run(output, args.seconds_per_trial)
    print(f"Evidence: {output}")
    print(json.dumps({"campaign_validity": result["campaign_validity"], "arms": result["arms"]}))
    if result["campaign_validity"] != "complete":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
