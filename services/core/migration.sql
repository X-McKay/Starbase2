PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
PRAGMA busy_timeout=5000;
CREATE TABLE IF NOT EXISTS missions (
 id TEXT PRIMARY KEY, input TEXT NOT NULL, state TEXT NOT NULL,
 updated_at REAL NOT NULL, detail TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS evidence (
 mission_id TEXT PRIMARY KEY REFERENCES missions(id), body TEXT NOT NULL
);
CREATE TRIGGER IF NOT EXISTS evidence_no_update BEFORE UPDATE ON evidence
BEGIN SELECT RAISE(ABORT, 'evidence is immutable'); END;
CREATE TRIGGER IF NOT EXISTS evidence_no_delete BEFORE DELETE ON evidence
BEGIN SELECT RAISE(ABORT, 'evidence is immutable'); END;
PRAGMA user_version=1;
