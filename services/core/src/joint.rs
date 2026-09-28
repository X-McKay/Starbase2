//! V5 bounded simulation coordination. Core owns grants, claims and independent grading.
use crate::{Result, Store, now, operations::hash, parameters as params, terminal};
use rusqlite::OptionalExtension;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct JointBudget {
    #[schemars(range(min = 1, max = 24))]
    pub requests: u32,
    #[schemars(range(min = 1, max = 384000))]
    pub tokens: u64,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "kebab-case")]
pub enum Scenario {
    RouteMismatch,
    Healthy,
    PersistentDependency,
    ListeningButBroken,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct JointInput {
    pub id: String,
    pub opportunity: String,
    pub build: String,
    pub scenario: Scenario,
    pub inference: bool,
    pub budget: JointBudget,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct JointBuild {
    pub digest: String,
    pub manifest: Value,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    Lead,
    Workload,
    Service,
}
fn overview() -> String {
    "overview".into()
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct TaskReservation {
    pub id: String,
    pub role: Role,
    #[schemars(range(min = 0, max = 3))]
    pub round: u32,
    #[schemars(length(min = 1, max = 2000))]
    pub question: String,
    #[serde(default = "overview")]
    pub focus: String,
    #[schemars(range(min = 1, max = 384000))]
    pub tokens: u64,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub enum TaskStatus {
    Completed,
    Failed,
    Unknown,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Usage {
    pub input_tokens: u64,
    pub output_tokens: u64,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct TaskResult {
    pub status: TaskStatus,
    pub output: Value,
    pub usage: Option<Usage>,
    pub error: Option<String>,
    #[serde(default)]
    pub trace: Option<Value>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct JointFinish {
    pub decision: Option<Value>,
    pub reason: String,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct JointTask {
    pub id: String,
    pub role: Role,
    pub round: u32,
    pub question: String,
    pub focus: String,
    pub tokens: u64,
    pub reservation: TaskReservation,
    pub state: String,
    pub result: Option<TaskResult>,
    pub eligible: bool,
    pub accounted_tokens: u64,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct JointLedgerBudget {
    pub requests_reserved: u32,
    pub tokens_reserved: u64,
    pub tokens_accounted: u64,
    pub requests_limit: u32,
    pub tokens_limit: u64,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct JointMission {
    #[serde(default)]
    pub learning_cycle: Option<String>,
    pub input: JointInput,
    pub build: JointBuild,
    pub state: String,
    pub deadline: f64,
    pub created_at: f64,
    pub updated_at: f64,
    pub tasks: Vec<JointTask>,
    pub budget: JointLedgerBudget,
    pub decision: Option<Value>,
    pub outcome: Option<String>,
    pub reason: Option<String>,
    pub finish: Option<JointFinish>,
    pub simulation: bool,
    pub xp: u32,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct JointSnapshot {
    pub schema_version: u32,
    pub enabled: bool,
    pub simulation: bool,
    pub observed_at: f64,
    pub missions: Vec<JointMission>,
    pub builds: Vec<JointBuild>,
    #[serde(default)]
    pub opportunities: Vec<crate::joint_opportunities::TrainerOpportunity>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct JointClaim {
    pub dispatch: bool,
    pub task: JointTask,
}
#[derive(JsonSchema)]
#[allow(dead_code)]
pub struct JointContract {
    pub input: JointInput,
    pub build: JointBuild,
    pub reservation: TaskReservation,
    pub result: TaskResult,
    pub finish: JointFinish,
    pub mission: JointMission,
    pub snapshot: JointSnapshot,
    pub claim: JointClaim,
}
fn identity(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 100
        && s.bytes()
            .all(|c| c.is_ascii_alphanumeric() || b"-_".contains(&c))
}
pub fn enabled() -> bool {
    admission(
        std::env::var("STARBASE_JOINT_ENABLED")
            .as_deref()
            .unwrap_or(""),
        std::env::var("STARBASE_ENV").as_deref().unwrap_or(""),
        std::env::var("STARBASE_ACCEPT_WORK")
            .as_deref()
            .unwrap_or(""),
    )
}
fn admission(flag: &str, environment: &str, accepting: &str) -> bool {
    flag == "true" && environment != "production" && accepting != "false"
}
pub(crate) fn budget_dispatch_fenced(m: &Value) -> bool {
    budget_fence(m, true)
}
pub(crate) fn budget_overrun(m: &Value) -> bool {
    budget_fence(m, false)
}
fn budget_fence(m: &Value, inclusive: bool) -> bool {
    let root_spent = m["budget"]["tokens_accounted"].as_u64().unwrap_or(0);
    let root_exhausted = m["input"]["budget"]["tokens"]
        .as_u64()
        .or_else(|| m["budget"]["tokens_limit"].as_u64())
        .is_some_and(|limit| {
            if inclusive {
                root_spent >= limit
            } else {
                root_spent > limit
            }
        });
    let child_overrun = m["tasks"].as_array().is_some_and(|tasks| {
        tasks.iter().any(|task| {
            task["tokens"].as_u64().is_some_and(|grant| {
                let usage = &task["result"]["usage"];
                task["accounted_tokens"].as_u64().unwrap_or(0) > grant
                    || usage["input_tokens"]
                        .as_u64()
                        .zip(usage["output_tokens"].as_u64())
                        .is_some_and(|(input, output)| {
                            input.checked_add(output).is_none_or(|total| total > grant)
                        })
            })
        })
    });
    root_exhausted || child_overrun
}
fn live(m: &Value, at: f64) -> Result<()> {
    if m["input"]["inference"] == true
        && std::env::var("STARBASE_INFERENCE_ENABLED").is_ok_and(|v| v == "false")
    {
        return Err("Inference disabled".into());
    }
    if budget_dispatch_fenced(m) {
        return Err("Retained usage exhausted the root budget or exceeded a child grant; further dispatch is fenced".into());
    }
    if terminal(m["state"].as_str().unwrap_or("")) || at >= m["deadline"].as_f64().unwrap_or(0.0) {
        Err("Mission cancelled, completed or expired".into())
    } else {
        Ok(())
    }
}
impl Store {
    pub fn joint_build(&self, b: &JointBuild) -> Result<Value> {
        if b.manifest.to_string().len() > 131072
            || b.digest != hash(&b.manifest)
            || b.manifest["profile"] != "joint-readiness-v1"
            || b.manifest["authority"] != "simulation-observation-and-proposal"
            || !b.manifest["inference"].is_boolean()
        {
            return Err("Invalid immutable joint build".into());
        }
        let body = json!(b);
        let old: Option<String> = self
            .db
            .query_row(
                "SELECT body FROM joint_builds WHERE digest=$1",
                params![b.digest],
                |r| r.get(0),
            )
            .optional()
            .map_err(|e| e.to_string())?;
        if let Some(old) = old {
            return if serde_json::from_str::<Value>(&old).map_err(|e| e.to_string())? == body {
                Ok(body)
            } else {
                Err("Build identity conflict".into())
            };
        }
        let count: i64 = self
            .db
            .query_row("SELECT COUNT(*) FROM joint_builds", params![], |r| r.get(0))
            .map_err(|e| e.to_string())?;
        if count >= 100 {
            return Err("Joint build retention limit reached".into());
        }
        self.db
            .execute(
                "INSERT INTO joint_builds VALUES ($1,$2)",
                params![b.digest, body.to_string()],
            )
            .map_err(|e| e.to_string())?;
        Ok(body)
    }
    pub fn joint_mission(&self, id: &str) -> Result<Value> {
        let body: String = self
            .db
            .query_row(
                "SELECT body FROM joint_missions WHERE id=$1",
                params![id],
                |r| r.get(0),
            )
            .map_err(|e| e.to_string())?;
        serde_json::from_str(&body).map_err(|e| e.to_string())
    }
    pub fn joint_snapshot(&self) -> Result<Value> {
        let read = |sql| -> Result<Vec<Value>> {
            self.db
                .prepare(sql)
                .map_err(|e| e.to_string())?
                .query_map(params![], |r| r.get::<_, String>(0))
                .map_err(|e| e.to_string())?
                .map(|r| {
                    serde_json::from_str(&r.map_err(|e| e.to_string())?).map_err(|e| e.to_string())
                })
                .collect()
        };
        let missions = read("SELECT body FROM joint_missions ORDER BY at DESC LIMIT 100")?;
        let opportunities = crate::joint_opportunities::project(&missions);
        Ok(
            json!({"schema_version":5,"enabled":enabled(),"simulation":true,"observed_at":now(),"missions":missions,"builds":read("SELECT body FROM joint_builds ORDER BY digest LIMIT 100")?,"opportunities":opportunities}),
        )
    }
    pub fn create_joint(&self, input: &JointInput) -> Result<Value> {
        if !enabled() {
            return Err("Joint simulations disabled or installation stopped".into());
        }
        self.create_joint_at(input, now())
    }
    fn create_joint_at(&self, input: &JointInput, at: f64) -> Result<Value> {
        self.create_joint_scoped(input, at, None)
    }
    pub(crate) fn create_joint_learning(
        &self,
        input: &JointInput,
        cycle: &str,
        at: f64,
    ) -> Result<Value> {
        self.create_joint_scoped(input, at, Some(cycle))
    }
    fn create_joint_scoped(
        &self,
        input: &JointInput,
        at: f64,
        learning_cycle: Option<&str>,
    ) -> Result<Value> {
        if !identity(&input.id)
            || !identity(&input.opportunity)
            || input.budget.requests == 0
            || input.budget.requests > 24
            || input.budget.tokens == 0
            || input.budget.tokens > 384000
        {
            return Err("Invalid joint identity or budget".into());
        }
        let old: Option<String> = self
            .db
            .query_row(
                "SELECT body FROM joint_missions WHERE id=$1 OR opportunity=$2",
                params![input.id, input.opportunity],
                |r| r.get(0),
            )
            .optional()
            .map_err(|e| e.to_string())?;
        if let Some(old) = old {
            let old: Value = serde_json::from_str(&old).map_err(|e| e.to_string())?;
            return if old["input"] == json!(input) && old["learning_cycle"] == json!(learning_cycle)
            {
                Ok(old)
            } else {
                Err("Mission/opportunity identity conflict".into())
            };
        }
        let count: i64 = self
            .db
            .query_row("SELECT COUNT(*) FROM joint_missions", params![], |r| {
                r.get(0)
            })
            .map_err(|e| e.to_string())?;
        if count >= 100 {
            return Err("Joint mission retention limit reached".into());
        }
        let build: String = self
            .db
            .query_row(
                "SELECT body FROM joint_builds WHERE digest=$1",
                params![input.build],
                |r| r.get(0),
            )
            .map_err(|_| "Registered joint build required")?;
        let build: Value = serde_json::from_str(&build).map_err(|e| e.to_string())?;
        if build["manifest"]["inference"] != input.inference {
            return Err("Build inference mode mismatch".into());
        }
        if input.inference
            && std::env::var("STARBASE_INFERENCE_ENABLED").is_ok_and(|v| v == "false")
        {
            return Err("Inference disabled".into());
        }
        let m = json!({"learning_cycle":learning_cycle,"input":input,"build":build,"state":"queued","deadline":at+600.0,"created_at":at,"updated_at":at,"tasks":[],"budget":{"requests_reserved":0,"tokens_reserved":0,"tokens_accounted":0,"requests_limit":input.budget.requests,"tokens_limit":input.budget.tokens},"decision":null,"outcome":null,"reason":null,"finish":null,"simulation":true,"xp":0});
        self.db
            .execute(
                "INSERT INTO joint_missions VALUES ($1,$2,$3,$4)",
                params![input.id, input.opportunity, m.to_string(), at],
            )
            .map_err(|e| e.to_string())?;
        Ok(m)
    }
    fn save_joint(&self, old: &Value, mut new: Value) -> Result<Value> {
        new["updated_at"] = json!(now());
        let changed = self
            .db
            .execute(
                "UPDATE joint_missions SET body=$1 WHERE id=$2 AND body=$3",
                params![
                    new.to_string(),
                    old["input"]["id"].as_str().unwrap(),
                    old.to_string()
                ],
            )
            .map_err(|e| e.to_string())?;
        if changed != 1 {
            return Err("Mission changed; reconcile before retry".into());
        }
        Ok(new)
    }
    pub fn reserve_joint(&self, id: &str, r: &TaskReservation) -> Result<Value> {
        self.reserve_joint_at(id, r, now(), enabled())
    }
    fn reserve_joint_at(
        &self,
        id: &str,
        r: &TaskReservation,
        at: f64,
        admitted: bool,
    ) -> Result<Value> {
        let old = self.joint_mission(id)?;
        let role = serde_json::to_value(&r.role).unwrap();
        let role = role.as_str().unwrap();
        if r.id != format!("r{}-{role}", r.round)
            || r.round > 3
            || r.question.is_empty()
            || r.question.len() > 2000
            || r.tokens == 0
            || r.tokens > 384000
            || !matches!(
                (role, r.focus.as_str()),
                ("lead", "overview")
                    | ("workload", "overview" | "diagnostics")
                    | ("service", "work")
            )
        {
            return Err("Invalid member task".into());
        }
        if let Some(task) = old["tasks"]
            .as_array()
            .unwrap()
            .iter()
            .find(|t| t["id"] == r.id)
        {
            return if task["reservation"] == json!(r) {
                Ok(task.clone())
            } else {
                Err("Task identity conflict".into())
            };
        }
        if !admitted {
            return Err("Joint dispatch disabled".into());
        }
        self.learning_dispatch(&old)?;
        live(&old, at)?;
        let requests = old["budget"]["requests_reserved"].as_u64().unwrap() + 1;
        let tokens = old["budget"]["tokens_reserved"].as_u64().unwrap() + r.tokens;
        if requests > old["input"]["budget"]["requests"].as_u64().unwrap()
            || tokens > old["input"]["budget"]["tokens"].as_u64().unwrap()
        {
            return Err("Root budget exhausted".into());
        }
        let task = json!({"id":r.id,"role":r.role,"round":r.round,"question":r.question,"focus":r.focus,"tokens":r.tokens,"reservation":r,"state":"reserved","result":null,"eligible":false,"accounted_tokens":0});
        let mut m = old.clone();
        m["tasks"].as_array_mut().unwrap().push(task.clone());
        m["budget"]["requests_reserved"] = json!(requests);
        m["budget"]["tokens_reserved"] = json!(tokens);
        m["state"] = json!("running");
        self.save_joint(&old, m)?;
        Ok(task)
    }
    pub fn claim_joint(&self, id: &str, task_id: &str) -> Result<Value> {
        self.claim_joint_at(id, task_id, now(), enabled())
    }
    fn claim_joint_at(&self, id: &str, task_id: &str, at: f64, admitted: bool) -> Result<Value> {
        let old = self.joint_mission(id)?;
        let mut m = old.clone();
        let t = m["tasks"]
            .as_array_mut()
            .unwrap()
            .iter_mut()
            .find(|t| t["id"] == task_id)
            .ok_or("Task not found")?;
        if t["state"] != "reserved" {
            return Ok(json!({"dispatch":false,"task":t}));
        }
        if !admitted {
            return Err("Joint dispatch disabled".into());
        }
        self.learning_dispatch(&old)?;
        live(&old, at)?;
        t["state"] = json!("claimed");
        let result = json!({"dispatch":true,"task":t});
        self.save_joint(&old, m)?;
        Ok(result)
    }
    pub fn result_joint(&self, id: &str, task_id: &str, result: &TaskResult) -> Result<Value> {
        if json!(result).to_string().len() > 65536
            || result.error.as_ref().is_some_and(|e| e.len() > 2000)
        {
            return Err("Member reply exceeds bound".into());
        }
        let old = self.joint_mission(id)?;
        let mut m = old.clone();
        let t = m["tasks"]
            .as_array_mut()
            .unwrap()
            .iter_mut()
            .find(|t| t["id"] == task_id)
            .ok_or("Task not found")?;
        if !t["result"].is_null() {
            return if t["result"] == json!(result) {
                Ok(t.clone())
            } else {
                Err("Member reply immutable".into())
            };
        }
        if t["state"] != "claimed" {
            return Err("Only a claimed task can reply".into());
        }
        let grant = t["tokens"].as_u64().unwrap();
        let usage = result
            .usage
            .as_ref()
            .and_then(|u| u.input_tokens.checked_add(u.output_tokens));
        let provider_usage = old["input"]["inference"] != true
            || result
                .usage
                .as_ref()
                .is_some_and(|u| u.input_tokens > 0 && u.output_tokens > 0);
        let known =
            !matches!(result.status, TaskStatus::Unknown) && usage.is_some() && provider_usage;
        let accounted = if known { usage.unwrap() } else { grant };
        let eligible = matches!(result.status, TaskStatus::Completed)
            && known
            && accounted <= grant
            && result.error.is_none()
            && valid_member_output(t, &result.output);
        t["result"] = json!(result);
        t["state"] = json!(if eligible {
            "completed"
        } else if matches!(result.status, TaskStatus::Unknown) {
            "unknown"
        } else {
            "failed"
        });
        t["eligible"] = json!(eligible);
        t["accounted_tokens"] = json!(accounted);
        let task = t.clone();
        m["budget"]["tokens_accounted"] = json!(
            m["budget"]["tokens_accounted"]
                .as_u64()
                .unwrap()
                .saturating_add(accounted)
        );
        self.save_joint(&old, m)?;
        Ok(task)
    }
    pub fn cancel_joint(&self, id: &str) -> Result<Value> {
        let old = self.joint_mission(id)?;
        if terminal(old["state"].as_str().unwrap()) {
            return Ok(old);
        }
        let mut m = old.clone();
        m["state"] = json!("cancelled");
        m["outcome"] = json!("unresolved");
        m["reason"] = json!("Commander cancelled; already claimed work may still report usage");
        self.save_joint(&old, m)
    }
    pub fn finish_joint(&self, id: &str, f: &JointFinish) -> Result<Value> {
        if f.reason.is_empty() || f.reason.len() > 2000 || json!(f).to_string().len() > 8192 {
            return Err("Invalid finish payload".into());
        }
        let old = self.joint_mission(id)?;
        if !old["finish"].is_null() {
            return if old["finish"] == json!(f) {
                Ok(old)
            } else {
                Err("Final result immutable".into())
            };
        }
        if old["state"] == "cancelled" {
            return Ok(old);
        }
        if terminal(old["state"].as_str().unwrap()) {
            return Err("Final result immutable".into());
        }
        let tasks = old["tasks"].as_array().unwrap();
        if tasks.iter().any(|t| t["state"] == "claimed") {
            return Err("Reconcile active member claims before finish".into());
        }
        let mut m = old.clone();
        let decision = f.decision.as_ref();
        let action = decision.and_then(|d| d["action"].as_str()).unwrap_or("");
        let members = ["workload", "service"].iter().all(|role| {
            tasks
                .iter()
                .any(|t| t["role"] == *role && t["eligible"] == true)
        });
        let latest_lead = tasks
            .iter()
            .filter(|t| t["role"] == "lead")
            .max_by_key(|t| t["round"].as_u64().unwrap());
        let retained_decision = latest_lead.is_some_and(|lead| {
            lead["eligible"] == true
                && lead["result"]["output"]["tasks"] == json!([])
                && decision.is_some_and(|d| lead["result"]["output"]["decision"] == *d)
                && tasks
                    .iter()
                    .filter(|t| t["role"] != "lead")
                    .all(|t| t["round"].as_u64().unwrap() < lead["round"].as_u64().unwrap())
        });
        let clean = tasks.iter().all(|t| t["state"] == "completed");
        let shape = decision.is_some_and(valid_decision);
        let expected = match old["input"]["scenario"].as_str().unwrap() {
            "route-mismatch" => "repair",
            "healthy" => "wait",
            _ => "abstain",
        };
        let receipt = simulation_receipt(old["input"]["scenario"].as_str().unwrap());
        let bound = action == "abstain"
            || decision.is_some_and(|d| {
                d["revision"] == receipt["revision"]
                    && d["observation_id"] == receipt["observation_id"]
            });
        let correct = shape
            && bound
            && action == expected
            && (action != "repair"
                || decision.is_some_and(|d| {
                    d["readiness_path"] == "/ready" && d["liveness_path"] == "/live"
                }));
        let eligible = now() < old["deadline"].as_f64().unwrap()
            && clean
            && retained_decision
            && !tasks.is_empty()
            && (action == "abstain" || members);
        let outcome = if !eligible || decision.is_none() {
            "unresolved"
        } else if correct {
            "diagnostic-pass"
        } else {
            "diagnostic-fail"
        };
        m["state"] = json!(if outcome == "diagnostic-pass" {
            "completed"
        } else {
            "failed"
        });
        m["outcome"] = json!(outcome);
        m["decision"] = json!(f.decision);
        m["reason"] = json!(f.reason);
        m["finish"] = json!(f);
        self.save_joint(&old, m)
    }
}
fn bounded_text(value: &Value, max: usize) -> bool {
    value
        .as_str()
        .is_some_and(|s| !s.is_empty() && s.len() <= max)
}
pub(crate) fn valid_member_output(task: &Value, output: &Value) -> bool {
    let Some(object) = output.as_object() else {
        return false;
    };
    if task["role"] == "lead" {
        let Some(tasks) = output["tasks"].as_array() else {
            return false;
        };
        let decision = output["decision"].is_object();
        object
            .keys()
            .all(|k| matches!(k.as_str(), "tasks" | "decision" | "rationale"))
            && bounded_text(&output["rationale"], 1500)
            && tasks.len() <= 2
            && (tasks.is_empty() && decision || !tasks.is_empty() && output["decision"].is_null())
            && tasks.iter().all(|t| {
                t.as_object().is_some_and(|o| {
                    o.keys()
                        .all(|k| matches!(k.as_str(), "role" | "focus" | "question"))
                }) && matches!(
                    (t["role"].as_str(), t["focus"].as_str()),
                    (Some("workload"), Some("overview" | "diagnostics"))
                        | (Some("service"), Some("work"))
                ) && bounded_text(&t["question"], 1000)
            })
            && (tasks.len() != 2 || tasks[0]["role"] != tasks[1]["role"])
    } else {
        object.keys().all(|k| {
            matches!(
                k.as_str(),
                "diagnosis" | "evidence_ids" | "summary" | "uncertainty" | "next_question"
            )
        }) && matches!(
            output["diagnosis"].as_str(),
            Some(
                "probe_mismatch" | "healthy" | "dependency_failure" | "incorrect_work" | "unknown"
            )
        ) && output["evidence_ids"].as_array().is_some_and(|ids| {
            !ids.is_empty() && ids.len() <= 4 && ids.iter().all(|id| bounded_text(id, 64))
        }) && bounded_text(&output["summary"], 1500)
            && bounded_text(&output["uncertainty"], 1000)
            && (output["next_question"].is_null()
                || output["next_question"]
                    .as_str()
                    .is_some_and(|s| s.len() <= 1000))
    }
}
fn simulation_receipt(scenario: &str) -> Value {
    let revision = hash(&json!({"public_readiness_fixture":scenario}))[..40].to_string();
    let data = json!({"ready":matches!(scenario,"healthy"|"listening-but-broken"),"probes":{"readiness":if scenario=="route-mismatch"{"/health"}else{"/ready"},"liveness":"/live"}});
    json!({"revision":revision,"observation_id":hash(&json!({"revision":revision,"view":"manifest","data":data}))})
}
fn valid_decision(d: &Value) -> bool {
    let Some(obj) = d.as_object() else {
        return false;
    };
    if obj.keys().any(|k| {
        !matches!(
            k.as_str(),
            "action"
                | "observation_id"
                | "revision"
                | "readiness_path"
                | "liveness_path"
                | "rationale"
        )
    }) {
        return false;
    }
    let action = d["action"].as_str().unwrap_or("");
    if !matches!(action, "repair" | "wait" | "abstain")
        || d["rationale"]
            .as_str()
            .is_none_or(|s| s.is_empty() || s.len() > 1500)
    {
        return false;
    }
    if action != "abstain"
        && ["observation_id", "revision"]
            .iter()
            .any(|k| d[k].as_str().is_none_or(|s| s.is_empty() || s.len() > 200))
    {
        return false;
    }
    if action != "repair" && (!d["readiness_path"].is_null() || !d["liveness_path"].is_null()) {
        return false;
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    fn setup(store: &Store) -> JointInput {
        let manifest = json!({"profile":"joint-readiness-v1","authority":"simulation-observation-and-proposal","inference":false});
        let build = JointBuild {
            digest: hash(&manifest),
            manifest,
        };
        store.joint_build(&build).unwrap();
        let input = JointInput {
            id: "joint-1".into(),
            opportunity: "op-1".into(),
            build: build.digest,
            scenario: Scenario::RouteMismatch,
            inference: false,
            budget: JointBudget {
                requests: 4,
                tokens: 400,
            },
        };
        store.create_joint_at(&input, now()).unwrap();
        input
    }
    fn reserve(role: Role) -> TaskReservation {
        let name = serde_json::to_value(&role).unwrap();
        TaskReservation {
            id: format!("r0-{}", name.as_str().unwrap()),
            focus: if matches!(role, Role::Service) {
                "work"
            } else {
                "overview"
            }
            .into(),
            role,
            round: 0,
            question: "Inspect evidence".into(),
            tokens: 100,
        }
    }
    fn reply() -> TaskResult {
        TaskResult {
            status: TaskStatus::Completed,
            output: json!({"diagnosis":"unknown","evidence_ids":["retained-public-evidence"],"summary":"Public finding","uncertainty":"Public simulation","next_question":null}),
            usage: Some(Usage {
                input_tokens: 20,
                output_tokens: 10,
            }),
            error: None,
            trace: None,
        }
    }
    fn complete(store: &Store, role: Role) {
        let r = reserve(role);
        store.reserve_joint_at("joint-1", &r, now(), true).unwrap();
        assert_eq!(
            store.claim_joint_at("joint-1", &r.id, now(), true).unwrap()["dispatch"],
            true
        );
        store.result_joint("joint-1", &r.id, &reply()).unwrap();
    }
    fn lead_finish(store: &Store, id: &str, f: &JointFinish) {
        let mut r = reserve(Role::Lead);
        r.round = 1;
        r.id = "r1-lead".into();
        store.reserve_joint_at(id, &r, now(), true).unwrap();
        store.claim_joint_at(id, &r.id, now(), true).unwrap();
        let mut result = reply();
        result.output = json!({"tasks":[],"decision":f.decision,"rationale":f.reason});
        store.result_joint(id, &r.id, &result).unwrap();
    }
    fn finish() -> JointFinish {
        JointFinish {
            decision: Some(
                json!({"action":"repair","observation_id":simulation_receipt("route-mismatch")["observation_id"],"revision":simulation_receipt("route-mismatch")["revision"],"readiness_path":"/ready","liveness_path":"/live","rationale":"Compared routes and useful work"}),
            ),
            reason: "Coordinator reached proposal".into(),
        }
    }
    #[test]
    fn explicit_opt_in_never_enables_production_or_stopped_installation() {
        assert!(admission("true", "development", "true"));
        assert!(!admission("", "development", "true"));
        assert!(!admission("true", "production", "true"));
        assert!(!admission("true", "development", "false"));
    }
    #[test]
    fn input_and_opportunity_duplicates_cannot_change_build_or_budget() {
        let s = crate::test_store();
        let mut i = setup(&s);
        let first = s.joint_mission(&i.id).unwrap();
        assert_eq!(s.create_joint_at(&i, now()).unwrap(), first);
        i.id = "other".into();
        assert!(s.create_joint_at(&i, now()).is_err());
        i.id = "joint-1".into();
        i.budget.requests = 3;
        assert!(s.create_joint_at(&i, now()).is_err());
        assert_eq!(
            s.joint_snapshot().unwrap()["missions"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
    }
    #[test]
    fn reservations_are_atomic_bounded_and_exactly_idempotent() {
        let s = crate::test_store();
        setup(&s);
        let mut r = reserve(Role::Workload);
        r.tokens = 350;
        let first = s.reserve_joint_at("joint-1", &r, now(), true).unwrap();
        assert_eq!(
            s.reserve_joint_at("joint-1", &r, now(), true).unwrap(),
            first
        );
        r.question = "different".into();
        assert!(s.reserve_joint_at("joint-1", &r, now(), true).is_err());
        assert!(
            s.reserve_joint_at("joint-1", &reserve(Role::Service), now(), true)
                .is_err()
        );
        assert_eq!(
            s.joint_mission("joint-1").unwrap()["budget"]["requests_reserved"],
            1
        );
        assert_eq!(
            s.joint_mission("joint-1").unwrap()["budget"]["tokens_reserved"],
            350
        );
    }
    #[test]
    fn request_budget_is_independent_of_token_budget() {
        let s = crate::test_store();
        let mut i = setup(&s);
        i.id = "short".into();
        i.opportunity = "short".into();
        i.budget.requests = 1;
        s.create_joint_at(&i, now()).unwrap();
        s.reserve_joint_at("short", &reserve(Role::Workload), now(), true)
            .unwrap();
        assert!(
            s.reserve_joint_at("short", &reserve(Role::Service), now(), true)
                .is_err()
        );
    }
    #[test]
    fn claims_are_at_most_once_and_unknown_usage_is_not_free() {
        let s = crate::test_store();
        setup(&s);
        let r = reserve(Role::Workload);
        s.reserve_joint_at("joint-1", &r, now(), true).unwrap();
        assert_eq!(
            s.claim_joint_at("joint-1", &r.id, now(), true).unwrap()["dispatch"],
            true
        );
        assert_eq!(
            s.claim_joint_at("joint-1", &r.id, now(), true).unwrap()["dispatch"],
            false
        );
        let result = TaskResult {
            status: TaskStatus::Unknown,
            output: Value::Null,
            usage: None,
            error: Some("Worker lost request".into()),
            trace: None,
        };
        let first = s.result_joint("joint-1", &r.id, &result).unwrap();
        assert_eq!(first["accounted_tokens"], 100);
        assert_eq!(s.result_joint("joint-1", &r.id, &result).unwrap(), first);
        assert!(s.result_joint("joint-1", &r.id, &reply()).is_err());
        assert_eq!(
            s.finish_joint("joint-1", &finish()).unwrap()["outcome"],
            "unresolved"
        );
    }
    #[test]
    fn cancellation_fences_dispatch_but_retains_late_accounting() {
        let s = crate::test_store();
        setup(&s);
        let a = reserve(Role::Workload);
        let b = reserve(Role::Service);
        s.reserve_joint_at("joint-1", &a, now(), true).unwrap();
        s.reserve_joint_at("joint-1", &b, now(), true).unwrap();
        s.claim_joint_at("joint-1", &a.id, now(), true).unwrap();
        s.cancel_joint("joint-1").unwrap();
        assert!(s.claim_joint_at("joint-1", &b.id, now(), true).is_err());
        assert!(
            s.reserve_joint_at("joint-1", &reserve(Role::Lead), now(), true)
                .is_err()
        );
        s.result_joint("joint-1", &a.id, &reply()).unwrap();
        let m = s.finish_joint("joint-1", &finish()).unwrap();
        assert_eq!(m["state"], "cancelled");
        assert_eq!(m["budget"]["tokens_accounted"], 30);
        assert_eq!(m["xp"], 0);
    }
    #[test]
    fn deadline_and_installation_stop_fence_dispatch() {
        let s = crate::test_store();
        setup(&s);
        let r = reserve(Role::Workload);
        let deadline = s.joint_mission("joint-1").unwrap()["deadline"]
            .as_f64()
            .unwrap();
        assert!(s.reserve_joint_at("joint-1", &r, deadline, true).is_err());
        assert!(s.reserve_joint_at("joint-1", &r, now(), false).is_err());
        s.reserve_joint_at("joint-1", &r, now(), true).unwrap();
        assert!(s.claim_joint_at("joint-1", &r.id, deadline, true).is_err());
        assert!(s.claim_joint_at("joint-1", &r.id, now(), false).is_err());
    }
    #[test]
    fn independently_grades_members_paths_and_zero_progression() {
        let s = crate::test_store();
        setup(&s);
        complete(&s, Role::Workload);
        complete(&s, Role::Service);
        let f = finish();
        lead_finish(&s, "joint-1", &f);
        let m = s.finish_joint("joint-1", &f).unwrap();
        assert_eq!(m["outcome"], "diagnostic-pass");
        assert_eq!(m["simulation"], true);
        serde_json::from_value::<JointMission>(m.clone()).unwrap();
        serde_json::from_value::<JointSnapshot>(s.joint_snapshot().unwrap()).unwrap();
        assert_eq!(m["xp"], 0);
        assert_eq!(s.finish_joint("joint-1", &f).unwrap(), m);
        let mut different = finish();
        different.reason = "changed".into();
        assert!(s.finish_joint("joint-1", &different).is_err());
        let s = crate::test_store();
        setup(&s);
        complete(&s, Role::Workload);
        assert_eq!(
            s.finish_joint("joint-1", &f).unwrap()["outcome"],
            "unresolved"
        );
        let s = crate::test_store();
        setup(&s);
        complete(&s, Role::Workload);
        complete(&s, Role::Service);
        let mut f = finish();
        f.decision.as_mut().unwrap()["readiness_path"] = json!("/live");
        lead_finish(&s, "joint-1", &f);
        assert_eq!(
            s.finish_joint("joint-1", &f).unwrap()["outcome"],
            "diagnostic-fail"
        );
    }
    #[test]
    fn unaccounted_or_excess_usage_and_active_claims_cannot_succeed() {
        for usage in [
            None,
            Some(Usage {
                input_tokens: 100,
                output_tokens: 1,
            }),
        ] {
            let s = crate::test_store();
            setup(&s);
            let r = reserve(Role::Workload);
            s.reserve_joint_at("joint-1", &r, now(), true).unwrap();
            s.claim_joint_at("joint-1", &r.id, now(), true).unwrap();
            assert!(s.finish_joint("joint-1", &finish()).is_err());
            let mut result = reply();
            result.usage = usage;
            s.result_joint("joint-1", &r.id, &result).unwrap();
            if result.usage.is_some() {
                assert!(
                    s.reserve_joint_at("joint-1", &reserve(Role::Service), now(), true)
                        .is_err()
                );
            } else {
                complete(&s, Role::Service);
            }
            assert_eq!(
                s.finish_joint("joint-1", &finish()).unwrap()["outcome"],
                "unresolved"
            );
        }
    }
    #[test]
    fn claimed_state_and_results_survive_schema_reopen() {
        let path = std::env::temp_dir().join(format!(
            "starbase-joint-{}-{}.sqlite",
            std::process::id(),
            now()
        ));
        {
            let s = Store::open(path.to_str().unwrap()).unwrap();
            setup(&s);
            let r = reserve(Role::Workload);
            s.reserve_joint_at("joint-1", &r, now(), true).unwrap();
            s.claim_joint_at("joint-1", &r.id, now(), true).unwrap();
        }
        {
            let s = Store::open(path.to_str().unwrap()).unwrap();
            assert_eq!(
                s.claim_joint_at("joint-1", "r0-workload", now(), true)
                    .unwrap()["dispatch"],
                false
            );
            s.result_joint("joint-1", "r0-workload", &reply()).unwrap();
        }
        {
            let s = Store::open(path.to_str().unwrap()).unwrap();
            assert_eq!(
                s.joint_mission("joint-1").unwrap()["tasks"][0]["result"],
                json!(reply())
            );
        }
        std::fs::remove_file(path).unwrap();
    }
    #[test]
    fn wrong_receipt_and_candidate_verdict_cannot_certify_success() {
        for change in ["observation_id", "passed"] {
            let s = crate::test_store();
            setup(&s);
            complete(&s, Role::Workload);
            complete(&s, Role::Service);
            let mut f = finish();
            f.decision.as_mut().unwrap()[change] = json!("invented");
            lead_finish(&s, "joint-1", &f);
            assert_eq!(
                s.finish_joint("joint-1", &f).unwrap()["outcome"],
                "diagnostic-fail"
            );
        }
    }
    #[test]
    fn compare_and_swap_rejects_stale_budget_writes() {
        let s = crate::test_store();
        setup(&s);
        let before = s.joint_mission("joint-1").unwrap();
        s.reserve_joint_at("joint-1", &reserve(Role::Workload), now(), true)
            .unwrap();
        let mut stale = before.clone();
        stale["budget"]["tokens_reserved"] = json!(1);
        assert!(s.save_joint(&before, stale).is_err());
        assert_eq!(
            s.joint_mission("joint-1").unwrap()["budget"]["tokens_reserved"],
            100
        );
    }
    #[test]
    fn public_scenario_matrix_checks_wait_and_abstention() {
        for (scenario, name, action) in [
            (Scenario::Healthy, "healthy", "wait"),
            (
                Scenario::PersistentDependency,
                "persistent-dependency",
                "abstain",
            ),
            (
                Scenario::ListeningButBroken,
                "listening-but-broken",
                "abstain",
            ),
        ] {
            let s = crate::test_store();
            let mut input = setup(&s);
            input.id = "matrix".into();
            input.opportunity = "matrix".into();
            input.scenario = scenario;
            s.create_joint_at(&input, now()).unwrap();
            for role in [Role::Workload, Role::Service] {
                let r = reserve(role);
                s.reserve_joint_at("matrix", &r, now(), true).unwrap();
                s.claim_joint_at("matrix", &r.id, now(), true).unwrap();
                s.result_joint("matrix", &r.id, &reply()).unwrap();
            }
            let receipt = simulation_receipt(name);
            let f = JointFinish {
                decision: Some(
                    json!({"action":action,"observation_id":receipt["observation_id"],"revision":receipt["revision"],"rationale":"Checked both independent diagnostic surfaces"}),
                ),
                reason: "Scenario comparison".into(),
            };
            lead_finish(&s, "matrix", &f);
            assert_eq!(
                s.finish_joint("matrix", &f).unwrap()["outcome"],
                "diagnostic-pass"
            );
        }
    }
    #[test]
    fn build_admission_rejects_drift_and_mode_mismatch() {
        let s = crate::test_store();
        let mut i = setup(&s);
        let manifest = json!({"profile":"joint-readiness-v1","authority":"simulation-observation-and-proposal","inference":false});
        assert!(
            s.joint_build(&JointBuild {
                digest: "forged".into(),
                manifest
            })
            .is_err()
        );
        i.id = "reasoning".into();
        i.opportunity = "reasoning".into();
        i.inference = true;
        assert!(s.create_joint_at(&i, now()).is_err());
    }
    #[test]
    fn migration_from_v5_preserves_existing_records() {
        let path = std::env::temp_dir().join(format!(
            "starbase-joint-migration-{}-{}.sqlite",
            std::process::id(),
            now()
        ));
        {
            let s = Store::open(path.to_str().unwrap()).unwrap();
            s.db.execute(
                "INSERT INTO repository_watches VALUES ($1,$2)",
                params!["retained", "{\"sentinel\":true}"],
            )
            .unwrap();
            s.db.execute_batch(
                "DROP TABLE sdlc_discoveries; DROP TABLE sdlc_missions; DROP TABLE sdlc_policy; DROP TABLE repository_discovery; DROP TABLE learning_cycles; DROP TABLE learning_control; DROP TABLE joint_missions; DROP TABLE joint_builds; PRAGMA user_version=5;",
            )
            .unwrap();
        }
        {
            let s = Store::open(path.to_str().unwrap()).unwrap();
            setup(&s);
            let retained: String =
                s.db.query_row(
                    "SELECT body FROM repository_watches WHERE id=$1",
                    params!["retained"],
                    |r| r.get(0),
                )
                .unwrap();
            assert_eq!(
                serde_json::from_str::<Value>(&retained).unwrap(),
                json!({"sentinel":true})
            );
        }
        std::fs::remove_file(path).unwrap();
    }
    #[test]
    fn a_finish_payload_cannot_replace_the_missing_lead_response() {
        let s = crate::test_store();
        setup(&s);
        complete(&s, Role::Workload);
        complete(&s, Role::Service);
        assert_eq!(
            s.finish_joint("joint-1", &finish()).unwrap()["outcome"],
            "unresolved"
        );
    }
    #[test]
    fn malformed_completed_output_is_retained_but_ineligible() {
        let s = crate::test_store();
        setup(&s);
        let r = reserve(Role::Workload);
        s.reserve_joint_at("joint-1", &r, now(), true).unwrap();
        s.claim_joint_at("joint-1", &r.id, now(), true).unwrap();
        let mut result = reply();
        result.output = json!("not a finding");
        let retained = s.result_joint("joint-1", &r.id, &result).unwrap();
        assert_eq!(retained["eligible"], false);
        assert_eq!(retained["result"], json!(result));
    }
    #[test]
    fn final_decision_must_match_latest_lead_after_specialists() {
        for previous_round in [false, true] {
            let s = crate::test_store();
            setup(&s);
            complete(&s, Role::Workload);
            complete(&s, Role::Service);
            let f = finish();
            if previous_round {
                let r = reserve(Role::Lead);
                s.reserve_joint_at("joint-1", &r, now(), true).unwrap();
                s.claim_joint_at("joint-1", &r.id, now(), true).unwrap();
                let mut result = reply();
                result.output = json!({"tasks":[],"decision":f.decision,"rationale":f.reason});
                s.result_joint("joint-1", &r.id, &result).unwrap();
            } else {
                let mut other = finish();
                other.decision.as_mut().unwrap()["rationale"] =
                    json!("Different retained response");
                lead_finish(&s, "joint-1", &other);
            }
            assert_eq!(
                s.finish_joint("joint-1", &f).unwrap()["outcome"],
                "unresolved"
            );
        }
    }
    #[test]
    fn inference_zero_usage_and_integer_overflow_are_not_free() {
        for usage in [
            Usage {
                input_tokens: 0,
                output_tokens: 0,
            },
            Usage {
                input_tokens: u64::MAX,
                output_tokens: 1,
            },
        ] {
            let s = crate::test_store();
            let mut input = setup(&s);
            let manifest = json!({"profile":"joint-readiness-v1","authority":"simulation-observation-and-proposal","inference":true});
            let b = JointBuild {
                digest: hash(&manifest),
                manifest,
            };
            s.joint_build(&b).unwrap();
            input.id = "inference".into();
            input.opportunity = "inference".into();
            input.inference = true;
            input.build = b.digest;
            s.create_joint_at(&input, now()).unwrap();
            let r = reserve(Role::Workload);
            s.reserve_joint_at("inference", &r, now(), true).unwrap();
            s.claim_joint_at("inference", &r.id, now(), true).unwrap();
            let mut result = reply();
            result.usage = Some(usage);
            let retained = s.result_joint("inference", &r.id, &result).unwrap();
            assert_eq!(retained["eligible"], false);
            assert_eq!(retained["accounted_tokens"], 100);
        }
    }
    #[test]
    fn trainer_snapshot_is_derived_read_only_and_supports_older_responses() {
        let s = crate::test_store();
        setup(&s);
        s.finish_joint(
            "joint-1",
            &JointFinish {
                decision: None,
                reason: "Unresolved public simulation".into(),
            },
        )
        .unwrap();
        let retained = s.joint_mission("joint-1").unwrap();
        let first = s.joint_snapshot().unwrap();
        let second = s.joint_snapshot().unwrap();
        assert_eq!(first["opportunities"], second["opportunities"]);
        assert_eq!(first["opportunities"].as_array().unwrap().len(), 1);
        assert_eq!(s.joint_mission("joint-1").unwrap(), retained);
        let mut legacy = first;
        legacy.as_object_mut().unwrap().remove("opportunities");
        assert!(
            serde_json::from_value::<JointSnapshot>(legacy)
                .unwrap()
                .opportunities
                .is_empty()
        );
    }
    #[test]
    fn known_child_overrun_fences_new_reservations_and_reserved_peers() {
        let s = crate::test_store();
        let mut input = setup(&s);
        input.id = "overrun".into();
        input.opportunity = "overrun".into();
        input.budget.tokens = 98304;
        input.budget.requests = 4;
        s.create_joint_at(&input, now()).unwrap();
        let mut lead = reserve(Role::Lead);
        lead.tokens = 32768;
        let mut workload = reserve(Role::Workload);
        workload.tokens = 32768;
        let mut service = reserve(Role::Service);
        service.tokens = 32768;
        for r in [&lead, &workload, &service] {
            s.reserve_joint_at("overrun", r, now(), true).unwrap();
        }
        s.claim_joint_at("overrun", &lead.id, now(), true).unwrap();
        let mut lead_result = reply();
        lead_result.usage = Some(Usage {
            input_tokens: 50,
            output_tokens: 50,
        });
        lead_result.output =
            json!({"tasks":[],"decision":finish().decision,"rationale":"Public proposal"});
        s.result_joint("overrun", &lead.id, &lead_result).unwrap();
        s.claim_joint_at("overrun", &workload.id, now(), true)
            .unwrap();
        let mut result = reply();
        result.usage = Some(Usage {
            input_tokens: 99900,
            output_tokens: 100,
        });
        let retained = s.result_joint("overrun", &workload.id, &result).unwrap();
        assert_eq!(retained["state"], "failed");
        assert_eq!(retained["accounted_tokens"], 100000);
        assert_eq!(
            s.joint_mission("overrun").unwrap()["budget"]["tokens_accounted"],
            100100
        );
        assert!(
            s.claim_joint_at("overrun", &service.id, now(), true)
                .is_err()
        );
        // A separate root with spare reserved capacity still cannot spend after a child overrun.
        let s = crate::test_store();
        setup(&s);
        let r = reserve(Role::Workload);
        s.reserve_joint_at("joint-1", &r, now(), true).unwrap();
        s.claim_joint_at("joint-1", &r.id, now(), true).unwrap();
        let mut result = reply();
        result.usage = Some(Usage {
            input_tokens: 100,
            output_tokens: 1,
        });
        s.result_joint("joint-1", &r.id, &result).unwrap();
        assert!(
            s.reserve_joint_at("joint-1", &reserve(Role::Lead), now(), true)
                .is_err()
        );
    }

    #[test]
    fn overflowing_reported_usage_also_fences_dispatch_without_erasing_the_report() {
        let s = crate::test_store();
        setup(&s);
        let r = reserve(Role::Workload);
        let peer = reserve(Role::Service);
        for task in [&r, &peer] {
            s.reserve_joint_at("joint-1", task, now(), true).unwrap();
        }
        s.claim_joint_at("joint-1", &r.id, now(), true).unwrap();
        let mut result = reply();
        result.usage = Some(Usage {
            input_tokens: u64::MAX,
            output_tokens: 1,
        });
        let retained = s.result_joint("joint-1", &r.id, &result).unwrap();
        assert_eq!(retained["result"], json!(result));
        assert_eq!(retained["accounted_tokens"], 100);
        assert!(s.claim_joint_at("joint-1", &peer.id, now(), true).is_err());
        assert!(
            s.reserve_joint_at("joint-1", &reserve(Role::Lead), now(), true)
                .is_err()
        );
        // Retrying a retained result is still harmless and accounting remains unchanged.
        assert_eq!(s.result_joint("joint-1", &r.id, &result).unwrap(), retained);
    }
}
