"""Deterministic, advisory Trainer queue derived from Core-owned SDLC records.

No model, provider effect, promotion, credential, or database access. Raw repository
and model prose are never interpreted as instructions or copied into proposals.
"""

import json
import math
import os
import re
from pathlib import Path
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from .review import digest

MAX_BYTES = 32_000_000
IDENTIFIER = re.compile(r"[a-zA-Z0-9_.:/-]{1,200}\Z")
TERMINAL = {"awaiting_review", "blocked", "failed", "cancelled"}


class Snapshot(BaseModel):
    model_config = ConfigDict(extra="ignore", strict=True)
    missions: list[dict[str, Any]] = Field(default_factory=list, max_length=256)
    verifications: list[dict[str, Any]] = Field(default_factory=list, max_length=256)


EXPERIMENTS = {
    "patch-rejected": {
        "factor": "tool",
        "change": {"editing": "digest-bound whole-symbol replacement", "inspect_diff": True},
        "hypothesis": "Inspecting applied symbol replacements reduces invalid patch submissions.",
    },
    "review-disagreement": {
        "factor": "procedure",
        "change": {
            "procedure": "review-repair-v2",
            "require": "case-level evidence reconciliation",
        },
        "hypothesis": "Explicit baseline/candidate interpretation reduces unsupported abstention.",
    },
    "behavior-failed": {
        "factor": "procedure",
        "change": {"procedure": "minimal-repair-v2", "require": "inspect-edit-test-diff loop"},
        "hypothesis": "Public feedback before submission increases independently verified repairs.",
    },
    "provider-failed": {
        "factor": "configuration",
        "change": {"experiment": "reasoning-enabled", "require": "resolved provider configuration"},
        "hypothesis": "A pinned reasoning configuration reduces malformed or truncated responses.",
    },
    "hard-gate-failed": {
        "factor": "procedure",
        "change": {"procedure": "scope-and-integrity-v2", "require": "preflight scope checks"},
        "hypothesis": "Explicit preflight checks reduce independent hard-gate failures.",
    },
}


def _id(value: object) -> str:
    return value if isinstance(value, str) and IDENTIFIER.fullmatch(value) else "unknown"


def _number(value: object) -> float | None:
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value) if math.isfinite(value) and 0 <= value <= 1e15 else None
    return None


def _obj(value: object) -> dict:
    return value if isinstance(value, dict) else {}


def _calls(value: object, depth: int = 0):
    """Walk bounded event payloads, stopping at each model invocation envelope."""
    if depth > 12:
        return
    if isinstance(value, dict):
        if "usage" in value and ("role" in value or "model" in value):
            yield value
            return
        for key, child in value.items():
            if key not in {"sources", "candidate_files", "output", "response_excerpt"}:
                yield from _calls(child, depth + 1)
    elif isinstance(value, list):
        for child in value[:256]:
            yield from _calls(child, depth + 1)


def _distribution(values: list[float]) -> dict:
    ordered = sorted(values)
    return {
        "count": len(ordered),
        "values": ordered,
        "median": ordered[(len(ordered) - 1) // 2] if ordered else None,
        "p95_nearest_rank": ordered[math.ceil(len(ordered) * 0.95) - 1] if ordered else None,
    }


def _rate(success: int, total: int) -> dict:
    return {
        "numerator": success,
        "denominator": total,
        "value": success / total if total else None,
        "uncertainty": "descriptive only; dependent operational tasks, no qualification interval",
    }


def derive_report(snapshot: dict) -> dict:
    """Read /v7/snapshot (or retained mission exports); all recommendations advisory.

    Input must come from trusted Core capture. Self-reported agent success inside
    output is ignored. Duplicate identities with divergent records are rejected.
    """
    encoded = json.dumps(snapshot, allow_nan=False)
    if len(encoded.encode()) > MAX_BYTES:
        raise ValueError("Trainer snapshot exceeds byte budget")
    source = Snapshot.model_validate(snapshot)
    children = list(source.verifications)
    for parent in source.missions:
        nested = parent.get("verifications", [])
        if not isinstance(nested, list) or len(nested) > 32:
            raise ValueError("Invalid bounded verification history")
        for child in nested:
            if not isinstance(child, dict):
                raise ValueError("Invalid verification record")
            child_input = _obj(child.get("input"))
            children.append(
                child
                | {
                    "input": child_input
                    | {
                        "opportunity": child_input.get(
                            "opportunity", _obj(parent.get("input")).get("opportunity")
                        )
                    }
                }
            )
    if len(children) > 256:
        raise ValueError("Trainer verification budget exceeded")
    rows, seen = [], {}
    clusters: dict[tuple[str, str, str], list[dict]] = {}
    for kind, missions in (("mission", source.missions), ("verification", children)):
        for mission in missions:
            identity = _id(mission.get("id"))
            if identity == "unknown":
                raise ValueError("Trainer needs a bounded mission identity")
            key = (kind, identity)
            fingerprint = digest(mission)
            if key in seen:
                if seen[key] != fingerprint:
                    raise ValueError("Conflicting mission evidence")
                continue
            seen[key] = fingerprint
            original = _obj(mission.get("input"))
            build = _id(_obj(original.get("build")).get("digest"))
            family = _id(original.get("opportunity"))
            evidence = _obj(mission.get("evidence"))
            testing, review = _obj(evidence.get("testing")), _obj(evidence.get("reviewing"))
            verdict = testing.get("verdict")
            events = mission.get("events", [])
            if not isinstance(events, list) or len(events) > 100:
                raise ValueError("Invalid bounded mission event history")
            failures, calls, event_keys = set(), [], set()
            for retained in events:
                event = _obj(_obj(retained).get("event"))
                event_key = _id(_obj(retained).get("key"))
                if event_key in event_keys:
                    raise ValueError("Duplicate mission event key")
                event_keys.add(event_key)
                data = _obj(event.get("data"))
                if data.get("validation_error"):
                    failures.add("patch-rejected")
                calls.extend(_calls(data))
            # Do not double count event evidence copied into current stage snapshots.
            if not events:
                calls = list(_calls(evidence))
            calls = list({digest(call): call for call in calls}.values())
            if any(c.get("error_type") for c in calls):
                failures.add("provider-failed")
            if testing.get("validation_error"):
                failures.add("patch-rejected")
            if verdict == "ineligible":
                failures.add("hard-gate-failed")
            elif verdict and verdict != "improved" and not testing.get("validation_error"):
                failures.add("behavior-failed")
            if verdict == "improved" and review.get("status") in {"abstain", "revise", "reject"}:
                failures.add("review-disagreement")
            verified = verdict == "improved" and review.get("status") == "accept"
            failed_before = "patch-rejected" in failures or bool(
                _obj(mission.get("coordination")).get("reassignments")
            )
            usage, missing_usage, latencies = 0, 0, []
            for call in calls:
                u = _obj(call.get("usage"))
                inp, out = _number(u.get("input_tokens")), _number(u.get("output_tokens"))
                if inp is None or out is None:
                    missing_usage += 1
                else:
                    usage += int(inp + out)
                elapsed = _number(call.get("elapsed_ms"))
                if elapsed is not None:
                    latencies.append(elapsed)
            reference = {"kind": kind, "id": identity, "record_digest": fingerprint}
            for category in sorted(failures):
                clusters.setdefault((build, family, category), []).append(reference)
            rows.append(
                {
                    "provenance": reference,
                    "build": build,
                    "family": family,
                    "state": _id(mission.get("state")),
                    "verified_repair": verified,
                    "qualification": "unqualified",
                    "failures": sorted(failures),
                    "encountered_failure": failed_before,
                    "recovered": failed_before and verified,
                    "tokens_observed": usage,
                    "calls_observed": len(calls),
                    "calls_missing_usage": missing_usage,
                    "latency_ms": _distribution(latencies),
                    "usage_complete": bool(calls) and missing_usage == 0,
                }
            )
    rows.sort(key=lambda r: (r["provenance"]["kind"], r["provenance"]["id"]))
    queue = []
    for (build, family, category), refs in sorted(clusters.items()):
        experiment = EXPERIMENTS[category]
        candidate = {"schema": 1, "baseline": build, "family": family, **experiment}
        proposal_id = digest(candidate)
        queue.append(
            {
                "id": proposal_id,
                "proposal": candidate,
                "failure_cluster": category,
                "evidence": sorted(refs, key=lambda r: (r["kind"], r["id"])),
                "state": "awaiting_frozen_inputs",
                "advisory": True,
                "campaign": {
                    "baseline": build,
                    "candidate_proposal_digest": proposal_id,
                    "candidate_build": None,
                    "fixtures_digest": None,
                    "grader_digest": None,
                    "environment_digest": None,
                    "primary_metric": "independently verified repair fraction per task",
                    "practical_margin": 0.05,
                    "design": "paired counterbalanced public pilot; task-clustered analysis",
                    "task_strata": ["repair", "no-change", "abstention", "malformed", "recovery"],
                    "repetitions_per_task": 2,
                    "maximum_pairs": 20,
                    "stopping_rule": "complete all frozen pairs or retain budget-truncated outcome",
                    "hard_gates": [
                        "correctness",
                        "scope",
                        "isolation",
                        "policy",
                        "evidence-integrity",
                    ],
                    "invalid_trials": (
                        "retain infrastructure/grader/contamination separately; "
                        "no silent replacement"
                    ),
                    "analysis": (
                        "retain per-trial failures; paired task-cluster bootstrap "
                        "when sufficient independent tasks"
                    ),
                    "promotion": "none; fresh held-out confirmation required",
                },
            }
        )
    completed = [r for r in rows if r["state"] in TERMINAL or r["verified_repair"]]
    recovery = [r for r in completed if r["encountered_failure"]]
    return {
        "schema": 1,
        "source_digest": digest(rows),
        "advisory": True,
        "authority_changes": [],
        "xp_awards": [],
        "active_build_changes": [],
        "attempts": rows,
        "campaign_queue": queue,
        "metrics": {
            "verified_repair_rate": _rate(
                sum(r["verified_repair"] for r in completed), len(completed)
            ),
            "agility": _rate(sum(r["recovered"] for r in recovery), len(recovery)),
            "speed_ms": _distribution([x for r in rows for x in r["latency_ms"]["values"]]),
            "constitution_tokens_observed": sum(r["tokens_observed"] for r in rows),
            "attempts_missing_usage": sum(not r["usage_complete"] for r in rows),
            "unknown_or_incomplete_attempts": sum(
                r["state"] not in TERMINAL and not r["verified_repair"] for r in rows
            ),
        },
        "limitations": [
            "Operational development evidence is not independent held-out qualification.",
            "Token totals include retained failed calls; missing usage is unknown, not zero.",
            "Copied call envelopes are deduplicated; identical real calls may be undercounted.",
            "Agility counts patch failures/reassignments; raw earlier events lack Core verdicts.",
            "Reviewer disagreement proposes investigation; it cannot override authority.",
            "Queue proposals require frozen fixture/grader/build bindings before execution.",
        ],
    }


def write_report(directory: Path, report: dict) -> Path:
    """Idempotent content-addressed artifact; exclusively create, never replace."""
    raw = (json.dumps(report, sort_keys=True, indent=2, allow_nan=False) + "\n").encode()
    if len(raw) > MAX_BYTES:
        raise ValueError("Trainer report exceeds byte budget")
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / ("trainer-" + digest(report) + ".json")
    try:
        fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o400)
    except FileExistsError:
        if target.is_symlink() or target.read_bytes() != raw:
            raise ValueError("Conflicting Trainer artifact") from None
        return target
    with os.fdopen(fd, "wb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    return target


def freeze_campaign(
    entry: dict,
    *,
    candidate_build: str,
    fixtures_digest: str,
    grader_digest: str,
    environment_digest: str,
    task_ids: list[str],
) -> dict:
    """Bind one advisory queue entry into an immutable, ordered public pilot plan.

    The caller supplies independently prepared fixtures/grader and candidate build.
    This function issues no execution capability and performs no external effects.
    """
    proposal = entry.get("proposal")
    if not isinstance(proposal, dict) or entry.get("id") != digest(proposal):
        raise ValueError("Proposal identity mismatch")
    if proposal.get("factor") not in {"tool", "procedure", "configuration"}:
        raise ValueError("Unsupported experiment factor")
    bindings = {
        "baseline": proposal.get("baseline"),
        "candidate_build": candidate_build,
        "fixtures_digest": fixtures_digest,
        "grader_digest": grader_digest,
        "environment_digest": environment_digest,
    }
    if any(
        not isinstance(v, str) or not re.fullmatch(r"[0-9a-f]{64}", v) for v in bindings.values()
    ):
        raise ValueError("Campaign requires immutable digest bindings")
    if candidate_build == proposal["baseline"]:
        raise ValueError("Candidate must differ from baseline")
    if not 1 <= len(task_ids) <= 10 or len(set(task_ids)) != len(task_ids):
        raise ValueError("Pilot requires one to ten distinct tasks")
    if any(_id(task) == "unknown" for task in task_ids):
        raise ValueError("Invalid task identity")
    # Derive the authored plan again; never trust modified queue policy fields.
    template = {
        "primary_metric": "independently verified repair fraction per task",
        "practical_margin": 0.05,
        "stop": "complete all pairs or retain budget-truncated outcome",
        "hard_gates": ["correctness", "scope", "isolation", "policy", "evidence-integrity"],
        "invalid_trials": "retain separately, no silent replacement",
        "analysis": "paired by task, exploratory only; fresh held-out confirmation required",
    }
    pairs = []
    for number, task in enumerate(task_ids):
        for repetition in range(2):
            order = ["baseline", "candidate"]
            if (number + repetition) % 2:
                order.reverse()
            pairs.append({"task": task, "repetition": repetition, "order": order})
    plan = {
        "schema": 1,
        "proposal_digest": entry["id"],
        "bindings": bindings,
        "protocol": template,
        "pairs": pairs,
        "advisory": True,
        "authority_changes": [],
        "state": "frozen_public_pilot",
    }
    return plan | {"digest": digest(plan)}
