//! Bounded, typed V7 projections for polling clients.
//!
//! The retained mission body (sources, evidence, up to 100 events) stays on
//! `GET /v7/missions/{id}`. Summaries are derived on read from that same record;
//! they add no storage and no authority. `None` (JSON null) always means the value
//! was not recorded or could not be interpreted, never an empty success.
use crate::{
    Result, Store,
    sdlc::{SdlcPolicy, capabilities, coordination, enabled, expected_cases, verification_enabled},
};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;

pub const DEFAULT_MISSION_LIMIT: usize = 25;
/// Equal to Core's V7 mission retention capacity.
pub const MAX_MISSION_LIMIT: usize = 100;
const TEXT_LIMIT: usize = 800;
const FIELD_LIMIT: usize = 400;
const LABEL_LIMIT: usize = 160;
const FINDING_LIMIT: usize = 5;
const RECENT_EVENT_LIMIT: usize = 3;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SdlcEventSummary {
    pub key: String,
    pub stage: String,
    // Core receipt time; null for a malformed legacy record.
    pub at: Option<f64>,
    // Short human label derived from the stage and retained role/status.
    pub label: String,
    // Role reported in the event data, when one was retained.
    pub role: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SdlcInputSummary {
    pub id: String,
    pub repository: Option<String>,
    pub revision: Option<String>,
    pub opportunity: Option<String>,
    pub build_digest: Option<String>,
    pub capability_digest: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SdlcPublicationSummary {
    // `none`, `claimed` (authority claimed; branch/PR effect may be in flight),
    // `submitted` or `awaiting_review`. Never `merged`: Starbase does not merge.
    pub state: String,
    pub branch: Option<String>,
    pub pr_number: Option<u64>,
    pub pr_url: Option<String>,
    // Last retained provider lifecycle checkpoint (`open`, `closed`, `merged`).
    pub pr_state: Option<String>,
    pub pr_observed_at: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SdlcVerificationInputSummary {
    pub head: Option<String>,
    pub build_digest: Option<String>,
    pub feedback_digest: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SdlcVerificationSummary {
    pub id: String,
    pub state: String,
    pub cancel_requested: bool,
    pub policy_generation: Option<u64>,
    pub updated_at: Option<f64>,
    pub input: SdlcVerificationInputSummary,
    // Core-graded outcome; null until the `verified` stage is retained.
    pub outcome: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SdlcPlanEvidence {
    pub role: Option<String>,
    // `implement` or `abstain` as returned by the lead.
    pub decision: Option<String>,
    pub rationale: Option<String>,
    pub task: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SdlcGradingSummary {
    pub verdict: Option<String>,
    // Null means the observation could not be graded (missing, malformed, not run).
    pub baseline_pass: Option<bool>,
    pub candidate_pass: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SdlcDiffStats {
    pub files: u32,
    pub additions: u32,
    pub deletions: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SdlcCaseResults {
    // Case ids whose observation exactly matched the trusted oracle.
    pub passed: Vec<String>,
    // Case ids whose observation differed, including unknown case ids.
    pub failed: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SdlcTestingEvidence {
    // Core-assigned verdict; a model's own claim is never copied here.
    pub verdict: Option<String>,
    pub grading: Option<SdlcGradingSummary>,
    // Null when the observation was not run, malformed, or the family has no oracle.
    pub baseline_cases: Option<SdlcCaseResults>,
    pub candidate_cases: Option<SdlcCaseResults>,
    // Null when no diff was retained; zeros mean an empty retained diff.
    pub diff: Option<SdlcDiffStats>,
    pub artifact_digest: Option<String>,
    pub validation_error: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SdlcReviewFinding {
    pub path: Option<String>,
    pub line: Option<u64>,
    pub problem: Option<String>,
    pub evidence: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SdlcReviewEvidence {
    pub role: Option<String>,
    pub status: Option<String>,
    pub rationale: Option<String>,
    // Null: the reviewer schema did not report findings. Empty: reported none.
    pub findings: Option<Vec<SdlcReviewFinding>>,
    pub findings_truncated: bool,
    pub missing_evidence: Option<String>,
}

// Each stage is null until Core retains it for the current revision round.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SdlcStageEvidence {
    // Latest lead decision retained in the mission event history.
    pub plan: Option<SdlcPlanEvidence>,
    pub testing: Option<SdlcTestingEvidence>,
    pub reviewing: Option<SdlcReviewEvidence>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SdlcMissionSummary {
    pub id: String,
    pub state: String,
    pub repository: Option<String>,
    // Pinned capability objective; null for legacy records without a contract.
    pub objective: Option<String>,
    // Stage of the latest retained event; null before the first event.
    pub current_stage: Option<String>,
    pub revision_count: u64,
    // Role to crew from the retained assignment plan; null when no plan was recorded.
    // A plan is not proof that the crew member is currently executing.
    pub assigned_crew: Option<BTreeMap<String, String>>,
    pub created_at: Option<f64>,
    pub updated_at: Option<f64>,
    pub latest_event: Option<SdlcEventSummary>,
    // Up to three most recent events, oldest first.
    pub recent_events: Vec<SdlcEventSummary>,
    pub event_count: usize,
    // Core testing verdict for the current round, when retained.
    pub verdict: Option<String>,
    pub publication: SdlcPublicationSummary,
    pub cancel_requested: bool,
    pub policy_generation: Option<u64>,
    pub retry_of: Option<String>,
    pub input: SdlcInputSummary,
    pub verifications: Vec<SdlcVerificationSummary>,
    pub stage_evidence: SdlcStageEvidence,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SdlcCoordinationSummary {
    pub admission: String,
    pub can_discover: bool,
    pub reserved_opportunities: Vec<String>,
    pub resolution: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SdlcPage {
    // Always `created_at_desc`: newest admitted mission first, id descending on ties.
    pub order: String,
    pub limit: usize,
    // Retained missions in Core, independent of this page.
    pub total: usize,
    pub returned: usize,
    // Pass as `before` to read the next older page; null on the last page.
    pub next_before: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct SdlcSnapshot {
    pub schema_version: u32,
    // `summary`; the full retained view is worker-only.
    pub view: String,
    pub enabled: bool,
    pub verification_enabled: bool,
    pub policy: SdlcPolicy,
    pub coordination: SdlcCoordinationSummary,
    pub capability_catalog: Value,
    pub discovery_count: usize,
    pub missions: Vec<SdlcMissionSummary>,
    pub page: SdlcPage,
}

fn text(v: &Value) -> Option<String> {
    v.as_str().map(|s| clip(s, FIELD_LIMIT))
}
fn clip(s: &str, limit: usize) -> String {
    if s.chars().count() <= limit {
        s.to_owned()
    } else {
        let mut out: String = s.chars().take(limit.saturating_sub(1)).collect();
        out.push('…');
        out
    }
}
fn long_text(v: &Value) -> Option<String> {
    v.as_str().map(|s| clip(s, TEXT_LIMIT))
}
fn humanize(stage: &str) -> String {
    stage.replace('_', " ")
}

pub(crate) fn event_summary(record: &Value) -> Option<SdlcEventSummary> {
    let event = &record["event"];
    let stage = event["stage"].as_str()?;
    let data = &event["data"];
    let role = text(&data["role"]);
    let status = data["status"]
        .as_str()
        .or_else(|| data["output"]["decision"].as_str())
        .or_else(|| data["output"]["status"].as_str())
        .or_else(|| data["verdict"].as_str())
        .or_else(|| data["outcome"].as_str());
    let mut label = humanize(stage);
    if let Some(role) = &role {
        label.push_str(" · ");
        label.push_str(role);
    }
    if let Some(status) = status {
        label.push_str(" · ");
        label.push_str(status);
    }
    Some(SdlcEventSummary {
        key: clip(record["key"].as_str().unwrap_or(""), 100),
        stage: stage.to_owned(),
        at: record["at"].as_f64(),
        label: clip(&label, LABEL_LIMIT),
        role,
    })
}

fn cases(run: &Value, family: &str) -> Option<SdlcCaseResults> {
    let expected = expected_cases(family)?;
    let cases = run["cases"].as_array()?;
    if run["not_executed"] == true || run["exit_code"].as_i64().is_none() {
        return None;
    }
    let mut out = SdlcCaseResults {
        passed: vec![],
        failed: vec![],
    };
    for case in cases.iter().take(100) {
        let id = clip(case["id"].as_str()?, 100);
        if expected.get(&id).is_some_and(|e| *e == case["actual"]) {
            out.passed.push(id);
        } else {
            out.failed.push(id);
        }
    }
    Some(out)
}

fn diff_stats(diff: &Value) -> Option<SdlcDiffStats> {
    let diff = diff.as_str()?;
    let mut stats = SdlcDiffStats {
        files: 0,
        additions: 0,
        deletions: 0,
    };
    for line in diff.lines() {
        if line.starts_with("+++ ") {
            stats.files += 1;
        } else if line.starts_with("--- ") {
        } else if line.starts_with('+') {
            stats.additions += 1;
        } else if line.starts_with('-') {
            stats.deletions += 1;
        }
    }
    Some(stats)
}

fn testing(data: &Value, family: &str) -> Option<SdlcTestingEvidence> {
    if !data.is_object() {
        return None;
    }
    let grading = &data["grading"];
    Some(SdlcTestingEvidence {
        verdict: text(&data["verdict"]),
        grading: grading.is_object().then(|| SdlcGradingSummary {
            verdict: text(&grading["verdict"]),
            baseline_pass: grading["baseline_pass"].as_bool(),
            candidate_pass: grading["candidate_pass"].as_bool(),
        }),
        baseline_cases: cases(&data["baseline"], family),
        candidate_cases: cases(&data["candidate"], family),
        diff: diff_stats(&data["diff"]),
        artifact_digest: text(&data["artifact_digest"]),
        validation_error: text(&data["validation_error"]),
    })
}

fn reviewing(data: &Value) -> Option<SdlcReviewEvidence> {
    if !data.is_object() {
        return None;
    }
    let findings = data["findings"].as_array();
    Some(SdlcReviewEvidence {
        role: text(&data["role"]),
        status: text(&data["status"]),
        rationale: long_text(&data["rationale"]),
        findings: findings.map(|items| {
            items
                .iter()
                .take(FINDING_LIMIT)
                .map(|f| SdlcReviewFinding {
                    path: text(&f["path"]),
                    line: f["line"].as_u64(),
                    problem: text(&f["problem"]),
                    evidence: text(&f["evidence"]),
                })
                .collect()
        }),
        findings_truncated: findings.is_some_and(|items| items.len() > FINDING_LIMIT),
        missing_evidence: long_text(&data["missing_evidence"]),
    })
}

fn plan(events: &[Value]) -> Option<SdlcPlanEvidence> {
    events.iter().rev().find_map(|record| {
        let data = &record["event"]["data"];
        let output = &data["output"];
        (data["role"] == "lead" && output["decision"].is_string()).then(|| SdlcPlanEvidence {
            role: text(&data["role"]),
            decision: text(&output["decision"]),
            rationale: long_text(&output["rationale"]),
            task: long_text(&output["task"]),
        })
    })
}

fn publication(v: &Value) -> SdlcPublicationSummary {
    let claim = &v["publication"];
    let submitted = &v["evidence"]["submitted"];
    let observed = &v["pr_observation"];
    let state = if claim.is_null() {
        "none"
    } else if v["state"] == "awaiting_review" {
        "awaiting_review"
    } else if submitted.is_object() {
        "submitted"
    } else {
        "claimed"
    };
    SdlcPublicationSummary {
        state: state.into(),
        branch: text(&claim["branch"]),
        pr_number: submitted["number"].as_u64(),
        pr_url: text(&submitted["url"]),
        pr_state: text(&observed["state"]),
        pr_observed_at: observed["observed_at"].as_f64(),
    }
}

fn verification(v: &Value) -> Option<SdlcVerificationSummary> {
    Some(SdlcVerificationSummary {
        id: v["id"].as_str()?.to_owned(),
        state: v["state"].as_str().unwrap_or("unknown").to_owned(),
        cancel_requested: v["cancel_requested"] == true,
        policy_generation: v["policy_generation"].as_u64(),
        updated_at: v["updated_at"].as_f64(),
        input: SdlcVerificationInputSummary {
            head: text(&v["input"]["head"]),
            build_digest: text(&v["input"]["build"]["digest"]),
            feedback_digest: text(&v["input"]["feedback_digest"]),
        },
        outcome: text(&v["evidence"]["verified"]["outcome"]),
    })
}

/// Project one retained mission body. Never fails: unknown fields become null.
pub fn summarize(v: &Value) -> SdlcMissionSummary {
    let input = &v["input"];
    let family = input["opportunity"].as_str().unwrap_or("");
    let events: &[Value] = v["events"].as_array().map_or(&[], Vec::as_slice);
    let summaries: Vec<SdlcEventSummary> = events.iter().filter_map(event_summary).collect();
    let recent = summaries[summaries.len().saturating_sub(RECENT_EVENT_LIMIT)..].to_vec();
    let assigned_crew = v["coordination"]["assignments"].as_array().map(|tasks| {
        tasks
            .iter()
            .filter_map(|t| Some((t["role"].as_str()?.into(), t["crew"].as_str()?.into())))
            .collect()
    });
    let id = v["id"]
        .as_str()
        .or_else(|| input["id"].as_str())
        .unwrap_or("")
        .to_owned();
    let testing_evidence = testing(&v["evidence"]["testing"], family);
    SdlcMissionSummary {
        state: v["state"].as_str().unwrap_or("unknown").into(),
        repository: text(&input["repository"]),
        objective: long_text(&v["capability"]["objective"]),
        current_stage: events
            .last()
            .and_then(|e| e["event"]["stage"].as_str())
            .map(String::from),
        revision_count: v["revision_loops"].as_u64().unwrap_or(0),
        assigned_crew,
        created_at: v["created_at"].as_f64(),
        updated_at: v["updated_at"].as_f64(),
        latest_event: summaries.last().cloned(),
        recent_events: recent,
        event_count: events.len(),
        verdict: testing_evidence.as_ref().and_then(|t| t.verdict.clone()),
        publication: publication(v),
        cancel_requested: v["cancel_requested"] == true,
        policy_generation: v["policy_generation"].as_u64(),
        retry_of: text(&v["retry_of"]),
        input: SdlcInputSummary {
            id: input["id"].as_str().unwrap_or(&id).to_owned(),
            repository: text(&input["repository"]),
            revision: text(&input["revision"]),
            opportunity: text(&input["opportunity"]),
            build_digest: text(&input["build"]["digest"]),
            capability_digest: text(&input["capability_digest"]),
        },
        verifications: v["verifications"]
            .as_array()
            .map_or(vec![], |a| a.iter().filter_map(verification).collect()),
        stage_evidence: SdlcStageEvidence {
            plan: plan(events),
            testing: testing_evidence,
            reviewing: reviewing(&v["evidence"]["reviewing"]),
        },
        id,
    }
}

fn order_key(v: &Value) -> (f64, String) {
    (
        v["created_at"].as_f64().unwrap_or(0.0),
        v["id"].as_str().unwrap_or("").to_owned(),
    )
}

impl Store {
    // Bounded polling view. `before` is the id of the last mission of the
    // previous page; an unknown cursor is rejected rather than silently restarted.
    pub fn sdlc_summary_snapshot(
        &self,
        limit: Option<usize>,
        before: Option<&str>,
    ) -> Result<SdlcSnapshot> {
        let limit = limit.unwrap_or(DEFAULT_MISSION_LIMIT);
        if !(1..=MAX_MISSION_LIMIT).contains(&limit) {
            return Err(format!("limit must be between 1 and {MAX_MISSION_LIMIT}"));
        }
        let mut records = self.sdlc_records()?;
        let policy_value = self.sdlc_policy()?;
        let coordination_value = coordination(&records, &policy_value, enabled());
        records.sort_by(|a, b| {
            let (a, b) = (order_key(a), order_key(b));
            b.0.total_cmp(&a.0).then_with(|| b.1.cmp(&a.1))
        });
        let total = records.len();
        let start = match before {
            None => 0,
            Some(cursor) => {
                records
                    .iter()
                    .position(|v| v["id"] == cursor)
                    .ok_or("Unknown mission cursor")?
                    + 1
            }
        };
        let page: Vec<SdlcMissionSummary> = records
            .iter()
            .skip(start)
            .take(limit)
            .map(summarize)
            .collect();
        let next_before = (start + page.len() < total)
            .then(|| page.last().map(|m| m.id.clone()))
            .flatten();
        Ok(SdlcSnapshot {
            schema_version: 7,
            view: "summary".into(),
            enabled: enabled(),
            verification_enabled: verification_enabled(),
            policy: serde_json::from_value(policy_value).map_err(|e| e.to_string())?,
            coordination: serde_json::from_value(coordination_value).map_err(|e| e.to_string())?,
            capability_catalog: capabilities(),
            discovery_count: self.sdlc_discoveries()?.len(),
            page: SdlcPage {
                order: "created_at_desc".into(),
                limit,
                total,
                returned: page.len(),
                next_before,
            },
            missions: page,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        now,
        sdlc::{SdlcEvent, SdlcInput, SdlcPolicy},
    };
    use serde_json::json;

    fn store(max_missions: u32) -> Store {
        let s = Store::open(":memory:").unwrap();
        s.sdlc_set_policy_at(
            &SdlcPolicy {
                repository: "X-McKay/algent".into(),
                enabled: true,
                publish: true,
                generation: 0,
                max_missions,
                expires_at: now() + 3600.0,
            },
            true,
        )
        .unwrap();
        s
    }
    fn input(id: &str, revision: char) -> SdlcInput {
        SdlcInput {
            id: id.into(),
            repository: "X-McKay/algent".into(),
            revision: revision.to_string().repeat(40),
            opportunity: "persistence-history".into(),
            build: json!({"digest":"b".repeat(64)}),
            capability_digest: None,
        }
    }
    fn event(s: &Store, id: &str, key: &str, stage: &str, data: Value) -> Value {
        s.sdlc_event(
            id,
            &SdlcEvent {
                key: key.into(),
                stage: stage.into(),
                data,
            },
        )
        .unwrap()
    }
    fn results() -> Value {
        let expected = expected_cases("persistence-history").unwrap();
        let cases: Vec<_> = expected
            .as_object()
            .unwrap()
            .iter()
            .map(|(id, actual)| json!({"id":id,"actual":actual}))
            .collect();
        let mut baseline = cases.clone();
        baseline[0]["actual"] = json!([]);
        json!({"baseline":{"exit_code":0,"cases":baseline},"candidate":{"exit_code":0,"cases":cases},
            "artifact_digest":"c".repeat(64),"verdict":"model says success",
            "diff":"--- a/x.py\n+++ b/x.py\n@@ -1,2 +1,2 @@\n-old\n+new\n+extra\n context\n",
            "sources":{"x.py":"x".repeat(100_000)}})
    }

    #[test]
    fn summary_shape_carries_typed_stage_evidence_without_bulky_fields() {
        let s = store(3);
        s.sdlc_admit_at(&input("m1", 'a'), true).unwrap();
        event(
            &s,
            "m1",
            "baseline",
            "investigating",
            json!({"sources":{"x.py":"y".repeat(100_000)}}),
        );
        event(
            &s,
            "m1",
            "lead-handoff",
            "implementing",
            json!({"role":"lead","output":{"decision":"implement","rationale":"r".repeat(5000),"task":"Fix history"}}),
        );
        event(&s, "m1", "testing-1", "testing", results());
        event(
            &s,
            "m1",
            "review-1",
            "reviewing",
            json!({"role":"reviewer","status":"accept","rationale":"Looks right",
                "findings":[{"path":"x.py","line":3,"problem":"p","evidence":"e"}],"missing_evidence":null}),
        );
        // Reproduction: the retained full view (the former public /v7/snapshot body)
        // carries every source and event payload.
        assert!(s.sdlc_snapshot().unwrap().to_string().len() > 300_000);
        let snap = s.sdlc_summary_snapshot(None, None).unwrap();
        let encoded = serde_json::to_string(&snap).unwrap();
        assert!(
            encoded.len() < 16_000,
            "summary stays bounded: {}",
            encoded.len()
        );
        assert!(!encoded.contains("yyyy") && !encoded.contains("xxxx"));
        let m = &snap.missions[0];
        assert_eq!(m.id, "m1");
        assert_eq!(m.state, "reviewing");
        assert_eq!(m.current_stage.as_deref(), Some("reviewing"));
        assert_eq!(m.repository.as_deref(), Some("X-McKay/algent"));
        assert!(m.objective.is_some());
        assert_eq!(m.event_count, 4);
        assert_eq!(m.recent_events.len(), 3);
        let latest = m.latest_event.as_ref().unwrap();
        assert_eq!(latest.stage, "reviewing");
        assert_eq!(latest.label, "reviewing · reviewer · accept");
        assert!(latest.at.is_some());
        assert_eq!(
            m.verdict.as_deref(),
            Some("improved"),
            "Core verdict, not model claim"
        );
        let crew = m.assigned_crew.as_ref().unwrap();
        assert!(crew.contains_key("lead") && crew.contains_key("implementer"));
        assert_eq!(m.publication.state, "none");
        let plan = m.stage_evidence.plan.as_ref().unwrap();
        assert_eq!(plan.decision.as_deref(), Some("implement"));
        assert!(plan.rationale.as_ref().unwrap().chars().count() <= TEXT_LIMIT);
        let testing = m.stage_evidence.testing.as_ref().unwrap();
        let baseline = testing.baseline_cases.as_ref().unwrap();
        assert_eq!(baseline.failed, vec!["history_all".to_owned()]);
        assert_eq!(baseline.passed.len(), 6);
        assert!(testing.candidate_cases.as_ref().unwrap().failed.is_empty());
        assert_eq!(
            testing.diff,
            Some(SdlcDiffStats {
                files: 1,
                additions: 2,
                deletions: 1
            })
        );
        assert_eq!(testing.grading.as_ref().unwrap().candidate_pass, Some(true));
        let review = m.stage_evidence.reviewing.as_ref().unwrap();
        assert_eq!(review.status.as_deref(), Some("accept"));
        assert_eq!(review.findings.as_ref().unwrap()[0].line, Some(3));
        assert_eq!(review.missing_evidence, None);
        // The generated JSON keeps keys the native client already reads.
        let raw = serde_json::to_value(&snap).unwrap();
        assert_eq!(raw["schema_version"], 7);
        assert!(raw["policy"]["enabled"].as_bool().unwrap());
        assert_eq!(raw["missions"][0]["input"]["repository"], "X-McKay/algent");
        assert!(raw["missions"][0]["verifications"].is_array());
    }

    #[test]
    fn unknown_and_missing_evidence_stays_distinct_from_empty() {
        let s = store(3);
        s.sdlc_admit_at(&input("m1", 'a'), true).unwrap();
        let fresh = &s.sdlc_summary_snapshot(None, None).unwrap().missions[0];
        assert_eq!(fresh.current_stage, None);
        assert_eq!(fresh.latest_event, None);
        assert_eq!(fresh.verdict, None);
        assert_eq!(
            fresh.stage_evidence,
            SdlcStageEvidence {
                plan: None,
                testing: None,
                reviewing: None
            }
        );
        event(&s, "m1", "baseline", "investigating", json!({}));
        event(&s, "m1", "handoff", "implementing", json!({}));
        let mut data = results();
        data["candidate"] = json!({"exit_code":null,"cases":[],"not_executed":true});
        data["baseline"]["cases"] = json!([]);
        data["diff"] = json!("");
        event(&s, "m1", "testing-1", "testing", data);
        event(
            &s,
            "m1",
            "review-1",
            "reviewing",
            json!({"role":"reviewer","status":"abstain","rationale":"no evidence","findings":[]}),
        );
        let m = &s.sdlc_summary_snapshot(None, None).unwrap().missions[0];
        let testing = m.stage_evidence.testing.as_ref().unwrap();
        assert_eq!(testing.candidate_cases, None, "not executed is unknown");
        assert_eq!(
            testing.baseline_cases,
            Some(SdlcCaseResults {
                passed: vec![],
                failed: vec![]
            }),
            "an executed empty case list is empty, not unknown"
        );
        assert_eq!(
            testing.diff,
            Some(SdlcDiffStats {
                files: 0,
                additions: 0,
                deletions: 0
            })
        );
        assert_eq!(testing.grading.as_ref().unwrap().candidate_pass, None);
        assert_eq!(m.stage_evidence.plan, None, "no lead decision retained");
        let review = m.stage_evidence.reviewing.as_ref().unwrap();
        assert_eq!(review.findings, Some(vec![]));
        let mut legacy = s.sdlc_mission("m1").unwrap();
        legacy["evidence"]["reviewing"]
            .as_object_mut()
            .unwrap()
            .remove("findings");
        legacy.as_object_mut().unwrap().remove("coordination");
        legacy.as_object_mut().unwrap().remove("capability");
        let projected = summarize(&legacy);
        assert_eq!(projected.stage_evidence.reviewing.unwrap().findings, None);
        assert_eq!(projected.assigned_crew, None);
        assert_eq!(projected.objective, None);
        let garbage = summarize(&json!({"id":"odd","events":"not-a-list","evidence":[]}));
        assert_eq!(garbage.state, "unknown");
        assert_eq!(garbage.event_count, 0);
        assert_eq!(garbage.created_at, None);
    }

    #[test]
    fn snapshot_is_bounded_newest_first_and_pages_with_before() {
        let s = store(3);
        for (n, id) in ["m-a", "m-b", "m-c"].iter().enumerate() {
            s.sdlc_admit_at(&input(id, ['a', 'b', 'c'][n]), true)
                .unwrap();
            event(&s, id, "stop", "blocked", json!({}));
        }
        let first = s.sdlc_summary_snapshot(Some(2), None).unwrap();
        let ids: Vec<_> = first.missions.iter().map(|m| m.id.as_str()).collect();
        assert_eq!(ids, ["m-c", "m-b"]);
        assert_eq!(first.page.total, 3);
        assert_eq!(first.page.returned, 2);
        assert_eq!(first.page.next_before.as_deref(), Some("m-b"));
        let second = s.sdlc_summary_snapshot(Some(2), Some("m-b")).unwrap();
        assert_eq!(second.missions.len(), 1);
        assert_eq!(second.missions[0].id, "m-a");
        assert_eq!(second.page.next_before, None);
        // Ordering follows immutable admission time, not later activity.
        let mut oldest = s.sdlc_mission("m-a").unwrap();
        oldest["updated_at"] = json!(now() + 60.0);
        s.sdlc_save(&oldest).unwrap();
        let again = s.sdlc_summary_snapshot(None, None).unwrap();
        assert_eq!(again.missions[0].id, "m-c");
        assert_eq!(again.page.limit, DEFAULT_MISSION_LIMIT);
        assert!(s.sdlc_summary_snapshot(Some(0), None).is_err());
        assert!(s.sdlc_summary_snapshot(Some(101), None).is_err());
        assert!(s.sdlc_summary_snapshot(None, Some("missing")).is_err());
        assert_eq!(
            json!(again.coordination.admission),
            s.sdlc_snapshot().unwrap()["coordination"]["admission"]
        );
    }
}
