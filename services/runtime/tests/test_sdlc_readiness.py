import pytest
from starbase_runtime.sdlc_readiness import Limits, assess


def snapshot():
    return {
        "enabled": True,
        "policy": {
            "enabled": True,
            "publish": True,
            "expires_at": 2000,
            "repository": "X-McKay/algent",
        },
        "missions": [],
        "discoveries": [],
    }


def facts():
    return {
        name: {"value": True, "observed_at": 1000}
        for name in (
            "qualified_build",
            "control_suite_passed",
            "backup_restore_verified",
            "stop_verified",
            "dedicated_identity",
        )
    } | {"identity_repositories": {"value": ["X-McKay/algent"], "observed_at": 1000}}


def codes(report):
    return {b["code"] for b in report["blockers"]}


def test_unknown_qualification_does_not_impersonate_authority():
    report = assess(snapshot(), now=1000)
    assert not report["ready"] and not report["circuit_open"] and report["advisory"]
    assert "qualified_build" in codes(report)


def test_narrow_draft_readiness_requires_all_fresh_facts():
    assert assess(snapshot(), now=1000, mode="draft-pr", facts=facts())["ready"]
    changed = facts()
    changed["identity_repositories"]["value"] = ["X-McKay/algent", "X-McKay/kubani"]
    assert "identity_scope" in codes(assess(snapshot(), now=1000, mode="draft-pr", facts=changed))
    assert "dedicated_identity" in codes(
        assess(snapshot(), now=1400, mode="draft-pr", facts=facts())
    )


@pytest.mark.parametrize("state", ["blocked", "failed", "cancelled"])
def test_uncertain_claims_stop_admission_even_after_cancellation(state):
    value = snapshot()
    value["missions"] = [{"id": "one", "state": state, "effects": [{"input": {"kind": "branch"}}]}]
    report = assess(value, now=1000)
    assert report["circuit_open"] and report["observations"]["ambiguous_effects"] == ["one"]


def test_failure_circuit_counts_ordered_consecutive_failures_and_children():
    value = snapshot()
    value["missions"] = [{"id": str(i), "state": "blocked", "updated_at": i} for i in range(3)]
    assert "repeated_failures" in codes(assess(value, now=1000))
    value["missions"].append({"id": "success", "state": "awaiting_review", "updated_at": 4})
    assert "repeated_failures" not in codes(assess(value, now=1000))
    value["missions"][-1]["verifications"] = [{"id": "child", "state": "blocked", "effects": [{}]}]
    assert "ambiguous_effects" in codes(assess(value, now=1000))


def test_capacity_provider_health_and_expiry():
    value = snapshot()
    value["missions"] = [{"id": "queued", "state": "queued", "feedback": [{}]}]
    value["discoveries"] = [{}]
    result = assess(
        value,
        now=2001,
        facts={"provider_available": {"value": False, "observed_at": 2000}},
        limits=Limits(queued_missions=1, discoveries=1, feedback_records=1),
    )
    assert {
        "queue_capacity",
        "discovery_retention",
        "feedback_retention",
        "policy_inactive",
        "provider_unavailable",
    } <= codes(result)


@pytest.mark.parametrize("observed_at", [0, 2000, None])
def test_stale_future_missing_health_does_not_assert_outage(observed_at):
    report = assess(
        snapshot(),
        now=1000,
        facts={"provider_available": {"value": False, "observed_at": observed_at}},
    )
    assert "provider_unavailable" not in codes(report)


def test_invalid_inputs_fail_closed():
    with pytest.raises(ValueError):
        Limits(consecutive_failures=0)
    with pytest.raises(ValueError):
        assess({"missions": None}, now=1000)


def test_policy_budget_counts_only_current_generation_and_retention_never_prunes():
    value = snapshot()
    value["policy"].update(generation=4, max_missions=1)
    value["missions"] = [{"id": "older", "state": "awaiting_review", "policy_generation": 3}]
    assert "policy_budget" not in codes(assess(value, now=1000))
    value["missions"].append(
        {"id": "current", "state": "awaiting_review", "policy_generation": 4, "verifications": [{}]}
    )
    result = assess(value, now=1000, limits=Limits(missions=2, verifications=1))
    assert {"policy_budget", "mission_retention", "verification_retention"} <= codes(result)
    assert len(value["missions"]) == 2
