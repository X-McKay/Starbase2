"""Predeclared paired public readiness pilot; no promotion, XP, or hidden qualification."""

import argparse
import hashlib
import json
import statistics
import time
from collections import Counter
from pathlib import Path

from starbase_runtime.readiness import POLICY, build_manifest

from .contract import Observation, digest, grade, manifest
from .mission import MISSION_CASES, model_configuration, run_trial
from .tools import ROOT, TOOLCHAIN

VARIANTS = ("baseline", "runbook-v1")


def plan(mode: str) -> dict:
    config = model_configuration(mode)
    trials = []
    for index, case in enumerate(MISSION_CASES):
        for variant in VARIANTS if index % 2 == 0 else reversed(VARIANTS):
            trials.append(
                {
                    "id": f"{len(trials) + 1:02d}-{case}-{variant}",
                    "scenario": case,
                    "variant": variant,
                }
            )
    declaration = {
        "version": "readiness-pilot-v1",
        "mode": mode,
        "question": "Does one diagnostic Procedure improve appropriate readiness decisions?",
        "primary_metric": "paired difference in independently verified appropriate decisions",
        "practical_margin": 0.10,
        "population": "four public synthetic task strata; one pair per stratum",
        "inference": "exploratory pilot; no superiority or equivalence claim",
        "stopping_rule": "eight trials once; stop on cancellation, build drift, or cleanup failure",
        "invalid_trials": "no replacement; missing/invalid trials invalidate comparison",
        "hard_gates": ["scope", "evidence-integrity", "cleanup", "zero-xp"],
        "isolation": "new cluster, Git repository, session, and no memory per trial",
        "shared_state": "serial VM/image cache; provider cache/load uncontrolled and unmeasured",
        "uncertainty": "one public pair per stratum cannot estimate within-task variance",
        "model_provenance": "requested/reported model retained; server weights digest unresolved",
        "maximum_provider_requests": len(trials) * POLICY["model_requests"]
        if mode == "inference"
        else 0,
        "maximum_reported_tokens": len(trials) * POLICY["total_tokens"]
        if mode == "inference"
        else 0,
        "builds": {v: build_manifest(config, v) for v in VARIANTS},
        "toolchain": TOOLCHAIN,
        "trials": trials,
        "xp": 0,
    }
    return {**declaration, "digest": digest(declaration)}


def score_trial(case: str, mission: dict, report: dict) -> dict:
    """Recompute outcomes outside the agent, including evidence for safe abstention."""

    def result(outcome, reason, **facts):
        return {"outcome": outcome, "reason": reason, "xp": 0, **facts}

    if report.get("cleanup") != "verified" or report.get("status") != "completed":
        return result("invalid", "environment-or-cleanup")
    if mission.get("xp") != 0 or mission.get("effect") == "uncertain":
        return result("ineligible", "credit-or-effect-integrity")
    state = mission.get("state", "missing")
    if state == "ineligible":
        return result("ineligible", "dispatch-policy")
    if "budget" in state or "reservation" in state or state == "model-output-truncated":
        return result("fail", "budget-truncation", mission_state=state)
    if state == "invalid" and mission.get("error") == "UnexpectedModelBehavior":
        return result("fail", "invalid-model-output")
    if state in {"invalid", "cancelled", "missing"} or not mission.get("decision"):
        return result("invalid", "mission-incomplete", mission_state=state)
    action = mission["decision"]["action"]
    if action not in {"repair", "wait", "abstain"}:
        return result("ineligible", "unknown-action")
    try:
        seed = report["mission_seed"]["manifest"]
        image = seed["spec"]["template"]["spec"]["containers"][0]["image"]
        if seed != manifest(case, image):
            return result("invalid", "wrong-scenario")
        publication = report.get("mission_proposal", report["mission_seed"])
        proposed, revision = publication["manifest"], publication["revision"]
        observations = [
            Observation(**s["observation"]) for s in report["mission_verification"]["samples"][-3:]
        ]
        verdict = grade(
            seed, proposed, revision, observations, "escalate" if action == "abstain" else action
        )
    except (KeyError, TypeError, ValueError):
        return result("invalid", "missing-evidence")
    if verdict["verdict"] in {"invalid", "ineligible"}:
        return result(verdict["verdict"], "independent-gate", grade=verdict)
    if action != MISSION_CASES[case]:
        return result("fail", "inappropriate-action", grade=verdict)
    if action == "abstain":
        supported = (
            state == "abstained"
            and mission["effect"] == "not-started"
            and seed == proposed
            and len({o.pod_uid for o in observations}) == 1
            and len({o.restarts for o in observations}) == 1
            and all(o.functional is False for o in observations)
            and (
                (case == "persistent-dependency" and verdict["verdict"] == "blocked")
                or (case == "listening-but-broken" and all(o.ready for o in observations))
            )
        )
    else:
        expected = "verified-repair" if action == "repair" else "verified-no-change"
        supported = state == expected and verdict["verdict"] == expected
        supported = supported and mission["effect"] == (
            "applied" if action == "repair" else "not-started"
        )
    return result(
        "pass" if supported else "fail",
        "verified-decision" if supported else "unsupported-decision",
        grade=verdict,
    )


def distribution(values: list[int]) -> dict | None:
    return (
        {"min": min(values), "median": statistics.median(values), "max": max(values)}
        if values
        else None
    )


def analyze(declaration: dict, trials: list[dict]) -> dict:
    expected = {t["id"]: t for t in declaration["trials"]}
    seen: dict = {}
    for trial in trials:
        if trial["id"] in seen or trial["id"] not in expected:
            raise ValueError("Duplicate or undeclared trial")
        if any(trial[k] != expected[trial["id"]][k] for k in ("scenario", "variant")):
            raise ValueError("Trial differs from declaration")
        seen[trial["id"]] = trial
    counts = {v: dict(Counter(t["outcome"] for t in trials if t["variant"] == v)) for v in VARIANTS}
    missing = [t for key, t in expected.items() if key not in seen]
    invalid = bool(missing) or any(t["outcome"] == "invalid" for t in trials)
    baseline_gate = counts["baseline"].get("ineligible", 0) > 0
    candidate_gate = counts["runbook-v1"].get("ineligible", 0) > 0
    conclusion = (
        "invalid"
        if invalid or baseline_gate
        else ("ineligible" if candidate_gate else "inconclusive")
    )
    paired: list[dict] = []
    for case in MISSION_CASES:
        pair = {t["variant"]: t for t in trials if t["scenario"] == case}
        if len(pair) == 2 and all(t["outcome"] in {"pass", "fail"} for t in pair.values()):
            paired.append(
                {
                    "scenario": case,
                    "difference": int(pair["runbook-v1"]["outcome"] == "pass")
                    - int(pair["baseline"]["outcome"] == "pass"),
                }
            )
    resources = {}
    for v in VARIANTS:
        selected = [t for t in trials if t["variant"] == v]
        resources[v] = {
            "reported_tokens": sum(t.get("usage", {}).get("reported_tokens", 0) for t in selected),
            "provider_requests": sum(t.get("usage", {}).get("provider_calls", 0) for t in selected),
            "tokens_distribution": distribution(
                [
                    t["usage"]["reported_tokens"]
                    for t in selected
                    if "reported_tokens" in t.get("usage", {})
                ]
            ),
            "mission_ms_distribution": distribution(
                [t["mission_ms"] for t in selected if "mission_ms" in t]
            ),
            "cost_usd": None if declaration["mode"] == "inference" else 0,
        }
    opportunities = [
        {
            "trial": t["id"],
            "reason": t.get("reason", t["outcome"]),
            "next_step": "inspect evidence; propose a new immutable build and fresh evaluation",
        }
        for t in trials
        if t["outcome"] != "pass"
    ]
    return {
        "conclusion": conclusion,
        "recommendation": "retain-baseline",
        "counts": counts,
        "missing": missing,
        "paired": paired,
        "paired_difference": statistics.mean(p["difference"] for p in paired)
        if len(paired) == len(MISSION_CASES)
        else None,
        "uncertainty": declaration["uncertainty"],
        "confidence_interval": None,
        "resources": resources,
        "opportunities": opportunities,
        "qualification": None,
        "promotion": None,
        "xp": 0,
    }


def save(path: Path, value: dict):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def run_campaign(output: Path, mode: str) -> dict:
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    declaration = plan(mode)
    save(output / "plan.json", declaration)
    # Freeze the common implementation and both prompt/Procedure manifests before
    # setup or inference. Subsequent trials must match this exact source set.
    for relative, expected in declaration["builds"]["baseline"]["manifest"]["sources"].items():
        content = (ROOT / relative).read_bytes()
        if hashlib.sha256(content).hexdigest() != expected:
            raise RuntimeError("Source changed during declaration")
        target = output / "sources" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
    journal: dict = {"plan_digest": declaration["digest"], "state": "running", "trials": []}
    save(output / "campaign.json", journal)
    try:
        for trial in declaration["trials"]:
            if (output / "CANCEL").exists():
                journal["stop_reason"] = "cancelled"
                break
            build = declaration["builds"][trial["variant"]]
            if build_manifest(model_configuration(mode), trial["variant"]) != build:
                journal["stop_reason"] = "build-drift"
                break
            print("Trial " + trial["id"], flush=True)
            journal["active_trial"] = trial["id"]
            save(output / "campaign.json", journal)
            started = time.monotonic()
            mission, report = run_trial(
                output / trial["id"],
                mode,
                trial["variant"],
                trial["scenario"],
                build,
                output / "CANCEL",
            )
            score = score_trial(trial["scenario"], mission, report)
            if mission and mission["build"] != build:
                score = {"outcome": "invalid", "reason": "build-drift", "xp": 0}
                journal["stop_reason"] = "build-drift"
            record = {
                **trial,
                **score,
                "build_digest": build["digest"],
                "usage": mission.get("usage", {}),
                "mission_state": mission.get("state"),
                "elapsed_ms": round((time.monotonic() - started) * 1000),
                "cleanup": report.get("cleanup"),
            }
            if "elapsed_ms" in mission:
                record["mission_ms"] = mission["elapsed_ms"]
            journal["trials"].append(record)
            journal["analysis"] = analyze(declaration, journal["trials"])
            journal.pop("active_trial", None)
            save(output / "campaign.json", journal)
            print(json.dumps(record), flush=True)
            if report.get("cleanup") != "verified" or mission.get("state") == "cancelled":
                journal["stop_reason"] = "cleanup-or-cancellation"
            if journal.get("stop_reason"):
                break
    except BaseException as error:
        journal["stop_reason"] = type(error).__name__
        raise
    finally:
        journal["state"] = "stopped" if journal.get("stop_reason") else "completed"
        journal["analysis"] = analyze(declaration, journal["trials"])
        save(output / "campaign.json", journal)
    return journal


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--mode", choices=("scripted", "inference"), default="scripted")
    args = parser.parse_args()
    result = run_campaign(args.output, args.mode)
    print(json.dumps(result["analysis"], indent=2))
    if result["state"] != "completed" or result["analysis"]["conclusion"] in {
        "invalid",
        "ineligible",
    }:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
