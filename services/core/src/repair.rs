//! Core-owned repair policy, independent grading, and cosmetic outcome ledger.
use crate::parameters as params;
use crate::{Result, Store, now, operations::hash, terminal};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

pub fn digest(source: &str) -> String {
    format!("{:x}", Sha256::digest(source.as_bytes()))
}
fn error(e: rusqlite::Error) -> String {
    e.to_string()
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct RepairInput {
    pub id: String,
    pub scenario: String,
    pub mode: String,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Proposal {
    pub source: String,
    pub rationale: String,
    pub inference: Value,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Execution {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
    pub policy: Value,
    pub elapsed_ms: u64,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
pub struct Action {
    pub stage: String,
    pub digest: String,
    pub source: String,
    pub inputs: Vec<Value>,
    pub attempts: u32,
    pub state: String,
    pub observation: Option<Execution>,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Receipt {
    pub digest: String,
    pub attempt: u32,
    pub observation: Execution,
}
#[derive(Clone, Debug, Serialize, Deserialize, JsonSchema)]
pub struct RepairRecord {
    pub input: RepairInput,
    pub build: Value,
    pub revision: String,
    pub baseline: String,
    pub task: String,
    pub state: String,
    pub detail: String,
    pub created_at: f64,
    pub expires_at: f64,
    pub proposal: Option<Proposal>,
    pub actions: Vec<Action>,
    pub summary: Option<Value>,
    pub events: Vec<Value>,
}
#[derive(JsonSchema)]
#[allow(dead_code)]
pub struct RepairContract {
    pub input: RepairInput,
    pub record: RepairRecord,
    pub proposal: Proposal,
    pub receipt: Receipt,
    pub action: Action,
}
// Fixtures and expected answers stay in the core. Only inputs are sent into a VM.
fn scenario(name: &str) -> Result<(&'static str, &'static str, Vec<Value>, Vec<Value>)> {
    match name {
        "clamp-v1" => Ok((
            "def transform(value):\n    return min(value, 100)\n",
            "Fix transform(value): clamp an integer into the inclusive range 0..100. Preserve integers. Examples: 4 -> 4, 150 -> 100. Only change solution.py. Return its complete Python source.",
            vec![
                json!(-12),
                json!(0),
                json!(1),
                json!(99),
                json!(100),
                json!(135),
            ],
            vec![
                json!(0),
                json!(0),
                json!(1),
                json!(99),
                json!(100),
                json!(100),
            ],
        )),
        "dedupe-v1" => Ok((
            "def transform(value):\n    return sorted(set(value))\n",
            "Fix transform(value): remove duplicate integers from a list, preserving their first occurrence order. Example: [3,1,3] -> [3,1]. Empty input returns []. Only change solution.py. Return its complete Python source.",
            vec![
                json!([]),
                json!([3, 1, 3]),
                json!([2, 2, 2]),
                json!([0, -1, 0, 2, -1]),
                json!([9, 4, 1]),
                json!([1, 2, 3]),
            ],
            vec![
                json!([]),
                json!([3, 1]),
                json!([2]),
                json!([0, -1, 2]),
                json!([9, 4, 1]),
                json!([1, 2, 3]),
            ],
        )),
        _ => Err("Unknown repair scenario".into()),
    }
}
impl Store {
    pub fn register_repair_build(&self, b: &Value) -> Result<()> {
        if b["digest"].as_str() != Some(hash(&b["manifest"]).as_str())
            || b["manifest"]["profile"] != "mender-v1"
            || b["manifest"]["sandbox"]["version"] != "0.6.14"
        {
            return Err("Invalid repair build".into());
        }
        self.db
            .execute(
                "INSERT INTO repair_builds (digest,body) VALUES ($1,$2) ON CONFLICT DO NOTHING",
                params![b["digest"].as_str(), b.to_string()],
            )
            .map_err(error)?;
        Ok(())
    }
    pub fn repair(&self, id: &str) -> Result<RepairRecord> {
        let s: String = self
            .db
            .query_row("SELECT body FROM repairs WHERE id=$1", params![id], |r| {
                r.get(0)
            })
            .map_err(error)?;
        serde_json::from_str(&s).map_err(|e| e.to_string())
    }
    fn save_repair(&self, r: &RepairRecord) -> Result<()> {
        self.db
            .execute(
                "UPDATE repairs SET body=$1 WHERE id=$2",
                params![serde_json::to_string(r).unwrap(), r.input.id],
            )
            .map_err(error)?;
        Ok(())
    }
    pub fn create_repair(&self, i: &RepairInput) -> Result<Value> {
        if i.id.is_empty()
            || i.id.len() > 80
            || !i.id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
            || !matches!(
                i.mode.as_str(),
                "inference" | "control-good" | "control-bad" | "control-unchanged"
            )
        {
            return Err("Invalid repair request".into());
        }
        let (source, task, _, _) = scenario(&i.scenario)?;
        if let Ok(old) = self.repair(&i.id) {
            return if old.input == *i {
                Ok(json!({"id":i.id}))
            } else {
                Err("Repair id reused".into())
            };
        }
        if self
            .repair_list()?
            .iter()
            .filter(|r| !terminal(&r.state))
            .count()
            >= 4
        {
            return Err("Repair queue budget: four active missions".into());
        }
        let b: String = self
            .db
            .query_row(
                "SELECT body FROM repair_builds ORDER BY rowid DESC LIMIT 1",
                params![],
                |r| r.get(0),
            )
            .map_err(error)?;
        let r = RepairRecord {
            input: i.clone(),
            build: serde_json::from_str(&b).unwrap(),
            revision: digest(source),
            baseline: source.into(),
            task: task.into(),
            state: "queued".into(),
            detail: "Awaiting durable dispatch; synthetic repository".into(),
            created_at: now(),
            expires_at: now() + 600.,
            proposal: None,
            actions: vec![],
            summary: None,
            events: vec![json!({"at":now(),"state":"queued"})],
        };
        self.db
            .execute(
                "INSERT INTO repairs (id,body) VALUES ($1,$2)",
                params![i.id, serde_json::to_string(&r).unwrap()],
            )
            .map_err(error)?;
        Ok(json!({"id":i.id}))
    }
    pub fn repair_list(&self) -> Result<Vec<RepairRecord>> {
        let mut stmt = self
            .db
            .prepare("SELECT body FROM repairs ORDER BY rowid DESC")
            .map_err(error)?;
        stmt.query_map(params![], |row| row.get::<_, String>(0))
            .map_err(error)?
            .map(|row| serde_json::from_str(&row.map_err(error)?).map_err(|e| e.to_string()))
            .collect()
    }
    fn repair_open(r: &RepairRecord) -> Result<()> {
        if terminal(&r.state) || r.state == "cancel_requested" || r.expires_at < now() {
            Err("Repair is terminal, cancelled, or expired".into())
        } else {
            Ok(())
        }
    }
    pub fn repair_transition(&self, id: &str, state: &str, detail: &str) -> Result<()> {
        let mut r = self.repair(id)?;
        if r.state == state {
            return Ok(());
        }
        if terminal(&r.state)
            || !matches!(
                state,
                "proposing" | "cancel_requested" | "cancelled" | "failed"
            )
            || (state == "cancelled" && r.state != "cancel_requested")
            || (state == "proposing" && r.state != "queued")
        {
            return Err("Invalid repair transition".into());
        }
        r.state = state.into();
        r.detail = detail.chars().take(500).collect();
        r.events
            .push(json!({"at":now(),"state":state,"detail":r.detail}));
        self.save_repair(&r)
    }
    pub fn repair_proposal(&self, id: &str, p: Proposal) -> Result<()> {
        let mut r = self.repair(id)?;
        if let Some(old) = &r.proposal {
            return if old == &p {
                Ok(())
            } else {
                Err("Proposal immutable".into())
            };
        }
        Self::repair_open(&r)?;
        if r.state != "proposing"
            || p.source.len() > 16000
            || p.rationale.len() > 2000
            || p.inference.to_string().len() > 10000
        {
            return Err("Proposal state or size invalid".into());
        }
        r.proposal = Some(p);
        r.state = "authorized".into();
        r.detail = "Frozen solution.py proposal; execution requires a fresh policy check".into();
        r.events.push(json!({"at":now(),"state":r.state,"source_digest":digest(&r.proposal.as_ref().unwrap().source)}));
        self.save_repair(&r)
    }
    pub fn authorize_repair(&self, id: &str, stage: &str) -> Result<Action> {
        let mut r = self.repair(id)?;
        Self::repair_open(&r)?;
        if !matches!(stage, "baseline" | "candidate")
            || r.proposal.is_none()
            || r.revision != digest(scenario(&r.input.scenario)?.0)
        {
            return Err("Action denied: target, revision, or proposal".into());
        }
        if stage == "candidate"
            && !r
                .actions
                .iter()
                .any(|a| a.stage == "baseline" && a.observation.is_some())
        {
            return Err("Baseline evidence required".into());
        }
        let source = if stage == "baseline" {
            r.baseline.clone()
        } else {
            r.proposal.as_ref().unwrap().source.clone()
        };
        let action_digest = hash(
            &json!({"source":source,"revision":r.revision,"build":r.build["digest"],"stage":stage,"policy":"disposable-solution-py-v1"}),
        );
        let position = r.actions.iter().position(|a| a.stage == stage);
        let index = if let Some(i) = position {
            i
        } else {
            r.actions.push(Action {
                stage: stage.into(),
                digest: action_digest,
                source,
                inputs: scenario(&r.input.scenario)?.2,
                attempts: 0,
                state: "authorized".into(),
                observation: None,
            });
            r.actions.len() - 1
        };
        if r.actions[index].observation.is_some() {
            return Ok(r.actions[index].clone());
        }
        if r.actions[index].attempts >= 2 {
            return Err("Action retry budget exhausted; reconciliation required".into());
        }
        r.actions[index].attempts += 1;
        r.actions[index].state = "executing".into();
        let action = r.actions[index].clone();
        r.state = "executing".into();
        r.detail = format!(
            "{} attempt {}; no external write authority",
            stage, action.attempts
        );
        r.events.push(json!({"at":now(),"state":"executing","stage":stage,"attempt":action.attempts,"digest":action.digest}));
        self.save_repair(&r)?;
        Ok(action)
    }
    pub fn repair_receipt(&mut self, id: &str, stage: &str, receipt: Receipt) -> Result<()> {
        let mut r = self.repair(id)?;
        let index = r
            .actions
            .iter()
            .position(|a| a.stage == stage)
            .ok_or("No authorized action")?;
        let a = &r.actions[index];
        if let Some(old) = &a.observation {
            return if old == &receipt.observation && a.digest == receipt.digest {
                Ok(())
            } else {
                Err("Execution evidence immutable".into())
            };
        }
        Self::repair_open(&r)?;
        if a.digest != receipt.digest
            || a.attempts != receipt.attempt
            || receipt.observation.stdout.len() > 32768
            || receipt.observation.stderr.len() > 32768
            || receipt.observation.policy != r.build["manifest"]["sandbox"]
        {
            return Err("Receipt provenance or budget mismatch".into());
        }
        r.actions[index].observation = Some(receipt.observation);
        r.actions[index].state = "retained".into();
        r.events
            .push(json!({"at":now(),"state":"retained","stage":stage}));
        self.save_repair(&r)
    }
    pub fn finish_repair(&mut self, id: &str) -> Result<Value> {
        let mut r = self.repair(id)?;
        if let Some(s) = &r.summary {
            return Ok(s.clone());
        }
        Self::repair_open(&r)?;
        let expected = scenario(&r.input.scenario)?.3;
        let mut scores = vec![];
        let mut trial_results = vec![];
        let mut gates = vec![];
        for stage in ["baseline", "candidate"] {
            let a = r
                .actions
                .iter()
                .find(|a| a.stage == stage)
                .ok_or("Missing execution")?;
            let obs = a
                .observation
                .as_ref()
                .ok_or("Missing execution observation")?;
            let outputs: Option<Vec<Value>> = serde_json::from_str(&obs.stdout).ok();
            let valid =
                obs.exit_code == 0 && outputs.as_ref().is_some_and(|v| v.len() == expected.len());
            if !valid {
                gates.push(format!("{stage}: execution or output protocol failure"))
            }
            let passed: Vec<bool> = (0..expected.len())
                .map(|i| valid && outputs.as_ref().unwrap()[i] == expected[i])
                .collect();
            scores.push(passed.iter().filter(|&&b| b).count());
            trial_results.push(
                json!({"stage":stage,"passed":passed,"observed":outputs,"expected":expected}),
            );
        }
        let unchanged = r.proposal.as_ref().unwrap().source == r.baseline;
        let outcome = if !gates.is_empty() {
            "ineligible"
        } else if unchanged {
            "no_change"
        } else if scores[1] < scores[0] {
            "regressed"
        } else if scores[1] == expected.len() && scores[1] > scores[0] {
            "improved"
        } else {
            "inconclusive"
        };
        r.state = "completed".into();
        r.detail = format!("{outcome}: independent core grading retained");
        let tx = self.db.transaction().map_err(error)?;
        let mut xp = 0;
        if outcome == "improved" && r.input.mode == "inference" {
            let key = format!("{}:{}", r.input.scenario, r.revision);
            xp = 25
                * tx.execute(
                    "INSERT INTO credits VALUES ($1,'mender',$2,$3,25,$4) ON CONFLICT DO NOTHING",
                    params![key, id, r.build["digest"].as_str(), now()],
                )
                .map_err(error)?;
            tx.execute(
                "INSERT INTO qualifications (build,scenario,run_id) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING",
                params![r.build["digest"].as_str(), r.input.scenario, id],
            )
            .map_err(error)?;
        }
        let summary = json!({"outcome":outcome,"baseline_passed":scores[0],"candidate_passed":scores[1],"cases":expected.len(),"trials":trial_results,"hard_gate_failures":gates,"xp_awarded":xp,"synthetic_task":true,"execution":"real isolated microVM","qualification":"This exact build and fixture only; no production authority","uncertainty":"One repair on six fixed cases. No stochastic or general capability superiority claim.","cost_usd":r.proposal.as_ref().unwrap().inference["cost_usd"]});
        r.summary = Some(summary.clone());
        r.events
            .push(json!({"at":now(),"state":"completed","outcome":outcome,"xp_awarded":xp}));
        tx.execute(
            "UPDATE repairs SET body=$1 WHERE id=$2",
            params![serde_json::to_string(&r).unwrap(), id],
        )
        .map_err(error)?;
        tx.commit().map_err(error)?;
        Ok(summary)
    }
    pub fn progression(&self) -> Result<Value> {
        let mut stmt=self.db.prepare("SELECT outcome_key,run_id,build,xp,at FROM credits WHERE crew_id='mender' ORDER BY at").map_err(error)?;
        let credits:Vec<Value>=stmt.query_map(params![],|r|Ok(json!({"outcome_key":r.get::<_,String>(0)?,"run_id":r.get::<_,String>(1)?,"build":r.get::<_,String>(2)?,"xp":r.get::<_,i64>(3)?,"at":r.get::<_,f64>(4)?}))).map_err(error)?.collect::<std::result::Result<_,_>>().map_err(error)?;
        let xp: i64 = credits.iter().map(|v| v["xp"].as_i64().unwrap()).sum();
        let mut stmt = self
            .db
            .prepare("SELECT build,scenario,run_id FROM qualifications ORDER BY rowid")
            .map_err(error)?;
        let qualifications:Vec<Value>=stmt.query_map(params![],|r|Ok(json!({"build":r.get::<_,String>(0)?,"scenario":r.get::<_,String>(1)?,"run_id":r.get::<_,String>(2)?}))).map_err(error)?.collect::<std::result::Result<_,_>>().map_err(error)?;
        let mut achievements = vec![];
        if xp > 0 {
            achievements.push("First verified repair")
        }
        if xp >= 50 {
            achievements.push("Two distinct repairs")
        }
        let identity: (String, String) = self
            .db
            .query_row(
                "SELECT name,role FROM crew_members WHERE id='mender'",
                params![],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .map_err(error)?;
        Ok(
            json!({"id":"mender","name":identity.0,"role":identity.1,"xp":xp,"level":1+xp/50,"next_level_xp":(xp/50+1)*50,"achievements":achievements,"credits":credits,"qualifications":qualifications,"authority":"Disposable synthetic solution.py only; no workspace, network, or production effects"}),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn store() -> Store {
        let s = crate::test_store();
        let manifest = json!({"profile":"mender-v1","sandbox":{"version":"0.6.14"}});
        s.register_repair_build(&json!({"digest":hash(&manifest),"manifest":manifest}))
            .unwrap();
        s
    }
    fn queued(s: &Store, id: &str, mode: &str) {
        s.create_repair(&RepairInput {
            id: id.into(),
            scenario: "clamp-v1".into(),
            mode: mode.into(),
        })
        .unwrap();
    }
    fn propose(s: &Store, id: &str) {
        s.repair_transition(id, "proposing", "test").unwrap();
        s.repair_proposal(
            id,
            Proposal {
                source: "def transform(value):\n    return max(0,min(100,value))\n".into(),
                rationale: "test".into(),
                inference: json!({"calls":1}),
            },
        )
        .unwrap();
    }
    fn complete(s: &mut Store, id: &str, mode: &str, candidate: Value) -> Value {
        queued(s, id, mode);
        propose(s, id);
        for (stage, output) in [
            ("baseline", json!([-12, 0, 1, 99, 100, 100])),
            ("candidate", candidate),
        ] {
            let a = s.authorize_repair(id, stage).unwrap();
            s.repair_receipt(
                id,
                stage,
                Receipt {
                    digest: a.digest,
                    attempt: a.attempts,
                    observation: Execution {
                        exit_code: 0,
                        stdout: output.to_string(),
                        stderr: String::new(),
                        policy: json!({"version":"0.6.14"}),
                        elapsed_ms: 1,
                    },
                },
            )
            .unwrap();
        }
        s.finish_repair(id).unwrap()
    }
    #[test]
    fn independent_grader_rejects_claimed_success_and_regressions() {
        let mut s = store();
        assert_eq!(
            complete(&mut s, "bad", "inference", json!({"success":true}))["outcome"],
            "ineligible"
        );
        assert_eq!(
            complete(
                &mut s,
                "regression",
                "inference",
                json!([null, null, null, null, null, null])
            )["outcome"],
            "regressed"
        );
        assert_eq!(s.progression().unwrap()["xp"], 0);
    }
    #[test]
    fn progression_atomic_deduplicated_and_build_scoped() {
        let mut s = store();
        let summary = complete(&mut s, "one", "inference", json!([0, 0, 1, 99, 100, 100]));
        assert_eq!(summary["xp_awarded"], 25);
        assert_eq!(s.finish_repair("one").unwrap(), summary);
        assert_eq!(
            complete(&mut s, "two", "inference", json!([0, 0, 1, 99, 100, 100]))["xp_awarded"],
            0
        );
        let p = s.progression().unwrap();
        assert_eq!(p["xp"], 25);
        assert_eq!(p["qualifications"].as_array().unwrap().len(), 1);
        let manifest = json!({"profile":"mender-v1","sandbox":{"version":"0.6.14"},"changed":true});
        s.register_repair_build(&json!({"digest":hash(&manifest),"manifest":manifest}))
            .unwrap();
        queued(&s, "new", "inference");
        assert_ne!(
            s.repair("new").unwrap().build["digest"],
            p["qualifications"][0]["build"]
        );
        assert!(
            s.db.execute("UPDATE credits SET xp=100", params![])
                .is_err()
        );
    }
    #[test]
    fn controls_do_not_earn_progression() {
        let mut s = store();
        assert_eq!(
            complete(
                &mut s,
                "control",
                "control-good",
                json!([0, 0, 1, 99, 100, 100])
            )["outcome"],
            "improved"
        );
        assert_eq!(s.progression().unwrap()["xp"], 0);
    }
    #[test]
    fn authority_checks_revision_expiry_and_cancellation() {
        let s = store();
        queued(&s, "cancel", "inference");
        propose(&s, "cancel");
        assert!(s.authorize_repair("cancel", "workspace").is_err());
        assert!(s.authorize_repair("cancel", "candidate").is_err());
        s.repair_transition("cancel", "cancel_requested", "stop")
            .unwrap();
        assert!(s.authorize_repair("cancel", "baseline").is_err());
        queued(&s, "expired", "inference");
        propose(&s, "expired");
        let mut r = s.repair("expired").unwrap();
        r.expires_at = 0.;
        s.save_repair(&r).unwrap();
        assert!(s.authorize_repair("expired", "baseline").is_err());
        r.expires_at = now() + 60.;
        r.revision = "wrong".into();
        s.save_repair(&r).unwrap();
        assert!(s.authorize_repair("expired", "baseline").is_err());
    }
    #[test]
    fn duplicate_requests_frozen_evidence_and_retry_budget() {
        let s = store();
        queued(&s, "run", "inference");
        queued(&s, "run", "inference");
        propose(&s, "run");
        let first = s.authorize_repair("run", "baseline").unwrap();
        let second = s.authorize_repair("run", "baseline").unwrap();
        assert_eq!(first.digest, second.digest);
        assert_eq!(second.attempts, 2);
        assert!(s.authorize_repair("run", "baseline").is_err());
        assert!(
            s.repair_proposal(
                "run",
                Proposal {
                    source: "changed".into(),
                    rationale: String::new(),
                    inference: json!({})
                }
            )
            .is_err()
        );
    }
    #[test]
    fn migration_preserves_v2_and_reopen_preserves_progression() {
        let path = std::env::temp_dir().join(format!("starbase-v3-{}.sqlite", std::process::id()));
        {
            let mut s = Store::open(path.to_str().unwrap()).unwrap();
            let manifest = json!({"profile":"mender-v1","sandbox":{"version":"0.6.14"}});
            s.register_repair_build(&json!({"digest":hash(&manifest),"manifest":manifest}))
                .unwrap();
            complete(
                &mut s,
                "persist",
                "inference",
                json!([0, 0, 1, 99, 100, 100]),
            );
        }
        let s = Store::open(path.to_str().unwrap()).unwrap();
        assert_eq!(s.progression().unwrap()["xp"], 25);
        assert_eq!(s.repair("persist").unwrap().state, "completed");
        assert_eq!(s.operations_snapshot().unwrap()["schema_version"], 2);
        drop(s);
        std::fs::remove_file(path).unwrap();
    }
}
