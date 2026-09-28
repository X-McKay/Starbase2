"""Deterministic local readiness evidence; never grants publication authority.

Facts are operator/trusted-adapter observations, not agent outputs. Missing facts
stay unknown. The admission circuit is separate from qualification: existing
work, cancellation and reconciliation must remain runnable when admission stops.
"""

from dataclasses import dataclass
from typing import Literal

TERMINAL = {"awaiting_review", "completed", "failed", "blocked", "cancelled"}


@dataclass(frozen=True)
class Limits:
    consecutive_failures: int = 3
    queued_missions: int = 32
    missions: int = 100
    verifications: int = 16
    discoveries: int = 256
    feedback_records: int = 16
    fact_max_age_seconds: int = 300

    def __post_init__(self):
        if any(type(value) is not int or value <= 0 for value in vars(self).values()):
            raise ValueError("Readiness limits must be positive integers")


def assess(
    snapshot: dict,
    *,
    now: float,
    mode: Literal["shadow", "sandbox", "draft-pr"] = "sandbox",
    facts: dict | None = None,
    limits: Limits | None = None,
) -> dict:
    if mode not in {"shadow", "sandbox", "draft-pr"}:
        raise ValueError("Unknown readiness mode")
    limits = limits or Limits()
    facts = facts or {}
    blockers: list[dict] = []

    def block(code: str, detail: str, circuit: bool = False):
        blockers.append({"code": code, "detail": detail, "circuit": circuit})

    def fact(name: str):
        value = facts.get(name, {})
        observed = value.get("observed_at") if isinstance(value, dict) else None
        if (
            not isinstance(observed, (int, float))
            or not 0 <= now - observed <= limits.fact_max_age_seconds
        ):
            return None
        return value.get("value")

    missions = snapshot.get("missions", [])
    discoveries = snapshot.get("discoveries", [])
    if not isinstance(missions, list) or not isinstance(discoveries, list):
        raise ValueError("Readiness requires authoritative mission and discovery lists")
    work = [item for parent in missions for item in [parent, *parent.get("verifications", [])]]
    queued = sum(item.get("state") == "queued" for item in work)
    if queued >= limits.queued_missions:
        block("queue_capacity", "Queued work reached the configured admission limit", True)
    if len(discoveries) >= limits.discoveries:
        block("discovery_retention", "Discovery retention requires operator maintenance", True)
    ambiguous = [
        item.get("id")
        for item in work
        if item.get("state") in {"blocked", "failed", "cancelled"} and item.get("effects")
    ]
    if ambiguous:
        block(
            "ambiguous_effects",
            "Retained effect claims need reconciliation: " + ", ".join(ambiguous),
            True,
        )
    terminal = sorted(
        (item for item in work if item.get("state") in TERMINAL),
        key=lambda item: (item.get("updated_at", 0), item.get("id", "")),
        reverse=True,
    )
    failures = 0
    for item in terminal:
        if item.get("state") not in {"blocked", "failed"}:
            break
        failures += 1
    if failures >= limits.consecutive_failures:
        block(
            "repeated_failures", f"{failures} consecutive retained failures require diagnosis", True
        )
    if fact("inference_available") is False:
        block("inference_unavailable", "Trusted inference health reports unavailable", True)
    if fact("provider_available") is False:
        block("provider_unavailable", "Trusted provider health reports unavailable", True)
    saturated_feedback = [
        p["id"] for p in missions if len(p.get("feedback", [])) >= limits.feedback_records
    ]
    if saturated_feedback:
        block(
            "feedback_retention",
            "Feedback capacity reached: " + ", ".join(saturated_feedback),
            True,
        )
    if len(missions) >= limits.missions:
        block("mission_retention", "Mission retention requires operator maintenance", True)
    if any(len(parent.get("verifications", [])) >= limits.verifications for parent in missions):
        block("verification_retention", "A PR reached verification retention capacity", True)
    policy = snapshot.get("policy", {})
    used = sum(item.get("policy_generation") == policy.get("generation") for item in missions)
    budget = policy.get("max_missions")
    if type(budget) is int and used >= budget:
        block("policy_budget", "Core mission budget for this policy generation is exhausted", True)
    if (
        not snapshot.get("enabled")
        or not policy.get("enabled")
        or policy.get("expires_at", 0) <= now
    ):
        block("policy_inactive", "Core policy is disabled, absent or expired", True)
    if mode != "shadow":
        for name in (
            "qualified_build",
            "control_suite_passed",
            "backup_restore_verified",
            "stop_verified",
        ):
            if fact(name) is not True:
                block(name, "Missing, stale or unsuccessful trusted evidence: " + name)
    if mode == "draft-pr":
        if not policy.get("publish"):
            block("publication_disabled", "Core policy does not permit publication")
        if fact("dedicated_identity") is not True:
            block("dedicated_identity", "A dedicated GitHub App identity has not been verified")
        scope = fact("identity_repositories")
        if not isinstance(scope, list) or {str(v).lower() for v in scope} != {
            str(policy.get("repository", "")).lower()
        }:
            block(
                "identity_scope",
                "Identity repository scope is missing or broader than the policy target",
            )
    return {
        "mode": mode,
        "advisory": True,
        "ready": not blockers,
        "circuit_open": any(b["circuit"] for b in blockers),
        "blockers": blockers,
        "observations": {
            "queued": queued,
            "discoveries": len(discoveries),
            "consecutive_failures": failures,
            "ambiguous_effects": ambiguous,
            "policy_missions_used": used,
            "assessed_at": now,
        },
    }
