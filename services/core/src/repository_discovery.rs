//! Trusted, explicitly owner-scoped discovery. No provider credential enters this ledger.
use crate::{Result, Store, now, operations::hash, parameters as params};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::BTreeSet;

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct RepositoryDiscovery {
    pub owner: String,
    pub observed_at: f64,
    pub interval_seconds: u32,
    pub complete: bool,
    pub repositories: Vec<String>,
    pub error: Option<String>,
}
impl Store {
    pub fn repository_discoveries(&self) -> Result<Vec<Value>> {
        self.db
            .prepare("SELECT body FROM repository_discovery ORDER BY owner")
            .map_err(|e| e.to_string())?
            .query_map(params![], |r| r.get::<_, String>(0))
            .map_err(|e| e.to_string())?
            .map(|r| {
                serde_json::from_str(&r.map_err(|e| e.to_string())?).map_err(|e| e.to_string())
            })
            .collect()
    }
    pub fn discover_repositories(
        &mut self,
        input: &RepositoryDiscovery,
        allowed_owner: &str,
    ) -> Result<Value> {
        let owner = input.owner.to_ascii_lowercase();
        if owner.is_empty()
            || owner.len() > 39
            || !owner
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || c == b'-')
            || owner != allowed_owner.to_ascii_lowercase()
            || !crate::field::enabled()
        {
            return Err("Repository discovery owner is not enabled".into());
        }
        if !(300..=86400).contains(&input.interval_seconds)
            || !input.observed_at.is_finite()
            || input.repositories.len() > crate::repositories::WATCH_CAPACITY
            || (input.complete && input.error.is_some())
            || (!input.complete
                && (!input.repositories.is_empty()
                    || !matches!(
                        input.error.as_deref(),
                        Some("unavailable" | "rate_limited" | "incomplete" | "authentication")
                    )))
        {
            return Err("Invalid bounded discovery observation".into());
        }
        let observations = self.repository_discoveries()?;
        let previous = observations.iter().find(|r| r["owner"] == owner);
        let input_digest = hash(&json!(input));
        if let Some(old) = previous {
            if old["input_digest"] == input_digest {
                return Ok(old.clone());
            }
            if input.observed_at <= old["observed_at"].as_f64().unwrap_or(0.0) {
                return Err("Stale or conflicting discovery checkpoint".into());
            }
        }
        if (now() - input.observed_at).abs() > 300.0 {
            return Err("Discovery observation is not fresh".into());
        }
        let mut names = BTreeSet::new();
        for name in &input.repositories {
            let name = name.to_ascii_lowercase();
            let parts: Vec<_> = name.split('/').collect();
            if parts.len() != 2
                || parts[0] != owner
                || parts[1].is_empty()
                || parts[1].len() > 100
                || matches!(parts[1], "." | "..")
                || !parts[1]
                    .bytes()
                    .all(|c| c.is_ascii_alphanumeric() || b"-_.".contains(&c))
                || !names.insert(name)
            {
                return Err("Discovery repository identity is invalid or outside owner".into());
            }
        }
        let watches = self.repositories()?;
        let existing: BTreeSet<String> = watches
            .iter()
            .filter_map(|w| w["config"]["repository"].as_str().map(String::from))
            .collect();
        let additions: Vec<_> = names.difference(&existing).cloned().collect();
        let active = watches
            .iter()
            .filter(|w| w["config"]["removed"] != true)
            .count();
        if active + additions.len() > crate::repositories::WATCH_CAPACITY {
            return Err("Repository watch capacity exceeded; inventory not applied".into());
        }
        let value = json!({"owner":owner,"observed_at":input.observed_at,"input_digest":input_digest,
            "complete":input.complete,"error":input.error,"interval_seconds":input.interval_seconds,
            "repositories":if input.complete {json!(names)} else {previous.map_or(json!([]),|r|r["repositories"].clone())},
            "last_success_at":if input.complete {json!(input.observed_at)} else {previous.map_or(Value::Null,|r|r["last_success_at"].clone())},
            "added":additions.len(),"authority":"read-only GitHub observation; local watch enrollment only"});
        let tx = self.db.transaction().map_err(|e| e.to_string())?;
        for repo in additions {
            let id = format!("repo-{}", &hash(&json!(repo))[..24]);
            let body = json!({"id":id,"config":{"repository":repo,"interval_seconds":input.interval_seconds,"enabled":true,"removed":false,"generation":0},"updated_at":now()});
            tx.execute(
                "INSERT INTO repository_watches VALUES ($1,$2)",
                params![id, body.to_string()],
            )
            .map_err(|e| e.to_string())?;
        }
        tx.execute("INSERT INTO repository_discovery VALUES ($1,$2) ON CONFLICT(owner) DO UPDATE SET body=excluded.body",params![owner,value.to_string()]).map_err(|e|e.to_string())?;
        tx.commit().map_err(|e| e.to_string())?;
        Ok(value)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn discovery_is_atomic_owner_scoped_and_preserves_operator_controls() {
        let mut s = crate::test_store();
        let mut input = RepositoryDiscovery {
            owner: "X-McKay".into(),
            observed_at: now(),
            interval_seconds: 900,
            complete: true,
            repositories: vec!["X-McKay/one".into(), "X-McKay/two".into()],
            error: None,
        };
        assert!(s.discover_repositories(&input, "another").is_err());
        let first = s.discover_repositories(&input, "X-McKay").unwrap();
        assert_eq!(first["added"], 2);
        assert_eq!(s.discover_repositories(&input, "X-McKay").unwrap(), first);
        s.set_repository(&crate::repositories::RepositoryWatch {
            repository: "x-mckay/one".into(),
            interval_seconds: 900,
            enabled: false,
            removed: true,
            generation: 1,
        })
        .unwrap();
        input.observed_at += 1.0;
        input.repositories.push("x-mckay/three".into());
        s.discover_repositories(&input, "X-McKay").unwrap();
        assert!(
            s.repositories()
                .unwrap()
                .iter()
                .any(|w| w["config"]["repository"] == "x-mckay/one"
                    && w["config"]["removed"] == true)
        );
        input.observed_at += 1.0;
        input.repositories.push("other/escape".into());
        assert!(s.discover_repositories(&input, "X-McKay").is_err());
        assert_eq!(s.repositories().unwrap().len(), 3);
        input.repositories.clear();
        input.complete = false;
        input.error = Some("unavailable".into());
        let failed = s.discover_repositories(&input, "X-McKay").unwrap();
        assert_eq!(failed["repositories"].as_array().unwrap().len(), 3);
        assert_eq!(s.repositories().unwrap().len(), 3);
        input.observed_at -= 1.0;
        assert!(s.discover_repositories(&input, "X-McKay").is_err());
    }
    #[test]
    fn checkpoint_and_watches_survive_reopen() {
        let path = std::env::temp_dir().join(format!(
            "starbase-discovery-{}-{}.sqlite",
            std::process::id(),
            now()
        ));
        let input = RepositoryDiscovery {
            owner: "example".into(),
            observed_at: now(),
            interval_seconds: 900,
            complete: true,
            repositories: vec!["example/repo".into()],
            error: None,
        };
        let mut s = Store::open(path.to_str().unwrap()).unwrap();
        let value = s.discover_repositories(&input, "example").unwrap();
        drop(s);
        let s = Store::open(path.to_str().unwrap()).unwrap();
        assert_eq!(s.repository_discoveries().unwrap(), vec![value]);
        assert_eq!(s.repositories().unwrap().len(), 1);
        drop(s);
        std::fs::remove_file(path).unwrap();
    }
}

#[cfg(test)]
mod fleet_acceptance_tests {
    use super::*;

    fn observation() -> RepositoryDiscovery {
        RepositoryDiscovery {
            owner: "fleet".into(),
            observed_at: now(),
            interval_seconds: 900,
            complete: true,
            repositories: vec!["fleet/new".into()],
            error: None,
        }
    }

    #[test]
    fn discovery_rolls_back_watch_enrollment_when_checkpoint_write_fails() {
        let mut store = crate::test_store();
        store.db.execute_batch("CREATE TRIGGER reject_checkpoint BEFORE INSERT ON repository_discovery BEGIN SELECT RAISE(ABORT, 'synthetic checkpoint failure'); END;").unwrap();
        assert!(
            store
                .discover_repositories(&observation(), "fleet")
                .is_err()
        );
        assert!(store.repositories().unwrap().is_empty());
        assert!(store.repository_discoveries().unwrap().is_empty());
        store
            .db
            .execute_batch("DROP TRIGGER reject_checkpoint;")
            .unwrap();
        assert_eq!(
            store
                .discover_repositories(&observation(), "fleet")
                .unwrap()["added"],
            1
        );
    }

    #[test]
    fn invalid_observations_do_not_advance_checkpoint_or_change_watches() {
        let mut store = crate::test_store();
        let input = observation();
        let first = store.discover_repositories(&input, "fleet").unwrap();
        let mut variants = Vec::new();
        let mut bad = input.clone();
        bad.observed_at = f64::NAN;
        variants.push(bad);
        let mut bad = input.clone();
        bad.observed_at += 301.0;
        variants.push(bad);
        let mut bad = input.clone();
        bad.observed_at -= 301.0;
        variants.push(bad);
        let mut bad = input.clone();
        bad.repositories.push("fleet/NEW".into());
        variants.push(bad);
        let mut bad = input.clone();
        bad.repositories.push("other/repo".into());
        variants.push(bad);
        let mut bad = input.clone();
        bad.complete = false;
        bad.error = Some("unavailable".into());
        variants.push(bad);
        let mut bad = input.clone();
        bad.error = Some("secret diagnostic".into());
        variants.push(bad);
        let mut bad = input.clone();
        bad.interval_seconds = 30;
        variants.push(bad);
        for mut bad in variants {
            // Distinct timestamp gets identity-validation variants past replay fencing.
            if bad.observed_at == input.observed_at {
                bad.observed_at += 1.0;
            }
            assert!(store.discover_repositories(&bad, "fleet").is_err());
            assert_eq!(store.repository_discoveries().unwrap(), vec![first.clone()]);
            assert_eq!(store.repositories().unwrap().len(), 1);
        }
        let mut untyped = json!(input);
        untyped["enabled"] = json!(true);
        assert!(serde_json::from_value::<RepositoryDiscovery>(untyped).is_err());
    }

    #[test]
    fn enrollment_preserves_pause_interval_generation_and_capacity_is_atomic() {
        let mut store = crate::test_store();
        store
            .set_repository(&crate::repositories::RepositoryWatch {
                repository: "fleet/existing".into(),
                interval_seconds: 3600,
                enabled: false,
                removed: false,
                generation: 0,
            })
            .unwrap();
        let mut input = observation();
        input.repositories.push("fleet/existing".into());
        store.discover_repositories(&input, "fleet").unwrap();
        let watched = store.repositories().unwrap();
        let paused = watched
            .iter()
            .find(|w| w["config"]["repository"] == "fleet/existing")
            .unwrap();
        assert_eq!(paused["config"]["enabled"], false);
        assert_eq!(paused["config"]["interval_seconds"], 3600);
        assert_eq!(paused["config"]["generation"], 0);
        let before = store.repository_discoveries().unwrap();
        input.observed_at += 1.0;
        input.repositories = (0..256).map(|n| format!("fleet/extra-{n}")).collect();
        assert!(
            store
                .discover_repositories(&input, "fleet")
                .unwrap_err()
                .contains("capacity")
        );
        assert_eq!(store.repositories().unwrap(), watched);
        assert_eq!(store.repository_discoveries().unwrap(), before);
    }

    #[test]
    fn sqlite_seven_upgrade_preserves_watches_and_adds_checkpoint_once() {
        let path = std::env::temp_dir().join(format!(
            "starbase-discovery-upgrade-{}-{}.sqlite",
            std::process::id(),
            now()
        ));
        let store = Store::open(path.to_str().unwrap()).unwrap();
        let watch = store
            .set_repository(&crate::repositories::RepositoryWatch {
                repository: "fleet/preserved".into(),
                interval_seconds: 900,
                enabled: false,
                removed: false,
                generation: 0,
            })
            .unwrap();
        store
            .db
            .execute_batch("DROP TABLE sdlc_discoveries; DROP TABLE sdlc_missions; DROP TABLE sdlc_policy; DROP TABLE repository_discovery; PRAGMA user_version=7;")
            .unwrap();
        drop(store);
        let mut upgraded = Store::open(path.to_str().unwrap()).unwrap();
        assert_eq!(upgraded.repositories().unwrap(), vec![watch]);
        assert!(upgraded.repository_discoveries().unwrap().is_empty());
        let checkpoint = upgraded
            .discover_repositories(&observation(), "fleet")
            .unwrap();
        drop(upgraded);
        let reopened = Store::open(path.to_str().unwrap()).unwrap();
        assert_eq!(reopened.repository_discoveries().unwrap(), vec![checkpoint]);
        assert_eq!(reopened.repositories().unwrap().len(), 2);
        drop(reopened);
        std::fs::remove_file(path).unwrap();
    }
}
