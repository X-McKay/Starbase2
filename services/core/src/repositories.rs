//! Repository watch configuration; removal retains the ledger and stops future dispatch.
use crate::operations::hash;
use crate::{Result, Store, now, parameters as params};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

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
        self.db
            .prepare("SELECT body FROM repository_watches ORDER BY id")
            .map_err(|e| e.to_string())?
            .query_map(params![], |r| r.get::<_, String>(0))
            .map_err(|e| e.to_string())?
            .map(|r| {
                serde_json::from_str(&r.map_err(|e| e.to_string())?).map_err(|e| e.to_string())
            })
            .collect()
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
                >= 20
        {
            return Err("Watch budget reached (20 repositories)".into());
        }
        let value = json!({"id":id,"config":config,"updated_at":now()});
        self.db.execute("INSERT INTO repository_watches VALUES ($1,$2) ON CONFLICT(id) DO UPDATE SET body=excluded.body",params![id,value.to_string()]).map_err(|e|e.to_string())?;
        Ok(value)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
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
