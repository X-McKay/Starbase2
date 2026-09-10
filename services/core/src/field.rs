//! V4 read-only field agents and reviewed memory. SQL owns the authoritative ledger.
use crate::operations::hash;
use crate::{Result, Store, now, parameters as params, terminal};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct FieldInput {
    pub id: String,
    pub agent: String,
    pub target: String,
    pub inference: bool,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Finding {
    pub key: String,
    pub code: String,
    pub subject: String,
    pub line: u32,
    pub summary: String,
    pub recommendation: String,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct FieldReport {
    pub snapshot_digest: String,
    pub findings: Vec<Finding>,
    pub coverage: Vec<String>,
    pub memory: Value,
    pub advisory: Option<Value>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct MemoryReview {
    pub id: String,
    pub revision: u64,
    pub decision: String,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum InferenceAdmission {
    Admitted,
    Skipped,
    NotRequested,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct InferenceBudget {
    pub status: InferenceAdmission,
    pub reason: String,
    pub utc_day: u64,
    pub limit: u32,
    pub used: u64,
    pub next_eligible_at: f64,
}
#[derive(JsonSchema)]
#[allow(dead_code)]
pub struct FieldContract {
    pub input: FieldInput,
    pub report: FieldReport,
    pub memory_review: MemoryReview,
    pub duty: FieldDuty,
    pub inference_budget: Option<InferenceBudget>,
    pub repository_watch: crate::repositories::RepositoryWatch,
}
fn error(e: rusqlite::Error) -> String {
    e.to_string()
}
fn identity(s: &str) -> bool {
    !s.is_empty() && s.len() <= 100 && s.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-')
}
fn agent(s: &str) -> bool {
    matches!(s, "watchkeeper" | "reviewer")
}
pub(crate) fn enabled() -> bool {
    std::env::var("STARBASE_FIELD_ENABLED").map_or_else(
        |_| !std::env::var("STARBASE_ENV").is_ok_and(|v| v == "production"),
        |v| v == "true",
    ) && !std::env::var("STARBASE_ACCEPT_WORK").is_ok_and(|v| v == "false")
}
impl Store {
    pub fn field_build(&self, body: &Value) -> Result<Value> {
        let m = &body["manifest"];
        let a = m["agent"].as_str().unwrap_or("");
        let t = m["target"]["id"].as_str().unwrap_or("");
        if !agent(a) || !identity(t) || body["digest"] != hash(m) || m["authority"] != "read-only" {
            return Err("Invalid field build".into());
        }
        if let Some(limit) = m["target"].get("daily_inference_limit")
            && !limit.as_u64().is_some_and(|v| (1..=24).contains(&v))
        {
            return Err("Daily inference limit must be between 1 and 24".into());
        }
        if let Some(interval) = m["target"].get("inference_min_interval_seconds")
            && !interval.as_u64().is_some_and(|v| v <= 86400)
        {
            return Err("Inference minimum interval must be between 0 and 86400 seconds".into());
        }
        self.db
            .execute(
                "INSERT INTO field_builds VALUES ($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING",
                params![
                    body["digest"].as_str().unwrap(),
                    a,
                    t,
                    body.to_string(),
                    now()
                ],
            )
            .map_err(error)?;
        Ok(json!({"registered":true}))
    }
    pub fn field_run(&self, id: &str) -> Result<Value> {
        let body: String = self
            .db
            .query_row(
                "SELECT body FROM field_runs WHERE id=$1",
                params![id],
                |r| r.get(0),
            )
            .map_err(error)?;
        serde_json::from_str(&body).map_err(|e| e.to_string())
    }
    pub fn field_memory(&self) -> Result<Vec<Value>> {
        self.db
            .prepare("SELECT body FROM agent_memory ORDER BY at DESC LIMIT 500")
            .map_err(error)?
            .query_map(params![], |r| r.get::<_, String>(0))
            .map_err(error)?
            .map(|r| serde_json::from_str(&r.map_err(error)?).map_err(|e| e.to_string()))
            .collect()
    }
    pub fn field_snapshot(&self) -> Result<Value> {
        let read = |sql| -> Result<Vec<Value>> {
            self.db
                .prepare(sql)
                .map_err(error)?
                .query_map(params![], |r| r.get::<_, String>(0))
                .map_err(error)?
                .map(|r| serde_json::from_str(&r.map_err(error)?).map_err(|e| e.to_string()))
                .collect()
        };
        // Keep every bounded active run visible even after more than 100 later completions.
        let runs = read(self.db.dialect(
            "SELECT body FROM field_runs ORDER BY CASE WHEN json_extract(body,'$.state') IN ('completed','failed','cancelled') THEN 1 ELSE 0 END,at DESC LIMIT 120",
            "SELECT body FROM field_runs ORDER BY CASE WHEN body::jsonb->>'state' IN ('completed','failed','cancelled') THEN 1 ELSE 0 END,at DESC LIMIT 120",
        ))?;
        // Polling clients receive summaries; full source, advice and memory are detail-only.
        let runs: Vec<Value> = runs.into_iter().map(|r| {
            let report=&r["report"];
            let count=report["findings"].as_array().map_or(0,Vec::len);
            let partial=report["coverage"].as_array().is_some_and(|v| !v.is_empty());
            let summary=if report.is_null() {Value::Null} else {json!({
                "outcome":if partial {"partial"} else if count>0 {"findings"} else {"no_findings"},
                "finding_count":count,"simulation":r["snapshot"]["data"]["simulation"],
                "memory_status":report["memory"]["status"],"source_kind":"field",
                "advisory_status":report["advisory"]["status"],"advisory_reason":report["advisory"]["reason"]
            })};
            json!({"input":r["input"],"state":r["state"],"detail":r["detail"],"created_at":r["created_at"],"updated_at":r["updated_at"],"source_observed_at":r["snapshot"]["observed_at"],"inference_budget":r["inference_budget"],"summary":summary})
        }).collect();
        let builds = read(
            "SELECT body FROM (SELECT body,at,ROW_NUMBER() OVER (PARTITION BY agent,target ORDER BY at DESC) AS rank FROM field_builds) AS latest WHERE rank=1 ORDER BY at DESC LIMIT 100",
        )?;
        Ok(
            json!({"schema_version":4,"enabled":enabled(),"runs":runs,"builds":builds,
            "repositories":self.repositories()?,"observed_at":now(),"memory":self.field_memory()?,"duties":self.field_duties()?,"authority":"Read-only observations and local review drafts; no external writes"}),
        )
    }
    pub fn create_field(&mut self, input: &FieldInput) -> Result<Value> {
        self.create_field_at(input, now())
    }
    fn create_field_at(&mut self, input: &FieldInput, at: f64) -> Result<Value> {
        if !enabled() || std::env::var("STARBASE_ACCEPT_WORK").is_ok_and(|v| v == "false") {
            return Err("Field work is disabled".into());
        }
        if !identity(&input.id) || !agent(&input.agent) || !identity(&input.target) {
            return Err("Invalid field request".into());
        }
        if let Ok(old) = self.field_run(&input.id) {
            return if old["input"] == json!(input) {
                Ok(old)
            } else {
                Err("Run identity conflict".into())
            };
        }
        if input.target.starts_with("repo-")
            && !self.repositories()?.iter().any(|r| {
                r["id"] == input.target
                    && r["config"]["enabled"] == true
                    && r["config"]["removed"] == false
            })
        {
            return Err("Repository watch is paused or removed".into());
        }
        let snapshot = self.field_snapshot()?;
        if snapshot["runs"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|r| !terminal(r["state"].as_str().unwrap_or("")))
            .count()
            >= 20
        {
            return Err("Field queue budget reached".into());
        }
        let body: String=self.db.query_row("SELECT body FROM field_builds WHERE agent=$1 AND target=$2 ORDER BY at DESC LIMIT 1",
            params![input.agent,input.target],|r|r.get(0)).map_err(|_|"No registered target/build")?;
        let build: Value = serde_json::from_str(&body).unwrap();
        if input.inference
            && (build["manifest"]["target"]["allow_inference"] != true
                || std::env::var("STARBASE_INFERENCE_ENABLED").is_ok_and(|v| v == "false"))
        {
            return Err("Inference not authorized for this target".into());
        }
        let memory: Vec<_> = self
            .field_memory()?
            .into_iter()
            .filter(|m| {
                m["agent"] == input.agent
                    && m["target"] == input.target
                    && m["decision"] == "approve"
                    && m["target_digest"] == hash(&build["manifest"]["target"])
            })
            .take(30)
            .collect();
        let day = (at / 86400.0).floor() as u64;
        let limit = build["manifest"]["target"]["daily_inference_limit"]
            .as_u64()
            .unwrap_or(24) as u32;
        // The single authoritative Core serializes requests; the count and reservation
        // additionally commit together. Failed/cancelled/uncertain runs never refund a slot.
        let tx = self.db.transaction().map_err(error)?;
        let used: i64 = tx.query_row(tx.dialect(
            "SELECT COUNT(*) FROM field_runs WHERE at >= $1 AND at < $2 AND json_extract(body,'$.input.target')=$3 AND json_extract(body,'$.input.inference')=1 AND COALESCE(json_extract(body,'$.inference_budget.status'),'admitted')='admitted'",
            "SELECT COUNT(*) FROM field_runs WHERE at >= $1 AND at < $2 AND body::jsonb->'input'->>'target'=$3 AND body::jsonb->'input'->>'inference'='true' AND COALESCE(body::jsonb->'inference_budget'->>'status','admitted')='admitted'"
        ),params![day as f64 * 86400.0,(day + 1) as f64 * 86400.0,input.target],|r|r.get(0)).map_err(error)?;
        let interval = build["manifest"]["target"]["inference_min_interval_seconds"]
            .as_u64()
            .unwrap_or(0);
        let latest: f64 = tx.query_row(tx.dialect(
            "SELECT COALESCE(MAX(at),0.0) FROM field_runs WHERE json_extract(body,'$.input.target')=$1 AND json_extract(body,'$.input.inference')=1 AND COALESCE(json_extract(body,'$.inference_budget.status'),'admitted')='admitted'",
            "SELECT COALESCE(MAX(at),0.0) FROM field_runs WHERE body::jsonb->'input'->>'target'=$1 AND body::jsonb->'input'->>'inference'='true' AND COALESCE(body::jsonb->'inference_budget'->>'status','admitted')='admitted'"
        ),params![input.target],|r|r.get(0)).map_err(error)?;
        let next = if latest > 0.0 {
            latest + interval as f64
        } else {
            0.0
        };
        let admitted = input.inference && used < i64::from(limit) && at >= next;
        let budget = InferenceBudget {
            status: if !input.inference {
                InferenceAdmission::NotRequested
            } else if admitted {
                InferenceAdmission::Admitted
            } else {
                InferenceAdmission::Skipped
            },
            reason: if !input.inference {
                "Inference not requested"
            } else if admitted {
                "Daily inference slot reserved; failed or uncertain attempts are not refunded"
            } else if used >= i64::from(limit) {
                "Daily inference admission limit reached"
            } else {
                "Inference minimum interval has not elapsed"
            }
            .into(),
            utc_day: day,
            limit,
            used: used as u64 + u64::from(admitted),
            next_eligible_at: if admitted {
                at + interval as f64
            } else if used >= i64::from(limit) {
                next.max((day + 1) as f64 * 86400.0)
            } else {
                next
            },
        };
        let body = json!({"schema_version":4,"input":input,"build":build,"inference_budget":budget,"state":"queued","created_at":at,
            "updated_at":at,"snapshot":null,"report":null,"memory_snapshot":memory,
            "detail":"Awaiting durable read-only dispatch","events":[{"state":"queued","at":at}]});
        tx.execute(
            "INSERT INTO field_runs VALUES ($1,$2,$3)",
            params![input.id, body.to_string(), at],
        )
        .map_err(error)?;
        tx.commit().map_err(error)?;
        Ok(body)
    }
    pub fn field_update(&mut self, id: &str, action: &str, payload: Value) -> Result<Value> {
        let mut r = self.field_run(id)?;
        let state = r["state"].as_str().unwrap().to_string();
        if action == "snapshot" && !r["snapshot"].is_null() {
            return if r["snapshot"] == payload {
                Ok(r)
            } else {
                Err("Immutable field snapshot".into())
            };
        }
        if action == "finish" && !r["report"].is_null() {
            return if r["report"] == payload {
                Ok(r)
            } else {
                Err("Immutable field report".into())
            };
        }
        if terminal(&state) {
            return if action == state {
                Ok(r)
            } else {
                Err("Run is terminal".into())
            };
        }
        if action == "running" && state == "running" {
            return Ok(r);
        }
        match action {
            "running" if state == "queued" => {
                r["state"] = json!("running");
                r["detail"] = json!("Reading bounded provider evidence");
            }
            "snapshot" if state == "running" => {
                if payload["target"] != r["input"]["target"]
                    || payload["digest"] != hash(&payload["data"])
                {
                    return Err("Invalid source snapshot".into());
                }
                r["snapshot"] = payload;
            }
            "finish" if state == "running" && !r["snapshot"].is_null() => {
                let report: FieldReport =
                    serde_json::from_value(payload.clone()).map_err(|e| e.to_string())?;
                if report.snapshot_digest != r["snapshot"]["digest"]
                    || report.findings.len() > 100
                    || report.coverage.len() > 100
                {
                    return Err("Report coverage or identity invalid".into());
                }
                if r["inference_budget"]["status"] == "skipped"
                    && (payload["advisory"]["status"] != "skipped"
                        || payload["advisory"]["calls"] != 0
                        || payload["advisory"]["reason"] != r["inference_budget"]["reason"])
                {
                    return Err("Inference report contradicts retained budget decision".into());
                }
                for f in &report.findings {
                    if !identity(&f.key)
                        || f.summary.len() > 1000
                        || f.recommendation.len() > 1000
                        || f.subject.len() > 500
                    {
                        return Err("Finding budget invalid".into());
                    }
                }
                r["report"] = payload;
                r["state"] = json!("completed");
                r["detail"] = json!(if !report.coverage.is_empty() {
                    "Partial coverage; findings remain advisory"
                } else if report.findings.is_empty() {
                    "No findings within declared checks"
                } else {
                    "Advisory findings retained"
                });
            }
            "cancel_requested" => {
                r["state"] = json!("cancel_requested");
                r["detail"] = json!("Stop requested; waiting for durable acknowledgement");
            }
            "cancelled" if state == "cancel_requested" => {
                r["state"] = json!("cancelled");
            }
            "failed" => {
                r["state"] = json!("failed");
                r["detail"] = json!("Provider/workflow failed; no completion inferred");
            }
            _ => return Err("Field transition fenced".into()),
        }
        let at = now();
        r["updated_at"] = json!(at);
        let event = json!({"state":r["state"],"at":at,"action":action});
        r["events"].as_array_mut().unwrap().push(event);
        let tx = self.db.transaction().map_err(error)?;
        tx.execute(
            "UPDATE field_runs SET body=$1 WHERE id=$2",
            params![r.to_string(), id],
        )
        .map_err(error)?;
        if action == "finish" {
            for finding in r["report"]["findings"].as_array().unwrap() {
                let key = hash(&json!([id, finding["key"]]));
                let memory = json!({"id":key,"agent":r["input"]["agent"],"target":r["input"]["target"],
                    "target_digest":hash(&r["build"]["manifest"]["target"]),"source_run":id,"source_digest":r["snapshot"]["digest"],"observed_at":r["snapshot"]["observed_at"],
                    "finding":finding,"revision":0,"decision":"pending"});
                tx.execute(
                    "INSERT INTO agent_memory VALUES ($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING",
                    params![
                        key,
                        r["input"]["agent"].as_str().unwrap(),
                        r["input"]["target"].as_str().unwrap(),
                        memory.to_string(),
                        at
                    ],
                )
                .map_err(error)?;
            }
        }
        tx.commit().map_err(error)?;
        Ok(r)
    }
    pub fn review_memory(&mut self, input: &MemoryReview) -> Result<Value> {
        if !matches!(input.decision.as_str(), "approve" | "reject" | "revoke") {
            return Err("Invalid memory decision".into());
        }
        let tx = self.db.transaction().map_err(error)?;
        let body: String = tx
            .query_row(
                "SELECT body FROM agent_memory WHERE id=$1",
                params![input.id],
                |r| r.get(0),
            )
            .map_err(error)?;
        let mut memory: Value = serde_json::from_str(&body).unwrap();
        if memory["revision"] != input.revision {
            return Err("Memory revision changed; refresh before reviewing".into());
        }
        memory["revision"] = json!(input.revision + 1);
        memory["decision"] = json!(input.decision);
        let event = json!({"request":input,"at":now()});
        tx.execute(
            "INSERT INTO memory_reviews VALUES ($1,$2,$3)",
            params![hash(&event), input.id, event.to_string()],
        )
        .map_err(error)?;
        tx.execute(
            "UPDATE agent_memory SET body=$1 WHERE id=$2",
            params![memory.to_string(), input.id],
        )
        .map_err(error)?;
        tx.commit().map_err(error)?;
        Ok(memory)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn recurring_inference_opt_in_contract() {
        let duty: FieldDuty = serde_json::from_value(json!({"id":"reason","agent":"watchkeeper","target":"cluster-fixture","interval_seconds":300,"enabled":true,"generation":0,"inference":true})).unwrap();
        assert_eq!(json!(duty)["inference"], true);
    }
    fn inference_build(store: &Store, limit: u32, interval: u32, revision: u32) {
        let m = json!({"agent":"watchkeeper","target":{"id":"cluster-fixture","allow_inference":true,"daily_inference_limit":limit,"inference_min_interval_seconds":interval},"authority":"read-only","revision":revision});
        store
            .field_build(&json!({"manifest":m,"digest":hash(&m)}))
            .unwrap();
    }
    fn reasoning(id: &str) -> FieldInput {
        FieldInput {
            inference: true,
            ..input(id)
        }
    }
    #[test]
    fn daily_admission_retains_failure_duplicates_legacy_and_day_boundary() {
        let mut store = setup();
        inference_build(&store, 2, 0, 1);
        let a = store
            .create_field_at(&reasoning("legacy"), 86401.0)
            .unwrap();
        // Pre-upgrade inference requests count even without a budget object.
        let mut old = a.clone();
        old.as_object_mut().unwrap().remove("inference_budget");
        store
            .db
            .execute(
                "UPDATE field_runs SET body=$1 WHERE id=$2",
                params![old.to_string(), "legacy"],
            )
            .unwrap();
        store.field_update("legacy", "failed", json!({})).unwrap();
        let b = store
            .create_field_at(&reasoning("uncertain"), 86402.0)
            .unwrap();
        assert_eq!(b["inference_budget"]["used"], 2);
        assert_eq!(
            store
                .create_field_at(&reasoning("uncertain"), 86403.0)
                .unwrap(),
            b
        );
        store
            .field_update("uncertain", "failed", json!({}))
            .unwrap();
        inference_build(&store, 2, 0, 2);
        let skipped = store.create_field_at(&reasoning("skip"), 86404.0).unwrap();
        assert_eq!(skipped["input"]["inference"], true);
        assert_eq!(skipped["inference_budget"]["status"], "skipped");
        assert_eq!(skipped["inference_budget"]["used"], 2);
        assert_eq!(
            store.create_field_at(&input("plain"), 86405.0).unwrap()["inference_budget"]["status"],
            "not_requested"
        );
        let next = store
            .create_field_at(&reasoning("tomorrow"), 172800.0)
            .unwrap();
        assert_eq!(next["inference_budget"]["status"], "admitted");
        assert_eq!(next["inference_budget"]["used"], 1);
        // Skipped worker advice cannot forge a provider call; deterministic evidence can finish.
        store.field_update("skip", "running", json!({})).unwrap();
        let data = json!({"simulation":true});
        store.field_update("skip","snapshot",json!({"target":"cluster-fixture","digest":hash(&data),"data":data,"observed_at":86404.0})).unwrap();
        let mut report = json!({"snapshot_digest":hash(&data),"findings":[],"coverage":[],"memory":{"status":"disabled"},"advisory":{"status":"unverified","calls":1}});
        assert!(
            store
                .field_update("skip", "finish", report.clone())
                .is_err()
        );
        report["advisory"] =
            json!({"status":"skipped","calls":0,"reason":skipped["inference_budget"]["reason"]});
        assert_eq!(
            store.field_update("skip", "finish", report).unwrap()["state"],
            "completed"
        );
    }
    #[test]
    fn cooldown_spans_midnight_without_charging_skipped_observations() {
        let mut store = setup();
        inference_build(&store, 24, 3600, 1);
        store.create_field_at(&reasoning("late"), 86300.0).unwrap();
        store.field_update("late", "failed", json!({})).unwrap();
        let wait = store.create_field_at(&reasoning("early"), 86401.0).unwrap();
        assert_eq!(wait["inference_budget"]["status"], "skipped");
        assert_eq!(
            wait["inference_budget"]["reason"],
            "Inference minimum interval has not elapsed"
        );
        assert_eq!(wait["inference_budget"]["used"], 0);
        assert_eq!(wait["inference_budget"]["next_eligible_at"], 89900.0);
        assert_eq!(
            store.create_field_at(&reasoning("ready"), 89900.0).unwrap()["inference_budget"]["status"],
            "admitted"
        );
    }
    #[test]
    fn concurrent_manual_and_duty_requests_share_daily_reservations() {
        let store = setup();
        inference_build(&store, 5, 0, 1);
        let shared = std::sync::Arc::new(std::sync::Mutex::new(store));
        let tasks: Vec<_> = (0..12)
            .map(|i| {
                let shared = shared.clone();
                std::thread::spawn(move || {
                    let mut store = shared.lock().unwrap();
                    let run = store
                        .create_field_at(&reasoning(&format!("parallel-{i}")), 86410.0)
                        .unwrap();
                    store
                        .field_update(&format!("parallel-{i}"), "failed", json!({}))
                        .unwrap();
                    run["inference_budget"]["status"]
                        .as_str()
                        .unwrap()
                        .to_owned()
                })
            })
            .collect();
        let statuses: Vec<_> = tasks.into_iter().map(|t| t.join().unwrap()).collect();
        assert_eq!(statuses.iter().filter(|s| *s == "admitted").count(), 5);
        assert_eq!(statuses.iter().filter(|s| *s == "skipped").count(), 7);
    }
    #[test]
    fn old_duties_remain_deterministic_and_policy_denials_do_not_reserve() {
        let mut store = setup();
        let old = json!({"id":"observe","agent":"watchkeeper","target":"cluster-fixture","interval_seconds":300,"enabled":true,"generation":0});
        let mut duty: FieldDuty = serde_json::from_value(old.clone()).unwrap();
        assert!(!duty.inference);
        store
            .db
            .execute(
                "INSERT INTO field_duties VALUES ($1,$2)",
                params!["observe", old.to_string()],
            )
            .unwrap();
        assert_eq!(store.set_field_duty(&duty).unwrap()["inference"], false);
        duty.inference = true;
        duty.generation = 1;
        assert!(store.set_field_duty(&duty).is_err());
        assert!(store.create_field(&reasoning("denied")).is_err());
        inference_build(&store, 1, 0, 1);
        store.set_field_duty(&duty).unwrap();
        let run = store.field_tick("observe", 1, 42).unwrap();
        assert_eq!(run["input"]["inference"], true);
        assert_eq!(run["inference_budget"]["used"], 1);
        store
            .field_update(run["input"]["id"].as_str().unwrap(), "failed", json!({}))
            .unwrap();
        assert_eq!(
            store.create_field(&reasoning("manual")).unwrap()["inference_budget"]["status"],
            "skipped"
        );
        for limit in [0, 25] {
            let m = json!({"agent":"watchkeeper","target":{"id":"bad","daily_inference_limit":limit},"authority":"read-only"});
            assert!(
                store
                    .field_build(&json!({"manifest":m,"digest":hash(&m)}))
                    .is_err()
            );
        }
    }
    fn setup() -> Store {
        let store = crate::test_store();
        let m = json!({"agent":"watchkeeper","target":{"id":"cluster-fixture","allow_inference":false},"authority":"read-only"});
        store
            .field_build(&json!({"manifest":m,"digest":hash(&m)}))
            .unwrap();
        store
    }
    fn input(id: &str) -> FieldInput {
        FieldInput {
            id: id.into(),
            agent: "watchkeeper".into(),
            target: "cluster-fixture".into(),
            inference: false,
        }
    }
    fn complete(store: &mut Store, id: &str) {
        store.create_field(&input(id)).unwrap();
        store.field_update(id, "running", json!({})).unwrap();
        let data = json!({"simulation":true});
        store.field_update(id,"snapshot",json!({"target":"cluster-fixture","digest":hash(&data),"data":data,"observed_at":1000.0})).unwrap();
        store
            .field_update(
                id,
                "finish",
                json!(FieldReport {
                    snapshot_digest: hash(&data),
                    findings: vec![Finding {
                        key: "issue".into(),
                        code: "unready".into(),
                        subject: "test/pod".into(),
                        line: 0,
                        summary: "Not ready".into(),
                        recommendation: "Inspect".into()
                    }],
                    coverage: vec![],
                    memory: json!({"status":"empty"}),
                    advisory: None
                }),
            )
            .unwrap();
    }
    #[test]
    fn field_identity_evidence_and_scope() {
        let mut store = setup();
        let first = store.create_field(&input("one")).unwrap();
        assert_eq!(store.create_field(&input("one")).unwrap(), first);
        assert!(
            store
                .create_field(&FieldInput {
                    target: "other".into(),
                    ..input("two")
                })
                .is_err()
        );
        assert!(
            store
                .create_field(&FieldInput {
                    inference: true,
                    ..input("three")
                })
                .is_err()
        );
        complete(&mut store, "one");
        let list = store.field_snapshot().unwrap();
        assert!(list["runs"][0].get("snapshot").is_none());
        assert_eq!(list["runs"][0]["source_observed_at"], 1000.0);
        assert_eq!(list["runs"][0]["summary"]["finding_count"], 1);
        assert!(!store.field_run("one").unwrap()["snapshot"].is_null());
        assert!(store.field_update("one", "snapshot", json!({})).is_err());
        assert!(store.field_update("one", "running", json!({})).is_err());
    }
    #[test]
    fn reviewed_memory_freezes_and_revokes_without_awarding_authority() {
        let mut store = setup();
        complete(&mut store, "source");
        let m = store.field_memory().unwrap()[0].clone();
        assert_eq!(m["decision"], "pending");
        assert_eq!(
            store.create_field(&input("before")).unwrap()["memory_snapshot"],
            json!([])
        );
        let request = MemoryReview {
            id: m["id"].as_str().unwrap().into(),
            revision: 0,
            decision: "approve".into(),
        };
        store.review_memory(&request).unwrap();
        assert!(store.review_memory(&request).is_err());
        let frozen = store.create_field(&input("after")).unwrap();
        assert_eq!(frozen["memory_snapshot"].as_array().unwrap().len(), 1);
        store
            .review_memory(&MemoryReview {
                revision: 1,
                decision: "revoke".into(),
                ..request
            })
            .unwrap();
        assert_eq!(
            store.create_field(&input("revoked")).unwrap()["memory_snapshot"],
            json!([])
        );
        assert_eq!(
            store.field_run("after").unwrap()["memory_snapshot"],
            frozen["memory_snapshot"]
        );
    }
    #[test]
    fn capture_retry_and_active_history_remain_visible() {
        let mut store = setup();
        store.create_field(&input("old-active")).unwrap();
        let r = store
            .field_update("old-active", "running", json!({}))
            .unwrap();
        assert_eq!(
            store
                .field_update("old-active", "running", json!({}))
                .unwrap(),
            r
        );
        for i in 0..110 {
            complete(&mut store, &format!("done-{i}"));
        }
        assert!(
            store.field_snapshot().unwrap()["runs"]
                .as_array()
                .unwrap()
                .iter()
                .any(|r| r["input"]["id"] == "old-active")
        );
    }
    #[test]
    fn duty_generation_pause_and_tick_identity() {
        let mut store = setup();
        let mut d = FieldDuty {
            inference: false,
            id: "observe".into(),
            agent: "watchkeeper".into(),
            target: "cluster-fixture".into(),
            interval_seconds: 30,
            enabled: true,
            generation: 0,
        };
        store.set_field_duty(&d).unwrap();
        store.set_field_duty(&d).unwrap();
        assert_eq!(
            store.field_tick("observe", 0, 100).unwrap()["input"]["id"],
            "duty-observe-0-100"
        );
        assert_eq!(
            store.field_tick("observe", 0, 101).unwrap()["outcome"],
            "busy"
        );
        d.enabled = false;
        assert!(store.set_field_duty(&d).is_err());
        d.generation = 1;
        store.set_field_duty(&d).unwrap();
        assert_eq!(
            store.field_tick("observe", 0, 102).unwrap()["outcome"],
            "paused"
        );
        assert_eq!(
            store.field_tick("observe", 1, 102).unwrap()["outcome"],
            "paused"
        );
        assert_eq!(
            store.field_run("duty-observe-0-100").unwrap()["state"],
            "queued"
        );
    }
    #[test]
    fn stopped_work_cannot_publish_evidence_or_memory() {
        let mut store = setup();
        store.create_field(&input("stop")).unwrap();
        store
            .field_update("stop", "cancel_requested", json!({}))
            .unwrap();
        assert!(store.field_update("stop", "running", json!({})).is_err());
        assert!(store.field_update("stop", "finish", json!({})).is_err());
        store.field_update("stop", "cancelled", json!({})).unwrap();
        assert!(store.field_memory().unwrap().is_empty());
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct FieldDuty {
    pub id: String,
    pub agent: String,
    pub target: String,
    pub interval_seconds: u32,
    #[serde(default)]
    pub inference: bool,
    pub enabled: bool,
    pub generation: u32,
}
impl Store {
    pub fn field_duties(&self) -> Result<Vec<Value>> {
        let mut duties: Vec<Value> = self
            .db
            .prepare("SELECT body FROM field_duties ORDER BY id")
            .map_err(error)?
            .query_map(params![], |r| r.get::<_, String>(0))
            .map_err(error)?
            .map(|r| serde_json::from_str(&r.map_err(error)?).map_err(|e| e.to_string()))
            .collect::<Result<_>>()?;
        for duty in &mut duties {
            if duty.get("inference").is_none() {
                duty["inference"] = json!(false);
            }
        }
        for r in self.repositories()? {
            let c = &r["config"];
            duties.push(json!({"id":r["id"],"target":r["id"],"agent":"reviewer","enabled":c["enabled"]==true && c["removed"]!=true,"generation":c["generation"],"interval_seconds":c["interval_seconds"],"inference":false}));
        }
        Ok(duties)
    }
    pub fn set_field_duty(&self, duty: &FieldDuty) -> Result<Value> {
        if duty.id.starts_with("repo-")
            || duty.target.starts_with("repo-")
            || !identity(&duty.id)
            || duty.id.len() > 40
            || !agent(&duty.agent)
            || !identity(&duty.target)
            || !(30..=86400).contains(&duty.interval_seconds)
        {
            return Err("Invalid field duty".into());
        }
        if duty.enabled
            && (!enabled() || std::env::var("STARBASE_ACCEPT_WORK").is_ok_and(|v| v == "false"))
        {
            return Err("Work is disabled".into());
        }
        let present: i64 = self
            .db
            .query_row(
                "SELECT COUNT(*) FROM field_builds WHERE agent=$1 AND target=$2",
                params![duty.agent, duty.target],
                |r| r.get(0),
            )
            .map_err(error)?;
        if present == 0 {
            return Err("Target not registered".into());
        }
        if duty.enabled && duty.inference {
            let body: String = self.db.query_row("SELECT body FROM field_builds WHERE agent=$1 AND target=$2 ORDER BY at DESC LIMIT 1", params![duty.agent,duty.target],|r|r.get(0)).map_err(error)?;
            let build: Value = serde_json::from_str(&body).map_err(|e| e.to_string())?;
            if build["manifest"]["target"]["allow_inference"] != true
                || std::env::var("STARBASE_INFERENCE_ENABLED").is_ok_and(|v| v == "false")
            {
                return Err("Inference not authorized for this target".into());
            }
        }
        let old = self
            .field_duties()?
            .into_iter()
            .find(|d| d["id"] == duty.id);
        if old.as_ref() == Some(&json!(duty)) {
            return Ok(json!(duty));
        }
        let expected = old
            .as_ref()
            .map_or(0, |d| d["generation"].as_u64().unwrap() + 1);
        if u64::from(duty.generation) != expected {
            return Err("Stale duty generation".into());
        }
        if old.is_none()
            && self
                .field_duties()?
                .iter()
                .filter(|d| !d["id"].as_str().unwrap_or("").starts_with("repo-"))
                .count()
                >= 20
        {
            return Err("Duty budget reached".into());
        }
        self.db.execute("INSERT INTO field_duties VALUES ($1,$2) ON CONFLICT(id) DO UPDATE SET body=excluded.body",
            params![duty.id,serde_json::to_string(duty).unwrap()]).map_err(error)?;
        Ok(json!(duty))
    }
    pub fn field_tick(&mut self, id: &str, generation: u32, tick: u64) -> Result<Value> {
        let value = self
            .field_duties()?
            .into_iter()
            .find(|d| d["id"] == id)
            .ok_or("Duty not found")?;
        let d: FieldDuty = serde_json::from_value(value).map_err(|e| e.to_string())?;
        if !d.enabled || d.generation != generation || !enabled() {
            return Ok(json!({"outcome":"paused"}));
        }
        let snapshot = self.field_snapshot()?;
        if snapshot["runs"].as_array().unwrap().iter().any(|r| {
            r["input"]["agent"] == d.agent
                && r["input"]["target"] == d.target
                && !terminal(r["state"].as_str().unwrap_or(""))
        }) {
            return Ok(json!({"outcome":"busy"}));
        }
        self.create_field(&FieldInput {
            id: format!("duty-{}-{}-{}", id, generation, tick),
            agent: d.agent,
            target: d.target,
            inference: d.inference,
        })
    }
}
