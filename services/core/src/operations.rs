//! Local operations are owned by the core; worker observations cannot grant authority.
use crate::parameters as params;
use crate::{Result, Store, now, terminal};
use rusqlite::OptionalExtension;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct RunInput {
    pub id: String,
    pub kind: String,
    pub target: String,
    pub profile: String,
    #[serde(default)]
    pub candidate: Option<String>,
    #[serde(default)]
    pub inference: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Duty {
    pub id: String,
    pub target: String,
    pub profile: String,
    pub interval_seconds: u32,
    pub enabled: bool,
    pub generation: u32,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SourceFile {
    pub path: String,
    pub source: String,
    pub sha256: String,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Omission {
    pub path: String,
    pub reason: String,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SourceSnapshot {
    pub digest: String,
    pub files: Vec<SourceFile>,
    pub skipped: Vec<Omission>,
    pub redaction: String,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ReviewFinding {
    pub code: String,
    pub file: String,
    pub line: u32,
    pub message: String,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ReviewReport {
    pub snapshot_digest: String,
    pub findings: Vec<ReviewFinding>,
    pub errors: Vec<Omission>,
    pub files_reviewed: u32,
    pub elapsed_ms: u64,
    pub engine: String,
    pub model_calls: u32,
    #[serde(default)]
    pub advisory: Option<Value>,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct CaseTrial {
    pub case_id: String,
    pub profile: String,
    pub report: ReviewReport,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct RunReport {
    #[serde(default)]
    pub review: Option<ReviewReport>,
    #[serde(default)]
    pub trials: Vec<CaseTrial>,
}
#[derive(JsonSchema)]
#[allow(dead_code)]
pub struct OperationsContract {
    pub snapshot: OperationsSnapshot,
    pub run_record: RunRecord,
    pub run_input: RunInput,
    pub duty: Duty,
    pub source_snapshot: SourceSnapshot,
    pub run_report: RunReport,
}
fn db_err(e: rusqlite::Error) -> String {
    e.to_string()
}
pub fn hash(v: &Value) -> String {
    format!("{:x}", Sha256::digest(serde_json::to_vec(v).unwrap()))
}
fn identity(s: &str) -> bool {
    !s.is_empty() && s.len() <= 80 && s.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-')
}
fn profile(s: &str) -> bool {
    matches!(s, "surveyor-v1" | "surveyor-v2" | "surveyor-regressed")
}
fn target(s: &str) -> bool {
    matches!(s, "workspace" | "sample")
}

impl Store {
    pub fn register_build(&self, body: &Value) -> Result<()> {
        let digest = body["digest"].as_str().ok_or("missing build digest")?;
        if hash(&body["manifest"]) != digest
            || !profile(body["manifest"]["profile"].as_str().unwrap_or(""))
        {
            return Err("invalid build manifest".into());
        }
        self.db
            .execute(
                "INSERT INTO builds_v2 (digest,body) VALUES ($1,$2) ON CONFLICT DO NOTHING",
                params![digest, body.to_string()],
            )
            .map_err(db_err)?;
        Ok(())
    }
    pub fn create_run(&mut self, input: &RunInput) -> Result<Value> {
        if std::env::var("STARBASE_ACCEPT_WORK").is_ok_and(|v| v == "false") {
            return Err("Installation is quiesced; new work is disabled".into());
        }
        if input.inference
            && std::env::var("STARBASE_INFERENCE_ENABLED").is_ok_and(|v| v == "false")
        {
            return Err("Inference is disabled for this installation".into());
        }
        if !identity(&input.id)
            || !target(&input.target)
            || !profile(&input.profile)
            || !matches!(input.kind.as_str(), "review" | "evaluation")
            || (input.kind == "evaluation"
                && (input.inference || input.candidate.as_deref().is_none_or(|c| !profile(c))))
            || (input.kind == "review" && input.candidate.is_some())
            || (input.inference && input.target != "sample")
        {
            return Err("invalid run configuration".into());
        }
        let tx = self.db.transaction().map_err(db_err)?;
        let old: Option<String> = tx
            .query_row(
                "SELECT input FROM tasks_v2 WHERE id=$1",
                params![&input.id],
                |r| r.get(0),
            )
            .optional()
            .map_err(db_err)?;
        if let Some(old) = old {
            let old: Value = serde_json::from_str(&old).unwrap();
            if old["request"] == serde_json::to_value(input).unwrap() {
                return Ok(json!({"id":input.id}));
            }
            return Err("run id already used by another request".into());
        }
        let pending: u32 = tx.query_row("SELECT COUNT(*) FROM tasks_v2 WHERE state NOT IN ('completed','failed','cancelled')", params![], |r|r.get(0)).map_err(db_err)?;
        if pending >= 20 {
            return Err("local queue budget reached (20 pending runs)".into());
        }
        let mut builds = Vec::new();
        for p in std::iter::once(input.profile.as_str()).chain(input.candidate.as_deref()) {
            let b: String = tx.query_row(tx.dialect("SELECT body FROM builds_v2 WHERE json_extract(body,'$.manifest.profile')=$1 ORDER BY rowid DESC LIMIT 1", "SELECT body FROM builds_v2 WHERE (body::jsonb #>> '{manifest,profile}')=$1 ORDER BY rowid DESC LIMIT 1"), params![p], |r| r.get(0)).map_err(|_| "Compatible worker has not registered this build")?;
            builds.push(serde_json::from_str::<Value>(&b).unwrap());
        }
        let frozen = json!({"request":input,"builds":builds});
        let at = now();
        tx.execute(
            "INSERT INTO tasks_v2 (id,input,state,created_at,updated_at,detail,snapshot,report) VALUES ($1,$2,'queued',$3,$4,'Awaiting durable dispatch',NULL,NULL)",
            params![input.id, frozen.to_string(), at, at],
        )
        .map_err(db_err)?;
        tx.execute("INSERT INTO events_v2(task_id,at,state,detail) VALUES ($1,$2,'queued','Awaiting durable dispatch')", params![input.id,at]).map_err(db_err)?;
        tx.commit().map_err(db_err)?;
        Ok(json!({"id":input.id}))
    }
    pub fn run_detail(&self, id: &str) -> Result<Value> {
        let mut result = self.db.query_row("SELECT rowid,input,state,created_at,updated_at,detail,snapshot,report FROM tasks_v2 WHERE id=$1", params![id], |r| {
            let input: String = r.get(1)?;
            let snap: Option<String> = r.get(6)?;
            let report: Option<String> = r.get(7)?;
            Ok(json!({"sequence":r.get::<_,i64>(0)?,"input":serde_json::from_str::<Value>(&input).unwrap(),"state":r.get::<_,String>(2)?,"created_at":r.get::<_,f64>(3)?,"updated_at":r.get::<_,f64>(4)?,"detail":r.get::<_,String>(5)?,"snapshot":snap.map(|s|serde_json::from_str::<Value>(&s).unwrap()),"report":report.map(|s|serde_json::from_str::<Value>(&s).unwrap())}))
        }).map_err(|_| "run not found")?;
        let mut stmt = self
            .db
            .prepare(
                "SELECT sequence,at,state,detail FROM events_v2 WHERE task_id=$1 ORDER BY sequence",
            )
            .map_err(db_err)?;
        result["events"] = Value::Array(stmt.query_map(params![id], |r| Ok(json!({"sequence":r.get::<_,i64>(0)?,"at":r.get::<_,f64>(1)?,"state":r.get::<_,String>(2)?,"detail":r.get::<_,String>(3)?}))).map_err(db_err)?.collect::<std::result::Result<Vec<_>,_>>().map_err(db_err)?);
        Ok(result)
    }
    pub fn runs(&self, before: i64, active: bool) -> Result<Vec<Value>> {
        let sql = if active {
            "SELECT id FROM tasks_v2 WHERE state NOT IN ('completed','failed','cancelled') AND rowid<$1 ORDER BY rowid LIMIT 20"
        } else {
            "SELECT id FROM tasks_v2 WHERE rowid<$1 ORDER BY rowid DESC LIMIT 20"
        };
        let mut stmt = self.db.prepare(sql).map_err(db_err)?;
        let ids = stmt
            .query_map(params![before], |r| r.get::<_, String>(0))
            .map_err(db_err)?
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(db_err)?;
        ids.iter()
            .map(|id| {
                let mut r = self.run_detail(id)?;
                r.as_object_mut().unwrap().remove("snapshot");
                r.as_object_mut().unwrap().remove("events");
                if let Some(report) = r["report"].as_object_mut() {
                    report.remove("evidence");
                }
                Ok(r)
            })
            .collect()
    }
    pub fn run_transition(&mut self, id: &str, state: &str, detail: &str) -> Result<()> {
        if detail.len() > 1000 {
            return Err("detail too long".into());
        }
        let tx = self.db.transaction().map_err(db_err)?;
        let old: String = tx
            .query_row("SELECT state FROM tasks_v2 WHERE id=$1", params![id], |r| {
                r.get(0)
            })
            .map_err(db_err)?;
        if terminal(&old) {
            return if old == state {
                Ok(())
            } else {
                Err("terminal run is immutable".into())
            };
        }
        let valid = match state {
            "running" => matches!(old.as_str(), "queued" | "running"),
            "cancel_requested" => true,
            "cancelled" => old == "cancel_requested",
            "failed" => true,
            _ => false,
        };
        if !valid {
            return Err("invalid run transition".into());
        }
        let at = now();
        tx.execute(
            "UPDATE tasks_v2 SET state=$1,detail=$2,updated_at=$3 WHERE id=$4",
            params![state, detail, at, id],
        )
        .map_err(db_err)?;
        if old != state {
            tx.execute(
                "INSERT INTO events_v2(task_id,at,state,detail) VALUES ($1,$2,$3,$4)",
                params![id, at, state, detail],
            )
            .map_err(db_err)?;
        }
        tx.commit().map_err(db_err)
    }
    pub fn retain_snapshot(&mut self, id: &str, snapshot: &SourceSnapshot) -> Result<Value> {
        let mut body = serde_json::to_value(snapshot).unwrap();
        body.as_object_mut().unwrap().remove("digest");
        if hash(&body) != snapshot.digest
            || snapshot.files.len() > 200
            || snapshot.redaction != "literal-and-comment-v1"
        {
            return Err("invalid snapshot identity or budget".into());
        }
        let mut paths = std::collections::HashSet::new();
        for f in &snapshot.files {
            if f.path.starts_with('/')
                || f.path.split('/').any(|p| matches!(p, ".." | "." | ""))
                || !f.path.ends_with(".py")
                || !paths.insert(&f.path)
                || f.sha256.len() != 64
            {
                return Err("invalid snapshot path or digest".into());
            }
        }
        let current = self.run_detail(id)?;
        let body = serde_json::to_value(snapshot).unwrap();
        if !current["snapshot"].is_null() {
            return if current["snapshot"] == body {
                Ok(body)
            } else {
                Err("snapshot already frozen".into())
            };
        }
        if current["state"] != "running" {
            return Err("snapshot requires a running run".into());
        }
        self.db
            .execute(
                "UPDATE tasks_v2 SET snapshot=$1,updated_at=$2 WHERE id=$3",
                params![body.to_string(), now(), id],
            )
            .map_err(db_err)?;
        Ok(body)
    }
    pub fn retain_report(&mut self, id: &str, report: &RunReport) -> Result<Value> {
        let current = self.run_detail(id)?;
        let evidence = serde_json::to_value(report).unwrap();
        if !current["report"].is_null() {
            return if current["report"]["evidence"] == evidence {
                Ok(current["report"].clone())
            } else {
                Err("report already frozen".into())
            };
        }
        if current["state"] != "running" {
            return Err("completion fenced by run state".into());
        }
        let input: RunInput = serde_json::from_value(current["input"]["request"].clone()).unwrap();
        let mut summary = if input.kind == "review" {
            if !report.trials.is_empty() {
                return Err("review cannot include evaluation trials".into());
            }
            let r = report.review.as_ref().ok_or("missing review")?;
            let snapshot: SourceSnapshot = serde_json::from_value(current["snapshot"].clone())
                .map_err(|_| "snapshot missing")?;
            if r.snapshot_digest != snapshot.digest
                || r.files_reviewed as usize != snapshot.files.len()
                || r.engine != "ruff-0.16.6"
                || r.model_calls != 0
            {
                return Err("review provenance mismatch".into());
            }
            for f in &r.findings {
                let file = snapshot
                    .files
                    .iter()
                    .find(|s| s.path == f.file)
                    .ok_or("finding outside snapshot")?;
                if f.line == 0 || f.line as usize > file.source.lines().count() {
                    return Err("invalid finding citation".into());
                }
            }
            let outcome = if !r.errors.is_empty()
                || !snapshot.skipped.is_empty()
                || snapshot.files.is_empty()
            {
                "incomplete"
            } else if r.findings.is_empty() {
                "no_findings"
            } else {
                "findings"
            };
            json!({"outcome":outcome,"finding_count":r.findings.len(),"files_reviewed":r.files_reviewed,"qualification":"Advisory static analysis; not proof of repository safety","simulation":input.target=="sample"})
        } else {
            grade_campaign(&input, report)?
        };
        if input.kind == "review" && summary["outcome"] != "incomplete" {
            let previous: Option<(String,String,String)> = self.db.query_row(
                self.db.dialect("SELECT id,input,snapshot FROM tasks_v2 WHERE state='completed' AND json_extract(input,'$.request.kind')='review' AND json_extract(input,'$.request.target')=$1 ORDER BY rowid DESC LIMIT 1", "SELECT id,input,snapshot FROM tasks_v2 WHERE state='completed' AND (input::jsonb #>> '{request,kind}')='review' AND (input::jsonb #>> '{request,target}')=$1 ORDER BY rowid DESC LIMIT 1"),
                params![&input.target], |r|Ok((r.get(0)?,r.get(1)?,r.get(2)?))).optional().map_err(db_err)?;
            if let Some((id, frozen, source)) = previous {
                let frozen: Value = serde_json::from_str(&frozen).unwrap();
                let source: Value = serde_json::from_str(&source).unwrap();
                if frozen["builds"] == current["input"]["builds"]
                    && source["digest"] == current["snapshot"]["digest"]
                {
                    summary["observation"] = summary["outcome"].clone();
                    summary["outcome"] = json!("no_change");
                    summary["previous_run"] = json!(id);
                }
            }
        }
        let result = json!({"summary":summary,"evidence":evidence});
        let tx = self.db.transaction().map_err(db_err)?;
        tx.execute("UPDATE tasks_v2 SET report=$1,state='completed',detail='Evidence retained',updated_at=$2 WHERE id=$3",params![result.to_string(),now(),id]).map_err(db_err)?;
        tx.execute("INSERT INTO events_v2(task_id,at,state,detail) VALUES ($1,$2,'completed','Evidence retained')",params![id,now()]).map_err(db_err)?;
        tx.commit().map_err(db_err)?;
        Ok(result)
    }
    pub fn duties(&self) -> Result<Vec<Duty>> {
        let mut stmt = self.db.prepare("SELECT id,target,profile,interval_seconds,enabled,generation FROM duties_v2 ORDER BY id").map_err(db_err)?;
        stmt.query_map(params![], |r| {
            Ok(Duty {
                id: r.get(0)?,
                target: r.get(1)?,
                profile: r.get(2)?,
                interval_seconds: r.get(3)?,
                enabled: r.get(4)?,
                generation: r.get(5)?,
            })
        })
        .map_err(db_err)?
        .collect::<std::result::Result<Vec<_>, _>>()
        .map_err(db_err)
    }
    pub fn set_duty(&self, d: &Duty) -> Result<()> {
        if !identity(&d.id)
            || !target(&d.target)
            || !profile(&d.profile)
            || !(30..=86400).contains(&d.interval_seconds)
        {
            return Err("invalid duty; interval must be 30–86400 seconds".into());
        }
        self.db.execute("INSERT INTO duties_v2 VALUES ($1,$2,$3,$4,$5,1) ON CONFLICT(id) DO UPDATE SET target=excluded.target,profile=excluded.profile,interval_seconds=excluded.interval_seconds,enabled=excluded.enabled,generation=duties_v2.generation+1",params![d.id,d.target,d.profile,d.interval_seconds,d.enabled]).map_err(db_err)?;
        Ok(())
    }
    pub fn duty_tick(&mut self, id: &str, tick: &str) -> Result<Value> {
        let d = self
            .duties()?
            .into_iter()
            .find(|d| d.id == id)
            .ok_or("duty not found")?;
        if !d.enabled {
            return Ok(json!({"outcome":"paused"}));
        }
        let run_id = format!("duty-{}-{}", d.id, tick);
        if !identity(&run_id) {
            return Err("invalid tick identity".into());
        }
        let active = self.runs(i64::MAX, true)?;
        if active
            .iter()
            .any(|r| r["input"]["request"]["target"] == d.target)
        {
            return Ok(json!({"outcome":"busy"}));
        }
        self.create_run(&RunInput {
            id: run_id,
            kind: "review".into(),
            target: d.target,
            profile: d.profile,
            candidate: None,
            inference: false,
        })
    }
    pub fn heartbeat(&self) -> Result<()> {
        self.db.execute("INSERT INTO runtime_v2 VALUES (1,$1) ON CONFLICT(id) DO UPDATE SET seen=excluded.seen",params![now()]).map_err(db_err)?;
        Ok(())
    }
    pub fn operations_snapshot(&self) -> Result<Value> {
        let seen: Option<f64> = self
            .db
            .query_row("SELECT seen FROM runtime_v2 WHERE id=1", params![], |r| {
                r.get(0)
            })
            .optional()
            .map_err(db_err)?;
        let mut stmt = self
            .db
            .prepare("SELECT body FROM builds_v2 ORDER BY rowid DESC LIMIT 12")
            .map_err(db_err)?;
        let builds = stmt
            .query_map(params![], |r| r.get::<_, String>(0))
            .map_err(db_err)?
            .map(|r| r.map(|s| serde_json::from_str::<Value>(&s).unwrap()))
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(db_err)?;
        let count: u64 = self
            .db
            .query_row(
                self.db.dialect("SELECT COUNT(*) FROM tasks_v2 WHERE state='completed' AND json_extract(input,'$.request.kind')='review'", "SELECT COUNT(*) FROM tasks_v2 WHERE state='completed' AND (input::jsonb #>> '{request,kind}')='review'"),
                params![],
                |r| r.get(0),
            )
            .map_err(db_err)?;
        let evaluations:u64=self.db.query_row(self.db.dialect("SELECT COUNT(*) FROM tasks_v2 WHERE state='completed' AND json_extract(input,'$.request.kind')='evaluation'", "SELECT COUNT(*) FROM tasks_v2 WHERE state='completed' AND (input::jsonb #>> '{request,kind}')='evaluation'"),params![],|r|r.get(0)).map_err(db_err)?;
        let progression = self.progression()?;
        let repairs = self.repair_list()?;
        let snapshot = OperationsSnapshot {
            progression: Some(progression.clone()),
            repairs: repairs.clone(),
            field_runs: self.field_snapshot()?["runs"].as_array().unwrap().clone(),
            schema_version: 2,
            observed_at: now(),
            worker: WorkerStatus {
                seen_at: seen,
                available: seen.is_some_and(|t| now() - t < 5.),
            },
            targets: vec![
                Target {
                    id: "workspace".into(),
                    label: "This checkout".into(),
                    simulation: false,
                },
                Target {
                    id: "sample".into(),
                    label: "Training repository".into(),
                    simulation: true,
                },
            ],
            crew: vec![
                Crew {
                    id: "surveyor".into(),
                    name: "Surveyor".into(),
                    role: "Python repository review".into(),
                    completed_runs: count,
                    xp: 0,
                    authority: "Read configured Python files; no writes".into(),
                },
                Crew {
                    id: "trainer".into(),
                    name: "Trainer".into(),
                    role: "Controlled rule comparisons".into(),
                    completed_runs: evaluations,
                    xp: 0,
                    authority: "Synthetic fixtures only".into(),
                },
                Crew {
                    id: "mender".into(),
                    name: "Mender".into(),
                    role: "Isolated repair missions".into(),
                    completed_runs: repairs.iter().filter(|r| r.state == "completed").count()
                        as u64,
                    xp: progression["xp"].as_u64().unwrap_or(0) as u32,
                    authority: progression["authority"]
                        .as_str()
                        .unwrap_or("Unknown")
                        .into(),
                },
            ],
            builds: builds
                .into_iter()
                .map(|v| serde_json::from_value(v).unwrap())
                .collect(),
            duties: self.duties()?,
            active: self
                .runs(i64::MAX, true)?
                .into_iter()
                .map(|v| serde_json::from_value(v).unwrap())
                .collect(),
            recent: self
                .runs(i64::MAX, false)?
                .into_iter()
                .map(|v| serde_json::from_value(v).unwrap())
                .collect(),
        };
        Ok(serde_json::to_value(snapshot).unwrap())
    }
}
fn grade_campaign(input: &RunInput, report: &RunReport) -> Result<Value> {
    // Grader cases stay in the owner, outside the Ruff child. Public conformance,
    // not hidden generalization evidence and not authority/XP certification.
    let cases = [
        ("eval", "S307", 2),
        ("timeout", "S113", 2),
        ("mutable", "B006", 1),
        ("bare-except", "E722", 3),
        ("clean", "", 0),
        ("injection", "", 0),
    ];
    if report.review.is_some() || report.trials.len() != 12 {
        return Err("campaign needs twelve paired trials".into());
    }
    let mut seen = std::collections::HashSet::new();
    let mut scores = [0, 0];
    let mut gates = Vec::new();
    let mut invalid = false;
    let candidate = input.candidate.as_deref().ok_or("candidate missing")?;
    if candidate == input.profile {
        return Err("comparison requires distinct profiles".into());
    }
    for t in &report.trials {
        let side = if t.profile == input.profile {
            0
        } else if t.profile == candidate {
            1
        } else {
            return Err("unrecognized trial profile".into());
        };
        let (_, expected, line) = cases
            .iter()
            .find(|c| c.0 == t.case_id)
            .ok_or("unrecognized case")?;
        if !seen.insert((t.case_id.clone(), side)) {
            return Err("duplicate trial".into());
        }
        if t.report.engine != "ruff-0.16.6"
            || t.report.model_calls != 0
            || t.report.files_reviewed != 1
            || !t.report.errors.is_empty()
        {
            invalid = true;
        }
        if t.report
            .findings
            .iter()
            .any(|f| f.file != "case.py" || f.line == 0 || f.line > 8)
        {
            gates.push(format!("{}:{}:invalid citation", t.profile, t.case_id));
        }
        let matched = if expected.is_empty() {
            t.report.findings.is_empty()
        } else {
            t.report.findings.len() == 1
                && t.report.findings[0].code == *expected
                && t.report.findings[0].line == *line
        };
        if matched {
            scores[side] += 1;
        }
    }
    let outcome = if invalid {
        "invalid"
    } else if !gates.is_empty() {
        "ineligible"
    } else if scores[1] > scores[0] {
        "improved"
    } else if scores[1] < scores[0] {
        "regressed"
    } else {
        "inconclusive"
    };
    Ok(
        json!({"outcome":outcome,"baseline_passed":scores[0],"candidate_passed":scores[1],"cases":6,"trials":12,"hard_gate_failures":gates,"simulation":true,"cost_usd":0,"uncertainty":"Deterministic public conformance suite only. Equal scores do not establish equivalence; no generalization claim.","qualification":"No promotion, XP, or permission change"}),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    fn store() -> Store {
        let s = crate::test_store();
        for p in ["surveyor-v1", "surveyor-v2", "surveyor-regressed"] {
            let manifest = json!({"profile":p});
            s.register_build(&json!({"digest":hash(&manifest),"manifest":manifest}))
                .unwrap();
        }
        s
    }
    fn input(id: &str) -> RunInput {
        RunInput {
            id: id.into(),
            kind: "review".into(),
            target: "sample".into(),
            profile: "surveyor-v2".into(),
            candidate: None,
            inference: false,
        }
    }
    fn source() -> SourceSnapshot {
        let mut s = SourceSnapshot {
            digest: String::new(),
            files: vec![SourceFile {
                path: "case.py".into(),
                source: "pass\n".into(),
                sha256: "0".repeat(64),
            }],
            skipped: vec![],
            redaction: "literal-and-comment-v1".into(),
        };
        let mut v = serde_json::to_value(&s).unwrap();
        v.as_object_mut().unwrap().remove("digest");
        s.digest = hash(&v);
        s
    }
    fn report(s: &SourceSnapshot) -> RunReport {
        RunReport {
            review: Some(ReviewReport {
                snapshot_digest: s.digest.clone(),
                findings: vec![],
                errors: vec![],
                files_reviewed: 1,
                elapsed_ms: 2,
                engine: "ruff-0.16.6".into(),
                model_calls: 0,
                advisory: None,
            }),
            trials: vec![],
        }
    }
    #[test]
    fn completion_is_atomic_immutable_and_idempotent() {
        let mut s = store();
        let i = input("review-one");
        s.create_run(&i).unwrap();
        s.create_run(&i).unwrap();
        let mut changed = i.clone();
        changed.profile = "surveyor-v1".into();
        assert!(s.create_run(&changed).is_err());
        s.run_transition(&i.id, "running", "start").unwrap();
        let snap = source();
        s.retain_snapshot(&i.id, &snap).unwrap();
        let r = report(&snap);
        let result = s.retain_report(&i.id, &r).unwrap();
        assert_eq!(result["summary"]["outcome"], "no_findings");
        assert_eq!(result, s.retain_report(&i.id, &r).unwrap());
        let mut bad = r;
        bad.review.as_mut().unwrap().elapsed_ms = 10;
        assert!(s.retain_report(&i.id, &bad).is_err());
        assert_eq!(
            s.run_detail(&i.id).unwrap()["events"]
                .as_array()
                .unwrap()
                .len(),
            3
        );
    }
    #[test]
    fn stop_fences_late_results_and_preserves_snapshot() {
        let mut s = store();
        s.create_run(&input("stop")).unwrap();
        s.run_transition("stop", "running", "start").unwrap();
        let snap = source();
        s.retain_snapshot("stop", &snap).unwrap();
        s.run_transition("stop", "cancel_requested", "stop")
            .unwrap();
        assert!(s.retain_report("stop", &report(&snap)).is_err());
        s.run_transition("stop", "cancelled", "ack").unwrap();
        assert_eq!(
            s.run_detail("stop").unwrap()["snapshot"]["digest"],
            snap.digest
        );
    }
    #[test]
    fn invalid_citations_and_unfrozen_reports_are_rejected() {
        let mut s = store();
        s.create_run(&input("citation")).unwrap();
        s.run_transition("citation", "running", "start").unwrap();
        let snap = source();
        assert!(s.retain_report("citation", &report(&snap)).is_err());
        s.retain_snapshot("citation", &snap).unwrap();
        let mut r = report(&snap);
        r.review.as_mut().unwrap().findings.push(ReviewFinding {
            file: "outside.py".into(),
            line: 1,
            code: "S307".into(),
            message: "test".into(),
        });
        assert!(s.retain_report("citation", &r).is_err());
    }
    #[test]
    fn empty_scope_is_incomplete_and_workspace_inference_is_denied() {
        let mut s = store();
        let mut i = input("empty");
        i.inference = true;
        i.target = "workspace".into();
        assert!(s.create_run(&i).is_err());
        i.inference = false;
        s.create_run(&i).unwrap();
        s.run_transition("empty", "running", "start").unwrap();
        let mut snap = source();
        snap.files.clear();
        let mut v = serde_json::to_value(&snap).unwrap();
        v.as_object_mut().unwrap().remove("digest");
        snap.digest = hash(&v);
        s.retain_snapshot("empty", &snap).unwrap();
        let mut r = report(&snap);
        r.review.as_mut().unwrap().files_reviewed = 0;
        assert_eq!(
            s.retain_report("empty", &r).unwrap()["summary"]["outcome"],
            "incomplete"
        );
    }
    #[test]
    fn duty_pause_fences_dispatch_and_busy_ticks_do_not_flood() {
        let mut s = store();
        let mut d = Duty {
            id: "watch".into(),
            target: "sample".into(),
            profile: "surveyor-v2".into(),
            interval_seconds: 30,
            enabled: false,
            generation: 0,
        };
        s.set_duty(&d).unwrap();
        assert_eq!(s.duty_tick("watch", "1").unwrap()["outcome"], "paused");
        d.enabled = true;
        s.set_duty(&d).unwrap();
        s.duty_tick("watch", "2").unwrap();
        assert_eq!(s.duty_tick("watch", "3").unwrap()["outcome"], "busy");
        assert_eq!(s.runs(i64::MAX, true).unwrap().len(), 1);
    }
    #[test]
    fn archive_paging_never_hides_active_dispatch() {
        let mut s = store();
        for n in 0..25 {
            let id = format!("run-{n}");
            s.create_run(&input(&id)).unwrap();
            s.run_transition(&id, "failed", "test archived").unwrap();
        }
        s.create_run(&input("pending")).unwrap();
        let first = s.runs(i64::MAX, false).unwrap();
        assert_eq!(first.len(), 20);
        let second = s
            .runs(first.last().unwrap()["sequence"].as_i64().unwrap(), false)
            .unwrap();
        assert_eq!(second.len(), 6);
        assert_eq!(s.runs(i64::MAX, true).unwrap().len(), 1);
    }
    #[test]
    fn unchanged_snapshot_and_build_are_reported_without_new_qualification() {
        let mut s = store();
        let snap = source();
        for id in ["first", "second"] {
            s.create_run(&input(id)).unwrap();
            s.run_transition(id, "running", "start").unwrap();
            s.retain_snapshot(id, &snap).unwrap();
            s.retain_report(id, &report(&snap)).unwrap();
        }
        let r = s.run_detail("second").unwrap();
        assert_eq!(r["report"]["summary"]["outcome"], "no_change");
        assert_eq!(r["report"]["summary"]["previous_run"], "first");
        let projection = s.operations_snapshot().unwrap();
        assert_eq!(projection["crew"][0]["completed_runs"], 2);
        assert_eq!(projection["crew"][0]["xp"], 0);
        let _: OperationsSnapshot = serde_json::from_value(projection).unwrap();
    }
    #[test]
    fn grader_distinguishes_inconclusive_invalid_ineligible_and_incomplete() {
        let mut i = input("gym");
        i.kind = "evaluation".into();
        i.candidate = Some("surveyor-regressed".into());
        let mut r = RunReport {
            review: None,
            trials: vec![],
        };
        for p in ["surveyor-v2", "surveyor-regressed"] {
            for case in [
                "eval",
                "timeout",
                "mutable",
                "bare-except",
                "clean",
                "injection",
            ] {
                r.trials.push(CaseTrial {
                    case_id: case.into(),
                    profile: p.into(),
                    report: report(&source()).review.unwrap(),
                });
            }
        }
        assert_eq!(grade_campaign(&i, &r).unwrap()["outcome"], "inconclusive");
        r.trials[0].report.errors.push(Omission {
            path: "case.py".into(),
            reason: "engine failed".into(),
        });
        assert_eq!(grade_campaign(&i, &r).unwrap()["outcome"], "invalid");
        r.trials[0].report.errors.clear();
        r.trials[0].report.findings.push(ReviewFinding {
            code: "S307".into(),
            file: "elsewhere.py".into(),
            line: 1,
            message: "invalid".into(),
        });
        assert_eq!(grade_campaign(&i, &r).unwrap()["outcome"], "ineligible");
        r.trials.pop();
        assert!(grade_campaign(&i, &r).is_err());
    }
    #[test]
    fn v1_data_survives_migration() {
        let path =
            std::env::temp_dir().join(format!("starbase-migration-{}.sqlite", std::process::id()));
        let db = rusqlite::Connection::open(&path).unwrap();
        db.execute_batch(include_str!("../migration.sql")).unwrap();
        db.execute(
            "INSERT INTO missions (id,input,state,updated_at,detail) VALUES ('old','{}','completed',1,'retained')",
            [],
        )
        .unwrap();
        drop(db);
        let s = Store::open(path.to_str().unwrap()).unwrap();
        let state: String =
            s.db.query_row(
                "SELECT state FROM missions WHERE id='old'",
                params![],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(state, "completed");
        assert_eq!(
            s.db.query_row("PRAGMA user_version", params![], |r| r.get::<_, i64>(0))
                .unwrap(),
            5
        );
        drop(s);
        std::fs::remove_file(path).unwrap();
    }
}

// Published response projections: detail includes source and events, list omits them.
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
pub struct RegisteredBuild {
    pub digest: String,
    pub manifest: Value,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
pub struct FrozenInput {
    pub request: RunInput,
    pub builds: Vec<RegisteredBuild>,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
pub struct RunEvent {
    pub sequence: i64,
    pub at: f64,
    pub state: String,
    pub detail: String,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
pub struct RetainedReport {
    pub summary: Value,
    #[serde(default)]
    pub evidence: Option<RunReport>,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
pub struct RunRecord {
    pub sequence: i64,
    pub input: FrozenInput,
    pub state: String,
    pub created_at: f64,
    pub updated_at: f64,
    pub detail: String,
    #[serde(default)]
    pub snapshot: Option<SourceSnapshot>,
    #[serde(default)]
    pub report: Option<RetainedReport>,
    #[serde(default)]
    pub events: Vec<RunEvent>,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
pub struct WorkerStatus {
    pub seen_at: Option<f64>,
    pub available: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
pub struct Target {
    pub id: String,
    pub label: String,
    pub simulation: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
pub struct Crew {
    pub id: String,
    pub name: String,
    pub role: String,
    pub completed_runs: u64,
    pub xp: u32,
    pub authority: String,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
pub struct OperationsSnapshot {
    #[serde(default)]
    pub field_runs: Vec<Value>,
    #[serde(default)]
    pub progression: Option<Value>,
    #[serde(default)]
    pub repairs: Vec<crate::repair::RepairRecord>,
    pub schema_version: u32,
    pub observed_at: f64,
    pub worker: WorkerStatus,
    pub targets: Vec<Target>,
    pub crew: Vec<Crew>,
    pub builds: Vec<RegisteredBuild>,
    pub duties: Vec<Duty>,
    pub active: Vec<RunRecord>,
    pub recent: Vec<RunRecord>,
}
