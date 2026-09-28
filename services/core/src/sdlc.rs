//! Bounded algent pilot. Trusted observations are graded here, not by candidate code.
use crate::{Result, Store, now, operations::hash, parameters as params};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

const VERIFICATION_RETENTION_LIMIT: usize = 16;

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SdlcPolicy {
    pub repository: String,
    pub enabled: bool,
    pub publish: bool,
    pub generation: u64,
    pub max_missions: u32,
    pub expires_at: f64,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SdlcInput {
    pub id: String,
    pub repository: String,
    pub revision: String,
    pub opportunity: String,
    pub build: Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub capability_digest: Option<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SdlcEvent {
    pub key: String,
    pub stage: String,
    pub data: Value,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SdlcPublication {
    pub artifact_digest: String,
    pub revision: String,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct SdlcEffect {
    pub key: String,
    pub kind: String,
    pub data: Value,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SdlcRetry {
    pub id: String,
    pub build: Value,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SdlcVerificationInput {
    pub id: String,
    pub head: String,
    pub build: Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub feedback_digest: Option<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct SdlcPrObservation {
    pub number: u64,
    pub head: String,
    pub state: String,
    pub observed_at: f64,
}
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct SdlcContract {
    pub feedback: crate::sdlc_feedback::FeedbackInput,
    pub discovery: crate::sdlc_discovery::DiscoveryInput,
    pub pr_observation: SdlcPrObservation,
    pub verification: SdlcVerificationInput,
    pub retry: SdlcRetry,
    pub effect: SdlcEffect,
    pub policy: SdlcPolicy,
    pub input: SdlcInput,
    pub event: SdlcEvent,
    pub publication: SdlcPublication,
}
pub fn enabled() -> bool {
    std::env::var("STARBASE_SDLC_ENABLED").is_ok_and(|v| v == "true")
        && std::env::var("STARBASE_ACCEPT_WORK")
            .ok()
            .is_none_or(|v| v != "false")
        && std::env::var("STARBASE_SDLC_REPOSITORY")
            .is_ok_and(|v| v.eq_ignore_ascii_case("X-McKay/algent"))
}
pub fn verification_enabled() -> bool {
    enabled() && std::env::var("STARBASE_SDLC_VERIFICATION_ENABLED").is_ok_and(|v| v == "true")
}

/// Authored by Core owners, never loaded from a monitored repository or model output.
pub(crate) fn capabilities() -> Value {
    let mut catalog: Value = serde_json::from_str(include_str!(
        "../../../contracts/repository-capabilities.json"
    ))
    .expect("checked-in capability catalog");
    for contract in catalog["capabilities"].as_array_mut().unwrap() {
        contract["digest"] = json!(hash(contract));
    }
    catalog
}
pub(crate) fn capability(repository: &str, opportunity: &str) -> Option<Value> {
    capabilities()["capabilities"]
        .as_array()?
        .iter()
        .find(|c| {
            c["repository"]
                .as_str()
                .is_some_and(|r| r.eq_ignore_ascii_case(repository))
                && c["opportunity"] == opportunity
        })
        .cloned()
}
/// Explain current admission capacity, including unresolved external effects.
fn reserves_publication(v: &Value) -> bool {
    if v["publication"].is_null() {
        return false;
    }
    let observed = &v["pr_observation"];
    !matches!(observed["state"].as_str(), Some("closed" | "merged"))
        || now() - observed["observed_at"].as_f64().unwrap_or(0.0) > 60.0
}
fn has_active_verification(records: &[Value]) -> bool {
    records.iter().any(|v| {
        v["verifications"]
            .as_array()
            .is_some_and(|children| children.iter().any(|child| !verification_terminal(child)))
    })
}
fn coordination(records: &[Value], p: &Value, on: bool) -> Value {
    let catalog = capabilities();
    let reserved: Vec<&str> = catalog["capabilities"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|cap| {
            records.iter().any(|run| {
                reserves_publication(run) && run["input"]["opportunity"] == cap["opportunity"]
            })
        })
        .filter_map(|cap| cap["opportunity"].as_str())
        .collect();
    let reason = if !on || p["enabled"] != true {
        "disabled"
    } else if p["expires_at"].as_f64().unwrap_or(0.0) <= now() {
        "policy_expired"
    } else if records
        .iter()
        .any(|v| !terminal(v["state"].as_str().unwrap_or("")))
    {
        "active_mission"
    } else if has_active_verification(records) {
        "active_verification"
    } else if reserved.len() == catalog["capabilities"].as_array().unwrap().len() {
        "publication_requires_resolution"
    } else if records.len() >= 100 {
        "retention_capacity"
    } else if records
        .iter()
        .filter(|v| v["policy_generation"] == p["generation"])
        .count()
        >= p["max_missions"].as_u64().unwrap_or(0) as usize
    {
        "policy_budget"
    } else {
        "ready"
    };
    json!({"admission":reason,"can_discover":reason=="ready",
        "reserved_opportunities":reserved,
        "resolution":"Admission remains per capability; fresh closed/merged PR observation releases that reservation; uncertain publication remains held; no automatic merge"})
}

fn digest(v: &str, n: usize) -> bool {
    v.len() == n
        && v.bytes()
            .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
}
fn terminal(v: &str) -> bool {
    matches!(v, "failed" | "blocked" | "cancelled" | "awaiting_review")
}
fn observation_pass_for(run: &Value, family: &str) -> Option<bool> {
    let expected = json!({"history_all":[0,1,2,3,4],"history_last3":[2,3,4],"history_last1":[4],"history_zero":[],"history_empty":[],"history_context":[9],"history_mixed":[0,1,2,3,4]});
    let expected = match family {
        "persistence-history" => expected,
        "memory-key" => {
            json!({"memory_empty_key":[7],"memory_named":[9],"memory_missing":[],"memory_other_agent":[11],"memory_all":[7,9],"memory_zero":[0]})
        }
        "logging-level" => {
            json!({"logging_initial":[10],"logging_update":[20],"logging_error":[40],"logging_handlers":[1],"logging_omitted":[40],"logging_other":[30]})
        }
        _ => return None,
    };
    let cases = run["cases"].as_array()?;
    if cases.len() != expected.as_object()?.len() || run["exit_code"] != 0 {
        return None;
    }
    let mut ids = std::collections::BTreeSet::new();
    let mut pass = true;
    for case in cases {
        let id = case["id"].as_str()?;
        if !expected.as_object()?.contains_key(id) || !ids.insert(id) {
            return None;
        }
        let actual = case["actual"].as_array()?;
        if actual.len() > 100 || actual.iter().any(|v| v.as_i64().is_none()) {
            return None;
        }
        pass &= case["actual"] == expected[id];
    }
    Some(pass)
}
#[cfg(test)]
fn grade(v: &Value) -> Value {
    grade_for(v, "persistence-history")
}
fn grade_for(v: &Value, family: &str) -> Value {
    let baseline = observation_pass_for(&v["baseline"], family);
    let candidate = observation_pass_for(&v["candidate"], family);
    json!({"verdict":if baseline==Some(false)&&candidate==Some(true){"improved"}else{"ineligible"},"baseline_pass":baseline,"candidate_pass":candidate})
}
fn verification_context(parent: &Value) -> String {
    let family = parent["input"]["opportunity"]
        .as_str()
        .unwrap_or("persistence-history");
    if family == "persistence-history" {
        "starbase/persistence-regression".into()
    } else {
        format!("starbase/{family}-regression")
    }
}
fn verification_terminal(v: &Value) -> bool {
    matches!(
        v["state"].as_str(),
        Some("completed" | "blocked" | "cancelled")
    )
}
#[cfg(test)]
fn verification_grade(v: &Value) -> Value {
    verification_grade_for(v, "persistence-history")
}
fn verification_grade_for(v: &Value, family: &str) -> Value {
    let observations = &v["observations"];
    let public = &v["public"];
    let cases = observation_pass_for(observations, family);
    let outcome = if v.get("infrastructure_error").is_some_and(|e| !e.is_null())
        || observations["exit_code"].as_i64().is_none()
        || public["exit_code"].as_i64().is_none()
        || (observations["exit_code"] == 0 && cases.is_none())
    {
        "infrastructure_blocked"
    } else if observations["exit_code"] != 0 || public["exit_code"] != 0 {
        "failed"
    } else {
        match cases {
            Some(true) => "passed",
            Some(false) => "failed",
            None => "infrastructure_blocked",
        }
    };
    json!({"outcome":outcome,"oracle_pass":cases,"public_pass":public["exit_code"]==0,"scope":format!("Independent {} cases and trusted public regression; not application-wide verification",family)})
}

impl Store {
    fn sdlc_records(&self) -> Result<Vec<Value>> {
        self.db
            .prepare("SELECT body FROM sdlc_missions ORDER BY id")
            .map_err(|e| e.to_string())?
            .query_map(params![], |r| r.get::<_, String>(0))
            .map_err(|e| e.to_string())?
            .map(|r| {
                serde_json::from_str(&r.map_err(|e| e.to_string())?).map_err(|e| e.to_string())
            })
            .collect()
    }
    pub fn sdlc_policy(&self) -> Result<Value> {
        let rows: Vec<String> = self
            .db
            .prepare("SELECT body FROM sdlc_policy WHERE id='pilot'")
            .map_err(|e| e.to_string())?
            .query_map(params![], |r| r.get(0))
            .map_err(|e| e.to_string())?
            .collect::<std::result::Result<_, _>>()
            .map_err(|e| e.to_string())?;
        rows.first().map_or_else(||Ok(json!({"repository":"x-mckay/algent","enabled":false,"publish":false,"generation":0,"max_missions":1,"expires_at":0})),|s|serde_json::from_str(s).map_err(|e|e.to_string()))
    }
    pub fn sdlc_snapshot(&self) -> Result<Value> {
        Ok(
            json!({"schema_version":7,"enabled":enabled(),"verification_enabled":verification_enabled(),"policy":self.sdlc_policy()?,"missions":self.sdlc_records()?,"capability_catalog":capabilities(),"discoveries":self.sdlc_discoveries()?,"coordination":coordination(&self.sdlc_records()?, &self.sdlc_policy()?, enabled())}),
        )
    }
    pub fn sdlc_set_policy(&self, p: &SdlcPolicy) -> Result<Value> {
        self.sdlc_set_policy_at(p, enabled())
    }
    pub(crate) fn sdlc_set_policy_at(&self, p: &SdlcPolicy, on: bool) -> Result<Value> {
        if !p.repository.eq_ignore_ascii_case("x-mckay/algent")
            || !(1..=3).contains(&p.max_missions)
            || !p.expires_at.is_finite()
            || (p.enabled && (!on || p.expires_at <= now() || p.expires_at > now() + 604800.0))
        {
            return Err("Invalid or disabled SDLC policy".into());
        }
        let old = self.sdlc_policy()?;
        if old["generation"].as_u64() != Some(p.generation) {
            return Err("Stale SDLC policy generation".into());
        }
        let mut result = json!(p);
        result["repository"] = json!("x-mckay/algent");
        result["generation"] = json!(p.generation + 1);
        self.db.execute("INSERT INTO sdlc_policy(id,body) VALUES('pilot',$1) ON CONFLICT(id) DO UPDATE SET body=excluded.body",params![result.to_string()]).map_err(|e|e.to_string())?;
        Ok(result)
    }
    pub fn sdlc_mission(&self, id: &str) -> Result<Value> {
        self.sdlc_records()?
            .into_iter()
            .find(|v| v["id"] == id)
            .ok_or("Unknown SDLC mission".into())
    }
    pub(crate) fn sdlc_save(&self, v: &Value) -> Result<Value> {
        self.db
            .execute(
                "UPDATE sdlc_missions SET body=$1 WHERE id=$2",
                params![v.to_string(), v["id"].as_str().unwrap()],
            )
            .map_err(|e| e.to_string())?;
        Ok(v.clone())
    }
    pub fn sdlc_admit(&self, i: &SdlcInput) -> Result<Value> {
        self.sdlc_admit_at(i, enabled())
    }
    pub(crate) fn sdlc_admit_at(&self, i: &SdlcInput, on: bool) -> Result<Value> {
        self.sdlc_insert_at(i, on, None)
    }
    pub fn sdlc_retry(&self, parent_id: &str, r: &SdlcRetry) -> Result<Value> {
        self.sdlc_retry_at(parent_id, r, enabled())
    }
    fn sdlc_retry_at(&self, parent_id: &str, r: &SdlcRetry, on: bool) -> Result<Value> {
        let parent = self.sdlc_mission(parent_id)?;
        if !matches!(
            parent["state"].as_str(),
            Some("failed" | "blocked" | "cancelled")
        ) || !parent["publication"].is_null()
            || parent
                .get("effects")
                .is_some_and(|e| e.as_array().is_none_or(|a| !a.is_empty()))
            || parent["input"]["build"]["digest"] == r.build["digest"]
        {
            return Err(
                "SDLC retry requires a stopped unpublished parent and a different immutable build"
                    .into(),
            );
        }
        let mut input: SdlcInput =
            serde_json::from_value(parent["input"].clone()).map_err(|e| e.to_string())?;
        input.id = r.id.clone();
        input.build = r.build.clone();
        input.capability_digest = r.build["manifest"]["capability_digest"]
            .as_str()
            .map(String::from);
        self.sdlc_insert_at(&input, on, Some(parent_id))
    }
    fn sdlc_insert_at(&self, i: &SdlcInput, on: bool, retry_of: Option<&str>) -> Result<Value> {
        let input = json!(i);
        let records = self.sdlc_records()?;
        if let Some(old) = records.iter().find(|v| v["id"] == i.id) {
            return if old["input"] == input && old["retry_of"] == json!(retry_of) {
                Ok(old.clone())
            } else {
                Err("Conflicting SDLC identity".into())
            };
        }
        let p = self.sdlc_policy()?;
        let contract = capability(&i.repository, &i.opportunity)
            .ok_or("No repository capability supports this opportunity")?;
        if i.capability_digest.is_none() && !i.build["manifest"]["capability_digest"].is_null() {
            return Err("Contract-aware builds require an admission contract".into());
        }
        if let Some(expected) = &i.capability_digest
            && (contract["digest"] != *expected
                || i.build["manifest"]["capability_digest"] != *expected)
        {
            return Err("Capability contract/build mismatch".into());
        }
        if !on
            || p["enabled"] != true
            || p["expires_at"].as_f64().unwrap_or(0.0) <= now()
            || !i.repository.eq_ignore_ascii_case("x-mckay/algent")
            || !digest(&i.revision, 40)
            || i.id.is_empty()
            || i.id.len() > 80
            || !i.id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
            || input.to_string().len() > 32768
            || !i.build.is_object()
            || !digest(i.build["digest"].as_str().unwrap_or(""), 64)
        {
            return Err("Ineligible SDLC input/policy".into());
        }
        if has_active_verification(&records)
            || records
                .iter()
                .any(|v| reserves_publication(v) && v["input"]["opportunity"] == i.opportunity)
        {
            return Err("Unresolved SDLC publication reserves the capability".into());
        }
        if records.len() >= 100
            || records
                .iter()
                .any(|v| !terminal(v["state"].as_str().unwrap_or("")))
            || records
                .iter()
                .filter(|v| v["policy_generation"] == p["generation"])
                .count()
                >= p["max_missions"].as_u64().unwrap_or(0) as usize
        {
            return Err("SDLC mission capacity exhausted".into());
        }
        let opportunity = if let Some(parent) = retry_of {
            hash(&json!(["operator-retry", parent, i.build["digest"]]))
        } else {
            hash(&json!([
                i.repository.to_ascii_lowercase(),
                i.revision,
                i.opportunity
            ]))
        };
        let at = now();
        let v = json!({"id":i.id,"retry_of":retry_of,"input":input,"policy_generation":p["generation"],"capability":contract,"coordination":{"assignments":contract["assignments"],"max_rounds":contract["limits"]["max_rounds"],"reservation":format!("{}:{}",i.repository.to_ascii_lowercase(),i.opportunity)},"state":"queued","events":[],"evidence":{},"publication":null,"cancel_requested":false,"revision_loops":0,"created_at":at,"updated_at":at});
        self.db
            .execute(
                "INSERT INTO sdlc_missions(id,opportunity,body) VALUES($1,$2,$3)",
                params![i.id.clone(), opportunity, v.to_string()],
            )
            .map_err(|e| e.to_string())?;
        Ok(v)
    }
    pub fn sdlc_observe_pr(&self, id: &str, input: &SdlcPrObservation) -> Result<Value> {
        let mut v = self.sdlc_mission(id)?;
        let observation = json!(input);
        if v["evidence"]["submitted"]["number"] != input.number
            || v["publication"].is_null()
            || !digest(&input.head, 40)
            || !matches!(input.state.as_str(), "open" | "closed" | "merged")
            || !input.observed_at.is_finite()
            || (now() - input.observed_at).abs() > 60.0
        {
            return Err("Invalid or stale PR lifecycle observation".into());
        }
        if v["pr_observation"] == observation {
            return Ok(v);
        }
        if input.observed_at <= v["pr_observation"]["observed_at"].as_f64().unwrap_or(0.0) {
            return Err("Conflicting PR observation checkpoint".into());
        }
        let changed = v["pr_observation"]["state"] != input.state
            || v["pr_observation"]["head"] != input.head;
        if v.get("pr_history").is_none() {
            v["pr_history"] = json!([]);
        }
        if changed {
            let history = v["pr_history"].as_array_mut().unwrap();
            if history.len() >= 100 {
                return Err("PR lifecycle retention exhausted".into());
            }
            history.push(observation.clone());
        }
        v["pr_observation"] = observation;
        self.sdlc_save(&v)
    }
    pub fn sdlc_cancel(&self, id: &str) -> Result<Value> {
        let mut v = self.sdlc_mission(id)?;
        if !terminal(v["state"].as_str().unwrap_or("")) {
            v["cancel_requested"] = json!(true);
            v["updated_at"] = json!(now());
        }
        self.sdlc_save(&v)
    }
    pub fn sdlc_event(&self, id: &str, e: &SdlcEvent) -> Result<Value> {
        let mut v = self.sdlc_mission(id)?;
        let event = json!(e);
        let events = v["events"].as_array().unwrap();
        if let Some(old) = events.iter().find(|r| r["key"] == e.key) {
            return if old["event"] == event {
                Ok(v)
            } else {
                Err("Conflicting SDLC event replay".into())
            };
        }
        if e.key.is_empty()
            || e.key.len() > 100
            || event.to_string().len() > 131072
            || events.len() >= 100
            || !e.data.is_object()
        {
            return Err("Invalid bounded SDLC event".into());
        }
        let state = v["state"].as_str().unwrap_or("");
        if terminal(state) || (v["cancel_requested"] == true && e.stage != "cancelled") {
            return Err("SDLC mission stopped".into());
        }
        let allowed = matches!(
            (state, e.stage.as_str()),
            ("queued", "investigating")
                | ("investigating", "implementing")
                | ("implementing", "testing")
                | ("testing", "reviewing")
                | ("reviewing", "ready_to_publish")
                | ("reviewing", "implementing")
                | ("publishing", "publishing")
                | ("publishing", "submitted")
                | ("submitted", "awaiting_review")
        ) || matches!(e.stage.as_str(), "failed" | "blocked" | "cancelled");
        if !allowed {
            return Err("Invalid SDLC stage transition".into());
        }
        if state == "reviewing" && e.stage == "implementing" {
            let n = v["revision_loops"].as_u64().unwrap_or(0);
            if n >= 3 {
                return Err("SDLC revision allowance exhausted".into());
            }
            let failed_candidate = v["evidence"]["testing"]["verdict"] != "improved";
            let fallback = v["capability"]["assignments"]
                .as_array()
                .and_then(|tasks| tasks.iter().find(|t| t["role"] == "implementer"))
                .and_then(|t| t["fallback_crews"][0].as_str())
                .map(String::from);
            if failed_candidate
                && v["coordination"]["reassignments"].is_null()
                && let Some(crew) = fallback
            {
                let tasks = v["coordination"]["assignments"].as_array_mut().unwrap();
                let task = tasks
                    .iter_mut()
                    .find(|t| t["role"] == "implementer")
                    .unwrap();
                let previous = task["crew"].clone();
                task["crew"] = json!(crew);
                v["coordination"]["reassignments"] = json!([{"role":"implementer","from":previous,"to":crew,"reason":"candidate_failed_independent_gate","round":n+1,"at":now()}]);
            }
            v["revision_loops"] = json!(n + 1);
            v["evidence"]["testing"] = Value::Null;
            v["evidence"]["reviewing"] = Value::Null;
        }
        let mut data = e.data.clone();
        if e.stage == "testing" {
            if !digest(data["artifact_digest"].as_str().unwrap_or(""), 64) {
                return Err("Missing tested artifact digest".into());
            }
            let grading = grade_for(
                &data,
                v["input"]["opportunity"]
                    .as_str()
                    .unwrap_or("persistence-history"),
            );
            data["verdict"] = grading["verdict"].clone();
            data["grading"] = grading;
        }
        if e.stage == "ready_to_publish"
            && (v["evidence"]["testing"]["verdict"] != "improved"
                || v["evidence"]["reviewing"]["status"] != "accept")
        {
            return Err("Independent SDLC test/review gates failed".into());
        }
        if e.stage == "submitted" {
            let number = data["number"]
                .as_u64()
                .filter(|n| *n > 0)
                .ok_or("Invalid PR number")?;
            let expected = format!("https://github.com/X-McKay/algent/pull/{number}");
            if data["url"] != expected
                || !digest(data["head"].as_str().unwrap_or(""), 40)
                || v["publication"].is_null()
            {
                return Err("Invalid submitted publication identity".into());
            }
        }
        v["evidence"][&e.stage] = data;
        v["state"] = json!(e.stage);
        v["updated_at"] = json!(now());
        v["events"]
            .as_array_mut()
            .unwrap()
            .push(json!({"key":e.key,"event":event,"at":now()}));
        self.sdlc_save(&v)
    }
    pub fn sdlc_publication(&self, id: &str, r: &SdlcPublication) -> Result<Value> {
        self.sdlc_publication_at(id, r, enabled())
    }
    fn sdlc_publication_at(&self, id: &str, r: &SdlcPublication, on: bool) -> Result<Value> {
        let mut v = self.sdlc_mission(id)?;
        let p = self.sdlc_policy()?;
        if !on
            || p["enabled"] != true
            || p["publish"] != true
            || p["generation"] != v["policy_generation"]
            || p["expires_at"].as_f64().unwrap_or(0.0) <= now()
            || v["cancel_requested"] == true
            || !matches!(v["state"].as_str(), Some("ready_to_publish" | "publishing"))
            || v["input"]["revision"] != r.revision
            || v["evidence"]["testing"]["artifact_digest"] != r.artifact_digest
            || v["evidence"]["testing"]["verdict"] != "improved"
            || v["evidence"]["reviewing"]["status"] != "accept"
        {
            return Err("SDLC publication authority/gate denied".into());
        }
        if !v["publication"].is_null() {
            if v["publication"]["artifact_digest"] != r.artifact_digest
                || v["publication"]["revision"] != r.revision
            {
                return Err("Conflicting publication replay".into());
            }
            return Ok(v["publication"].clone());
        }
        let claim = json!({"id":id,"repository":"X-McKay/algent","branch":format!("starbase/{id}"),"revision":r.revision,"artifact_digest":r.artifact_digest,"policy_generation":p["generation"],"claimed_at":now(),"expires_at":p["expires_at"],"status":"claimed","authority":"create branch and pull request only; no merge"});
        v["publication"] = claim.clone();
        v["state"] = json!("publishing");
        v["updated_at"] = json!(now());
        self.sdlc_save(&v)?;
        Ok(claim)
    }
    pub fn sdlc_effect(&self, id: &str, e: &SdlcEffect) -> Result<Value> {
        self.sdlc_effect_at(id, e, enabled())
    }
    fn sdlc_effect_at(&self, id: &str, e: &SdlcEffect, on: bool) -> Result<Value> {
        let mut v = self.sdlc_mission(id)?;
        if v["state"] != "publishing"
            || v["publication"].is_null()
            || e.key.is_empty()
            || e.key.len() > 100
            || !matches!(e.kind.as_str(), "branch" | "pr" | "review")
            || !e.data.is_object()
            || json!(e).to_string().len() > 32768
        {
            return Err("Invalid SDLC effect claim".into());
        }
        let r: SdlcPublication = SdlcPublication {
            artifact_digest: v["publication"]["artifact_digest"].as_str().unwrap().into(),
            revision: v["publication"]["revision"].as_str().unwrap().into(),
        };
        self.sdlc_publication_at(id, &r, on)?;
        if v.get("effects").is_none() {
            v["effects"] = json!([])
        }
        let effects = v["effects"].as_array_mut().unwrap();
        if let Some(old) = effects.iter().find(|old| old["input"]["key"] == e.key) {
            return if old["input"] == json!(e) {
                Ok(json!({"claimed":false,"claim":old}))
            } else {
                Err("Conflicting effect claim".into())
            };
        }
        if effects.len() >= 20 || effects.iter().any(|old| old["input"]["kind"] == e.kind) {
            return Err("Effect allowance exhausted".into());
        }
        let claim = json!({"input":e,"claimed_at":now()});
        effects.push(claim.clone());
        v["updated_at"] = json!(now());
        self.sdlc_save(&v)?;
        Ok(json!({"claimed":true,"claim":claim}))
    }
}

impl Store {
    fn sdlc_verification(&self, mid: &str, vid: &str) -> Result<Value> {
        self.sdlc_mission(mid)?["verifications"]
            .as_array()
            .and_then(|a| a.iter().find(|v| v["id"] == vid))
            .cloned()
            .ok_or("Unknown SDLC verification".into())
    }
    fn sdlc_save_verification(&self, mid: &str, v: &Value) -> Result<Value> {
        let mut parent = self.sdlc_mission(mid)?;
        let children = parent["verifications"]
            .as_array_mut()
            .ok_or("Missing verification ledger")?;
        let index = children
            .iter()
            .position(|old| old["id"] == v["id"])
            .ok_or("Unknown verification identity")?;
        children[index] = v.clone();
        self.sdlc_save(&parent)?;
        Ok(v.clone())
    }
    fn sdlc_verification_authority(&self, v: &Value, on: bool) -> Result<()> {
        let p = self.sdlc_policy()?;
        if !on
            || p["enabled"] != true
            || p["publish"] != true
            || p["generation"] != v["policy_generation"]
            || p["expires_at"].as_f64().unwrap_or(0.0) <= now()
            || v["cancel_requested"] == true
            || verification_terminal(v)
        {
            return Err("SDLC verification authority revoked, expired or stopped".into());
        }
        Ok(())
    }
    pub fn sdlc_verification_authorize(&self, mid: &str, vid: &str) -> Result<Value> {
        let v = self.sdlc_verification(mid, vid)?;
        self.sdlc_verification_authority(&v, verification_enabled())?;
        Ok(v)
    }
    pub fn sdlc_verification_admit(&self, mid: &str, i: &SdlcVerificationInput) -> Result<Value> {
        self.sdlc_verification_admit_at(mid, i, verification_enabled())
    }
    fn sdlc_verification_admit_at(
        &self,
        mid: &str,
        i: &SdlcVerificationInput,
        on: bool,
    ) -> Result<Value> {
        let mut parent = self.sdlc_mission(mid)?;
        let children = parent["verifications"]
            .as_array()
            .cloned()
            .unwrap_or_default();
        let input = json!(i);
        if let Some(old) = children.iter().find(|v| v["id"] == i.id) {
            return if old["input"] == input {
                Ok(old.clone())
            } else {
                Err("Conflicting verification identity".into())
            };
        }
        if parent["state"] != "awaiting_review"
            || parent["publication"].is_null()
            || parent["evidence"]["submitted"]["number"]
                .as_u64()
                .is_none_or(|n| n == 0)
            || !parent["input"]["repository"]
                .as_str()
                .unwrap_or("")
                .eq_ignore_ascii_case("x-mckay/algent")
            || i.id.is_empty()
            || i.id.len() > 80
            || !i.id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
            || !digest(&i.head, 40)
            || !i.build.is_object()
            || !digest(i.build["digest"].as_str().unwrap_or(""), 64)
            || input.to_string().len() > 32768
        {
            return Err("Ineligible SDLC verification input/parent".into());
        }
        let feedback = if let Some(digest) = &i.feedback_digest {
            parent["feedback"]
                .as_array()
                .and_then(|records| {
                    records.iter().find(|r| {
                        r["digest"] == *digest
                            && r["head"] == i.head
                            && r["proposal"]["output"]["state"] == "current"
                    })
                })
                .cloned()
                .ok_or("Feedback is absent, stale or not actionable")?
        } else {
            Value::Null
        };
        if children.iter().any(|v| {
            v["input"]["head"] == i.head
                && v["input"]["build"]["digest"] == i.build["digest"]
                && v["input"]["feedback_digest"] == json!(i.feedback_digest)
        }) {
            return Err("Verification head/build already retained".into());
        }
        let records = self.sdlc_records()?;
        if records
            .iter()
            .any(|v| !terminal(v["state"].as_str().unwrap_or("")))
            || children.len() >= VERIFICATION_RETENTION_LIMIT
            || records.iter().any(|p| {
                p["verifications"]
                    .as_array()
                    .is_some_and(|a| a.iter().any(|v| !verification_terminal(v)))
            })
        {
            return Err("SDLC verification capacity exhausted".into());
        }
        let p = self.sdlc_policy()?;
        let at = now();
        let v = json!({"id":i.id,"input":input,"policy_generation":p["generation"],"state":"queued","events":[],"evidence":{},"feedback":feedback,"effects":[],"cancel_requested":false,"revision_loops":0,"created_at":at,"updated_at":at});
        self.sdlc_verification_authority(&v, on)?;
        parent["verifications"] = json!(children);
        parent["verifications"]
            .as_array_mut()
            .unwrap()
            .push(v.clone());
        self.sdlc_save(&parent)?;
        Ok(v)
    }
    pub fn sdlc_verification_cancel(&self, mid: &str, vid: &str) -> Result<Value> {
        let mut v = self.sdlc_verification(mid, vid)?;
        if !verification_terminal(&v) {
            v["cancel_requested"] = json!(true);
            v["updated_at"] = json!(now());
        }
        self.sdlc_save_verification(mid, &v)
    }
    pub fn sdlc_verification_event(&self, mid: &str, vid: &str, e: &SdlcEvent) -> Result<Value> {
        let mut v = self.sdlc_verification(mid, vid)?;
        let event = json!(e);
        let events = v["events"].as_array().unwrap();
        if let Some(old) = events.iter().find(|old| old["key"] == e.key) {
            return if old["event"] == event {
                Ok(v)
            } else {
                Err("Conflicting verification event replay".into())
            };
        }
        if e.key.is_empty()
            || e.key.len() > 100
            || !e.data.is_object()
            || event.to_string().len() > 131072
            || events.len() >= 100
            || verification_terminal(&v)
            || (v["cancel_requested"] == true && e.stage != "cancelled")
        {
            return Err("Invalid, cancelled or exhausted verification event".into());
        }
        let state = v["state"].as_str().unwrap_or("").to_owned();
        let allowed = matches!(
            (state.as_str(), e.stage.as_str()),
            ("queued", "verifying")
                | ("verifying", "verifying")
                | ("verifying", "verified")
                | ("verified", "completed")
                | ("verified", "repairing")
                | ("repairing", "testing")
                | ("testing", "reviewing")
                | ("reviewing", "ready_to_update")
                | ("reviewing", "repairing")
                | ("updating", "completed")
        ) || matches!(e.stage.as_str(), "blocked" | "cancelled");
        if !allowed {
            return Err("Invalid verification stage transition".into());
        }
        if e.stage == "repairing"
            && state == "verified"
            && v["evidence"]["verified"]["outcome"] != "failed"
        {
            return Err("Only an observed regression can authorize repair".into());
        }
        if state == "reviewing" && e.stage == "repairing" {
            let loops = v["revision_loops"].as_u64().unwrap_or(0);
            if loops >= 3 {
                return Err("Verification revision allowance exhausted".into());
            }
            v["revision_loops"] = json!(loops + 1);
            v["evidence"]["testing"] = Value::Null;
            v["evidence"]["reviewing"] = Value::Null;
        }
        if e.stage == "completed" {
            let claims = v["effects"].as_array().unwrap();
            let has = |kind: &str| claims.iter().any(|c| c["input"]["kind"] == kind);
            if !has("status_result")
                || (state == "updating" && (!has("branch_update") || !has("review")))
            {
                return Err("Verification completion requires retained publication claims".into());
            }
        }
        let mut data = e.data.clone();
        if e.stage == "verified" {
            let parent = self.sdlc_mission(mid)?;
            let family = parent["input"]["opportunity"]
                .as_str()
                .unwrap_or("persistence-history");
            let grading = verification_grade_for(&data, family);
            data["outcome"] = grading["outcome"].clone();
            data["grading"] = grading;
        }
        if e.stage == "testing" {
            if !digest(data["artifact_digest"].as_str().unwrap_or(""), 64) {
                return Err("Missing tested verification artifact".into());
            }
            let parent = self.sdlc_mission(mid)?;
            let family = parent["input"]["opportunity"]
                .as_str()
                .unwrap_or("persistence-history");
            let mut grading = grade_for(&data, family);
            if data["public"]["exit_code"] != 0 {
                grading["verdict"] = json!("ineligible");
            }
            grading["public_pass"] = json!(data["public"]["exit_code"] == 0);
            data["verdict"] = grading["verdict"].clone();
            data["grading"] = grading;
        }
        if e.stage == "ready_to_update"
            && (v["evidence"]["testing"]["verdict"] != "improved"
                || v["evidence"]["reviewing"]["status"] != "accept")
        {
            return Err("Verification repair gates failed".into());
        }
        v["state"] = json!(e.stage);
        v["evidence"][&e.stage] = data;
        v["events"]
            .as_array_mut()
            .unwrap()
            .push(json!({"key":e.key,"event":event,"at":now()}));
        v["updated_at"] = json!(now());
        self.sdlc_save_verification(mid, &v)
    }
    pub fn sdlc_verification_effect(&self, mid: &str, vid: &str, e: &SdlcEffect) -> Result<Value> {
        self.sdlc_verification_effect_at(mid, vid, e, verification_enabled())
    }
    fn sdlc_verification_effect_at(
        &self,
        mid: &str,
        vid: &str,
        e: &SdlcEffect,
        on: bool,
    ) -> Result<Value> {
        let mut v = self.sdlc_verification(mid, vid)?;
        self.sdlc_verification_authority(&v, on)?;
        if e.key.is_empty()
            || e.key.len() > 100
            || !e.data.is_object()
            || json!(e).to_string().len() > 32768
        {
            return Err("Invalid bounded verification effect".into());
        }
        let effects = v["effects"].as_array().unwrap();
        if let Some(old) = effects.iter().find(|old| old["input"]["key"] == e.key) {
            return if old["input"] == json!(e) {
                Ok(json!({"claimed":false,"claim":old}))
            } else {
                Err("Conflicting verification effect replay".into())
            };
        }
        let head = &v["input"]["head"];
        let state = v["state"].as_str().unwrap_or("");
        let data = &e.data;
        match e.kind.as_str() {
            "status_pending" => {
                if !matches!(state, "queued" | "verifying")
                    || data["head"] != *head
                    || data["state"] != "pending"
                    || data["context"] != verification_context(&self.sdlc_mission(mid)?)
                {
                    return Err("Invalid pending verification status".into());
                }
            }
            "status_result" => {
                let outcome = v["evidence"]["verified"]["outcome"]
                    .as_str()
                    .ok_or("Verification result missing")?;
                let expected = match outcome {
                    "passed" => "success",
                    "failed" => "failure",
                    "infrastructure_blocked" => "error",
                    _ => return Err("Unknown verification outcome".into()),
                };
                if data["head"] != *head
                    || data["state"] != expected
                    || data["context"] != verification_context(&self.sdlc_mission(mid)?)
                {
                    return Err("Verification status must match Core grade and exact head".into());
                }
            }
            "branch_update" => {
                if !matches!(state, "ready_to_update" | "updating")
                    || data["expected_head"] != *head
                    || !digest(data["candidate_head"].as_str().unwrap_or(""), 40)
                    || data["candidate_head"] == *head
                    || data["artifact_digest"] != v["evidence"]["testing"]["artifact_digest"]
                    || v["evidence"]["testing"]["verdict"] != "improved"
                    || v["evidence"]["reviewing"]["status"] != "accept"
                {
                    return Err(
                        "Verification branch update requires exact tested artifact/head and review"
                            .into(),
                    );
                }
            }
            "review" => {
                let branch = v["effects"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .find(|c| c["input"]["kind"] == "branch_update")
                    .ok_or("Branch update claim missing")?;
                if state != "updating"
                    || data["candidate_head"] != branch["input"]["data"]["candidate_head"]
                {
                    return Err("Verification review must match claimed candidate".into());
                }
            }
            _ => return Err("Unknown verification effect kind".into()),
        }
        let effects = v["effects"].as_array_mut().unwrap();
        if effects.iter().any(|old| old["input"]["kind"] == e.kind) {
            return Err("Verification effect already claimed".into());
        }
        let claim = json!({"input":e,"claimed_at":now()});
        effects.push(claim.clone());
        if e.kind == "branch_update" {
            v["state"] = json!("updating");
        }
        v["updated_at"] = json!(now());
        self.sdlc_save_verification(mid, &v)?;
        Ok(json!({"claimed":true,"claim":claim}))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn setup() -> Store {
        let s = Store::open(":memory:").unwrap();
        s.sdlc_set_policy_at(&policy(0), true).unwrap();
        s
    }
    fn policy(generation: u64) -> SdlcPolicy {
        SdlcPolicy {
            repository: "X-McKay/algent".into(),
            enabled: true,
            publish: true,
            generation,
            max_missions: 3,
            expires_at: now() + 3600.0,
        }
    }
    fn input() -> SdlcInput {
        SdlcInput {
            id: "sdlc-pilot".into(),
            repository: "X-McKay/algent".into(),
            revision: "a".repeat(40),
            opportunity: "persistence-history".into(),
            build: json!({"digest":"b".repeat(64)}),
            capability_digest: None,
        }
    }
    fn results() -> Value {
        let expected = json!({"history_all":[0,1,2,3,4],"history_last3":[2,3,4],"history_last1":[4],"history_zero":[],"history_empty":[],"history_context":[9],"history_mixed":[0,1,2,3,4]});
        let cases: Vec<_> = expected
            .as_object()
            .unwrap()
            .iter()
            .map(|(id, actual)| json!({"id":id,"actual":actual}))
            .collect();
        let mut baseline = cases.clone();
        baseline[0]["actual"] = json!([]);
        json!({"baseline":{"exit_code":0,"cases":baseline},"candidate":{"exit_code":0,"cases":cases},"artifact_digest":"c".repeat(64),"verdict":"model says success"})
    }
    fn event(s: &Store, stage: &str, data: Value) -> Value {
        s.sdlc_event(
            "sdlc-pilot",
            &SdlcEvent {
                key: stage.into(),
                stage: stage.into(),
                data,
            },
        )
        .unwrap()
    }
    fn ready(s: &Store) {
        s.sdlc_admit_at(&input(), true).unwrap();
        for stage in ["investigating", "implementing"] {
            event(s, stage, json!({}));
        }
        event(s, "testing", results());
        event(s, "reviewing", json!({"status":"accept"}));
        event(s, "ready_to_publish", json!({}));
    }
    fn publication() -> SdlcPublication {
        SdlcPublication {
            artifact_digest: "c".repeat(64),
            revision: "a".repeat(40),
        }
    }
    #[test]
    fn oracle_rejects_missing_duplicate_unknown_exit_and_self_certification() {
        let good = results();
        assert_eq!(grade(&good)["verdict"], "improved");
        for bad in 0..5 {
            let mut v = good.clone();
            match bad {
                0 => {
                    v["candidate"]["cases"].as_array_mut().unwrap().pop();
                }
                1 => v["candidate"]["cases"][0] = v["candidate"]["cases"][1].clone(),
                2 => v["candidate"]["cases"][0]["id"] = json!("invented"),
                3 => v["candidate"]["exit_code"] = json!(1),
                _ => v["candidate"]["cases"][0]["actual"] = json!(null),
            }
            assert_eq!(grade(&v)["verdict"], "ineligible");
        }
    }
    #[test]
    fn admission_policy_scope_capacity_and_replay() {
        let s = setup();
        let i = input();
        assert!(s.sdlc_admit_at(&i, false).is_err());
        let mut bad = i.clone();
        bad.repository = "X-McKay/Starbase2".into();
        assert!(s.sdlc_admit_at(&bad, true).is_err());
        let a = s.sdlc_admit_at(&i, true).unwrap();
        assert_eq!(a, s.sdlc_admit_at(&i, true).unwrap());
        bad = i.clone();
        bad.id = "second".into();
        assert!(s.sdlc_admit_at(&bad, true).is_err());
        bad = i.clone();
        bad.revision = "b".repeat(40);
        assert!(s.sdlc_admit_at(&bad, true).is_err());
        assert!(s.sdlc_set_policy_at(&policy(0), true).is_err());
    }
    #[test]
    fn claims_are_at_most_once_and_revocation_fences_replays() {
        let s = setup();
        ready(&s);
        let claim = s
            .sdlc_publication_at("sdlc-pilot", &publication(), true)
            .unwrap();
        assert_eq!(
            claim,
            s.sdlc_publication_at("sdlc-pilot", &publication(), true)
                .unwrap()
        );
        let effect = SdlcEffect {
            key: "create-pr".into(),
            kind: "pr".into(),
            data: json!({"head":"d".repeat(40)}),
        };
        assert_eq!(
            s.sdlc_effect_at("sdlc-pilot", &effect, true).unwrap()["claimed"],
            true
        );
        assert_eq!(
            s.sdlc_effect_at("sdlc-pilot", &effect, true).unwrap()["claimed"],
            false
        );
        s.sdlc_set_policy_at(&policy(1), true).unwrap();
        assert!(
            s.sdlc_publication_at("sdlc-pilot", &publication(), true)
                .is_err()
        );
        assert!(s.sdlc_effect_at("sdlc-pilot", &effect, true).is_err());
        assert_eq!(s.sdlc_mission("sdlc-pilot").unwrap()["publication"], claim);
    }
    #[test]
    fn cancellation_fences_new_effects_but_retains_claim() {
        let s = setup();
        ready(&s);
        let claim = s
            .sdlc_publication_at("sdlc-pilot", &publication(), true)
            .unwrap();
        s.sdlc_cancel("sdlc-pilot").unwrap();
        assert!(
            s.sdlc_publication_at("sdlc-pilot", &publication(), true)
                .is_err()
        );
        event(&s, "cancelled", json!({"external_outcome":"unknown"}));
        assert_eq!(s.sdlc_mission("sdlc-pilot").unwrap()["publication"], claim);
    }
    #[test]
    fn stage_replays_preserve_evidence_and_grading() {
        let s = setup();
        ready(&s);
        assert_eq!(
            s.sdlc_mission("sdlc-pilot").unwrap()["evidence"]["testing"]["verdict"],
            "improved"
        );
        let e = SdlcEvent {
            key: "testing".into(),
            stage: "testing".into(),
            data: results(),
        };
        assert!(s.sdlc_event("sdlc-pilot", &e).is_ok());
        let mut e = e;
        e.data["verdict"] = json!("changed");
        assert!(s.sdlc_event("sdlc-pilot", &e).is_err());
        assert!(
            s.sdlc_event(
                "sdlc-pilot",
                &SdlcEvent {
                    key: "skip".into(),
                    stage: "submitted".into(),
                    data: json!({})
                }
            )
            .is_err()
        );
    }
    #[test]
    fn failed_tests_cannot_publish_even_with_reviewer_acceptance() {
        let s = setup();
        s.sdlc_admit_at(&input(), true).unwrap();
        event(&s, "investigating", json!({}));
        event(&s, "implementing", json!({}));
        let mut r = results();
        r["candidate"]["cases"][0]["actual"] = json!(null);
        event(&s, "testing", r);
        event(&s, "reviewing", json!({"status":"accept"}));
        assert!(
            s.sdlc_event(
                "sdlc-pilot",
                &SdlcEvent {
                    key: "ready".into(),
                    stage: "ready_to_publish".into(),
                    data: json!({})
                }
            )
            .is_err()
        );
        assert!(
            s.sdlc_publication_at("sdlc-pilot", &publication(), true)
                .is_err()
        );
    }
    #[test]
    fn sqlite_eight_migration_and_claim_survive_reopen() {
        let path =
            std::env::temp_dir().join(format!("sdlc-{}-{}.sqlite", std::process::id(), now()));
        {
            let s = Store::open(path.to_str().unwrap()).unwrap();
            s.db.execute_batch(
                "DROP TABLE sdlc_discoveries; DROP TABLE sdlc_missions; DROP TABLE sdlc_policy; PRAGMA user_version=8;",
            )
            .unwrap();
        }
        {
            let s = Store::open(path.to_str().unwrap()).unwrap();
            s.sdlc_set_policy_at(&policy(0), true).unwrap();
            ready(&s);
            s.sdlc_publication_at("sdlc-pilot", &publication(), true)
                .unwrap();
        }
        {
            let s = Store::open(path.to_str().unwrap()).unwrap();
            assert_eq!(s.sdlc_mission("sdlc-pilot").unwrap()["state"], "publishing");
            assert_eq!(s.sdlc_policy().unwrap()["generation"], 1);
        }
        std::fs::remove_file(path).unwrap();
    }
    #[test]
    fn explicit_retry_preserves_parent_and_never_bypasses_discovery_dedup() {
        let s = setup();
        s.sdlc_admit_at(&input(), true).unwrap();
        let parent = event(&s, "blocked", json!({"reason":"ambiguous edit"}));
        let retry = SdlcRetry {
            id: "retry-1".into(),
            build: json!({"digest":"d".repeat(64)}),
        };
        let child = s.sdlc_retry_at("sdlc-pilot", &retry, true).unwrap();
        assert_eq!(child["retry_of"], "sdlc-pilot");
        assert_eq!(child["input"]["revision"], parent["input"]["revision"]);
        assert_eq!(s.sdlc_mission("sdlc-pilot").unwrap(), parent);
        assert_eq!(s.sdlc_retry_at("sdlc-pilot", &retry, true).unwrap(), child);
        let conflicting = SdlcRetry {
            id: "retry-1".into(),
            build: json!({"digest":"e".repeat(64)}),
        };
        assert!(s.sdlc_retry_at("sdlc-pilot", &conflicting, true).is_err());
        s.sdlc_event(
            "retry-1",
            &SdlcEvent {
                key: "done".into(),
                stage: "blocked".into(),
                data: json!({}),
            },
        )
        .unwrap();
        let mut auto = input();
        auto.id = "automatic-new-id".into();
        auto.build = retry.build.clone();
        assert!(s.sdlc_admit_at(&auto, true).is_err());
        let duplicate = SdlcRetry {
            id: "retry-duplicate".into(),
            build: retry.build,
        };
        assert!(s.sdlc_retry_at("sdlc-pilot", &duplicate, true).is_err());
    }
    #[test]
    fn retry_requires_new_build_quota_policy_and_no_external_claim() {
        let s = setup();
        s.sdlc_admit_at(&input(), true).unwrap();
        let retry = SdlcRetry {
            id: "retry-1".into(),
            build: json!({"digest":"d".repeat(64)}),
        };
        assert!(s.sdlc_retry_at("sdlc-pilot", &retry, true).is_err());
        event(&s, "blocked", json!({}));
        assert!(s.sdlc_retry_at("sdlc-pilot", &retry, false).is_err());
        assert!(
            s.sdlc_retry_at(
                "sdlc-pilot",
                &SdlcRetry {
                    id: "same-build".into(),
                    build: input().build
                },
                true
            )
            .is_err()
        );
        let mut p = policy(1);
        p.max_missions = 1;
        s.sdlc_set_policy_at(&p, true).unwrap();
        s.sdlc_retry_at("sdlc-pilot", &retry, true).unwrap();
        let next = SdlcRetry {
            id: "retry-2".into(),
            build: json!({"digest":"e".repeat(64)}),
        };
        assert!(s.sdlc_retry_at("sdlc-pilot", &next, true).is_err());
        s.sdlc_event(
            "retry-1",
            &SdlcEvent {
                key: "done".into(),
                stage: "blocked".into(),
                data: json!({}),
            },
        )
        .unwrap();
        assert!(s.sdlc_retry_at("retry-1", &next, true).is_err());
        let s = setup();
        ready(&s);
        s.sdlc_publication_at("sdlc-pilot", &publication(), true)
            .unwrap();
        event(&s, "blocked", json!({"unknown":true}));
        assert!(s.sdlc_retry_at("sdlc-pilot", &retry, true).is_err());
    }
    fn submitted(s: &Store) -> Value {
        ready(s);
        s.sdlc_publication_at("sdlc-pilot", &publication(), true)
            .unwrap();
        event(
            s,
            "submitted",
            json!({"url":"https://github.com/X-McKay/algent/pull/9","number":9,"head":"e".repeat(40)}),
        );
        event(s, "awaiting_review", json!({"verified_merge":false}))
    }
    fn verification_input() -> SdlcVerificationInput {
        SdlcVerificationInput {
            id: "verify-1".into(),
            feedback_digest: None,
            head: "e".repeat(40),
            build: json!({"digest":"f".repeat(64)}),
        }
    }
    fn vevent(s: &Store, stage: &str, data: Value) -> Value {
        s.sdlc_verification_event(
            "sdlc-pilot",
            "verify-1",
            &SdlcEvent {
                key: stage.into(),
                stage: stage.into(),
                data,
            },
        )
        .unwrap()
    }
    fn status_effect(kind: &str, state: &str) -> SdlcEffect {
        SdlcEffect {
            key: kind.into(),
            kind: kind.into(),
            data: json!({"head":"e".repeat(40),"state":state,"context":"starbase/persistence-regression"}),
        }
    }
    fn verified(s: &Store, pass: bool) -> Value {
        s.sdlc_verification_admit_at("sdlc-pilot", &verification_input(), true)
            .unwrap();
        vevent(s, "verifying", json!({}));
        vevent(
            s,
            "verified",
            json!({"observations":results()[if pass{"candidate"}else{"baseline"}],"public":{"exit_code":0},"outcome":"self-certified"}),
        )
    }
    #[test]
    fn verification_admission_is_exact_bounded_and_preserves_parent() {
        let s = setup();
        let parent = submitted(&s);
        s.sdlc_set_policy_at(&policy(1), true).unwrap();
        let i = verification_input();
        let first = s
            .sdlc_verification_admit_at("sdlc-pilot", &i, true)
            .unwrap();
        assert_eq!(first["policy_generation"], 2);
        assert_eq!(
            s.sdlc_verification_admit_at("sdlc-pilot", &i, true)
                .unwrap(),
            first
        );
        let mut duplicate = i.clone();
        duplicate.id = "verify-2".into();
        assert!(
            s.sdlc_verification_admit_at("sdlc-pilot", &duplicate, true)
                .is_err()
        );
        duplicate.head = "a".repeat(40);
        assert!(
            s.sdlc_verification_admit_at("sdlc-pilot", &duplicate, true)
                .is_err()
        );
        let mut after = s.sdlc_mission("sdlc-pilot").unwrap();
        after.as_object_mut().unwrap().remove("verifications");
        assert_eq!(after, parent);
        vevent(&s, "blocked", json!({}));
        duplicate = i.clone();
        duplicate.id = "new-id-same-build-head".into();
        assert!(
            s.sdlc_verification_admit_at("sdlc-pilot", &duplicate, true)
                .is_err()
        );
        for index in 2..=VERIFICATION_RETENTION_LIMIT {
            let mut next = i.clone();
            next.id = format!("verify-{index}");
            next.head = format!("{index:040x}");
            s.sdlc_verification_admit_at("sdlc-pilot", &next, true)
                .unwrap();
            s.sdlc_verification_event(
                "sdlc-pilot",
                &next.id,
                &SdlcEvent {
                    key: "stop".into(),
                    stage: "blocked".into(),
                    data: json!({}),
                },
            )
            .unwrap();
        }
        duplicate.id = "verify-17".into();
        duplicate.head = "f".repeat(40);
        assert!(
            s.sdlc_verification_admit_at("sdlc-pilot", &duplicate, true)
                .is_err()
        );
    }
    #[test]
    fn verification_grade_distinguishes_code_failure_from_malformed_and_infrastructure() {
        let good = json!({"observations":results()["candidate"],"public":{"exit_code":0}});
        assert_eq!(verification_grade(&good)["outcome"], "passed");
        let mut failed = good.clone();
        failed["observations"] = results()["baseline"].clone();
        assert_eq!(verification_grade(&failed)["outcome"], "failed");
        let mut failed = good.clone();
        failed["public"]["exit_code"] = json!(1);
        assert_eq!(verification_grade(&failed)["outcome"], "failed");
        let mut failed = good.clone();
        failed["observations"] = json!({"exit_code":1});
        assert_eq!(verification_grade(&failed)["outcome"], "failed");
        for variation in 0..4 {
            let mut bad = good.clone();
            match variation {
                0 => bad["observations"]["cases"][0]["actual"] = json!(null),
                1 => bad["observations"]["cases"][0]["id"] = json!("unknown"),
                2 => bad["infrastructure_error"] = json!("VM unavailable"),
                _ => bad["public"] = json!({}),
            };
            assert_eq!(
                verification_grade(&bad)["outcome"],
                "infrastructure_blocked"
            );
        }
    }
    #[test]
    fn verification_status_claims_cannot_change_grade_head_or_authority() {
        let s = setup();
        submitted(&s);
        s.sdlc_verification_admit_at("sdlc-pilot", &verification_input(), true)
            .unwrap();
        let pending = status_effect("status_pending", "pending");
        assert_eq!(
            s.sdlc_verification_effect_at("sdlc-pilot", "verify-1", &pending, true)
                .unwrap()["claimed"],
            true
        );
        vevent(&s, "verifying", json!({}));
        vevent(
            &s,
            "verified",
            json!({"observations":results()["candidate"],"public":{"exit_code":0}}),
        );
        assert_eq!(
            s.sdlc_verification_effect_at("sdlc-pilot", "verify-1", &pending, true)
                .unwrap()["claimed"],
            false
        );
        assert!(
            s.sdlc_verification_effect_at(
                "sdlc-pilot",
                "verify-1",
                &status_effect("status_result", "failure"),
                true
            )
            .is_err()
        );
        let mut result = status_effect("status_result", "success");
        result.data["head"] = json!("a".repeat(40));
        assert!(
            s.sdlc_verification_effect_at("sdlc-pilot", "verify-1", &result, true)
                .is_err()
        );
        result = status_effect("status_result", "success");
        assert_eq!(
            s.sdlc_verification_effect_at("sdlc-pilot", "verify-1", &result, true)
                .unwrap()["claimed"],
            true
        );
        assert_eq!(
            s.sdlc_verification_effect_at("sdlc-pilot", "verify-1", &result, true)
                .unwrap()["claimed"],
            false
        );
        s.sdlc_set_policy_at(&policy(1), true).unwrap();
        assert!(
            s.sdlc_verification_effect_at("sdlc-pilot", "verify-1", &result, true)
                .is_err()
        );
    }
    #[test]
    fn verification_completion_and_cancellation_preserve_effect_uncertainty() {
        let s = setup();
        submitted(&s);
        verified(&s, true);
        let complete = SdlcEvent {
            key: "complete".into(),
            stage: "completed".into(),
            data: json!({}),
        };
        assert!(
            s.sdlc_verification_event("sdlc-pilot", "verify-1", &complete)
                .is_err()
        );
        let result = status_effect("status_result", "success");
        s.sdlc_verification_effect_at("sdlc-pilot", "verify-1", &result, true)
            .unwrap();
        s.sdlc_verification_cancel("sdlc-pilot", "verify-1")
            .unwrap();
        assert!(
            s.sdlc_verification_effect_at("sdlc-pilot", "verify-1", &result, true)
                .is_err()
        );
        assert!(
            s.sdlc_verification_event("sdlc-pilot", "verify-1", &complete)
                .is_err()
        );
        let cancelled = vevent(&s, "cancelled", json!({"effect_outcome":"unknown"}));
        assert_eq!(cancelled["effects"].as_array().unwrap().len(), 1);
    }
    #[test]
    fn verification_repair_requires_failed_observation_public_suite_and_review() {
        let s = setup();
        submitted(&s);
        verified(&s, true);
        let repair = SdlcEvent {
            key: "repair".into(),
            stage: "repairing".into(),
            data: json!({}),
        };
        assert!(
            s.sdlc_verification_event("sdlc-pilot", "verify-1", &repair)
                .is_err()
        );
        let s = setup();
        submitted(&s);
        verified(&s, false);
        vevent(&s, "repairing", json!({}));
        let tested = vevent(&s, "testing", results());
        assert_eq!(tested["evidence"]["testing"]["verdict"], "ineligible");
        vevent(&s, "reviewing", json!({"status":"accept"}));
        let ready = SdlcEvent {
            key: "ready".into(),
            stage: "ready_to_update".into(),
            data: json!({}),
        };
        assert!(
            s.sdlc_verification_event("sdlc-pilot", "verify-1", &ready)
                .is_err()
        );
        s.sdlc_verification_event(
            "sdlc-pilot",
            "verify-1",
            &SdlcEvent {
                key: "retry".into(),
                stage: "repairing".into(),
                data: json!({}),
            },
        )
        .unwrap();
        let mut data = results();
        data["public"] = json!({"exit_code":0});
        s.sdlc_verification_event(
            "sdlc-pilot",
            "verify-1",
            &SdlcEvent {
                key: "test2".into(),
                stage: "testing".into(),
                data,
            },
        )
        .unwrap();
        s.sdlc_verification_event(
            "sdlc-pilot",
            "verify-1",
            &SdlcEvent {
                key: "review2".into(),
                stage: "reviewing".into(),
                data: json!({"status":"accept"}),
            },
        )
        .unwrap();
        s.sdlc_verification_event("sdlc-pilot", "verify-1", &ready)
            .unwrap();
        let mut branch = SdlcEffect {
            key: "branch".into(),
            kind: "branch_update".into(),
            data: json!({"expected_head":"e".repeat(40),"candidate_head":"f".repeat(40),"artifact_digest":"c".repeat(64)}),
        };
        branch.data["expected_head"] = json!("a".repeat(40));
        assert!(
            s.sdlc_verification_effect_at("sdlc-pilot", "verify-1", &branch, true)
                .is_err()
        );
        branch.data["expected_head"] = json!("e".repeat(40));
        assert_eq!(
            s.sdlc_verification_effect_at("sdlc-pilot", "verify-1", &branch, true)
                .unwrap()["claimed"],
            true
        );
        let mut review = SdlcEffect {
            key: "review".into(),
            kind: "review".into(),
            data: json!({"candidate_head":"a".repeat(40)}),
        };
        assert!(
            s.sdlc_verification_effect_at("sdlc-pilot", "verify-1", &review, true)
                .is_err()
        );
        review.data["candidate_head"] = json!("f".repeat(40));
        s.sdlc_verification_effect_at("sdlc-pilot", "verify-1", &review, true)
            .unwrap();
        s.sdlc_verification_effect_at(
            "sdlc-pilot",
            "verify-1",
            &status_effect("status_result", "failure"),
            true,
        )
        .unwrap();
        assert_eq!(
            vevent(&s, "completed", json!({"candidate_unverified":true}))["state"],
            "completed"
        );
    }
    #[test]
    fn capability_bound_admission_retains_plan_and_rejects_contract_drift() {
        let s = setup();
        let contract = capability("X-McKay/algent", "persistence-history").unwrap();
        let mut i = input();
        i.capability_digest = Some("0".repeat(64));
        assert!(s.sdlc_admit_at(&i, true).is_err());
        i.capability_digest = contract["digest"].as_str().map(String::from);
        assert!(s.sdlc_admit_at(&i, true).is_err()); // build did not bind the contract
        i.build["manifest"] = json!({"capability_digest":contract["digest"]});
        let admitted = s.sdlc_admit_at(&i, true).unwrap();
        assert_eq!(admitted["capability"], contract);
        assert_eq!(
            admitted["coordination"]["assignments"],
            contract["assignments"]
        );
        assert_eq!(s.sdlc_admit_at(&i, true).unwrap(), admitted);
        let other = setup();
        i.capability_digest = None;
        assert!(other.sdlc_admit_at(&i, true).is_err()); // no downgrade to legacy
        i.opportunity = "arbitrary-shell".into();
        assert!(other.sdlc_admit_at(&i, true).is_err());
    }

    #[test]
    fn publication_reservation_requires_fresh_closure_and_reopens() {
        let s = setup();
        submitted(&s);
        let p = s.sdlc_policy().unwrap();
        assert_eq!(
            coordination(&s.sdlc_records().unwrap(), &p, true)["reserved_opportunities"],
            json!(["persistence-history"])
        );
        let mut next = input();
        next.id = "next-revision".into();
        next.revision = "c".repeat(40);
        assert!(s.sdlc_admit_at(&next, true).is_err());
        let mut observed = SdlcPrObservation {
            number: 9,
            head: "e".repeat(40),
            state: "closed".into(),
            observed_at: now(),
        };
        let closed = s.sdlc_observe_pr("sdlc-pilot", &observed).unwrap();
        assert_eq!(closed["state"], "awaiting_review"); // observation never certifies merge/XP
        assert_eq!(s.sdlc_observe_pr("sdlc-pilot", &observed).unwrap(), closed);
        assert_eq!(
            coordination(&s.sdlc_records().unwrap(), &p, true)["admission"],
            "ready"
        );
        observed.observed_at += 0.001;
        observed.state = "open".into();
        s.sdlc_observe_pr("sdlc-pilot", &observed).unwrap();
        assert!(s.sdlc_admit_at(&next, true).is_err());
        observed.state = "merged".into();
        assert!(s.sdlc_observe_pr("sdlc-pilot", &observed).is_err()); // conflicting timestamp
        observed.observed_at += 0.001;
        let merged = s.sdlc_observe_pr("sdlc-pilot", &observed).unwrap();
        assert_eq!(merged["pr_history"].as_array().unwrap().len(), 3);
        let mut stale = merged.clone();
        stale["pr_observation"]["observed_at"] = json!(now() - 61.0);
        assert!(reserves_publication(&stale));
        s.sdlc_admit_at(&next, true).unwrap();
        assert_eq!(s.sdlc_mission("sdlc-pilot").unwrap(), merged);
    }

    #[test]
    fn malformed_pr_observations_cannot_release_reservations() {
        let s = setup();
        submitted(&s);
        for (number, head, state, at) in [
            (10, "e".repeat(40), "closed", now()),
            (9, "wrong".into(), "closed", now()),
            (9, "e".repeat(40), "success", now()),
            (9, "e".repeat(40), "closed", now() - 61.0),
            (9, "e".repeat(40), "closed", f64::NAN),
        ] {
            assert!(
                s.sdlc_observe_pr(
                    "sdlc-pilot",
                    &SdlcPrObservation {
                        number,
                        head,
                        state: state.into(),
                        observed_at: at
                    }
                )
                .is_err()
            );
        }
        assert!(reserves_publication(&s.sdlc_mission("sdlc-pilot").unwrap()));
        let pending = setup();
        pending.sdlc_admit_at(&input(), true).unwrap();
        assert!(
            pending
                .sdlc_observe_pr(
                    "sdlc-pilot",
                    &SdlcPrObservation {
                        number: 9,
                        head: "e".repeat(40),
                        state: "closed".into(),
                        observed_at: now()
                    }
                )
                .is_err()
        );
    }

    #[test]
    fn active_verifier_reserves_capacity_even_after_pr_closes() {
        let s = setup();
        submitted(&s);
        s.sdlc_verification_admit_at("sdlc-pilot", &verification_input(), true)
            .unwrap();
        s.sdlc_observe_pr(
            "sdlc-pilot",
            &SdlcPrObservation {
                number: 9,
                head: "e".repeat(40),
                state: "closed".into(),
                observed_at: now(),
            },
        )
        .unwrap();
        assert_eq!(
            coordination(&s.sdlc_records().unwrap(), &s.sdlc_policy().unwrap(), true)["admission"],
            "active_verification"
        );
        let mut i = input();
        i.id = "another".into();
        i.revision = "c".repeat(40);
        assert!(s.sdlc_admit_at(&i, true).is_err());
    }

    #[test]
    fn capability_and_pr_checkpoints_survive_store_reopen() {
        let path =
            std::env::temp_dir().join(format!("starbase-capability-{}.sqlite", std::process::id()));
        let s = Store::open(path.to_str().unwrap()).unwrap();
        s.sdlc_set_policy_at(&policy(0), true).unwrap();
        submitted(&s);
        let observation = SdlcPrObservation {
            number: 9,
            head: "e".repeat(40),
            state: "closed".into(),
            observed_at: now(),
        };
        let saved = s.sdlc_observe_pr("sdlc-pilot", &observation).unwrap();
        drop(s);
        let reopened = Store::open(path.to_str().unwrap()).unwrap();
        assert_eq!(reopened.sdlc_mission("sdlc-pilot").unwrap(), saved);
        assert_eq!(
            reopened
                .sdlc_observe_pr("sdlc-pilot", &observation)
                .unwrap(),
            saved
        );
        drop(reopened);
        std::fs::remove_file(path).unwrap();
    }
    #[test]
    fn reopened_pr_cannot_start_verification_over_an_active_initial_mission() {
        let s = setup();
        submitted(&s);
        let observed = SdlcPrObservation {
            number: 9,
            head: "e".repeat(40),
            state: "closed".into(),
            observed_at: now(),
        };
        s.sdlc_observe_pr("sdlc-pilot", &observed).unwrap();
        let mut next = input();
        next.id = "next-revision".into();
        next.revision = "c".repeat(40);
        s.sdlc_admit_at(&next, true).unwrap();
        let reopened = SdlcPrObservation {
            state: "open".into(),
            observed_at: now() + 0.001,
            ..observed
        };
        s.sdlc_observe_pr("sdlc-pilot", &reopened).unwrap();
        assert!(
            s.sdlc_verification_admit_at("sdlc-pilot", &verification_input(), true)
                .is_err()
        );
    }
    #[test]
    fn distinct_family_oracles_require_exact_behavior_and_never_inherit_history_pass() {
        for (family, expected) in [
            (
                "memory-key",
                json!({"memory_empty_key":[7],"memory_named":[9],"memory_missing":[],"memory_other_agent":[11],"memory_all":[7,9],"memory_zero":[0]}),
            ),
            (
                "logging-level",
                json!({"logging_initial":[10],"logging_update":[20],"logging_error":[40],"logging_handlers":[1],"logging_omitted":[40],"logging_other":[30]}),
            ),
        ] {
            let cases: Vec<Value> = expected
                .as_object()
                .unwrap()
                .iter()
                .map(|(id, actual)| json!({"id":id,"actual":actual}))
                .collect();
            let passing = json!({"exit_code":0,"cases":cases});
            let mut failing = passing.clone();
            failing["cases"][0]["actual"] = json!([-99]);
            let test = json!({"baseline":failing,"candidate":passing});
            assert_eq!(grade_for(&test, family)["verdict"], "improved");
            assert_eq!(grade(&test)["verdict"], "ineligible");
            assert_eq!(
                grade_for(&json!({"baseline":passing,"candidate":passing}), family)["verdict"],
                "ineligible"
            );
            let verified = json!({"observations":passing,"public":{"exit_code":0}});
            assert_eq!(
                verification_grade_for(&verified, family)["outcome"],
                "passed"
            );
            assert_eq!(
                verification_grade(&verified)["outcome"],
                "infrastructure_blocked"
            );
        }
    }

    #[test]
    fn failed_candidate_reassigns_once_without_changing_reviewer_or_build() {
        let s = setup();
        let original = s.sdlc_admit_at(&input(), true).unwrap();
        event(&s, "investigating", json!({}));
        event(&s, "implementing", json!({}));
        let mut failed = results();
        failed["candidate"]["cases"][0]["actual"] = json!([-1]);
        event(&s, "testing", failed);
        event(&s, "reviewing", json!({"status":"revise"}));
        let reassigned = s
            .sdlc_event(
                "sdlc-pilot",
                &SdlcEvent {
                    key: "revise-0".into(),
                    stage: "implementing".into(),
                    data: json!({}),
                },
            )
            .unwrap();
        assert_eq!(reassigned["coordination"]["assignments"][1]["crew"], "moss");
        assert_eq!(
            reassigned["coordination"]["assignments"][2]["crew"],
            "prism"
        );
        assert_eq!(reassigned["input"]["build"], original["input"]["build"]);
        assert_eq!(
            reassigned["coordination"]["reassignments"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
        assert!(
            s.sdlc_publication_at("sdlc-pilot", &publication(), true)
                .is_err()
        );
    }

    fn retained_test_feedback(s: &Store, sequence: usize, state: &str) -> Value {
        let mut parent = s.sdlc_mission("sdlc-pilot").unwrap();
        parent["evidence"]["submitted"]["branch"] = json!("starbase/sdlc-pilot");
        s.sdlc_save(&parent).unwrap();
        let head = verification_input().head;
        let comment_head = if state == "stale" {
            "a".repeat(40)
        } else {
            head.clone()
        };
        let mut captured = json!({
            "head":head,"lifecycle":"open","coverage":"complete",
            "comments":[{"id":"review:1","body":format!("feedback {sequence}"),
                "kind":"review","state":if state == "stale" { "stale" } else { "current" },
                "head":comment_head,"path":"src/utils/persistence.py"}]
        });
        let digest = hash(&captured);
        captured["digest"] = json!(digest);
        let input = crate::sdlc_feedback::FeedbackInput {
            head: head.clone(),
            digest: digest.clone(),
            captured,
            observed_at: now(),
            proposal: json!({"role":"feedback","output":{
                "head":head,"feedback_digest":digest,"advisory":true,"state":state,
                "comment_ids":["review:1"],"rationale":"Bounded review evidence",
                "paths":if state == "current" { json!(["src/utils/persistence.py"]) } else { json!([]) },
                "task":if state == "current" { "Preserve insertion order" } else { "" }
            }}),
        };
        serde_json::to_value(s.sdlc_record_feedback("sdlc-pilot", &input).unwrap()).unwrap()
    }

    #[test]
    fn feedback_verification_pins_current_evidence_and_deduplicates_changed_digests() {
        let s = setup();
        submitted(&s);
        let original = retained_test_feedback(&s, 1, "current");
        let mut i = verification_input();
        i.feedback_digest = original["digest"].as_str().map(String::from);
        let child = s
            .sdlc_verification_admit_at("sdlc-pilot", &i, true)
            .unwrap();
        assert_eq!(child["feedback"], original);
        assert_eq!(child["input"]["head"], original["head"]);
        assert_eq!(
            s.sdlc_verification_admit_at("sdlc-pilot", &i, true)
                .unwrap(),
            child
        );
        vevent(&s, "blocked", json!({"reason":"retained test outcome"}));
        let mut same = i.clone();
        same.id = "verify-duplicate-feedback".into();
        assert!(
            s.sdlc_verification_admit_at("sdlc-pilot", &same, true)
                .unwrap_err()
                .contains("already retained")
        );
        let changed = retained_test_feedback(&s, 2, "current");
        assert_ne!(original["digest"], changed["digest"]);
        // Adding new feedback cannot mutate evidence frozen into the first child.
        assert_eq!(
            s.sdlc_verification("sdlc-pilot", &i.id).unwrap()["feedback"],
            original
        );
        let mut next = i.clone();
        next.id = "verify-new-feedback".into();
        next.feedback_digest = changed["digest"].as_str().map(String::from);
        let second = s
            .sdlc_verification_admit_at("sdlc-pilot", &next, true)
            .unwrap();
        assert_eq!(second["feedback"], changed);
        assert_eq!(second["input"]["build"], child["input"]["build"]);
        assert_eq!(second["input"]["head"], child["input"]["head"]);
        i.feedback_digest = next.feedback_digest;
        assert!(
            s.sdlc_verification_admit_at("sdlc-pilot", &i, true)
                .unwrap_err()
                .contains("Conflicting verification identity")
        );
    }

    #[test]
    fn feedback_verification_rejects_wrong_head_missing_and_non_actionable_feedback() {
        for state in [
            "stale",
            "conflicting",
            "unknown",
            "no-change",
            "out-of-scope",
        ] {
            let s = setup();
            submitted(&s);
            let record = retained_test_feedback(&s, 0, state);
            let mut i = verification_input();
            i.feedback_digest = record["digest"].as_str().map(String::from);
            assert!(
                s.sdlc_verification_admit_at("sdlc-pilot", &i, true)
                    .unwrap_err()
                    .contains("not actionable")
            );
            assert!(s.sdlc_mission("sdlc-pilot").unwrap()["verifications"].is_null());
        }
        let s = setup();
        submitted(&s);
        let record = retained_test_feedback(&s, 0, "current");
        let mut i = verification_input();
        i.feedback_digest = record["digest"].as_str().map(String::from);
        i.head = "b".repeat(40);
        assert!(
            s.sdlc_verification_admit_at("sdlc-pilot", &i, true)
                .is_err()
        );
        i.head = verification_input().head;
        i.feedback_digest = Some("0".repeat(64));
        assert!(
            s.sdlc_verification_admit_at("sdlc-pilot", &i, true)
                .is_err()
        );
    }

    #[test]
    fn current_feedback_cannot_bypass_independent_regression_gate() {
        let s = setup();
        submitted(&s);
        let record = retained_test_feedback(&s, 0, "current");
        let mut i = verification_input();
        i.feedback_digest = record["digest"].as_str().map(String::from);
        s.sdlc_verification_admit_at("sdlc-pilot", &i, true)
            .unwrap();
        vevent(&s, "verifying", json!({}));
        let verified = vevent(
            &s,
            "verified",
            json!({
                "observations":results()["candidate"],"public":{"exit_code":0}
            }),
        );
        assert_eq!(verified["evidence"]["verified"]["outcome"], "passed");
        assert!(
            s.sdlc_verification_event(
                "sdlc-pilot",
                &i.id,
                &SdlcEvent {
                    key: "repair-from-comment".into(),
                    stage: "repairing".into(),
                    data: json!({})
                }
            )
            .unwrap_err()
            .contains("Only an observed regression")
        );
    }
}
