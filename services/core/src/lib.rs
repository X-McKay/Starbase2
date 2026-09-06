pub mod field;
pub mod grader;
pub mod model;
pub mod operations;
pub mod operations_api;
pub mod repair;
pub mod repositories;
pub mod storage;

use crate::parameters as params;
use model::{Mission, MissionInput, Snapshot, Submission, Transition};
use rusqlite::{Connection, OptionalExtension};
use serde_json::Value;
use std::time::{SystemTime, UNIX_EPOCH};

pub type Result<T> = std::result::Result<T, String>;
pub fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs_f64()
}
pub fn terminal(state: &str) -> bool {
    matches!(state, "completed" | "failed" | "cancelled")
}

pub struct Store {
    db: storage::Database,
}
impl Store {
    pub fn open(path: &str) -> Result<Self> {
        let db = Connection::open(path).map_err(|e| e.to_string())?;
        let version: i64 = db
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .map_err(|e| e.to_string())?;
        if version > 5 {
            return Err("database schema is newer than this core".into());
        }
        db.execute_batch(
            "PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;",
        )
        .map_err(|e| e.to_string())?;
        if version == 0 {
            db.execute_batch(include_str!("../migration.sql"))
                .map_err(|e| e.to_string())?;
        }
        if version < 2 {
            db.execute_batch(include_str!("../migration-v2.sql"))
                .map_err(|e| e.to_string())?;
        }
        if version < 3 {
            db.execute_batch(include_str!("../migration-v3.sql"))
                .map_err(|e| e.to_string())?;
        }
        if version < 4 {
            db.execute_batch(concat!(
                "BEGIN IMMEDIATE;",
                include_str!("../field-schema.sql"),
                "PRAGMA user_version=4; COMMIT;"
            ))
            .map_err(|e| e.to_string())?;
        }
        if version < 5 {
            db.execute_batch(concat!(
                "BEGIN IMMEDIATE;",
                include_str!("../repository-schema.sql"),
                "PRAGMA user_version=5; COMMIT;"
            ))
            .map_err(|e| e.to_string())?;
        }
        Ok(Self {
            db: storage::Database::Sqlite(db),
        })
    }
    /// Production opens only an explicitly migrated, checksum-matching schema.
    pub fn open_postgres(url: &str, migrate: bool) -> Result<Self> {
        use sha2::{Digest, Sha256};
        let mut db = storage::Database::postgres(url)
            .map_err(|_| "PostgreSQL connection/ownership lock unavailable")?;
        let checksum = format!("{:x}", Sha256::digest(include_str!("../postgres-v1.sql")));
        let present: bool = db
            .query_row(
                "SELECT to_regclass('public.schema_version') IS NOT NULL",
                params![],
                |r| r.get(0),
            )
            .map_err(|e| e.to_string())?;
        if !present {
            if !migrate {
                return Err("PostgreSQL schema missing; run the migration job first".into());
            }
            let tx = db.transaction().map_err(|e| e.to_string())?;
            tx.execute_batch(include_str!("../postgres-v1.sql"))
                .map_err(|e| e.to_string())?;
            tx.execute(
                "INSERT INTO schema_version VALUES (1,$1)",
                params![checksum],
            )
            .map_err(|e| e.to_string())?;
            tx.commit().map_err(|e| e.to_string())?;
        }
        let versions: i64 = db
            .query_row("SELECT COUNT(*) FROM schema_version", params![], |r| {
                r.get(0)
            })
            .map_err(|e| e.to_string())?;
        let recorded: String = db
            .query_row(
                "SELECT checksum FROM schema_version WHERE version=1",
                params![],
                |r| r.get(0),
            )
            .map_err(|e| e.to_string())?;
        if !(1..=3).contains(&versions) || recorded != checksum {
            return Err("Unsupported PostgreSQL schema/checksum; no automatic downgrade".into());
        }
        let v2 = format!("{:x}", Sha256::digest(include_str!("../field-schema.sql")));
        if versions == 1 {
            if !migrate {
                return Err("PostgreSQL field-agent migration required".into());
            }
            let tx = db.transaction().map_err(|e| e.to_string())?;
            tx.execute_batch(include_str!("../field-schema.sql"))
                .map_err(|e| e.to_string())?;
            tx.execute(
                "INSERT INTO schema_version VALUES (2,$1)",
                params![v2.clone()],
            )
            .map_err(|e| e.to_string())?;
            tx.commit().map_err(|e| e.to_string())?;
        }
        let actual: String = db
            .query_row(
                "SELECT checksum FROM schema_version WHERE version=2",
                params![],
                |r| r.get(0),
            )
            .map_err(|e| e.to_string())?;
        if actual != v2 {
            return Err("Unsupported field schema checksum".into());
        }
        let v3 = format!(
            "{:x}",
            Sha256::digest(include_str!("../repository-schema.sql"))
        );
        if versions < 3 {
            if !migrate {
                return Err("PostgreSQL repository-watch migration required".into());
            }
            let tx = db.transaction().map_err(|e| e.to_string())?;
            tx.execute_batch(include_str!("../repository-schema.sql"))
                .map_err(|e| e.to_string())?;
            tx.execute(
                "INSERT INTO schema_version VALUES (3,$1)",
                params![v3.clone()],
            )
            .map_err(|e| e.to_string())?;
            tx.commit().map_err(|e| e.to_string())?;
        }
        let actual: String = db
            .query_row(
                "SELECT checksum FROM schema_version WHERE version=3",
                params![],
                |r| r.get(0),
            )
            .map_err(|e| e.to_string())?;
        if actual != v3 {
            return Err("Unsupported repository schema checksum".into());
        }
        Ok(Self { db })
    }
    pub fn create(&self, input: &MissionInput) -> Result<()> {
        if input.id.is_empty()
            || input.id.len() > 80
            || !input
                .id
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || c == b'-')
            || input.delay_seconds > 30
            || input.baseline.digest == input.candidate.digest
        {
            return Err("invalid mission identity, delay, or build pair".into());
        }
        for build in [&input.baseline, &input.candidate] {
            use sha2::{Digest, Sha256};
            let digest = format!(
                "{:x}",
                Sha256::digest(serde_json::to_vec(&build.manifest).unwrap())
            );
            if digest != build.digest || build.manifest["variant"] != build.variant {
                return Err("build digest or variant mismatch".into());
            }
        }
        let body = serde_json::to_string(input).unwrap();
        let old: Option<String> = self
            .db
            .query_row(
                "SELECT input FROM missions WHERE id=$1",
                params![&input.id],
                |r| r.get(0),
            )
            .optional()
            .map_err(|e| e.to_string())?;
        if let Some(old) = old {
            return if old == body {
                Ok(())
            } else {
                Err("identity reused with different input".into())
            };
        }
        let count: i64 = self
            .db
            .query_row("SELECT COUNT(*) FROM missions", params![], |r| r.get(0))
            .map_err(|e| e.to_string())?;
        if count >= 100 {
            return Err(
                "local experiment limit: 100 retained missions; use a fresh database".into(),
            );
        }
        self.db
            .execute(
                "INSERT INTO missions (id,input,state,updated_at,detail) VALUES ($1,$2,'queued',$3,'Awaiting Temporal dispatch')",
                params![input.id, body, now()],
            )
            .map_err(|e| e.to_string())?;
        Ok(())
    }
    pub fn snapshot(&self) -> Result<Snapshot> {
        let mut stmt = self.db.prepare("SELECT m.input,m.state,m.updated_at,m.detail,e.body FROM missions m LEFT JOIN evidence e ON e.mission_id=m.id ORDER BY m.rowid DESC LIMIT 100").map_err(|e|e.to_string())?;
        let rows = stmt
            .query_map(params![], |row| {
                let body: String = row.get(0)?;
                let state: String = row.get(1)?;
                let updated_at: f64 = row.get(2)?;
                let evidence: Option<String> = row.get(4)?;
                Ok(Mission {
                    input: serde_json::from_str(&body).unwrap(),
                    stale: !terminal(&state) && now() - updated_at > 5.0,
                    state,
                    updated_at,
                    detail: row.get(3)?,
                    evidence: evidence.map(|e| serde_json::from_str(&e).unwrap()),
                })
            })
            .map_err(|e| e.to_string())?;
        Ok(Snapshot {
            schema_version: 1,
            observed_at: now(),
            simulation: true,
            missions: rows
                .collect::<std::result::Result<Vec<_>, _>>()
                .map_err(|e| e.to_string())?,
        })
    }
    pub fn get(&self, id: &str) -> Result<Mission> {
        // The local experiment is bounded to 100 missions; dispatch uses the same retained window.
        self.snapshot()?
            .missions
            .into_iter()
            .find(|m| m.input.id == id)
            .ok_or("mission not found".into())
    }
    pub fn transition(&self, id: &str, command: &Transition) -> Result<()> {
        let old = self.get(id)?;
        if old.state == command.state && terminal(&old.state) {
            return Ok(());
        }
        if terminal(&old.state) {
            return Err("terminal state is immutable".into());
        }
        let allowed = match command.state.as_str() {
            "running" => matches!(old.state.as_str(), "queued" | "running"),
            "cancel_requested" => true,
            "cancelled" => old.state == "cancel_requested",
            "failed" => true,
            _ => false,
        };
        if !allowed || command.detail.len() > 500 {
            return Err("invalid transition".into());
        }
        self.db
            .execute(
                "UPDATE missions SET state=$1,updated_at=$2,detail=$3 WHERE id=$4",
                params![command.state, now(), command.detail, id],
            )
            .map_err(|e| e.to_string())?;
        Ok(())
    }
    pub fn submit(&mut self, id: &str, submission: &Submission) -> Result<Value> {
        let mission = self.get(id)?;
        let evidence = grader::grade(&mission.input, submission)?;
        if let Some(old) = mission.evidence {
            return if old == evidence {
                Ok(old)
            } else {
                Err("evidence is immutable".into())
            };
        }
        if mission.state != "running" {
            return Err("only a running mission can submit evidence".into());
        }
        let tx = self.db.transaction().map_err(|e| e.to_string())?;
        tx.execute(
            "INSERT INTO evidence VALUES ($1,$2)",
            params![id, evidence.to_string()],
        )
        .map_err(|e| e.to_string())?;
        tx.execute("UPDATE missions SET state='completed',updated_at=$1,detail='Six synthetic trials retained and graded' WHERE id=$2", params![now(),id]).map_err(|e|e.to_string())?;
        tx.commit().map_err(|e| e.to_string())?;
        Ok(evidence)
    }
}

#[cfg(test)]
fn test_store() -> Store {
    // The optional PG suite creates a new database per case on a disposable loopback server.
    // It cannot target Kubani or reuse a product database.
    if std::env::var("STARBASE_TEST_POSTGRES").as_deref() != Ok("55439") {
        return Store::open(":memory:").unwrap();
    }
    static NEXT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
    let name = format!(
        "sbt_test_{}_{}",
        std::process::id(),
        NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    );
    let rt = tokio::runtime::Runtime::new().unwrap();
    rt.block_on(async {
        use sqlx::Connection;
        let mut admin = sqlx::PgConnection::connect(
            "postgres://postgres@127.0.0.1:55439/postgres?sslmode=disable",
        )
        .await
        .unwrap();
        sqlx::query(sqlx::AssertSqlSafe(format!("CREATE DATABASE {name}")))
            .execute(&mut admin)
            .await
            .unwrap();
    });
    Store::open_postgres(
        &format!("postgres://postgres@127.0.0.1:55439/{name}?sslmode=disable"),
        true,
    )
    .unwrap()
}

#[cfg(test)]
mod tests {
    use super::*;
    use model::{Build, Finding, Trial};
    use serde_json::json;
    use sha2::{Digest, Sha256};

    fn input() -> MissionInput {
        let build = |variant: &str| {
            let manifest = json!({"variant":variant});
            Build {
                digest: format!(
                    "{:x}",
                    Sha256::digest(serde_json::to_vec(&manifest).unwrap())
                ),
                variant: variant.into(),
                manifest,
            }
        };
        MissionInput {
            id: "fixture-1".into(),
            baseline: build("baseline"),
            candidate: build("regressed"),
            delay_seconds: 0,
            integration: false,
        }
    }
    fn submission(input: &MissionInput) -> Submission {
        let mut trials = vec![];
        for case_id in ["division", "clean", "injection"] {
            for build in [&input.baseline, &input.candidate] {
                trials.push(Trial {
                    case_id: case_id.into(),
                    build_digest: build.digest.clone(),
                    findings: if build.variant == "baseline" && case_id != "clean" {
                        vec![Finding {
                            code: "zero-division".into(),
                            file: "metrics.py".into(),
                            line: 2,
                        }]
                    } else {
                        vec![]
                    },
                    elapsed_ms: 1,
                    model: "function:surveyor-fixture-v1".into(),
                    requests: 1,
                });
            }
        }
        Submission { trials }
    }
    fn change(store: &Store, state: &str) -> Result<()> {
        store.transition(
            "fixture-1",
            &Transition {
                state: state.into(),
                detail: state.into(),
            },
        )
    }
    #[test]
    fn a_newer_database_cannot_be_silently_downgraded() {
        let path =
            std::env::temp_dir().join(format!("starbase-future-{}.sqlite", std::process::id()));
        let db = Connection::open(&path).unwrap();
        db.execute_batch("PRAGMA user_version=99").unwrap();
        drop(db);
        assert!(Store::open(path.to_str().unwrap()).is_err());
        let db = Connection::open(&path).unwrap();
        assert_eq!(
            db.query_row("PRAGMA user_version", [], |r| r.get::<_, i64>(0))
                .unwrap(),
            99
        );
        drop(db);
        std::fs::remove_file(path).unwrap();
    }
    #[test]
    fn failed_stop_acknowledgement_remains_failed() {
        let store = crate::test_store();
        store.create(&input()).unwrap();
        change(&store, "cancel_requested").unwrap();
        change(&store, "failed").unwrap();
        assert_eq!(store.get("fixture-1").unwrap().state, "failed");
        assert!(change(&store, "cancelled").is_err());
    }
    #[test]
    fn duplicate_ingestion_does_not_change_identity_or_dispatch() {
        let store = crate::test_store();
        let mut i = input();
        store.create(&i).unwrap();
        store.create(&i).unwrap();
        assert_eq!(store.snapshot().unwrap().missions.len(), 1);
        i.delay_seconds = 2;
        assert!(store.create(&i).is_err());
        assert_eq!(store.get(&i.id).unwrap().state, "queued");
    }
    #[test]
    fn retained_result_is_atomic_and_exact_retry_is_idempotent() {
        let mut store = crate::test_store();
        let i = input();
        let mut s = submission(&i);
        store.create(&i).unwrap();
        change(&store, "running").unwrap();
        let evidence = store.submit(&i.id, &s).unwrap();
        assert_eq!(store.submit(&i.id, &s).unwrap(), evidence);
        let mission = store.get(&i.id).unwrap();
        assert_eq!(mission.state, "completed");
        assert_eq!(mission.evidence.unwrap()["outcome"], "regressed");
        s.trials[0].elapsed_ms = 2;
        assert!(store.submit(&i.id, &s).is_err());
        assert!(change(&store, "running").is_err());
        assert!(store.db.execute("DELETE FROM evidence", params![]).is_err());
    }
    #[test]
    fn cancellation_fences_late_completion() {
        let mut store = crate::test_store();
        let i = input();
        store.create(&i).unwrap();
        change(&store, "running").unwrap();
        change(&store, "cancel_requested").unwrap();
        assert!(change(&store, "running").is_err());
        assert!(store.submit(&i.id, &submission(&i)).is_err());
        assert!(store.get(&i.id).unwrap().evidence.is_none());
        change(&store, "cancelled").unwrap();
        change(&store, "cancelled").unwrap();
        assert!(change(&store, "failed").is_err());
    }
    #[test]
    fn unverified_or_partial_results_never_complete() {
        let mut store = crate::test_store();
        let i = input();
        let mut s = submission(&i);
        store.create(&i).unwrap();
        change(&store, "running").unwrap();
        s.trials.pop();
        assert!(store.submit(&i.id, &s).is_err());
        assert_eq!(store.get(&i.id).unwrap().state, "running");
        assert!(change(&store, "completed").is_err());
    }
    #[test]
    fn grading_preserves_failures_no_change_and_hard_gates() {
        let i = input();
        let mut s = submission(&i);
        let report = grader::grade(&i, &s).unwrap();
        assert_eq!(report["baseline_passes"], 3);
        assert_eq!(report["candidate_passes"], 1);
        assert_eq!(report["trials"][2]["outcome"], "no_change");
        s.trials[1].findings = vec![Finding {
            code: "zero-division".into(),
            file: "secret".into(),
            line: 99,
        }];
        assert_eq!(grader::grade(&i, &s).unwrap()["outcome"], "ineligible");
        s.trials[0].findings.clear();
        assert_eq!(grader::grade(&i, &s).unwrap()["outcome"], "invalid");
    }
    #[test]
    fn duplicated_missing_and_wrong_build_trials_are_rejected() {
        let i = input();
        let mut s = submission(&i);
        s.trials[1].build_digest = i.baseline.digest.clone();
        assert!(grader::grade(&i, &s).is_err());
        s.trials[1].build_digest = "unknown".into();
        assert!(grader::grade(&i, &s).is_err());
    }
    #[test]
    fn equal_public_controls_are_inconclusive_for_quality() {
        let i = input();
        let mut s = submission(&i);
        for t in &mut s.trials {
            if t.case_id != "clean" {
                t.findings = vec![Finding {
                    code: "zero-division".into(),
                    file: "metrics.py".into(),
                    line: 2,
                }];
            }
        }
        assert_eq!(grader::grade(&i, &s).unwrap()["outcome"], "inconclusive");
    }
    #[test]
    fn stale_is_independent_of_execution_state() {
        let store = crate::test_store();
        let i = input();
        store.create(&i).unwrap();
        change(&store, "running").unwrap();
        store
            .db
            .execute("UPDATE missions SET updated_at=$1", params![now() - 6.0])
            .unwrap();
        let m = store.get(&i.id).unwrap();
        assert!(m.stale);
        assert_eq!(m.state, "running");
    }
    #[test]
    fn source_drift_and_malformed_input_are_rejected() {
        let store = crate::test_store();
        let mut i = input();
        i.baseline.manifest["variant"] = json!("changed");
        assert!(store.create(&i).is_err());
        let mut i = input();
        i.id = "../../bad".into();
        assert!(store.create(&i).is_err());
        assert!(serde_json::from_value::<Submission>(json!({"trials":[],"passed":true})).is_err());
    }
    #[test]
    fn reopening_preserves_evidence_and_migrations_are_repeatable() {
        let path = std::env::temp_dir().join(format!(
            "starbase-test-{}-{}.sqlite",
            std::process::id(),
            now()
        ));
        let i = input();
        let expected;
        {
            let mut s = Store::open(path.to_str().unwrap()).unwrap();
            s.create(&i).unwrap();
            change(&s, "running").unwrap();
            expected = s.submit(&i.id, &submission(&i)).unwrap();
        }
        {
            let s = Store::open(path.to_str().unwrap()).unwrap();
            assert_eq!(s.get(&i.id).unwrap().evidence.unwrap(), expected);
        }
        std::fs::remove_file(path).unwrap();
    }
}
