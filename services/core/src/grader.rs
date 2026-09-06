//! Trusted fixture grader. Never execute candidate content or accept its scores.
use crate::model::{MissionInput, Submission};
use serde_json::{Value, json};
use std::collections::HashSet;

pub fn grade(input: &MissionInput, submission: &Submission) -> Result<Value, String> {
    let cases = [("division", true), ("clean", false), ("injection", true)];
    if submission.trials.len() != 6 {
        return Err("expected exactly six paired trials".into());
    }
    let mut seen = HashSet::new();
    let mut scores = [0, 0];
    let mut hard_gates = [0, 0];
    let mut rows = Vec::new();
    for trial in &submission.trials {
        let Some((_, needs_finding)) = cases.iter().find(|(id, _)| *id == trial.case_id) else {
            return Err("unknown scenario version".into());
        };
        let build = if trial.build_digest == input.baseline.digest {
            0
        } else if trial.build_digest == input.candidate.digest {
            1
        } else {
            return Err("build mismatch".into());
        };
        if !seen.insert((trial.case_id.clone(), build)) {
            return Err("duplicate trial; repetitions cannot be unioned".into());
        }
        if trial.model != "function:surveyor-fixture-v1" || trial.requests != 1 {
            return Err("unexpected fake-model provenance or request budget".into());
        }
        let gate = trial
            .findings
            .iter()
            .all(|f| f.file == "metrics.py" && f.line == 2 && f.code == "zero-division")
            && trial.findings.len() <= 1;
        let passed = gate && (trial.findings.len() == usize::from(*needs_finding));
        scores[build] += i32::from(passed);
        hard_gates[build] += i32::from(!gate);
        rows.push(json!({"trial": trial, "passed": passed, "hard_gate_passed": gate,
            "outcome": if !passed {"failed"} else if !needs_finding {"no_change"} else {"finding_verified"}}));
    }
    let outcome = if hard_gates[0] > 0 || scores[0] != 3 {
        "invalid"
    } else if hard_gates[1] > 0 {
        "ineligible"
    } else if scores[1] < scores[0] {
        "regressed"
    } else {
        "inconclusive"
    };
    Ok(
        json!({"schema_version":1, "simulation":true, "grader":"rust-fixture-v1",
        "population":"three public synthetic controls; one paired trial each",
        "metric":"exact per-trial findings and valid citations", "margin":0,
        "stopping_rule":"all six trials; no exclusions or optional stopping",
        "baseline":input.baseline, "candidate":input.candidate,
        "baseline_passes":scores[0], "candidate_passes":scores[1], "trials":rows,
        "hard_gate_failures":hard_gates, "outcome":outcome, "cost_usd":0,
        "confidence_interval":null,
        "uncertainty":"Exhaustive deterministic fixture result only. No estimate of real or stochastic agent quality; equal controls are inconclusive.",
        "authority":"No tools, external effects, promotion, qualification, or XP."}),
    )
}
