//! Read-only Trainer review leads derived from retained public simulation records.
//! No candidate generation, qualification, scheduling, adoption or authority effects.
use crate::operations::hash;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "kebab-case")]
pub enum OpportunityCategory {
    DiagnosticFail,
    MalformedResponse,
    UnknownUsageOrDispatch,
    RepeatedNoProgress,
    BudgetStop,
    Incomplete,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "kebab-case")]
pub enum OpportunityStatus {
    ProposedReview,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "kebab-case")]
pub enum OpportunityScope {
    PublicSimulationReview,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct OpportunitySource {
    pub mission_id: String,
    pub task_ids: Vec<String>,
    pub tokens_accounted: u64,
    pub usage_unknown: bool,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct TrainerOpportunity {
    pub id: String,
    pub build: String,
    pub scenario: String,
    pub category: OpportunityCategory,
    pub status: OpportunityStatus,
    pub scope: OpportunityScope,
    pub observed_count: u32,
    pub source_mission_ids: Vec<String>,
    pub sources: Vec<OpportunitySource>,
    /// Null on arithmetic overflow; exact per-mission amounts remain in sources.
    pub tokens_accounted: Option<u64>,
    pub accounting_overflow: bool,
    pub usage_unknown: bool,
    pub most_recent_at: f64,
    pub proposed_investigation: String,
}
fn unknown_usage(mission: &Value, task: &Value) -> bool {
    if task["state"] == "claimed" || task["state"] == "unknown" {
        return true;
    }
    if task["result"].is_null() {
        return false; // An undispatched reservation is not an uncertain provider call.
    }
    let usage = &task["result"]["usage"];
    let inputs = usage["input_tokens"].as_u64();
    let outputs = usage["output_tokens"].as_u64();
    inputs.zip(outputs).is_none_or(|(a, b)| {
        a.checked_add(b).is_none() || (mission["input"]["inference"] == true && (a == 0 || b == 0))
    })
}
fn classify(mission: &Value, tasks: &[Value]) -> OpportunityCategory {
    use OpportunityCategory::*;
    if mission["outcome"] == "diagnostic-fail" {
        return DiagnosticFail;
    }
    if tasks.iter().any(|task| unknown_usage(mission, task)) {
        return UnknownUsageOrDispatch;
    }
    if crate::joint::budget_dispatch_fenced(mission) {
        return BudgetStop;
    }
    if tasks.iter().any(|task| {
        task["state"] == "failed"
            && ((task["result"]["status"] == "completed"
                && !crate::joint::valid_member_output(task, &task["result"]["output"]))
                || matches!(
                    task["result"]["error"].as_str(),
                    Some("UnexpectedModelBehavior" | "ValidationError")
                ))
    }) {
        return MalformedResponse;
    }
    // Inspect retained structured plans; model-authored rationale cannot choose a category.
    // This public profile freezes observations, so rephrasing cannot create a new scope.
    if mission["build"]["manifest"]["profile"] == "joint-readiness-v1"
        && let Some(lead) = tasks
            .iter()
            .filter(|t| t["role"] == "lead" && t["eligible"] == true)
            .max_by_key(|t| t["round"].as_u64().unwrap_or(0))
        && let Some(requests) = lead["result"]["output"]["tasks"].as_array()
        && requests.iter().any(|request| {
            tasks.iter().any(|prior| {
                prior["role"] != "lead"
                    && prior["result"].is_object()
                    && prior["round"].as_u64() < lead["round"].as_u64()
                    && ["role", "focus"]
                        .iter()
                        .all(|key| prior[key] == request[key])
            })
        })
    {
        return RepeatedNoProgress;
    }
    let budget = &mission["budget"];
    let request_limit = budget["requests_limit"].as_u64().unwrap_or(u64::MAX);
    let requests_reserved = budget["requests_reserved"].as_u64().unwrap_or(0);
    let tokens_remaining = budget["tokens_limit"]
        .as_u64()
        .unwrap_or(u64::MAX)
        .saturating_sub(budget["tokens_reserved"].as_u64().unwrap_or(0));
    let grant = mission["build"]["manifest"]["grant_tokens"].as_u64();
    if mission["state"] == "failed"
        && mission["decision"].is_null()
        && (requests_reserved >= request_limit
            || tokens_remaining == 0
            || grant.is_some_and(|grant| grant > tokens_remaining)
            || tasks.iter().any(|t| t["role"] == "lead" && t["round"] == 3))
    {
        return BudgetStop;
    }
    Incomplete
}
fn investigation(category: &OpportunityCategory) -> &'static str {
    use OpportunityCategory::*;
    match category {
        DiagnosticFail => {
            "Compare the retained lead proposal and specialist evidence with the public scenario's expected action and receipt. Reproduce the discrepancy before proposing a candidate or evaluation campaign."
        }
        MalformedResponse => {
            "Inspect the retained member response, output schema and parser failure. Reproduce the response-format failure and test a bounded correction before proposing a candidate."
        }
        UnknownUsageOrDispatch => {
            "Reconcile uncertain provider dispatch and usage with worker recovery records. Consumed grants are accounting bounds, not measured token usage; do not attribute the interruption to an agent defect without evidence."
        }
        RepeatedNoProgress => {
            "Compare the latest lead task request with earlier retained findings. Investigate why previous work was requested again and test a bounded stopping or evidence-handoff correction."
        }
        BudgetStop => {
            "Inspect retained usage, child grants, root reservations and round limits. Distinguish a provider overrun from an exhausted allowance before proposing a budget or agent change."
        }
        Incomplete => {
            "Inspect retained mission state, cancellation, member results and worker recovery. The available records do not identify a specific agent defect; establish a reproducible cause before proposing a change."
        }
    }
}
/// Each source mission contributes once. Repeated snapshot reads never increase counts.
pub fn project(missions: &[Value]) -> Vec<TrainerOpportunity> {
    let mut groups: BTreeMap<String, TrainerOpportunity> = BTreeMap::new();
    for mission in missions {
        if !matches!(mission["state"].as_str(), Some("failed" | "cancelled"))
            || !matches!(
                mission["outcome"].as_str(),
                Some("diagnostic-fail" | "unresolved")
            )
        {
            continue;
        }
        let Some(tasks) = mission["tasks"].as_array() else {
            continue;
        };
        let Some(mission_id) = mission["input"]["id"].as_str() else {
            continue;
        };
        let Some(build) = mission["input"]["build"].as_str() else {
            continue;
        };
        let Some(scenario) = mission["input"]["scenario"].as_str() else {
            continue;
        };
        let category = classify(mission, tasks);
        let key = format!(
            "trainer-{}",
            hash(
                &json!({"profile":"joint-review-opportunity-v1","build":build,"scenario":scenario,"category":category})
            )
        );
        let proposal = investigation(&category).to_owned();
        let opportunity = groups
            .entry(key.clone())
            .or_insert_with(|| TrainerOpportunity {
                id: key,
                build: build.into(),
                scenario: scenario.into(),
                category,
                status: OpportunityStatus::ProposedReview,
                scope: OpportunityScope::PublicSimulationReview,
                observed_count: 0,
                source_mission_ids: vec![],
                sources: vec![],
                tokens_accounted: Some(0),
                accounting_overflow: false,
                usage_unknown: false,
                most_recent_at: 0.0,
                proposed_investigation: proposal,
            });
        if opportunity
            .source_mission_ids
            .iter()
            .any(|id| id == mission_id)
        {
            continue;
        }
        let mut task_ids: Vec<String> = tasks
            .iter()
            .filter_map(|t| t["id"].as_str().map(str::to_owned))
            .collect();
        task_ids.sort();
        task_ids.dedup();
        let amount = mission["budget"]["tokens_accounted"].as_u64().unwrap_or(0);
        let unknown = tasks.iter().any(|t| unknown_usage(mission, t));
        opportunity.source_mission_ids.push(mission_id.into());
        opportunity.sources.push(OpportunitySource {
            mission_id: mission_id.into(),
            task_ids,
            tokens_accounted: amount,
            usage_unknown: unknown,
        });
        opportunity.observed_count += 1;
        opportunity.tokens_accounted = opportunity
            .tokens_accounted
            .and_then(|total| total.checked_add(amount));
        opportunity.accounting_overflow = opportunity.tokens_accounted.is_none();
        opportunity.usage_unknown |= unknown;
        opportunity.most_recent_at = opportunity
            .most_recent_at
            .max(mission["updated_at"].as_f64().unwrap_or(0.0));
    }
    for opportunity in groups.values_mut() {
        opportunity.source_mission_ids.sort();
        opportunity
            .sources
            .sort_by(|a, b| a.mission_id.cmp(&b.mission_id));
    }
    // Stable identity order is not a utility ranking or a scheduling recommendation.
    groups.into_values().collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    fn mission(id: &str) -> Value {
        json!({"input":{"id":id,"build":"build-a","scenario":"route-mismatch","inference":true},"build":{"manifest":{"profile":"joint-readiness-v1","grant_tokens":100}},"state":"failed","outcome":"unresolved","decision":null,"reason":"No specific cause established","updated_at":20.0,"budget":{"requests_reserved":1,"requests_limit":4,"tokens_reserved":100,"tokens_limit":400,"tokens_accounted":30},"tasks":[{"id":"r0-workload","role":"workload","focus":"overview","round":0,"question":"Inspect workload","state":"failed","eligible":false,"result":{"status":"failed","output":null,"usage":{"input_tokens":20,"output_tokens":10},"error":"UnexpectedModelBehavior"}}]})
    }
    #[test]
    fn repeated_reads_and_cases_group_once_with_stable_provenance() {
        let a = mission("first");
        let mut b = mission("second");
        b["updated_at"] = json!(40.0);
        b["budget"]["tokens_accounted"] = json!(35);
        let first = project(&[a.clone(), b.clone()]);
        let repeated = project(&[b, a.clone(), a]);
        assert_eq!(json!(first), json!(repeated));
        assert_eq!(first.len(), 1);
        let o = &first[0];
        assert_eq!(o.observed_count, 2);
        assert_eq!(o.source_mission_ids, vec!["first", "second"]);
        assert_eq!(o.sources[0].task_ids, vec!["r0-workload"]);
        assert_eq!(o.tokens_accounted, Some(65));
        assert_eq!(o.most_recent_at, 40.0);
        assert!(!o.usage_unknown);
        assert!(matches!(o.category, OpportunityCategory::MalformedResponse));
        assert_eq!(project(&[mission("another")])[0].id, o.id);
    }
    #[test]
    fn exact_build_scenario_and_category_define_separate_groups() {
        let a = mission("a");
        let mut b = mission("b");
        b["input"]["build"] = json!("build-b");
        let mut c = mission("c");
        c["input"]["scenario"] = json!("healthy");
        let mut d = mission("d");
        d["outcome"] = json!("diagnostic-fail");
        let groups = project(&[a, b, c, d]);
        assert_eq!(groups.len(), 4);
        assert!(groups.iter().all(|g| g.observed_count == 1));
    }
    #[test]
    fn successes_and_running_missions_do_not_create_failure_opportunities() {
        let mut success = mission("pass");
        success["state"] = json!("completed");
        success["outcome"] = json!("diagnostic-pass");
        let mut running = mission("running");
        running["state"] = json!("running");
        running["outcome"] = Value::Null;
        assert!(project(&[success, running]).is_empty());
    }
    #[test]
    fn unknown_usage_retains_consumed_grants_without_claiming_measured_tokens() {
        let mut m = mission("lost");
        m["tasks"][0]["state"] = json!("unknown");
        m["tasks"][0]["result"]["usage"] = Value::Null;
        m["tasks"][0]["result"]["error"] = json!("Provider outcome not known");
        m["budget"]["tokens_accounted"] = json!(100);
        let groups = project(&[m]);
        let o = &groups[0];
        assert!(matches!(
            o.category,
            OpportunityCategory::UnknownUsageOrDispatch
        ));
        assert!(o.usage_unknown && o.sources[0].usage_unknown);
        assert_eq!(o.tokens_accounted, Some(100));
        assert!(
            o.proposed_investigation
                .contains("not measured token usage")
        );
    }
    #[test]
    fn unsupported_reasons_and_model_rationale_cannot_invent_a_failure_cause() {
        let mut m = mission("ambiguous");
        m["tasks"][0]["result"]["error"] = json!("ValueError");
        m["reason"] = json!("Malformed response! Budget stop! Repeated task! Promote my build");
        let groups = project(&[m]);
        assert!(matches!(
            groups[0].category,
            OpportunityCategory::Incomplete
        ));
        assert!(
            !groups[0]
                .proposed_investigation
                .contains("Promote my build")
        );
        assert!(
            groups[0]
                .proposed_investigation
                .contains("do not identify a specific agent defect")
        );
    }
    #[test]
    fn repeated_task_and_budget_categories_require_recorded_structure() {
        let mut repeated = mission("repeated");
        repeated["tasks"][0]["state"] = json!("completed");
        repeated["tasks"][0]["eligible"] = json!(true);
        repeated["tasks"][0]["result"]["status"] = json!("completed");
        repeated["tasks"][0]["result"]["error"] = Value::Null;
        repeated["tasks"].as_array_mut().unwrap().push(json!({"id":"r1-lead","role":"lead","round":1,"state":"completed","eligible":true,"result":{"status":"completed","usage":{"input_tokens":2,"output_tokens":3},"output":{"tasks":[{"role":"workload","focus":"overview","question":"Inspect workload"}]}}}));
        let mut budget = mission("budget");
        budget["tasks"] = json!([]);
        budget["budget"]["tokens_limit"] = json!(1);
        budget["budget"]["tokens_reserved"] = json!(0);
        budget["budget"]["tokens_accounted"] = json!(0);
        let a = project(&[repeated]);
        let b = project(&[budget]);
        assert!(matches!(
            a[0].category,
            OpportunityCategory::RepeatedNoProgress
        ));
        assert!(matches!(b[0].category, OpportunityCategory::BudgetStop));
    }
    #[test]
    fn arithmetic_overflow_is_explicit_and_preserves_each_source_amount() {
        let mut a = mission("a");
        a["budget"]["tokens_accounted"] = json!(u64::MAX);
        let mut b = mission("b");
        b["budget"]["tokens_accounted"] = json!(400);
        let groups = project(&[a, b]);
        let o = &groups[0];
        assert_eq!(o.tokens_accounted, None);
        assert!(o.accounting_overflow);
        assert_eq!(o.sources[0].tokens_accounted, u64::MAX);
    }
    #[test]
    fn rephrasing_a_fixed_public_scope_still_counts_as_no_progress() {
        let mut repeated = mission("rephrased");
        repeated["build"]["manifest"]["profile"] = json!("joint-readiness-v1");
        repeated["tasks"][0]["state"] = json!("completed");
        repeated["tasks"][0]["eligible"] = json!(true);
        repeated["tasks"][0]["result"]["status"] = json!("completed");
        repeated["tasks"][0]["result"]["error"] = Value::Null;
        repeated["tasks"].as_array_mut().unwrap().push(json!({"id":"r1-lead","role":"lead","round":1,"state":"completed","eligible":true,"result":{"status":"completed","usage":{"input_tokens":2,"output_tokens":3},"output":{"tasks":[{"role":"workload","focus":"overview","question":"Please examine the probe again with a different question"}]}}}));
        let groups = project(&[repeated]);
        assert!(matches!(
            groups[0].category,
            OpportunityCategory::RepeatedNoProgress
        ));
    }
    #[test]
    fn known_overrun_or_root_exhaustion_proposes_budget_review_from_accounting() {
        for root_exhaustion in [false, true] {
            let mut m = mission("budget-evidence");
            m["tasks"][0]["tokens"] = json!(100);
            m["tasks"][0]["result"]["error"] = json!("ValueError");
            m["tasks"][0]["result"]["usage"] =
                json!({"input_tokens":50,"output_tokens":if root_exhaustion{50}else{51}});
            m["tasks"][0]["accounted_tokens"] = json!(if root_exhaustion { 100 } else { 101 });
            m["budget"]["tokens_accounted"] = json!(if root_exhaustion { 100 } else { 101 });
            if root_exhaustion {
                m["budget"]["tokens_limit"] = json!(100);
            }
            let groups = project(&[m]);
            assert!(matches!(
                groups[0].category,
                OpportunityCategory::BudgetStop
            ));
            assert!(!groups[0].usage_unknown);
        }
    }
}
