//! Local developmental learning. Core alone binds evidence, budgets and practice adoption.
use crate::{
    Result, Store,
    joint::{JointBudget, JointBuild, JointInput, Scenario, TaskStatus, Usage},
    now,
    operations::hash,
    parameters as params, terminal,
};
use rusqlite::OptionalExtension;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
fn error(e: rusqlite::Error) -> String {
    e.to_string()
}
fn max_cycles() -> u32 {
    2
}
fn cooldown() -> u32 {
    60
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct LearningBudget {
    pub proposal_requests: u32,
    pub proposal_tokens: u64,
    pub trial_requests: u32,
    pub trial_tokens: u64,
}
impl Default for LearningBudget {
    fn default() -> Self {
        Self {
            proposal_requests: 1,
            proposal_tokens: 32768,
            trial_requests: 24,
            trial_tokens: 384000,
        }
    }
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct LearningDuty {
    pub id: String,
    pub generation: u32,
    #[serde(default)]
    pub enabled: bool,
    pub baseline: String,
    #[serde(default = "max_cycles")]
    pub max_cycles: u32,
    #[serde(default = "cooldown")]
    pub cooldown_seconds: u32,
    #[serde(default)]
    pub budget: LearningBudget,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ProcedureResult {
    pub status: TaskStatus,
    pub procedure: Option<String>,
    pub rationale: String,
    pub usage: Option<Usage>,
    pub error: Option<String>,
    #[serde(default)]
    pub trace: Option<Value>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct PracticeIncumbent {
    pub build: String,
    pub generation: u64,
    pub source_cycle: Option<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct PracticeRebase {
    pub previous_build: String,
    pub build: String,
    pub duty_generation: u32,
    pub incumbent_generation: u64,
    pub at: f64,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct LearningControl {
    pub duty: LearningDuty,
    pub practice_incumbent: PracticeIncumbent,
    pub admitted_cycles: u32,
    pub last_started_at: Option<f64>,
    #[serde(default)]
    pub rebases: Vec<PracticeRebase>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct LearningTrial {
    pub slot: String,
    pub pair: u32,
    pub arm: String,
    pub scenario: Scenario,
    pub mission_id: String,
    pub requests: u32,
    pub tokens: u64,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct LearningGrant {
    pub requests: u32,
    pub tokens: u64,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct LearningProposal {
    pub state: String,
    pub grant: LearningGrant,
    pub result: Option<ProcedureResult>,
    pub accounted_tokens: u64,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct LearningCycle {
    pub id: String,
    pub dedup_key: String,
    pub duty_generation: u32,
    pub source_opportunity: Value,
    pub source_build: JointBuild,
    pub evidence_digest: String,
    pub source_missions: Vec<Value>,
    pub baseline: JointBuild,
    pub baseline_generation: u64,
    pub candidate: Option<JointBuild>,
    pub state: String,
    pub deadline: f64,
    pub budget: Value,
    pub proposal: LearningProposal,
    pub trials: Vec<LearningTrial>,
    pub trial_order: Vec<String>,
    pub policy: Value,
    pub summary: Option<Value>,
    pub created_at: f64,
    pub updated_at: f64,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct LearningSnapshot {
    pub schema_version: u32,
    pub enabled: bool,
    pub control: Option<LearningControl>,
    pub cycles: Vec<LearningCycle>,
    pub policy: Value,
}
#[derive(JsonSchema)]
#[allow(dead_code)]
pub struct LearningContract {
    pub duty: LearningDuty,
    pub proposal_result: ProcedureResult,
    pub cycle: LearningCycle,
    pub snapshot: LearningSnapshot,
}
pub fn enabled() -> bool {
    crate::joint::enabled() && std::env::var("STARBASE_LEARNING_ENABLED").as_deref() == Ok("true")
}
pub fn policy() -> Value {
    json!({"id":"public-practice-adoption-v1","grader_digest":hash(&json!({"joint":include_str!("joint.rs"),"learning":include_str!("learning.rs"),"opportunities":include_str!("joint_opportunities.rs")})),"scope":"local-public-simulation","suite":"readiness-public-four-v1","rule":"Eight complete paired public trials; candidate passes every case, improves pass count, no paired regression, no hard or unknown gates, budgets respected; compare-and-swap simulation practice pointer only","conclusion":"exploratory-development","trial_rule":"Known bounded model protocol/diagnostic/no-progress failures count as failed trials. Unknown usage, infrastructure, cancellation, identity mismatch and overruns invalidate adoption.","held_out":false,"qualification":false,"xp":0,"production_authority":false})
}
fn comparison_trial(m: &Value) -> Value {
    let invalid = |reason: &str| json!({"status":"invalid","reason":reason});
    if !terminal(m["state"].as_str().unwrap_or("")) || m["state"] == "cancelled" {
        return invalid("cancelled-or-active");
    }
    if crate::joint::budget_overrun(m) {
        return invalid("usage-overrun");
    }
    let Some(tasks) = m["tasks"].as_array() else {
        return invalid("missing-task-ledger");
    };
    let mut model_failure = false;
    for task in tasks {
        if task["state"] == "reserved" {
            continue;
        }
        if task["state"] == "claimed" || task["state"] == "unknown" || task["result"].is_null() {
            return invalid("unknown-dispatch");
        }
        let result = &task["result"];
        let usage = &result["usage"];
        if result["status"] == "unknown"
            || usage["input_tokens"]
                .as_u64()
                .zip(usage["output_tokens"].as_u64())
                .is_none_or(|(a, b)| {
                    a.checked_add(b).is_none()
                        || (m["input"]["inference"] == true && (a == 0 || b == 0))
                })
        {
            return invalid("unknown-usage");
        }
        if task["state"] == "failed" {
            if matches!(
                result["error"].as_str(),
                Some("UnexpectedModelBehavior" | "ValidationError" | "ValueError")
            ) || (result["status"] == "completed"
                && result["error"].is_null()
                && !crate::joint::valid_member_output(task, &result["output"]))
            {
                model_failure = true;
            } else {
                return invalid("infrastructure-or-unclassified-failure");
            }
        }
    }
    if m["outcome"] == "diagnostic-pass" {
        return json!({"status":"pass","reason":"core-diagnostic-pass"});
    }
    if m["outcome"] == "diagnostic-fail" {
        return json!({"status":"fail","reason":"core-diagnostic-fail"});
    }
    if model_failure {
        return json!({"status":"fail","reason":"known-model-protocol-failure"});
    }
    let latest = tasks
        .iter()
        .filter(|t| t["role"] == "lead" && t["state"] == "completed")
        .max_by_key(|t| t["round"].as_u64().unwrap_or(0));
    if latest.is_none_or(|t| t["result"]["output"]["decision"].is_null()) {
        let opportunities = crate::joint_opportunities::project(std::slice::from_ref(m));
        if opportunities.first().is_some_and(|o| {
            matches!(
                o.category,
                crate::joint_opportunities::OpportunityCategory::RepeatedNoProgress
                    | crate::joint_opportunities::OpportunityCategory::BudgetStop
            )
        }) {
            return json!({"status":"fail","reason":"known-no-progress-or-allowance-stop"});
        }
    }
    invalid("incomplete-without-established-model-cause")
}
impl Store {
    pub fn learning_control(&self) -> Result<Option<Value>> {
        let body: Option<String> = self
            .db
            .query_row(
                "SELECT body FROM learning_control WHERE id='readiness-practice'",
                params![],
                |r| r.get(0),
            )
            .optional()
            .map_err(error)?;
        body.map(|s| serde_json::from_str(&s).map_err(|e| e.to_string()))
            .transpose()
    }
    pub fn learning_cycle(&self, id: &str) -> Result<Value> {
        let body: String = self
            .db
            .query_row(
                "SELECT body FROM learning_cycles WHERE id=$1",
                params![id],
                |r| r.get(0),
            )
            .map_err(error)?;
        serde_json::from_str(&body).map_err(|e| e.to_string())
    }
    fn learning_cycles(&self) -> Result<Vec<Value>> {
        self.db
            .prepare("SELECT body FROM learning_cycles ORDER BY at DESC LIMIT 100")
            .map_err(error)?
            .query_map(params![], |r| r.get::<_, String>(0))
            .map_err(error)?
            .map(|r| serde_json::from_str(&r.map_err(error)?).map_err(|e| e.to_string()))
            .collect()
    }
    pub fn learning_snapshot(&self) -> Result<Value> {
        Ok(
            json!({"schema_version":6,"enabled":enabled(),"control":self.learning_control()?,"cycles":self.learning_cycles()?,"policy":policy()}),
        )
    }
    fn learning_build(&self, digest: &str) -> Result<Value> {
        let body: String = self
            .db
            .query_row(
                "SELECT body FROM joint_builds WHERE digest=$1",
                params![digest],
                |r| r.get(0),
            )
            .map_err(error)?;
        serde_json::from_str(&body).map_err(|e| e.to_string())
    }
    pub fn set_learning_duty(&self, d: &LearningDuty) -> Result<Value> {
        self.set_learning_duty_at(d, enabled())
    }
    fn set_learning_duty_at(&self, d: &LearningDuty, admitted: bool) -> Result<Value> {
        if d.id != "readiness-practice"
            || !(1..=10).contains(&d.max_cycles)
            || !(60..=86400).contains(&d.cooldown_seconds)
            || d.budget.proposal_requests != 1
            || !(1..=128000).contains(&d.budget.proposal_tokens)
            || !(1..=24).contains(&d.budget.trial_requests)
            || !(1..=384000).contains(&d.budget.trial_tokens)
        {
            return Err("Invalid bounded learning duty".into());
        }
        if d.enabled && !admitted {
            return Err("Local learning disabled".into());
        }
        let build = self.learning_build(&d.baseline)?;
        if build["manifest"]["profile"] != "joint-readiness-v1" {
            return Err("Joint readiness baseline required".into());
        }
        let old = self.learning_control()?;
        if let Some(c) = &old {
            if c["duty"] == json!(d) {
                return Ok(c.clone());
            }
            if c["duty"]["generation"].as_u64().unwrap() + 1 != u64::from(d.generation) {
                return Err("Stale learning duty generation".into());
            }
        } else if d.generation != 0 {
            return Err("First duty generation is zero".into());
        }
        let mut incumbent = old
            .as_ref()
            .map(|c| c["practice_incumbent"].clone())
            .unwrap_or(json!({"build":d.baseline,"generation":0,"source_cycle":null}));
        let mut rebases = old
            .as_ref()
            .and_then(|c| c["rebases"].as_array())
            .cloned()
            .unwrap_or_default();
        if let Some(previous) = &old
            && incumbent["build"] != d.baseline
        {
            if d.enabled || previous["duty"]["enabled"] != false {
                return Err(
                    "Rebase requires an already disabled duty and must remain disabled".into(),
                );
            }
            if self.learning_cycles()?.iter().any(|c| {
                !terminal(c["state"].as_str().unwrap_or("")) || c["proposal"]["state"] == "claimed"
            }) || self.joint_snapshot()?["missions"]
                .as_array()
                .unwrap()
                .iter()
                .any(|m| {
                    !m["learning_cycle"].is_null()
                        && (!terminal(m["state"].as_str().unwrap_or(""))
                            || m["tasks"]
                                .as_array()
                                .unwrap()
                                .iter()
                                .any(|t| t["state"] == "claimed"))
                })
            {
                return Err(
                    "Reconcile all learning cycles and claimed requests before rebase".into(),
                );
            }
            if rebases.len() >= 100 {
                return Err("Practice rebase retention limit reached".into());
            }
            let generation = incumbent["generation"]
                .as_u64()
                .unwrap()
                .checked_add(1)
                .ok_or("Practice generation exhausted")?;
            rebases.push(json!({"previous_build":incumbent["build"],"build":d.baseline,"duty_generation":d.generation,"incumbent_generation":generation,"at":now()}));
            incumbent = json!({"build":d.baseline,"generation":generation,"source_cycle":null});
        }
        let c = json!({"duty":d,"practice_incumbent":incumbent,"admitted_cycles":0,"last_started_at":null,"rebases":rebases});
        let changed = if let Some(previous) = old {
            self.db.execute("UPDATE learning_control SET body=$1 WHERE id='readiness-practice' AND body=$2", params![c.to_string(), previous.to_string()])
        } else {
            self.db.execute("INSERT INTO learning_control VALUES ('readiness-practice',$1) ON CONFLICT(id) DO NOTHING", params![c.to_string()])
        }.map_err(error)?;
        if changed != 1 {
            return Err("Learning duty changed; reconcile".into());
        }
        Ok(c)
    }
    fn save_learning_cycle(&self, old: &Value, mut c: Value) -> Result<Value> {
        c["updated_at"] = json!(now());
        let changed = self
            .db
            .execute(
                "UPDATE learning_cycles SET body=$1 WHERE id=$2 AND body=$3",
                params![c.to_string(), old["id"].as_str().unwrap(), old.to_string()],
            )
            .map_err(error)?;
        if changed != 1 {
            return Err("Learning cycle changed; reconcile".into());
        }
        Ok(c)
    }
    pub fn learning_tick(&mut self, generation: u32) -> Result<Value> {
        self.learning_tick_at(generation, now(), enabled())
    }
    fn learning_tick_at(&mut self, generation: u32, at: f64, admitted: bool) -> Result<Value> {
        let Some(mut control) = self.learning_control()? else {
            return Ok(json!({"outcome":"paused","cycle":null}));
        };
        let old_control = control.clone();
        let d: LearningDuty =
            serde_json::from_value(control["duty"].clone()).map_err(|e| e.to_string())?;
        let idle = |outcome: &str| Ok(json!({"outcome":outcome,"cycle":null}));
        if !admitted || !d.enabled || d.generation != generation {
            return idle("paused");
        }
        let cycles = self.learning_cycles()?;
        if let Some(c) = cycles
            .iter()
            .find(|c| !terminal(c["state"].as_str().unwrap()))
        {
            return Ok(json!({"outcome":"busy","cycle":c}));
        }
        if control["admitted_cycles"].as_u64().unwrap() >= u64::from(d.max_cycles) {
            return idle("exhausted");
        }
        if control["last_started_at"]
            .as_f64()
            .is_some_and(|last| at - last < f64::from(d.cooldown_seconds))
        {
            return idle("cooldown");
        }
        if cycles.len() >= 100 {
            return Err("Learning cycle retention limit reached".into());
        }
        let baseline =
            self.learning_build(control["practice_incumbent"]["build"].as_str().unwrap())?;
        let snapshot = self.joint_snapshot()?;
        let mut opportunities = snapshot["opportunities"].as_array().unwrap().clone();
        opportunities.sort_by_key(|o| {
            (
                o["build"] != baseline["digest"],
                o["id"].as_str().unwrap().to_owned(),
            )
        });
        let mut chosen = None;
        for o in opportunities {
            let source_build = self.learning_build(o["build"].as_str().unwrap())?;
            if source_build["manifest"]["profile"] != "joint-readiness-v1"
                || source_build["manifest"]["inference"] != baseline["manifest"]["inference"]
            {
                continue;
            }
            let mut sources = Vec::new();
            for id in o["source_mission_ids"].as_array().unwrap() {
                sources.push(self.joint_mission(id.as_str().unwrap())?);
            }
            sources.sort_by_key(|m| m["input"]["id"].as_str().unwrap().to_owned());
            let evidence_digest = hash(&json!({"source_build":o["build"],"missions":sources}));
            let dedup = hash(
                &json!({"duty":"readiness-practice","generation":generation,"evidence":evidence_digest}),
            );
            if cycles.iter().any(|c| c["dedup_key"] == dedup) {
                continue;
            }
            chosen = Some((o, source_build, sources, evidence_digest, dedup));
            break;
        }
        let Some((opportunity, source_build, sources, evidence_digest, dedup)) = chosen else {
            return idle("no-op");
        };
        let id = format!("learn-{}", &dedup[..32]);
        let mut trials = Vec::new();
        let mut order = Vec::new();
        for (pair, scenario) in [
            "route-mismatch",
            "healthy",
            "persistent-dependency",
            "listening-but-broken",
        ]
        .iter()
        .enumerate()
        {
            for arm in ["baseline", "candidate"] {
                let slot = format!("p{pair}-{arm}");
                trials.push(json!({"slot":slot,"pair":pair,"arm":arm,"scenario":scenario,"mission_id":format!("{id}-{slot}"),"requests":d.budget.trial_requests,"tokens":d.budget.trial_tokens}));
            }
            let arms = if pair % 2 == 0 {
                ["baseline", "candidate"]
            } else {
                ["candidate", "baseline"]
            };
            for arm in arms {
                order.push(format!("p{pair}-{arm}"));
            }
        }
        let c = json!({"id":id,"dedup_key":dedup,"duty_generation":generation,"source_opportunity":opportunity,"source_build":source_build,"evidence_digest":evidence_digest,"source_missions":sources,"baseline":baseline,"baseline_generation":control["practice_incumbent"]["generation"],"candidate":null,"state":"queued","deadline":at+7200.0,"budget":{"requests_reserved":1+8*d.budget.trial_requests,"tokens_reserved":d.budget.proposal_tokens+8*d.budget.trial_tokens},"proposal":{"state":"reserved","grant":{"requests":1,"tokens":d.budget.proposal_tokens},"result":null,"accounted_tokens":0},"trials":trials,"trial_order":order,"policy":policy(),"summary":null,"created_at":at,"updated_at":at});
        control["admitted_cycles"] = json!(control["admitted_cycles"].as_u64().unwrap() + 1);
        control["last_started_at"] = json!(at);
        let tx = self.db.transaction().map_err(error)?;
        tx.execute(
            "INSERT INTO learning_cycles VALUES ($1,$2,$3,$4)",
            params![id, dedup, c.to_string(), at],
        )
        .map_err(error)?;
        if tx
            .execute(
                "UPDATE learning_control SET body=$1 WHERE id='readiness-practice' AND body=$2",
                params![control.to_string(), old_control.to_string()],
            )
            .map_err(error)?
            != 1
        {
            return Err("Learning control changed".into());
        }
        tx.commit().map_err(error)?;
        Ok(json!({"outcome":"started","cycle":c}))
    }
    fn learning_usage(&self, c: &Value) -> Result<(u64, bool)> {
        let mut total = c["proposal"]["accounted_tokens"].as_u64().unwrap();
        let grant = c["proposal"]["grant"]["tokens"].as_u64().unwrap();
        let u = &c["proposal"]["result"]["usage"];
        let mut over = total > grant
            || u["input_tokens"]
                .as_u64()
                .zip(u["output_tokens"].as_u64())
                .is_some_and(|(a, b)| a.checked_add(b).is_none_or(|n| n > grant));
        for t in c["trials"].as_array().unwrap() {
            if let Ok(m) = self.joint_mission(t["mission_id"].as_str().unwrap()) {
                let amount = m["budget"]["tokens_accounted"].as_u64().unwrap();
                total = match total.checked_add(amount) {
                    Some(n) => n,
                    None => {
                        over = true;
                        u64::MAX
                    }
                };
                if crate::joint::budget_overrun(&m) {
                    over = true;
                }
            }
        }
        Ok((
            total,
            over || total > c["budget"]["tokens_reserved"].as_u64().unwrap(),
        ))
    }
    fn learning_open(&self, c: &Value, at: f64, admitted: bool) -> Result<()> {
        let control = self.learning_control()?.ok_or("Learning duty missing")?;
        if !admitted
            || c["policy"] != policy()
            || control["duty"]["enabled"] != true
            || control["duty"]["generation"] != c["duty_generation"]
            || terminal(c["state"].as_str().unwrap())
            || at >= c["deadline"].as_f64().unwrap()
        {
            return Err("Learning cycle stopped, expired or disabled".into());
        }
        if c["baseline"]["manifest"]["inference"] == true
            && std::env::var("STARBASE_INFERENCE_ENABLED").as_deref() == Ok("false")
        {
            return Err("Learning inference disabled".into());
        }
        if self.learning_usage(c)?.1 {
            return Err("Learning budget overrun; dispatch fenced".into());
        }
        Ok(())
    }
    pub(crate) fn learning_dispatch(&self, m: &Value) -> Result<()> {
        if let Some(id) = m["learning_cycle"].as_str() {
            self.learning_open(&self.learning_cycle(id)?, now(), enabled())?;
        }
        Ok(())
    }
    pub fn claim_learning_proposal(&self, id: &str) -> Result<Value> {
        self.claim_learning_proposal_at(id, now(), enabled())
    }
    fn claim_learning_proposal_at(&self, id: &str, at: f64, admitted: bool) -> Result<Value> {
        let old = self.learning_cycle(id)?;
        if old["proposal"]["state"] != "reserved" {
            return Ok(json!({"dispatch":false,"grant":old["proposal"]["grant"],"cycle":old}));
        }
        self.learning_open(&old, at, admitted)?;
        let mut c = old.clone();
        c["proposal"]["state"] = json!("claimed");
        c["state"] = json!("proposing");
        let c = self.save_learning_cycle(&old, c)?;
        Ok(json!({"dispatch":true,"grant":c["proposal"]["grant"],"cycle":c}))
    }
    pub fn learning_proposal_result(&self, id: &str, result: &ProcedureResult) -> Result<Value> {
        if json!(result).to_string().len() > 131072
            || result.rationale.len() > 3000
            || result.error.as_ref().is_some_and(|s| s.len() > 2000)
            || result.procedure.as_ref().is_some_and(|s| s.len() > 12000)
        {
            return Err("Procedure result exceeds bound".into());
        }
        let old = self.learning_cycle(id)?;
        if !old["proposal"]["result"].is_null() {
            return if old["proposal"]["result"] == json!(result) {
                Ok(old)
            } else {
                Err("Trainer response immutable".into())
            };
        }
        if old["proposal"]["state"] != "claimed" {
            return Err("Claim proposal before submitting".into());
        }
        let grant = old["proposal"]["grant"]["tokens"].as_u64().unwrap();
        let usage = result
            .usage
            .as_ref()
            .and_then(|u| u.input_tokens.checked_add(u.output_tokens));
        let known = !matches!(result.status, TaskStatus::Unknown)
            && usage.is_some()
            && (old["baseline"]["manifest"]["inference"] != true
                || result
                    .usage
                    .as_ref()
                    .is_some_and(|u| u.input_tokens > 0 && u.output_tokens > 0));
        let accounted = if known { usage.unwrap() } else { grant };
        let acceptable = matches!(result.status, TaskStatus::Completed)
            && known
            && accounted <= grant
            && result.error.is_none()
            && result
                .procedure
                .as_ref()
                .is_some_and(|s| !s.trim().is_empty());
        let mut c = old.clone();
        c["proposal"]["result"] = json!(result);
        c["proposal"]["accounted_tokens"] = json!(accounted);
        c["proposal"]["state"] = json!(if acceptable {
            "completed"
        } else if matches!(result.status, TaskStatus::Unknown) {
            "unknown"
        } else {
            "failed"
        });
        if acceptable && !terminal(c["state"].as_str().unwrap()) {
            let procedure = result.procedure.as_ref().unwrap();
            let previous = c["baseline"]["manifest"]["procedure"]
                .as_str()
                .unwrap_or("");
            if procedure == previous {
                c["state"] = json!("completed");
                c["summary"] = json!({"outcome":"no-change","reason":"Trainer proposed the incumbent Procedure unchanged","policy":policy(),"xp":0});
            } else {
                let mut manifest = c["baseline"]["manifest"].clone();
                manifest["procedure"] = json!(procedure);
                let build = JointBuild {
                    digest: hash(&manifest),
                    manifest,
                };
                match self.joint_build(&build) {
                    Ok(candidate) => {
                        c["candidate"] = candidate;
                        c["state"] = json!("evaluating");
                    }
                    Err(_) => {
                        c["state"] = json!("failed");
                        c["summary"] = json!({"outcome":"unresolved","reason":"Candidate registration unavailable; Trainer response and usage retained","policy":policy(),"xp":0});
                    }
                }
            }
        }
        self.save_learning_cycle(&old, c)
    }
    pub fn admit_learning_trial(&self, id: &str, slot: &str) -> Result<Value> {
        self.admit_learning_trial_at(id, slot, now(), enabled())
    }
    fn admit_learning_trial_at(
        &self,
        id: &str,
        slot: &str,
        at: f64,
        admitted: bool,
    ) -> Result<Value> {
        let c = self.learning_cycle(id)?;
        let t = c["trials"]
            .as_array()
            .unwrap()
            .iter()
            .find(|t| t["slot"] == slot)
            .ok_or("Unknown frozen trial slot")?;
        if let Ok(m) = self.joint_mission(t["mission_id"].as_str().unwrap()) {
            if m["learning_cycle"] != id {
                return Err("Trial identity collision".into());
            }
            return Ok(m);
        }
        self.learning_open(&c, at, admitted)?;
        if c["state"] != "evaluating" || c["candidate"].is_null() {
            return Err("A frozen candidate is required".into());
        }
        for previous in c["trial_order"].as_array().unwrap() {
            if previous == slot {
                break;
            }
            let previous = c["trials"]
                .as_array()
                .unwrap()
                .iter()
                .find(|t| t["slot"] == *previous)
                .unwrap();
            let mission = self
                .joint_mission(previous["mission_id"].as_str().unwrap())
                .map_err(|_| "Follow frozen counterbalanced trial order")?;
            if !terminal(mission["state"].as_str().unwrap()) {
                return Err("Wait for the preceding paired trial to finish".into());
            }
        }
        let build = &c[t["arm"].as_str().unwrap()];
        let input = JointInput {
            id: t["mission_id"].as_str().unwrap().into(),
            opportunity: t["mission_id"].as_str().unwrap().into(),
            build: build["digest"].as_str().unwrap().into(),
            scenario: serde_json::from_value::<Scenario>(t["scenario"].clone()).unwrap(),
            inference: c["baseline"]["manifest"]["inference"].as_bool().unwrap(),
            budget: JointBudget {
                requests: t["requests"].as_u64().unwrap() as u32,
                tokens: t["tokens"].as_u64().unwrap(),
            },
        };
        self.create_joint_learning(&input, id, at)
    }
    pub fn reconcile_learning_stop(&self, id: &str) -> Result<Value> {
        self.reconcile_learning_stop_at(id, now(), enabled())
    }
    fn reconcile_learning_stop_at(&self, id: &str, at: f64, admitted: bool) -> Result<Value> {
        let c = self.learning_cycle(id)?;
        if !terminal(c["state"].as_str().unwrap()) && self.learning_open(&c, at, admitted).is_ok() {
            return Err("Eligible learning cycle cannot be stopped by reconciliation".into());
        }
        self.cancel_learning(id)
    }
    pub fn cancel_learning(&self, id: &str) -> Result<Value> {
        let old = self.learning_cycle(id)?;
        if matches!(old["state"].as_str(), Some("completed" | "failed")) {
            return Ok(old);
        }
        let c = if old["state"] == "cancelled" {
            old
        } else {
            let mut c = old.clone();
            c["state"] = json!("cancelled");
            c["summary"] = json!({"outcome":"unresolved","reason":"Learning cycle cancelled; late results remain accounted","policy":policy(),"xp":0});
            self.save_learning_cycle(&old, c)?
        };
        // Repeat the cascade even when the parent was saved before an interruption.
        // A missing child was never admitted; database errors must remain retryable.
        for t in c["trials"].as_array().unwrap() {
            let mid = t["mission_id"].as_str().unwrap();
            let body: Option<String> = self
                .db
                .query_row(
                    "SELECT body FROM joint_missions WHERE id=$1",
                    params![mid],
                    |r| r.get(0),
                )
                .optional()
                .map_err(error)?;
            if let Some(body) = body {
                let child: Value = serde_json::from_str(&body).map_err(|e| e.to_string())?;
                if child["learning_cycle"] != id {
                    return Err("Learning trial identity mismatch during cancellation".into());
                }
                self.cancel_joint(mid)?;
            }
        }
        Ok(c)
    }
    pub fn finish_learning(&mut self, id: &str) -> Result<Value> {
        self.finish_learning_at(id, now(), enabled())
    }
    fn finish_learning_at(&mut self, id: &str, at: f64, admitted: bool) -> Result<Value> {
        let old = self.learning_cycle(id)?;
        if !old["summary"].is_null() {
            return Ok(old);
        }
        if old["proposal"]["state"] == "claimed" {
            return Err("Reconcile claimed Trainer request before finish".into());
        }
        let mut records = Vec::new();
        let mut missing = false;
        for t in old["trials"].as_array().unwrap() {
            match self.joint_mission(t["mission_id"].as_str().unwrap()) {
                Ok(m) => {
                    if !terminal(m["state"].as_str().unwrap())
                        || m["tasks"]
                            .as_array()
                            .unwrap()
                            .iter()
                            .any(|t| t["state"] == "claimed")
                    {
                        return Err("Reconcile active campaign trials before finish".into());
                    }
                    records.push((t.clone(), m));
                }
                Err(_) => missing = true,
            }
        }
        let (accounted, overrun) = self.learning_usage(&old)?;
        let mut gates = Vec::new();
        if missing {
            gates.push("missing-trials");
        }
        if overrun {
            gates.push("budget-overrun");
        }
        if old["proposal"]["state"] != "completed" {
            gates.push("trainer-failed-or-unknown");
        }
        let mut baseline = 0;
        let mut candidate = 0;
        let mut paired_regression = false;
        for (t, m) in &records {
            if m["learning_cycle"] != old["id"]
                || m["input"]["build"] != old[t["arm"].as_str().unwrap()]["digest"]
                || m["input"]["scenario"] != t["scenario"]
                || m["input"]["budget"]["requests"] != t["requests"]
                || m["input"]["budget"]["tokens"] != t["tokens"]
                || m["input"]["inference"] != old["baseline"]["manifest"]["inference"]
            {
                gates.push("trial-identity-mismatch");
            }
            if comparison_trial(m)["status"] == "invalid" {
                gates.push("invalid-or-unknown-trial");
            }
        }
        for pair in 0..4 {
            let passed = |arm: &str| {
                records.iter().any(|(t, m)| {
                    t["pair"] == pair && t["arm"] == arm && comparison_trial(m)["status"] == "pass"
                })
            };
            let b = passed("baseline");
            let c = passed("candidate");
            baseline += u32::from(b);
            candidate += u32::from(c);
            paired_regression |= b && !c;
        }
        let mut control = self.learning_control()?.ok_or("Learning duty missing")?;
        let old_control = control.clone();
        let current = self.learning_open(&old, at, admitted).is_ok()
            && control["practice_incumbent"]["build"] == old["baseline"]["digest"]
            && control["practice_incumbent"]["generation"] == old["baseline_generation"];
        if !current {
            gates.push("stopped-expired-or-incumbent-changed");
        }
        gates.sort();
        gates.dedup();
        let outcome = if !gates.is_empty() {
            "unresolved"
        } else if candidate == 4 && candidate > baseline && !paired_regression {
            "practice-adopted"
        } else if paired_regression || candidate < baseline {
            "practice-rejected"
        } else {
            "inconclusive"
        };
        let mut c = old.clone();
        c["state"] = json!(if gates.is_empty() {
            "completed"
        } else {
            "failed"
        });
        c["updated_at"] = json!(at);
        c["summary"] = json!({"outcome":outcome,"baseline_passes":baseline,"candidate_passes":candidate,"pairs":4,"paired_regression":paired_regression,"hard_gates":gates,"tokens_accounted":accounted,"policy":old["policy"],"trials":records.iter().map(|(t,m)|json!({"slot":t["slot"],"mission_id":t["mission_id"],"build":m["input"]["build"],"outcome":m["outcome"],"comparison":comparison_trial(m),"tokens_accounted":m["budget"]["tokens_accounted"]})).collect::<Vec<_>>(),"xp":0});
        if outcome == "practice-adopted" {
            control["practice_incumbent"] = json!({"build":old["candidate"]["digest"],"generation":old["baseline_generation"].as_u64().unwrap()+1,"source_cycle":id});
        }
        let tx = self.db.transaction().map_err(error)?;
        if tx
            .execute(
                "UPDATE learning_cycles SET body=$1 WHERE id=$2 AND body=$3",
                params![c.to_string(), id, old.to_string()],
            )
            .map_err(error)?
            != 1
        {
            return Err("Learning cycle changed".into());
        }
        if outcome == "practice-adopted"
            && tx
                .execute(
                    "UPDATE learning_control SET body=$1 WHERE id='readiness-practice' AND body=$2",
                    params![control.to_string(), old_control.to_string()],
                )
                .map_err(error)?
                != 1
        {
            return Err("Practice incumbent changed".into());
        }
        tx.commit().map_err(error)?;
        Ok(c)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn bootstrap(s: &Store) -> LearningDuty {
        let m = json!({"profile":"joint-readiness-v1","authority":"simulation-observation-and-proposal","inference":false,"procedure":"","grant_tokens":100});
        let b = JointBuild {
            digest: hash(&m),
            manifest: m,
        };
        s.joint_build(&b).unwrap();
        let m = json!({"learning_cycle":null,"input":{"id":"development-failure","opportunity":"development-failure","build":b.digest,"scenario":"route-mismatch","inference":false,"budget":{"requests":24,"tokens":384000}},"build":b,"state":"failed","outcome":"unresolved","tasks":[],"decision":null,"finish":{"decision":null,"reason":"Historical development failure"},"budget":{"requests_reserved":0,"tokens_reserved":0,"tokens_accounted":0,"requests_limit":24,"tokens_limit":384000},"created_at":1.0,"updated_at":2.0,"deadline":3.0,"reason":"Historical development failure","simulation":true,"xp":0});
        s.db.execute(
            "INSERT INTO joint_missions VALUES ($1,$2,$3,$4)",
            params![
                "development-failure",
                "development-failure",
                m.to_string(),
                1.0
            ],
        )
        .unwrap();
        let d = LearningDuty {
            id: "readiness-practice".into(),
            generation: 0,
            enabled: true,
            baseline: b.digest,
            max_cycles: 2,
            cooldown_seconds: 60,
            budget: LearningBudget::default(),
        };
        s.set_learning_duty_at(&d, true).unwrap();
        d
    }
    fn cycle(s: &mut Store) -> Value {
        bootstrap(s);
        let tick = s.learning_tick_at(0, now(), true).unwrap();
        assert_eq!(tick["outcome"], "started");
        tick["cycle"].clone()
    }
    fn proposal() -> ProcedureResult {
        ProcedureResult {
            status: TaskStatus::Completed,
            procedure: Some(
                "Require both specialist observations; use the current manifest receipt.".into(),
            ),
            rationale: "Address retained public failure".into(),
            usage: Some(Usage {
                input_tokens: 100,
                output_tokens: 50,
            }),
            error: None,
            trace: None,
        }
    }
    fn candidate(s: &Store, c: &Value) -> Value {
        let id = c["id"].as_str().unwrap();
        assert_eq!(
            s.claim_learning_proposal_at(id, now(), true).unwrap()["dispatch"],
            true
        );
        s.learning_proposal_result(id, &proposal()).unwrap()
    }
    fn trials(s: &Store, c: &Value, baseline_failure: Option<&str>, candidate_failure: bool) {
        for t in c["trials"].as_array().unwrap() {
            let id = t["mission_id"].as_str().unwrap();
            let arm = t["arm"].as_str().unwrap();
            let fail = (arm == "baseline" && t["pair"] == 0 && baseline_failure.is_some())
                || (arm == "candidate" && t["pair"] == 0 && candidate_failure);
            let input = JointInput {
                id: id.into(),
                opportunity: id.into(),
                build: c[arm]["digest"].as_str().unwrap().into(),
                scenario: serde_json::from_value(t["scenario"].clone()).unwrap(),
                inference: false,
                budget: JointBudget {
                    requests: t["requests"].as_u64().unwrap() as u32,
                    tokens: t["tokens"].as_u64().unwrap(),
                },
            };
            let mut m = s
                .create_joint_learning(&input, c["id"].as_str().unwrap(), now())
                .unwrap();
            m["state"] = json!(if fail { "failed" } else { "completed" });
            m["outcome"] = json!(if fail
                && matches!(baseline_failure, Some("malformed" | "unknown"))
            {
                "unresolved"
            } else if fail {
                "diagnostic-fail"
            } else {
                "diagnostic-pass"
            });
            m["tasks"] = json!([{"id":"r0-lead","role":"lead","round":0,"tokens":100,"accounted_tokens":30,"state":if fail&&baseline_failure==Some("unknown"){"unknown"}else if fail&&baseline_failure==Some("malformed"){"failed"}else{"completed"},"result":{"status":if fail&&baseline_failure==Some("unknown"){"unknown"}else if fail&&baseline_failure==Some("malformed"){"failed"}else{"completed"},"usage":{"input_tokens":20,"output_tokens":10},"error":if fail&&baseline_failure==Some("malformed"){json!("UnexpectedModelBehavior")}else{Value::Null},"output":{}}}]);
            m["budget"]["tokens_accounted"] = json!(30);
            s.db.execute(
                "UPDATE joint_missions SET body=$1 WHERE id=$2",
                params![m.to_string(), id],
            )
            .unwrap();
        }
    }
    #[test]
    fn duty_defaults_are_disabled_and_generation_is_compare_and_swap() {
        let s = crate::test_store();
        let mut d = bootstrap(&s);
        let old = s.learning_control().unwrap().unwrap();
        assert_eq!(s.set_learning_duty_at(&d, true).unwrap(), old);
        d.enabled = false;
        assert!(s.set_learning_duty_at(&d, true).is_err());
        d.generation = 1;
        assert_eq!(
            s.set_learning_duty_at(&d, true).unwrap()["duty"]["enabled"],
            false
        );
        let minimal: LearningDuty = serde_json::from_value(
            json!({"id":"readiness-practice","generation":0,"baseline":"digest"}),
        )
        .unwrap();
        assert!(!minimal.enabled);
        assert_eq!(minimal.max_cycles, 2);
        assert_eq!(minimal.cooldown_seconds, 60);
    }
    #[test]
    fn practice_rebase_requires_stopped_reconciled_duty_and_preserves_history() {
        let mut s = crate::test_store();
        let c = cycle(&mut s);
        let id = c["id"].as_str().unwrap();
        s.claim_learning_proposal_at(id, now(), true).unwrap();
        let mut manifest = c["baseline"]["manifest"].clone();
        manifest["procedure"] = json!("A new locally installed baseline procedure.");
        let b = JointBuild {
            digest: hash(&manifest),
            manifest,
        };
        s.joint_build(&b).unwrap();
        let mut d: LearningDuty =
            serde_json::from_value(s.learning_control().unwrap().unwrap()["duty"].clone()).unwrap();
        d.generation = 1;
        d.baseline = b.digest.clone();
        assert!(s.set_learning_duty_at(&d, true).is_err());
        d.enabled = false;
        assert!(s.set_learning_duty_at(&d, true).is_err());
        d.baseline = c["baseline"]["digest"].as_str().unwrap().into();
        s.set_learning_duty_at(&d, true).unwrap();
        d.generation = 2;
        d.baseline = b.digest.clone();
        assert!(s.set_learning_duty_at(&d, true).is_err());
        s.cancel_learning(id).unwrap();
        assert!(s.set_learning_duty_at(&d, true).is_err());
        let mut lost = proposal();
        lost.status = TaskStatus::Unknown;
        lost.usage = None;
        lost.procedure = None;
        lost.error = Some("Interrupted request".into());
        s.learning_proposal_result(id, &lost).unwrap();
        let before = s.learning_cycle(id).unwrap();
        let changed = s.set_learning_duty_at(&d, true).unwrap();
        assert_eq!(changed["practice_incumbent"]["build"], b.digest);
        assert_eq!(changed["practice_incumbent"]["generation"], 1);
        assert!(changed["practice_incumbent"]["source_cycle"].is_null());
        assert_eq!(
            changed["rebases"][0]["previous_build"],
            c["baseline"]["digest"]
        );
        assert_eq!(changed["rebases"][0]["build"], b.digest);
        assert_eq!(changed["rebases"][0]["duty_generation"], 2);
        assert_eq!(changed["rebases"][0]["incumbent_generation"], 1);
        assert_eq!(s.set_learning_duty_at(&d, true).unwrap(), changed);
        assert_eq!(s.learning_cycle(id).unwrap(), before);
        d.enabled = true;
        d.generation = 3;
        let enabled = s.set_learning_duty_at(&d, true).unwrap();
        assert_eq!(enabled["rebases"], changed["rebases"]);
        assert_eq!(enabled["practice_incumbent"], changed["practice_incumbent"]);
        serde_json::from_value::<LearningControl>(enabled).unwrap();
    }
    #[test]
    fn cancelled_trial_claim_must_be_accounted_before_practice_rebase() {
        let mut s = crate::test_store();
        let c = cycle(&mut s);
        let c = candidate(&s, &c);
        let id = c["id"].as_str().unwrap();
        let mut m = s
            .admit_learning_trial_at(id, "p0-baseline", now(), true)
            .unwrap();
        // Model a started member surviving cancellation and worker restart.
        m["tasks"] = json!([{"id":"r0-lead","state":"claimed"}]);
        s.db.execute(
            "UPDATE joint_missions SET body=$1 WHERE id=$2",
            params![m.to_string(), m["input"]["id"].as_str().unwrap()],
        )
        .unwrap();
        let mut d: LearningDuty =
            serde_json::from_value(s.learning_control().unwrap().unwrap()["duty"].clone()).unwrap();
        d.enabled = false;
        d.generation = 1;
        s.set_learning_duty_at(&d, true).unwrap();
        s.cancel_learning(id).unwrap();
        d.generation = 2;
        d.baseline = c["candidate"]["digest"].as_str().unwrap().into();
        assert!(
            s.set_learning_duty_at(&d, true)
                .unwrap_err()
                .contains("Reconcile")
        );
        // Unknown is a retained outcome, not an active dispatch; it transfers no qualification.
        m = s.joint_mission(m["input"]["id"].as_str().unwrap()).unwrap();
        m["tasks"][0]["state"] = json!("unknown");
        s.db.execute(
            "UPDATE joint_missions SET body=$1 WHERE id=$2",
            params![m.to_string(), m["input"]["id"].as_str().unwrap()],
        )
        .unwrap();
        let ctl = s.set_learning_duty_at(&d, true).unwrap();
        assert!(ctl["practice_incumbent"]["source_cycle"].is_null());
        assert_eq!(s.learning_cycle(id).unwrap()["state"], "cancelled");
        assert_eq!(
            s.joint_mission(m["input"]["id"].as_str().unwrap()).unwrap(),
            m
        );
    }
    #[test]
    fn repeated_cancellation_repairs_interrupted_child_cascade() {
        let mut s = crate::test_store();
        let c = cycle(&mut s);
        let c = candidate(&s, &c);
        let id = c["id"].as_str().unwrap();
        let child = s
            .admit_learning_trial_at(id, "p0-baseline", now(), true)
            .unwrap();
        let cancelled = s.cancel_learning(id).unwrap();
        // Restore the child row to the crash boundary: parent saved, child not yet cancelled.
        s.db.execute(
            "UPDATE joint_missions SET body=$1 WHERE id=$2",
            params![child.to_string(), child["input"]["id"].as_str().unwrap()],
        )
        .unwrap();
        assert_eq!(s.cancel_learning(id).unwrap(), cancelled);
        assert_eq!(
            s.joint_mission(child["input"]["id"].as_str().unwrap())
                .unwrap()["state"],
            "cancelled"
        );
    }
    #[test]
    fn stopped_duty_reconciles_queued_child_without_a_workflow() {
        for mode in ["duty", "generation", "installation", "expiry", "policy"] {
            let mut s = crate::test_store();
            let c = cycle(&mut s);
            let c = candidate(&s, &c);
            let id = c["id"].as_str().unwrap();
            let child = s
                .admit_learning_trial_at(id, "p0-baseline", now(), true)
                .unwrap();
            assert!(s.reconcile_learning_stop_at(id, now(), true).is_err());
            assert_eq!(s.learning_cycle(id).unwrap(), c);
            let mut at = now();
            if matches!(mode, "duty" | "generation") {
                let mut d: LearningDuty =
                    serde_json::from_value(s.learning_control().unwrap().unwrap()["duty"].clone())
                        .unwrap();
                d.enabled = mode == "generation";
                d.generation = 1;
                s.set_learning_duty_at(&d, true).unwrap();
            } else if mode == "expiry" {
                at = c["deadline"].as_f64().unwrap();
            } else if mode == "policy" {
                let mut changed = c.clone();
                changed["policy"]["grader_digest"] = json!("old-grader");
                s.save_learning_cycle(&c, changed).unwrap();
            }
            let stopped = s
                .reconcile_learning_stop_at(id, at, mode != "installation")
                .unwrap();
            assert_eq!(stopped["state"], "cancelled");
            assert_eq!(stopped["summary"]["outcome"], "unresolved");
            assert_eq!(
                s.joint_mission(child["input"]["id"].as_str().unwrap())
                    .unwrap()["state"],
                "cancelled"
            );
            assert_eq!(s.reconcile_learning_stop_at(id, at, true).unwrap(), stopped);
            assert_eq!(s.finish_learning_at(id, at, true).unwrap(), stopped);
        }
        let mut s = crate::test_store();
        let c = cycle(&mut s);
        let id = c["id"].as_str().unwrap();
        // A Core admission may precede creation of the Temporal parent workflow.
        let stopped = s.reconcile_learning_stop_at(id, now(), false).unwrap();
        assert_eq!(stopped["state"], "cancelled");
        assert_eq!(stopped["proposal"]["state"], "reserved");
    }
    #[test]
    fn stop_reconciliation_preserves_terminal_campaign_results() {
        for failed in [false, true] {
            let mut s = crate::test_store();
            let c = cycle(&mut s);
            let c = candidate(&s, &c);
            trials(&s, &c, if failed { Some("unknown") } else { None }, false);
            let id = c["id"].as_str().unwrap();
            let final_result = s.finish_learning_at(id, now(), true).unwrap();
            let child = s
                .joint_mission(c["trials"][0]["mission_id"].as_str().unwrap())
                .unwrap();
            assert_eq!(
                s.reconcile_learning_stop_at(id, now(), false).unwrap(),
                final_result
            );
            assert_eq!(s.cancel_learning(id).unwrap(), final_result);
            assert_eq!(
                s.joint_mission(c["trials"][0]["mission_id"].as_str().unwrap())
                    .unwrap(),
                child
            );
        }
    }
    #[test]
    fn full_cycle_grant_claim_and_candidate_are_frozen() {
        let mut s = crate::test_store();
        let c = cycle(&mut s);
        assert_eq!(c["budget"]["tokens_reserved"], 32768 + 8 * 384000);
        assert_eq!(c["budget"]["requests_reserved"], 193);
        let frozen = candidate(&s, &c);
        let id = c["id"].as_str().unwrap();
        assert_eq!(
            s.claim_learning_proposal_at(id, now(), true).unwrap()["dispatch"],
            false
        );
        assert_eq!(s.learning_proposal_result(id, &proposal()).unwrap(), frozen);
        let mut changed = proposal();
        changed.procedure = Some("Changed response".into());
        assert!(s.learning_proposal_result(id, &changed).is_err());
        let mut expected = c["baseline"]["manifest"].clone();
        expected["procedure"] = json!(proposal().procedure);
        assert_eq!(frozen["candidate"]["manifest"], expected);
        assert_eq!(frozen["candidate"]["digest"], hash(&expected));
        serde_json::from_value::<LearningCycle>(frozen).unwrap();
        serde_json::from_value::<LearningSnapshot>(s.learning_snapshot().unwrap()).unwrap();
    }
    #[test]
    fn historical_signal_is_deduplicated_even_after_baseline_changes() {
        let mut s = crate::test_store();
        let c = cycle(&mut s);
        let id = c["id"].as_str().unwrap();
        s.cancel_learning(id).unwrap();
        let baseline = s.learning_control().unwrap().unwrap()["practice_incumbent"].clone();
        assert_eq!(
            s.learning_tick_at(0, now() + 61.0, true).unwrap()["outcome"],
            "no-op"
        );
        let mut ctl = s.learning_control().unwrap().unwrap();
        ctl["practice_incumbent"]["generation"] =
            json!(baseline["generation"].as_u64().unwrap() + 1);
        s.db.execute(
            "UPDATE learning_control SET body=$1",
            params![ctl.to_string()],
        )
        .unwrap();
        assert_eq!(
            s.learning_tick_at(0, now() + 61.0, true).unwrap()["outcome"],
            "no-op"
        );
    }
    #[test]
    fn admission_is_fixed_counterbalanced_and_idempotent() {
        let mut s = crate::test_store();
        let c = cycle(&mut s);
        let c = candidate(&s, &c);
        let id = c["id"].as_str().unwrap();
        assert!(
            s.admit_learning_trial_at(id, "p0-candidate", now(), true)
                .is_err()
        );
        let m = s
            .admit_learning_trial_at(id, "p0-baseline", now(), true)
            .unwrap();
        assert_eq!(m["input"]["build"], c["baseline"]["digest"]);
        assert_eq!(m["learning_cycle"], id);
        assert_eq!(
            s.admit_learning_trial_at(id, "p0-baseline", now(), true)
                .unwrap(),
            m
        );
        assert!(
            s.admit_learning_trial_at(id, "invented", now(), true)
                .is_err()
        );
        assert_eq!(c["trial_order"][2], "p1-candidate");
    }
    #[test]
    fn known_failed_baseline_can_adopt_but_unknown_baseline_cannot() {
        for failure in ["diagnostic", "malformed", "unknown"] {
            let mut s = crate::test_store();
            let c = cycle(&mut s);
            let c = candidate(&s, &c);
            trials(&s, &c, Some(failure), false);
            let id = c["id"].as_str().unwrap();
            let before = s
                .joint_mission(c["trials"][0]["mission_id"].as_str().unwrap())
                .unwrap();
            let done = s.finish_learning_at(id, now(), true).unwrap();
            assert_eq!(
                done["summary"]["outcome"],
                if failure == "unknown" {
                    "unresolved"
                } else {
                    "practice-adopted"
                }
            );
            assert_eq!(done["summary"]["xp"], 0);
            let ctl = s.learning_control().unwrap().unwrap();
            assert_eq!(
                ctl["practice_incumbent"]["build"],
                c[if failure == "unknown" {
                    "baseline"
                } else {
                    "candidate"
                }]["digest"]
            );
            assert_eq!(s.finish_learning_at(id, now(), true).unwrap(), done);
            assert_eq!(
                s.joint_mission(c["trials"][0]["mission_id"].as_str().unwrap())
                    .unwrap(),
                before
            );
        }
    }
    #[test]
    fn ties_regressions_and_wrong_trial_identity_do_not_adopt() {
        for mode in ["tie", "regression", "identity"] {
            let mut s = crate::test_store();
            let c = cycle(&mut s);
            let c = candidate(&s, &c);
            trials(
                &s,
                &c,
                if mode == "identity" {
                    Some("diagnostic")
                } else {
                    None
                },
                mode == "regression",
            );
            if mode == "identity" {
                let id = c["trials"][0]["mission_id"].as_str().unwrap();
                let mut m = s.joint_mission(id).unwrap();
                m["input"]["build"] = json!("wrong");
                s.db.execute(
                    "UPDATE joint_missions SET body=$1 WHERE id=$2",
                    params![m.to_string(), id],
                )
                .unwrap();
            }
            let done = s
                .finish_learning_at(c["id"].as_str().unwrap(), now(), true)
                .unwrap();
            assert_eq!(
                done["summary"]["outcome"],
                match mode {
                    "tie" => "inconclusive",
                    "regression" => "practice-rejected",
                    _ => "unresolved",
                }
            );
            assert_eq!(
                s.learning_control().unwrap().unwrap()["practice_incumbent"]["build"],
                c["baseline"]["digest"]
            );
        }
    }
    #[test]
    fn stop_and_cancel_fence_linked_dispatch_but_keep_late_results() {
        let mut s = crate::test_store();
        let c = cycle(&mut s);
        let id = c["id"].as_str().unwrap();
        s.claim_learning_proposal_at(id, now(), true).unwrap();
        s.cancel_learning(id).unwrap();
        let late = s.learning_proposal_result(id, &proposal()).unwrap();
        assert_eq!(late["state"], "cancelled");
        assert_eq!(late["proposal"]["accounted_tokens"], 150);
        assert!(late["candidate"].is_null());
        assert!(
            s.admit_learning_trial_at(id, "p0-baseline", now(), true)
                .is_err()
        );
        let mut s = crate::test_store();
        let c = cycle(&mut s);
        let c = candidate(&s, &c);
        let mut d: LearningDuty =
            serde_json::from_value(s.learning_control().unwrap().unwrap()["duty"].clone()).unwrap();
        d.enabled = false;
        d.generation += 1;
        s.set_learning_duty_at(&d, true).unwrap();
        assert!(s.learning_open(&c, now(), true).is_err());
        assert!(
            s.admit_learning_trial_at(c["id"].as_str().unwrap(), "p0-baseline", now(), true)
                .is_err()
        );
    }
    #[test]
    fn incomplete_proposal_can_finish_but_claimed_unknown_must_reconcile() {
        let mut s = crate::test_store();
        let c = cycle(&mut s);
        assert_eq!(
            s.finish_learning_at(c["id"].as_str().unwrap(), now(), true)
                .unwrap()["state"],
            "failed"
        );
        let mut s = crate::test_store();
        let c = cycle(&mut s);
        let id = c["id"].as_str().unwrap();
        s.claim_learning_proposal_at(id, now(), true).unwrap();
        assert!(s.finish_learning_at(id, now(), true).is_err());
        let unknown = ProcedureResult {
            status: TaskStatus::Unknown,
            procedure: None,
            rationale: "Lost provider dispatch".into(),
            usage: None,
            error: Some("Worker ended".into()),
            trace: None,
        };
        s.learning_proposal_result(id, &unknown).unwrap();
        assert_eq!(
            s.finish_learning_at(id, now(), true).unwrap()["summary"]["outcome"],
            "unresolved"
        );
    }
    #[test]
    fn exact_root_allowance_is_valid_but_child_overrun_stops_learning() {
        let mut s = crate::test_store();
        let c = cycle(&mut s);
        let c = candidate(&s, &c);
        trials(&s, &c, Some("diagnostic"), false);
        let mid = c["trials"][0]["mission_id"].as_str().unwrap();
        let mut m = s.joint_mission(mid).unwrap();
        m["budget"]["tokens_accounted"] = m["input"]["budget"]["tokens"].clone();
        m["tasks"] = json!([]);
        s.db.execute(
            "UPDATE joint_missions SET body=$1 WHERE id=$2",
            params![m.to_string(), mid],
        )
        .unwrap();
        assert!(!s.learning_usage(&c).unwrap().1);
        m["budget"]["tokens_accounted"] = json!(384001);
        s.db.execute(
            "UPDATE joint_missions SET body=$1 WHERE id=$2",
            params![m.to_string(), mid],
        )
        .unwrap();
        assert!(s.learning_usage(&c).unwrap().1);
        assert!(s.learning_open(&c, now(), true).is_err());
        assert_eq!(
            s.finish_learning_at(c["id"].as_str().unwrap(), now(), true)
                .unwrap()["summary"]["outcome"],
            "unresolved"
        );
    }
    #[test]
    fn changed_policy_blocks_continuation_and_adoption() {
        let mut s = crate::test_store();
        let c = cycle(&mut s);
        let c = candidate(&s, &c);
        trials(&s, &c, Some("diagnostic"), false);
        let mut changed = c.clone();
        changed["policy"]["grader_digest"] = json!("other-grader");
        s.db.execute(
            "UPDATE learning_cycles SET body=$1 WHERE id=$2",
            params![changed.to_string(), c["id"].as_str().unwrap()],
        )
        .unwrap();
        assert!(s.learning_open(&changed, now(), true).is_err());
        assert_eq!(
            s.finish_learning_at(c["id"].as_str().unwrap(), now(), true)
                .unwrap()["summary"]["outcome"],
            "unresolved"
        );
        assert_eq!(
            s.learning_control().unwrap().unwrap()["practice_incumbent"]["build"],
            c["baseline"]["digest"]
        );
    }
    #[test]
    fn claimed_proposal_survives_reopen_without_redispatch() {
        let path = std::env::temp_dir().join(format!(
            "starbase-learning-{}-{}.sqlite",
            std::process::id(),
            now()
        ));
        let id;
        {
            let mut s = Store::open(path.to_str().unwrap()).unwrap();
            let c = cycle(&mut s);
            id = c["id"].as_str().unwrap().to_owned();
            s.claim_learning_proposal_at(&id, now(), true).unwrap();
        }
        {
            let s = Store::open(path.to_str().unwrap()).unwrap();
            assert_eq!(
                s.claim_learning_proposal_at(&id, now(), true).unwrap()["dispatch"],
                false
            );
            s.learning_proposal_result(&id, &proposal()).unwrap();
        }
        {
            let s = Store::open(path.to_str().unwrap()).unwrap();
            assert_eq!(
                s.learning_cycle(&id).unwrap()["proposal"]["result"],
                json!(proposal())
            );
        }
        std::fs::remove_file(path).unwrap();
    }
    #[test]
    fn bounds_and_incumbent_revision_prevent_lucky_retries_or_stale_adoption() {
        let mut s = crate::test_store();
        let c = cycle(&mut s);
        assert_eq!(
            s.learning_tick_at(0, now(), true).unwrap()["outcome"],
            "busy"
        );
        let c = candidate(&s, &c);
        trials(&s, &c, Some("diagnostic"), false);
        let mut control = s.learning_control().unwrap().unwrap();
        control["practice_incumbent"]["generation"] = json!(1);
        s.db.execute(
            "UPDATE learning_control SET body=$1",
            params![control.to_string()],
        )
        .unwrap();
        assert_eq!(
            s.finish_learning_at(c["id"].as_str().unwrap(), now(), true)
                .unwrap()["summary"]["outcome"],
            "unresolved"
        );
        assert_eq!(
            s.learning_tick_at(0, c["created_at"].as_f64().unwrap() + 1.0, true)
                .unwrap()["outcome"],
            "cooldown"
        );
        control["admitted_cycles"] = json!(2);
        s.db.execute(
            "UPDATE learning_control SET body=$1",
            params![control.to_string()],
        )
        .unwrap();
        assert_eq!(
            s.learning_tick_at(0, now() + 100.0, true).unwrap()["outcome"],
            "exhausted"
        );
    }
}
