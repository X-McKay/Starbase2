//! Repository watch configuration; removal retains the ledger and stops future dispatch.
use crate::operations::hash;
use crate::{Result, Store, now, parameters as params};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

pub(crate) const WATCH_CAPACITY: usize = 256;

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct RepositoryWatch {
    pub repository: String,
    pub interval_seconds: u32,
    pub enabled: bool,
    pub removed: bool,
    pub generation: u32,
}
impl Store {
    pub fn repositories(&self) -> Result<Vec<Value>> {
        let mut watches: Vec<Value> = self
            .db
            .prepare("SELECT body FROM repository_watches ORDER BY id")
            .map_err(|e| e.to_string())?
            .query_map(params![], |r| r.get::<_, String>(0))
            .map_err(|e| e.to_string())?
            .map(|r| {
                serde_json::from_str(&r.map_err(|e| e.to_string())?).map_err(|e| e.to_string())
            })
            .collect::<Result<_>>()?;
        let latest: std::collections::HashMap<String, Value> = self.db.prepare(self.db.dialect(
            "SELECT target,body FROM (SELECT body,json_extract(body,'$.input.target') AS target,ROW_NUMBER() OVER (PARTITION BY json_extract(body,'$.input.target') ORDER BY at DESC,id DESC) AS rank FROM field_runs) AS latest WHERE rank=1 AND target IN (SELECT id FROM repository_watches)",
            "SELECT target,body FROM (SELECT body,body::jsonb->'input'->>'target' AS target,ROW_NUMBER() OVER (PARTITION BY body::jsonb->'input'->>'target' ORDER BY at DESC,id DESC) AS rank FROM field_runs) AS latest WHERE rank=1 AND target IN (SELECT id FROM repository_watches)",
        )).map_err(|e| e.to_string())?.query_map(params![], |r| Ok((r.get::<_,String>(0)?,r.get::<_,String>(1)?)))
            .map_err(|e| e.to_string())?.map(|r| {
                let (target, body) = r.map_err(|e| e.to_string())?;
                let run: Value = serde_json::from_str(&body).map_err(|e| e.to_string())?;
                Ok((target, crate::field::summarize_run(&run)))
            }).collect::<Result<_>>()?;
        for watch in &mut watches {
            watch["latest_run"] = latest
                .get(watch["id"].as_str().unwrap())
                .cloned()
                .unwrap_or(Value::Null);
        }
        Ok(watches)
    }
    pub fn set_repository(&self, input: &RepositoryWatch) -> Result<Value> {
        let repo = input.repository.trim().to_ascii_lowercase();
        let parts: Vec<_> = repo.split('/').collect();
        if parts.len() != 2
            || parts.iter().any(|p| {
                p.is_empty()
                    || p.len() > 100
                    || *p == "."
                    || *p == ".."
                    || !p
                        .bytes()
                        .all(|c| c.is_ascii_alphanumeric() || b"-_.".contains(&c))
            })
            || !(30..=86400).contains(&input.interval_seconds)
            || (input.removed && input.enabled)
        {
            return Err(
                "Use owner/repository, a 30–86400 second interval and a valid watch state".into(),
            );
        }
        if input.enabled && !crate::field::enabled() {
            return Err("Field work is disabled".into());
        }
        let id = format!("repo-{}", &hash(&json!(repo))[..24]);
        let all = self.repositories()?;
        let old = all.iter().find(|r| r["id"] == id);
        let config = json!(RepositoryWatch {
            repository: repo,
            ..input.clone()
        });
        if old.is_some_and(|r| r["config"] == config) {
            return Ok(old.unwrap().clone());
        }
        let expected = old.map_or(0, |r| r["config"]["generation"].as_u64().unwrap() + 1);
        if u64::from(input.generation) != expected {
            return Err("Watch changed; refresh before editing".into());
        }
        if !input.removed
            && old.is_none_or(|r| r["config"]["removed"] == true)
            && all
                .iter()
                .filter(|r| r["config"]["removed"] != true)
                .count()
                >= WATCH_CAPACITY
        {
            return Err(format!(
                "Watch budget reached ({WATCH_CAPACITY} repositories)"
            ));
        }
        let mut value = json!({"id":id,"config":config,"updated_at":now()});
        self.db.execute("INSERT INTO repository_watches VALUES ($1,$2) ON CONFLICT(id) DO UPDATE SET body=excluded.body",params![id,value.to_string()]).map_err(|e|e.to_string())?;
        value["latest_run"] = old.map_or(Value::Null, |r| r["latest_run"].clone());
        Ok(value)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn watch(store: &Store, number: usize) -> Value {
        store
            .set_repository(&RepositoryWatch {
                repository: format!("fixture/repository-{number}"),
                interval_seconds: 300,
                enabled: true,
                removed: false,
                generation: 0,
            })
            .unwrap()
    }
    fn register(store: &Store, watch: &Value) {
        let manifest = json!({"agent":"reviewer","target":{"id":watch["id"],"kind":"github_repository","repository":watch["config"]["repository"],"allow_inference":false},"authority":"read-only"});
        store
            .field_build(&json!({"manifest":manifest,"digest":hash(&manifest)}))
            .unwrap();
    }
    #[test]
    fn capacity_and_snapshot_preserve_every_watched_target() {
        let store = crate::test_store();
        for n in 0..WATCH_CAPACITY {
            let w = watch(&store, n);
            register(&store, &w);
        }
        assert_eq!(
            store.field_snapshot().unwrap()["builds"]
                .as_array()
                .unwrap()
                .len(),
            WATCH_CAPACITY
        );
        assert!(
            store
                .set_repository(&RepositoryWatch {
                    repository: "fixture/overflow".into(),
                    interval_seconds: 300,
                    enabled: false,
                    removed: false,
                    generation: 0,
                })
                .unwrap_err()
                .contains("256")
        );
    }
    #[test]
    fn fleet_admission_is_fair_bounded_and_keeps_per_watch_history() {
        let mut store = crate::test_store();
        let mut watches: Vec<_> = (0..41)
            .map(|n| {
                let w = watch(&store, n);
                register(&store, &w);
                w
            })
            .collect();
        watches.sort_by_key(|w| w["id"].as_str().unwrap().to_owned());
        // A late-sorting timer cannot repeatedly steal a never-observed target's slot.
        assert_eq!(
            store
                .field_tick(watches[40]["id"].as_str().unwrap(), 0, 1)
                .unwrap()["outcome"],
            "deferred"
        );
        let mut admitted = Vec::new();
        for w in &watches[..20] {
            admitted.push(store.field_tick(w["id"].as_str().unwrap(), 0, 1).unwrap());
        }
        assert_eq!(
            admitted.iter().filter(|r| r["state"] == "queued").count(),
            20
        );
        assert_eq!(
            store
                .field_tick(watches[20]["id"].as_str().unwrap(), 0, 1)
                .unwrap()["reason"],
            "active_run_budget"
        );
        for r in &admitted {
            store
                .field_update(r["input"]["id"].as_str().unwrap(), "failed", json!({}))
                .unwrap();
        }
        for w in &watches[20..40] {
            let run = store.field_tick(w["id"].as_str().unwrap(), 0, 2).unwrap();
            assert_eq!(run["state"], "queued");
            store
                .field_update(run["input"]["id"].as_str().unwrap(), "failed", json!({}))
                .unwrap();
        }
        assert_eq!(
            store
                .field_tick(watches[40]["id"].as_str().unwrap(), 0, 3)
                .unwrap()["state"],
            "queued"
        );
        // Newer runs can evict an old observation from global history, not its watch.
        let hot = watches[20]["id"].as_str().unwrap();
        for n in 0..125 {
            let run = store
                .create_field(&crate::field::FieldInput {
                    id: format!("recent-{n}"),
                    agent: "reviewer".into(),
                    target: hot.into(),
                    inference: false,
                })
                .unwrap();
            store
                .field_update(run["input"]["id"].as_str().unwrap(), "failed", json!({}))
                .unwrap();
        }
        let snapshot = store.field_snapshot().unwrap();
        assert!(
            !snapshot["runs"]
                .as_array()
                .unwrap()
                .iter()
                .any(|r| r["input"]["target"] == watches[0]["id"])
        );
        let old = store
            .repositories()
            .unwrap()
            .into_iter()
            .find(|w| w["id"] == watches[0]["id"])
            .unwrap();
        assert_eq!(old["latest_run"]["state"], "failed");
        assert!(old["latest_run"].get("snapshot").is_none());
    }
    #[test]
    fn watch_normalizes_fences_stale_edits_and_retains_removal() {
        let mut s = crate::test_store();
        let mut w = RepositoryWatch {
            repository: " X-McKay/Starbase2 ".into(),
            interval_seconds: 300,
            enabled: true,
            removed: false,
            generation: 0,
        };
        let first = s.set_repository(&w).unwrap();
        assert_eq!(first["config"]["repository"], "x-mckay/starbase2");
        assert_eq!(s.set_repository(&w).unwrap(), first);
        let id = first["id"].as_str().unwrap();
        let manifest = json!({"agent":"reviewer","target":{"id":id,"kind":"github_repository","repository":"x-mckay/starbase2","allow_inference":false},"authority":"read-only"});
        s.field_build(&json!({"manifest":manifest,"digest":hash(&manifest)}))
            .unwrap();
        let run = s.field_tick(id, 0, 123).unwrap();
        assert_eq!(run["state"], "queued");
        w.enabled = false;
        w.removed = true;
        assert!(s.set_repository(&w).is_err());
        w.generation = 1;
        s.set_repository(&w).unwrap();
        assert_eq!(s.field_tick(id, 0, 124).unwrap()["outcome"], "paused");
        assert_eq!(
            s.field_run(run["input"]["id"].as_str().unwrap()).unwrap()["state"],
            "queued"
        );
        assert!(
            s.create_field(&crate::field::FieldInput {
                id: "manual".into(),
                agent: "reviewer".into(),
                target: id.into(),
                inference: false
            })
            .is_err()
        );
        assert_eq!(s.repositories().unwrap().len(), 1);
        w.repository = "https://github.com/a/b".into();
        assert!(s.set_repository(&w).is_err());
    }
}

#[cfg(test)]
mod persistence_tests {
    use super::*;
    #[test]
    fn repository_configuration_survives_sqlite_reopen() {
        let path = std::env::temp_dir().join(format!(
            "starbase-watch-{}-{}.sqlite",
            std::process::id(),
            now()
        ));
        let store = Store::open(path.to_str().unwrap()).unwrap();
        let watch = store
            .set_repository(&RepositoryWatch {
                repository: "fixture/persist".into(),
                interval_seconds: 300,
                enabled: false,
                removed: false,
                generation: 0,
            })
            .unwrap();
        drop(store);
        let reopened = Store::open(path.to_str().unwrap()).unwrap();
        assert_eq!(reopened.repositories().unwrap(), vec![watch]);
        drop(reopened);
        std::fs::remove_file(path).unwrap();
    }
}
