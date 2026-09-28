import json

from scripts import sdlc_tools_campaign as campaign


def test_plan_is_balanced_and_contains_no_retries():
    plan = campaign.plan()
    assert len(plan) == 9
    assert len({(row["family"], row["profile"]) for row in plan}) == 9
    for position in range(3):
        assert {plan[i * 3 + position]["profile"] for i in range(3)} == set(campaign.PROFILES)


def test_summary_retains_failed_trials_and_unknown_usage():
    rows = [{**row, "status": "candidate_failed", "usage": None} for row in campaign.plan()]
    rows[0]["status"] = "accepted"
    rows[1]["status"] = "model_or_provider_failure"
    result = campaign.summarize(rows)
    assert result["campaign_validity"] == "complete"
    assert result["qualification"] == "not_qualified"
    assert result["comparison"] == "inconclusive"
    assert result["arms"]["legacy"]["accepted"] == 1
    assert result["arms"]["legacy"]["candidate_failed"] == 2
    assert result["arms"]["tools"]["model_or_provider_failure"] == 1
    assert result["arms"]["tools"]["trials_missing_usage"] == 3
    assert campaign.summarize(rows + [rows[0]])["campaign_validity"] == "incomplete"
    assert campaign.summarize(rows, drift=True)["campaign_validity"] == "contaminated"


def test_classification_never_accepts_missing_or_crashed_evidence():
    assert campaign.classify(None, 0) == "infrastructure_failure"
    row = {"mission": {}, "candidate_verified": True}
    assert campaign.classify(row, 0) == "accepted"
    assert campaign.classify(row, 1) == "infrastructure_failure"
    assert campaign.classify(row, 0, True) == "timeout"
    row["candidate_verified"] = False
    assert campaign.classify(row, 1) == "candidate_failed"
    row["error_type"] = "MemberFailure"
    assert campaign.classify(row, 1) == "model_or_provider_failure"


def test_fingerprints_include_runtime_procedures_and_fixture_changes(tmp_path):
    path = tmp_path / "services/runtime/starbase_runtime/agents/sdlc/procedures/repair.md"
    path.parent.mkdir(parents=True)
    path.write_text("first")
    first = campaign.fingerprints(tmp_path)
    path.write_text("second")
    assert campaign.fingerprints(tmp_path) != first
    assert str(path.relative_to(tmp_path)) in first


def test_environment_provenance_does_not_record_secrets(monkeypatch):
    monkeypatch.setenv("STARBASE_INFERENCE_URL", "https://secret:password@example.test/v1")
    monkeypatch.setenv("STARBASE_TOKEN_FILE", "/secret/token")
    value = campaign.configuration_fingerprint()
    assert "STARBASE_TOKEN_FILE" not in value
    assert "password" not in json.dumps(value)
    endpoint = value["STARBASE_INFERENCE_URL"]
    assert isinstance(endpoint, str) and len(endpoint) == 64


def test_manifest_precedes_all_trials_failures_do_not_retry(tmp_path, monkeypatch):
    monkeypatch.setattr(campaign, "fingerprints", lambda: {"source": "frozen"})
    output = tmp_path / "campaign"
    calls = []

    def execute(trial, folder, seconds):
        assert json.loads((output / "manifest.json").read_text())["retries"] == 0
        calls.append(trial)
        if trial["sequence"] == 2:
            raise RuntimeError("provider process failed")
        return {**trial, "status": "candidate_failed", "usage": None}

    result = campaign.run(output, executor=execute)
    assert calls == campaign.plan()
    assert result["campaign_validity"] == "complete"
    assert result["trials"][1]["status"] == "infrastructure_failure"
    assert result["arms"]["legacy"]["candidate_failed"] == 3


def test_source_drift_stops_remaining_dispatch_and_retains_attempt(tmp_path, monkeypatch):
    state = {"source": "before"}
    monkeypatch.setattr(campaign, "fingerprints", lambda: dict(state))

    def execute(trial, folder, seconds):
        state["source"] = "after"
        return {**trial, "status": "accepted", "usage": None}

    result = campaign.run(tmp_path / "campaign", executor=execute)
    assert result["campaign_validity"] == "contaminated"
    assert len(result["trials"]) == 1
    assert result["trials"][0]["status"] == "accepted"


def test_usage_sums_member_receipts_and_preserves_missing_information():
    result = campaign.usage_of(
        [
            {"payload": {"usage": {"input_tokens": 5, "output_tokens": 3}}},
            {"payload": {"usage": None}},
            {"payload": {"usage": {"input_tokens": 2, "output_tokens": 4}}},
        ]
    )
    assert result == {"input_tokens": 7, "output_tokens": 7, "records": 2}
