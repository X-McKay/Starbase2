"""Trial reporting must not turn absent evidence or failed attempts into qualification."""

import json
from pathlib import Path

import pytest

from scripts import autonomy_trial as trial


def test_passed_wiring_keeps_missing_gates_and_qualification_explicit():
    result = trial.summarize([{"control": name, "status": "passed"} for name in trial.CONTROLS])
    assert result["wiring_result"] == "passed"
    assert result["autonomy_qualification"] == "not_qualified"
    assert result["model_qualification"] == "not_attempted"
    assert result["coverage"]["pr_feedback"]["status"] == "passed_synthetic"
    assert result["coverage"]["provider_interruption"]["status"] == "passed_synthetic"
    assert result["coverage"]["concurrent_head_drift"]["status"] == "passed_synthetic"


def test_prior_failure_cannot_be_hidden_by_later_success():
    rows = [{"control": name, "status": "passed"} for name in trial.CONTROLS]
    rows.insert(0, {"control": trial.CONTROLS[0], "status": "failed"})
    assert trial.summarize(rows)["wiring_result"] == "failed"
    assert trial.summarize(rows, drift=True)["wiring_result"] == "contaminated"
    assert trial.summarize([])["wiring_result"] == "incomplete"


def test_manifest_precedes_execution_and_stops_on_failure(tmp_path, monkeypatch):
    monkeypatch.setattr(trial, "fingerprints", lambda: {"fixture": "abc"})
    output = tmp_path / "trial"
    calls = []

    def execute(control, folder, seconds):
        plan = json.loads((output / "manifest.json").read_text())
        assert plan["duration_seconds"] == 0.5
        assert plan["source_digests"] == {"fixture": "abc"}
        assert 0 < seconds <= 0.5
        calls.append(control)
        return {"status": "failed"}

    result = trial.run(output, 0.5, "soak", execute)
    assert calls == [trial.CONTROLS[0]]
    assert result["wiring_result"] == "failed"
    assert (output / "results.json").exists()


def test_fast_iteration_finishes_without_waiting_out_budget(tmp_path, monkeypatch):
    monkeypatch.setattr(trial, "fingerprints", lambda: {"fixture": "abc"})
    result = trial.run(tmp_path / "trial", execute=lambda *_: {"status": "passed"})
    assert result["wiring_result"] == "passed"
    assert len(result["results"]) == len(trial.CONTROLS)


def test_changed_sources_invalidate_run(tmp_path, monkeypatch):
    digests = iter([{"fixture": "before"}, {"fixture": "after"}])
    monkeypatch.setattr(trial, "fingerprints", lambda: next(digests))
    result = trial.run(tmp_path / "trial", execute=lambda *_: {"status": "passed"})
    assert result["wiring_result"] == "contaminated"


@pytest.mark.parametrize("duration", [0, -1, float("nan"), float("inf"), 7201])
def test_invalid_budget_rejected(tmp_path, duration):
    with pytest.raises(ValueError):
        trial.run(tmp_path / "trial", duration)
    assert not (tmp_path / "trial").exists()


def test_missing_or_foreign_evidence_never_passes():
    assert trial.validate_evidence("sdlc_integration", "") == {"status": "evidence_missing"}
    assert trial.validate_evidence("sdlc_integration", "Evidence: /etc") == {
        "status": "evidence_invalid"
    }


def test_completion_evidence_requires_exact_controls(tmp_path, monkeypatch):
    monkeypatch.setattr(trial, "ROOT", tmp_path)
    evidence = tmp_path / ".local/sdlc-integration-1"
    evidence.mkdir(parents=True)
    events = [
        {
            "event": "complete",
            "synthetic_external_controls": True,
            "replay": "passed",
            "effects": 3,
            "duplicate_missions": 0,
            "state": "awaiting_review",
            "verdict": "improved",
        }
    ]
    log = f"Evidence: {evidence}\n"
    (evidence / "events.json").write_text(json.dumps(events))
    assert trial.validate_evidence("sdlc_integration", log)["status"] == "passed"
    events[0]["duplicate_missions"] = 1
    (evidence / "events.json").write_text(json.dumps(events))
    assert trial.validate_evidence("sdlc_integration", log)["status"] == "evidence_invalid"


def test_run_does_not_replace_existing_evidence(tmp_path):
    with pytest.raises(FileExistsError):
        trial.run(tmp_path)


def test_execution_environment_drops_credentials_and_timeout_cannot_pass(tmp_path, monkeypatch):
    class Process:
        returncode = 0

        def wait(self, timeout=None):
            if timeout != 45:
                raise trial.subprocess.TimeoutExpired("control", float(timeout or 0))

        def send_signal(self, value):
            assert value == trial.signal.SIGINT

    def popen(args, **kwargs):
        assert "GITHUB_TOKEN" not in kwargs["env"]
        assert "STARBASE_SDLC_ENABLED" not in kwargs["env"]
        assert Path(args[1]).name == "sdlc_integration.py"
        return Process()

    monkeypatch.setenv("GITHUB_TOKEN", "test-secret")
    monkeypatch.setenv("STARBASE_SDLC_ENABLED", "true")
    monkeypatch.setattr(trial.subprocess, "Popen", popen)
    result = trial.run_control("sdlc_integration", tmp_path, 0.01)
    assert result["status"] == "deadline_exceeded"


def test_launch_failure_retains_nonpassing_result(tmp_path, monkeypatch):
    monkeypatch.setattr(trial, "fingerprints", lambda: {})

    def failed(*_):
        raise FileNotFoundError("private path omitted from report")

    result = trial.run(tmp_path / "trial", execute=failed)
    assert result["wiring_result"] == "failed"
    assert result["results"][0]["status"] == "infrastructure_error"
    assert result["results"][0]["error_type"] == "FileNotFoundError"


@pytest.mark.parametrize("events", [None, {"complete": True}, [None], [1]])
def test_malformed_control_events_are_nonpassing(tmp_path, monkeypatch, events):
    monkeypatch.setattr(trial, "ROOT", tmp_path)
    evidence = tmp_path / ".local/sdlc-integration-1"
    evidence.mkdir(parents=True)
    (evidence / "events.json").write_text(json.dumps(events))
    assert trial.validate_evidence("sdlc_integration", f"Evidence: {evidence}\n")["status"] == (
        "evidence_invalid"
    )


def test_coordination_completion_requires_declared_interventions(tmp_path, monkeypatch):
    monkeypatch.setattr(trial, "ROOT", tmp_path)
    evidence = tmp_path / ".local/sdlc-coordination-integration-1"
    evidence.mkdir(parents=True)
    complete = {
        "event": "complete",
        "synthetic_external_controls": True,
        "families": ["persistence-history", "memory-key", "logging-level"],
        "priority_order": ["persistence-history", "memory-key", "logging-level"],
        "reassignment": True,
        "no_change_dispatches": 0,
        "unavailable_dispatches": 0,
        "duplicate_missions": 0,
        "external_effects": 0,
        "operator_cancellations": 3,
        "verified_not_published": 3,
    }
    (evidence / "events.json").write_text(json.dumps([complete]))
    assert (
        trial.validate_evidence("sdlc_coordination_integration", f"Evidence: {evidence}\n")[
            "status"
        ]
        == "passed"
    )
    del complete["operator_cancellations"]
    (evidence / "events.json").write_text(json.dumps([complete]))
    assert (
        trial.validate_evidence("sdlc_coordination_integration", f"Evidence: {evidence}\n")[
            "status"
        ]
        == "evidence_invalid"
    )
