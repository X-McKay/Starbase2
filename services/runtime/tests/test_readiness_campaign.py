"""Campaign controls: paired evidence, honest abstention, and immutable conditions."""

import copy

import pytest
from starbase_runtime.readiness import build_manifest

from scripts.readiness.campaign import analyze, plan, score_trial
from scripts.readiness.contract import manifest, repair


def trial(case, action, *, ready=True, functional=True):
    seed = manifest(case, "fixture-image")
    proposed = repair(seed, case) if action == "repair" else seed
    revision = "b" * 40
    samples = [
        {
            "observation": {
                "elapsed_seconds": t,
                "revision": revision,
                "flux_current": True,
                "workload_current": True,
                "ready": ready,
                "pod_uid": "current-pod",
                "restarts": 0,
                "functional": functional,
            }
        }
        for t in (36, 40, 44)
    ]
    mission = {
        "state": "abstained"
        if action == "abstain"
        else ("verified-repair" if action == "repair" else "verified-no-change"),
        "decision": {"action": action},
        "effect": "applied" if action == "repair" else "not-started",
        "xp": 0,
    }
    report = {
        "cleanup": "verified",
        "status": "completed",
        "mission_seed": {"manifest": seed, "revision": "a" * 40},
        "mission_verification": {"samples": samples},
    }
    if action == "repair":
        report["mission_proposal"] = {"manifest": proposed, "revision": revision}
    else:
        report["mission_seed"]["revision"] = revision
    return mission, report


@pytest.mark.parametrize(
    "case,action,ready,functional",
    [
        ("route-mismatch", "repair", True, True),
        ("healthy", "wait", True, True),
        ("persistent-dependency", "abstain", False, False),
        ("listening-but-broken", "abstain", True, False),
    ],
)
def test_independent_expected_actions(case, action, ready, functional):
    m, r = trial(case, action, ready=ready, functional=functional)
    assert score_trial(case, m, r)["outcome"] == "pass"
    r["mission_verification"]["samples"][-1]["observation"]["revision"] = "c" * 40
    assert score_trial(case, m, r)["outcome"] == "invalid"


def test_abstention_does_not_get_credit_without_evidence():
    m, r = trial("healthy", "abstain")
    assert score_trial("healthy", m, r)["outcome"] == "fail"
    m, r = trial("persistent-dependency", "abstain", ready=False, functional=False)
    r["mission_verification"]["samples"] = []
    assert score_trial("persistent-dependency", m, r)["outcome"] == "invalid"


def test_gate_failure_and_cleanup_are_never_success():
    m, r = trial("route-mismatch", "repair")
    r["mission_proposal"]["manifest"]["spec"]["replicas"] = 20
    assert score_trial("route-mismatch", m, r)["outcome"] == "ineligible"
    m, r = trial("healthy", "wait")
    r["cleanup"] = "failed"
    assert score_trial("healthy", m, r)["outcome"] == "invalid"


def test_claimed_success_and_unstable_abstention_do_not_override_observations():
    m, r = trial("route-mismatch", "repair", functional=False)
    m["grade"] = {"verdict": "verified-repair"}
    assert score_trial("route-mismatch", m, r)["outcome"] == "fail"
    m, r = trial("listening-but-broken", "abstain", functional=False)
    r["mission_verification"]["samples"][-1]["observation"]["pod_uid"] = "replacement-pod"
    assert score_trial("listening-but-broken", m, r)["outcome"] == "fail"
    m, r = trial("persistent-dependency", "abstain", ready=False, functional=False)
    for sample, elapsed in zip(r["mission_verification"]["samples"], [1, 4, 8], strict=True):
        sample["observation"]["elapsed_seconds"] = elapsed
    assert score_trial("persistent-dependency", m, r)["outcome"] == "invalid"


def test_build_diff_is_only_procedure_and_prompt():
    config = {"mode": "scripted", "name": "test", "endpoint": None}
    baseline = build_manifest(config, "baseline")
    candidate = build_manifest(config, "runbook-v1")
    assert baseline["digest"] != candidate["digest"]
    left, right = copy.deepcopy(baseline["manifest"]), copy.deepcopy(candidate["manifest"])
    assert left.pop("procedure") is None
    assert right.pop("procedure")["version"] == 1
    assert left.pop("prompt") != right.pop("prompt")
    assert left == right
    with pytest.raises(ValueError):
        build_manifest(config, "unknown")


def test_plan_pairs_inputs_and_counterbalances_order():
    p = plan("scripted")
    assert len(p["trials"]) == 8
    for index in range(0, 8, 2):
        a, b = p["trials"][index : index + 2]
        assert a["scenario"] == b["scenario"]
        assert {a["variant"], b["variant"]} == {"baseline", "runbook-v1"}
        assert a["variant"] == ("baseline" if index % 4 == 0 else "runbook-v1")


def test_analysis_retains_failures_and_incomplete_pairs():
    p = plan("scripted")
    records = [dict(t, outcome="pass", usage={"reported_tokens": 10}) for t in p["trials"]]
    records[1]["outcome"] = "fail"
    a = analyze(p, records)
    assert a["conclusion"] == "inconclusive"
    assert a["paired_difference"] == -0.25
    assert a["counts"]["runbook-v1"]["fail"] == 1
    assert a["recommendation"] == "retain-baseline"
    assert analyze(p, records[:-1])["conclusion"] == "invalid"
    records[1]["outcome"] = "ineligible"
    assert analyze(p, records)["conclusion"] == "ineligible"
    records[1]["outcome"] = "invalid"
    assert analyze(p, records)["conclusion"] == "invalid"
    with pytest.raises(ValueError):
        analyze(p, records + [records[0]])


def test_campaign_runs_every_pair_once_and_retains_environment_failure(tmp_path, monkeypatch):
    from scripts.readiness import campaign

    calls = []

    def run(output, mode, variant, case, build, cancel_path):
        assert (output.parent / "plan.json").exists()
        assert not output.exists()
        calls.append((case, variant))
        m, r = trial(
            case,
            campaign.MISSION_CASES[case],
            ready=case != "persistent-dependency",
            functional=case in {"healthy", "route-mismatch"},
        )
        m["build"] = build
        if len(calls) == 1:
            r["status"] = "invalid"
        return m, r

    monkeypatch.setattr(campaign, "run_trial", run)
    result = campaign.run_campaign(tmp_path / "pilot", "scripted")
    assert len(calls) == len(set(calls)) == 8
    assert result["state"] == "completed"
    assert result["analysis"]["conclusion"] == "invalid"
    assert result["analysis"]["opportunities"][0]["reason"] == "environment-or-cleanup"
    with pytest.raises(FileExistsError):
        campaign.run_campaign(tmp_path / "pilot", "scripted")


def test_campaign_stops_after_cleanup_failure(tmp_path, monkeypatch):
    from scripts.readiness import campaign

    def run(*args):
        return {}, {"cleanup": "failed", "status": "invalid"}

    monkeypatch.setattr(campaign, "run_trial", run)
    result = campaign.run_campaign(tmp_path / "pilot", "scripted")
    assert result["state"] == "stopped"
    assert len(result["trials"]) == 1
    assert len(result["analysis"]["missing"]) == 7


def test_campaign_cancel_fences_model_and_lab_commands(tmp_path):
    from starbase_runtime.readiness import FenceError, MissionSession

    from scripts.readiness.mission import MissionLab
    from services.runtime.tests.test_readiness_mission import Port

    cancel = tmp_path / "CANCEL"
    lab = MissionLab(tmp_path / "run")
    lab.cancel_path = cancel
    s = MissionSession(Port(), lab.output / "mission.json", {"digest": "frozen"})
    s.cancel_paths.append(cancel)
    cancel.touch()
    with pytest.raises(FenceError, match="cancelled"):
        s.guard()
    with pytest.raises(FenceError, match="cancelled"):
        lab.call("this-must-never-run")
