//! Bounded, durable opportunity observations. Discovery is not publication authority.
use crate::{Result, Store, now, operations::hash, parameters as params, sdlc};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

const MAX_DISCOVERIES: usize = 256;
const MAX_HISTORY: usize = 16;

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct DiscoveryInput {
    pub repository: String,
    pub revision: Option<String>,
    pub opportunity: String,
    pub build: Value,
    pub capability_digest: String,
    pub source_digest: Option<String>,
    pub outcome: String,
    pub reason: String,
    pub observed_at: f64,
}

fn digest(value: &str, length: usize) -> bool {
    value.len() == length
        && value
            .bytes()
            .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
}

impl Store {
    fn sdlc_discovery_records(&self) -> Result<Vec<Value>> {
        self.db
            .prepare("SELECT body FROM sdlc_discoveries ORDER BY id")
            .map_err(|e| e.to_string())?
            .query_map(params![], |r| r.get::<_, String>(0))
            .map_err(|e| e.to_string())?
            .map(|row| {
                serde_json::from_str(&row.map_err(|e| e.to_string())?).map_err(|e| e.to_string())
            })
            .collect()
    }

    fn sdlc_discovery_view(&self, mut record: Value) -> Result<Value> {
        match self.sdlc_mission(
            record["mission_id"]
                .as_str()
                .ok_or("Missing mission identity")?,
        ) {
            Ok(mission) => {
                record["status"] = json!("admitted");
                record["mission_state"] = mission["state"].clone();
            }
            Err(error) if error == "Unknown SDLC mission" => {
                record["status"] = record["outcome"].clone();
                record["mission_state"] = Value::Null;
            }
            Err(error) => return Err(error),
        }
        Ok(record)
    }

    pub fn sdlc_discoveries(&self) -> Result<Vec<Value>> {
        self.sdlc_discovery_records()?
            .into_iter()
            .map(|record| self.sdlc_discovery_view(record))
            .collect()
    }

    pub fn sdlc_discover(&self, input: &DiscoveryInput) -> Result<Value> {
        self.sdlc_discover_at(input, sdlc::enabled(), now())
    }

    fn sdlc_discover_at(&self, input: &DiscoveryInput, on: bool, at: f64) -> Result<Value> {
        let policy = self.sdlc_policy()?;
        if !on || policy["enabled"] != true || policy["expires_at"].as_f64().unwrap_or(0.0) <= at {
            return Err("Discovery policy is disabled or expired".into());
        }
        let contract = sdlc::capability(&input.repository, &input.opportunity)
            .ok_or("Unknown repository capability")?;
        if contract["digest"] != input.capability_digest
            || input.build["manifest"]["capability_digest"] != input.capability_digest
        {
            return Err("Discovery capability/build mismatch".into());
        }
        if !input.build.is_object()
            || !digest(input.build["digest"].as_str().unwrap_or(""), 64)
            || json!(input).to_string().len() > 32768
            || !matches!(
                input.outcome.as_str(),
                "candidate" | "no_change" | "unavailable"
            )
            || input.reason.trim().is_empty()
            || input.reason.len() > 500
            || !input.observed_at.is_finite()
            || (input.observed_at - at).abs() > 60.0
            || input.revision.as_ref().is_some_and(|r| !digest(r, 40))
            || input.source_digest.as_ref().is_some_and(|d| !digest(d, 64))
            || (input.outcome != "unavailable"
                && (input.revision.is_none() || input.source_digest.is_none()))
        {
            return Err("Invalid or stale discovery observation".into());
        }
        let identity = hash(&json!([
            input.repository.to_ascii_lowercase(),
            input.revision,
            input.opportunity,
            input.build["digest"]
        ]));
        let id = format!("discovery-{}", &identity[..24]);
        let records = self.sdlc_discovery_records()?;
        let checkpoint = json!({"outcome":input.outcome, "reason":input.reason,
            "source_digest":input.source_digest, "observed_at":input.observed_at});
        let mut record = if let Some(old) = records.iter().find(|r| r["id"] == id) {
            if old["build"] != input.build
                || old["capability_digest"] != input.capability_digest
                || old["repository"] != input.repository.to_ascii_lowercase()
                || old["revision"] != json!(input.revision)
                || old["opportunity"] != input.opportunity
                || (!old["pinned_source_digest"].is_null()
                    && input.source_digest.is_some()
                    && old["pinned_source_digest"] != json!(input.source_digest))
            {
                return Err("Conflicting immutable discovery identity".into());
            }
            if input.observed_at < old["observed_at"].as_f64().unwrap_or(0.0) {
                return Err("Older discovery checkpoint".into());
            }
            let changed = old["outcome"] != input.outcome
                || old["reason"] != input.reason
                || old["source_digest"] != json!(input.source_digest);
            if changed && input.observed_at == old["observed_at"].as_f64().unwrap_or(0.0) {
                return Err("Conflicting discovery checkpoint".into());
            }
            let mut updated = old.clone();
            if changed {
                let history = updated["history"]
                    .as_array_mut()
                    .ok_or("Missing discovery history")?;
                if history.len() >= MAX_HISTORY {
                    return Err("Discovery history capacity exhausted".into());
                }
                history.push(checkpoint);
            }
            updated["outcome"] = json!(input.outcome);
            updated["reason"] = json!(input.reason);
            updated["source_digest"] = json!(input.source_digest);
            if updated["pinned_source_digest"].is_null() && input.source_digest.is_some() {
                updated["pinned_source_digest"] = json!(input.source_digest);
            }
            updated["observed_at"] = json!(input.observed_at);
            updated["updated_at"] = json!(at);
            updated
        } else {
            if records.len() >= MAX_DISCOVERIES {
                return Err("Discovery retention capacity exhausted".into());
            }
            let mut created = json!(input);
            created["id"] = json!(id);
            created["repository"] = json!(input.repository.to_ascii_lowercase());
            created["mission_id"] = json!(format!("sdlc-{}", &identity[..24]));
            created["priority"] = contract["priority"].clone();
            created["pinned_source_digest"] = json!(input.source_digest);
            created["created_at"] = json!(at);
            created["updated_at"] = json!(at);
            created["history"] = json!([checkpoint]);
            created
        };
        // Derived mission status never replaces the original discovery build or observation.
        record.as_object_mut().unwrap().remove("status");
        record.as_object_mut().unwrap().remove("mission_state");
        self.db.execute(
            "INSERT INTO sdlc_discoveries(id,body) VALUES($1,$2) ON CONFLICT(id) DO UPDATE SET body=excluded.body",
            params![id, record.to_string()],
        ).map_err(|e| e.to_string())?;
        self.sdlc_discovery_view(record)
    }

    pub fn sdlc_admit_discovery(&self, id: &str) -> Result<Value> {
        self.sdlc_admit_discovery_at(id, sdlc::enabled(), now())
    }

    fn sdlc_admit_discovery_at(&self, id: &str, on: bool, at: f64) -> Result<Value> {
        let record = self
            .sdlc_discovery_records()?
            .into_iter()
            .find(|r| r["id"] == id)
            .ok_or("Unknown discovery identity")?;
        let observed_at = record["observed_at"]
            .as_f64()
            .ok_or("Invalid discovery checkpoint")?;
        if !on
            || record["outcome"] != "candidate"
            || at - observed_at > 300.0
            || observed_at > at + 60.0
        {
            return Err("Discovery is not a fresh candidate".into());
        }
        let input = sdlc::SdlcInput {
            id: record["mission_id"]
                .as_str()
                .ok_or("Missing mission identity")?
                .into(),
            repository: record["repository"]
                .as_str()
                .ok_or("Missing repository")?
                .into(),
            revision: record["revision"]
                .as_str()
                .ok_or("Missing revision")?
                .into(),
            opportunity: record["opportunity"]
                .as_str()
                .ok_or("Missing opportunity")?
                .into(),
            build: record["build"].clone(),
            capability_digest: Some(
                record["capability_digest"]
                    .as_str()
                    .ok_or("Missing capability digest")?
                    .into(),
            ),
        };
        // Mission insertion is the single durable write: a lost acknowledgement replays
        // the same immutable input/id through Core's ordinary policy and uniqueness gates.
        self.sdlc_admit_at(&input, on)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn setup() -> Store {
        let store = Store::open(":memory:").unwrap();
        enable(&store);
        store
    }
    fn enable(store: &Store) {
        store
            .sdlc_set_policy_at(
                &sdlc::SdlcPolicy {
                    repository: "X-McKay/algent".into(),
                    enabled: true,
                    publish: true,
                    generation: 0,
                    max_missions: 3,
                    expires_at: now() + 3600.0,
                },
                true,
            )
            .unwrap();
    }
    fn input() -> DiscoveryInput {
        let cap = sdlc::capability("x-mckay/algent", "memory-key").unwrap();
        DiscoveryInput {
            repository: "X-McKay/algent".into(),
            revision: Some("a".repeat(40)),
            opportunity: "memory-key".into(),
            build: json!({"digest":"b".repeat(64), "manifest":{"capability_digest":cap["digest"]}}),
            capability_digest: cap["digest"].as_str().unwrap().into(),
            source_digest: Some("c".repeat(64)),
            outcome: "candidate".into(),
            reason: "known empty-key condition".into(),
            observed_at: now(),
        }
    }
    #[test]
    fn checkpoints_deduplicate_and_preserve_build() {
        let store = setup();
        let mut i = input();
        let first = store.sdlc_discover_at(&i, true, i.observed_at).unwrap();
        i.observed_at += 1.0;
        let refresh = store.sdlc_discover_at(&i, true, i.observed_at).unwrap();
        assert_eq!(first["id"], refresh["id"]);
        assert_eq!(refresh["history"].as_array().unwrap().len(), 1);
        assert_eq!(refresh["build"], first["build"]);
        i.observed_at += 1.0;
        i.outcome = "unavailable".into();
        let failed = store.sdlc_discover_at(&i, true, i.observed_at).unwrap();
        assert_eq!(failed["history"].as_array().unwrap().len(), 2);
        assert_eq!(failed["status"], "unavailable");
        assert_eq!(store.sdlc_discoveries().unwrap().len(), 1);
        i.build["digest"] = json!("d".repeat(64));
        let other = store.sdlc_discover_at(&i, true, i.observed_at).unwrap();
        assert_ne!(first["id"], other["id"]);
        assert_eq!(store.sdlc_discoveries().unwrap().len(), 2);
    }
    #[test]
    fn only_fresh_candidates_admit_and_replay_one_mission() {
        let store = setup();
        let i = input();
        let found = store.sdlc_discover_at(&i, true, i.observed_at).unwrap();
        let id = found["id"].as_str().unwrap();
        assert!(
            store
                .sdlc_admit_discovery_at(id, true, i.observed_at + 301.0)
                .is_err()
        );
        assert!(
            store
                .sdlc_admit_discovery_at(id, false, i.observed_at)
                .is_err()
        );
        let first = store
            .sdlc_admit_discovery_at(id, true, i.observed_at)
            .unwrap();
        let replay = store
            .sdlc_admit_discovery_at(id, true, i.observed_at)
            .unwrap();
        assert_eq!(first, replay);
        assert_eq!(
            store.sdlc_snapshot().unwrap()["missions"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
        let view = store.sdlc_discoveries().unwrap().remove(0);
        assert_eq!(view["status"], "admitted");
        assert_eq!(view["mission_state"], "queued");
        assert_eq!(view["build"], i.build);
    }
    #[test]
    fn nochange_and_unknown_revision_cannot_admit() {
        for outcome in ["no_change", "unavailable"] {
            let store = setup();
            let mut i = input();
            i.outcome = outcome.into();
            if outcome == "unavailable" {
                i.revision = None;
                i.source_digest = None;
            }
            let found = store.sdlc_discover_at(&i, true, i.observed_at).unwrap();
            assert_eq!(found["status"], outcome);
            assert!(
                store
                    .sdlc_admit_discovery_at(found["id"].as_str().unwrap(), true, i.observed_at)
                    .is_err()
            );
        }
    }
    #[test]
    fn invalid_scope_build_revision_and_clock_are_rejected() {
        let store = setup();
        for mutation in 0..9 {
            let mut i = input();
            let at = i.observed_at;
            match mutation {
                0 => i.repository = "x-mckay/other".into(),
                1 => i.capability_digest = "d".repeat(64),
                2 => i.build["manifest"]["capability_digest"] = json!("d".repeat(64)),
                3 => i.revision = None,
                4 => i.source_digest = None,
                5 => i.observed_at -= 61.0,
                6 => i.observed_at += 61.0,
                7 => i.observed_at = f64::NAN,
                _ => i.reason = "x".repeat(501),
            }
            assert!(
                store.sdlc_discover_at(&i, true, at).is_err(),
                "mutation {mutation}"
            );
        }
        assert!(store.sdlc_discover_at(&input(), false, now()).is_err());
    }
    #[test]
    fn stale_conflicting_checkpoint_and_mutated_build_are_rejected() {
        let store = setup();
        let i = input();
        store.sdlc_discover_at(&i, true, i.observed_at).unwrap();
        let mut older = i.clone();
        older.observed_at -= 1.0;
        assert!(store.sdlc_discover_at(&older, true, i.observed_at).is_err());
        let mut changed = i.clone();
        changed.reason = "conflict".into();
        assert!(
            store
                .sdlc_discover_at(&changed, true, i.observed_at)
                .is_err()
        );
        let mut changed = i.clone();
        changed.build["manifest"]["unexpected"] = json!(true);
        assert!(
            store
                .sdlc_discover_at(&changed, true, i.observed_at)
                .is_err()
        );
        let mut changed = i.clone();
        changed.source_digest = Some("f".repeat(64));
        assert!(
            store
                .sdlc_discover_at(&changed, true, i.observed_at)
                .is_err()
        );
    }
    #[test]
    fn unavailable_refresh_cannot_erase_original_source_identity() {
        let store = setup();
        let mut i = input();
        store.sdlc_discover_at(&i, true, i.observed_at).unwrap();
        i.observed_at += 1.0;
        i.outcome = "unavailable".into();
        i.source_digest = None;
        store.sdlc_discover_at(&i, true, i.observed_at).unwrap();
        i.observed_at += 1.0;
        i.outcome = "candidate".into();
        i.source_digest = Some("f".repeat(64));
        assert!(store.sdlc_discover_at(&i, true, i.observed_at).is_err());
        i.source_digest = Some("c".repeat(64));
        assert!(store.sdlc_discover_at(&i, true, i.observed_at).is_ok());
    }
    #[test]
    fn history_bound_stops_changes_but_permits_refresh() {
        let store = setup();
        let mut i = input();
        for index in 0..MAX_HISTORY {
            i.reason = format!("checkpoint {index}");
            i.observed_at += 1.0;
            store.sdlc_discover_at(&i, true, i.observed_at).unwrap();
        }
        i.observed_at += 1.0;
        let refreshed = store.sdlc_discover_at(&i, true, i.observed_at).unwrap();
        assert_eq!(refreshed["history"].as_array().unwrap().len(), MAX_HISTORY);
        i.reason = "over capacity".into();
        i.observed_at += 1.0;
        assert!(store.sdlc_discover_at(&i, true, i.observed_at).is_err());
    }
    #[test]
    fn record_bound_does_not_delete_evidence() {
        let store = setup();
        let mut i = input();
        for index in 0..MAX_DISCOVERIES {
            i.revision = Some(format!("{index:040x}"));
            store.sdlc_discover_at(&i, true, i.observed_at).unwrap();
        }
        i.revision = Some("f".repeat(40));
        assert!(store.sdlc_discover_at(&i, true, i.observed_at).is_err());
        assert_eq!(store.sdlc_discoveries().unwrap().len(), MAX_DISCOVERIES);
    }
    #[test]
    fn migration_and_reopen_preserve_discovery_and_admission() {
        let path = std::env::temp_dir().join(format!(
            "starbase-discovery-{}.sqlite",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let i = input();
        let store = Store::open(path.to_str().unwrap()).unwrap();
        enable(&store);
        let found = store.sdlc_discover_at(&i, true, i.observed_at).unwrap();
        let id = found["id"].as_str().unwrap();
        let admitted = store
            .sdlc_admit_discovery_at(id, true, i.observed_at)
            .unwrap();
        drop(store);
        let reopened = Store::open(path.to_str().unwrap()).unwrap();
        assert_eq!(reopened.sdlc_discoveries().unwrap()[0]["build"], i.build);
        assert_eq!(
            reopened
                .sdlc_admit_discovery_at(id, true, i.observed_at)
                .unwrap(),
            admitted
        );
        drop(reopened);
        std::fs::remove_file(path).unwrap();
    }
}
