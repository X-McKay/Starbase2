BEGIN IMMEDIATE;
CREATE TABLE IF NOT EXISTS repair_builds (digest TEXT PRIMARY KEY, body TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS repairs (id TEXT PRIMARY KEY, body TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS crew_members (id TEXT PRIMARY KEY, name TEXT NOT NULL, role TEXT NOT NULL);
INSERT OR IGNORE INTO crew_members VALUES ('mender','Mender','Bounded repair missions');
CREATE TABLE IF NOT EXISTS credits (
 outcome_key TEXT PRIMARY KEY, crew_id TEXT NOT NULL REFERENCES crew_members(id),
 run_id TEXT NOT NULL REFERENCES repairs(id), build TEXT NOT NULL, xp INTEGER NOT NULL, at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS qualifications (
 build TEXT NOT NULL, scenario TEXT NOT NULL, run_id TEXT NOT NULL REFERENCES repairs(id),
 PRIMARY KEY(build,scenario)
);
CREATE TRIGGER IF NOT EXISTS credits_no_update BEFORE UPDATE ON credits BEGIN SELECT RAISE(ABORT,'immutable credit'); END;
CREATE TRIGGER IF NOT EXISTS credits_no_delete BEFORE DELETE ON credits BEGIN SELECT RAISE(ABORT,'immutable credit'); END;
PRAGMA user_version=3;
COMMIT;
