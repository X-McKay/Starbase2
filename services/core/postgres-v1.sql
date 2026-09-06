-- Fresh production schema. SQLite histories are intentionally not imported.
CREATE TABLE schema_version(version BIGINT PRIMARY KEY, checksum TEXT NOT NULL);
CREATE TABLE missions (
 id TEXT PRIMARY KEY, input TEXT NOT NULL, state TEXT NOT NULL,
 updated_at DOUBLE PRECISION NOT NULL, detail TEXT NOT NULL,
 rowid BIGINT GENERATED ALWAYS AS IDENTITY UNIQUE
);
CREATE TABLE evidence(mission_id TEXT PRIMARY KEY REFERENCES missions(id), body TEXT NOT NULL);
CREATE TABLE builds_v2(digest TEXT PRIMARY KEY, body TEXT NOT NULL, rowid BIGINT GENERATED ALWAYS AS IDENTITY UNIQUE);
CREATE TABLE tasks_v2 (
 id TEXT PRIMARY KEY, input TEXT NOT NULL, state TEXT NOT NULL,
 created_at DOUBLE PRECISION NOT NULL, updated_at DOUBLE PRECISION NOT NULL,
 detail TEXT NOT NULL, snapshot TEXT, report TEXT,
 rowid BIGINT GENERATED ALWAYS AS IDENTITY UNIQUE
);
CREATE TABLE events_v2 (
 sequence BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 task_id TEXT NOT NULL REFERENCES tasks_v2(id), at DOUBLE PRECISION NOT NULL,
 state TEXT NOT NULL, detail TEXT NOT NULL
);
CREATE INDEX events_task ON events_v2(task_id, sequence);
CREATE TABLE duties_v2 (
 id TEXT PRIMARY KEY, target TEXT NOT NULL, profile TEXT NOT NULL,
 interval_seconds BIGINT NOT NULL, enabled BIGINT NOT NULL CHECK(enabled IN (0,1)), generation BIGINT NOT NULL
);
CREATE TABLE runtime_v2(id BIGINT PRIMARY KEY CHECK(id=1), seen DOUBLE PRECISION NOT NULL);
CREATE TABLE repair_builds(digest TEXT PRIMARY KEY, body TEXT NOT NULL, rowid BIGINT GENERATED ALWAYS AS IDENTITY UNIQUE);
CREATE TABLE repairs(id TEXT PRIMARY KEY, body TEXT NOT NULL, rowid BIGINT GENERATED ALWAYS AS IDENTITY UNIQUE);
CREATE TABLE crew_members(id TEXT PRIMARY KEY, name TEXT NOT NULL, role TEXT NOT NULL);
INSERT INTO crew_members VALUES ('mender','Mender','Bounded repair missions');
CREATE TABLE credits (
 outcome_key TEXT PRIMARY KEY, crew_id TEXT NOT NULL REFERENCES crew_members(id),
 run_id TEXT NOT NULL REFERENCES repairs(id), build TEXT NOT NULL, xp BIGINT NOT NULL, at DOUBLE PRECISION NOT NULL
);
CREATE TABLE qualifications (
 build TEXT NOT NULL, scenario TEXT NOT NULL, run_id TEXT NOT NULL REFERENCES repairs(id),
 rowid BIGINT GENERATED ALWAYS AS IDENTITY UNIQUE, PRIMARY KEY(build,scenario)
);
CREATE FUNCTION reject_evidence_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'retained evidence is immutable'; END $$;
CREATE TRIGGER evidence_immutable BEFORE UPDATE OR DELETE ON evidence FOR EACH ROW EXECUTE FUNCTION reject_evidence_change();
CREATE TRIGGER credits_immutable BEFORE UPDATE OR DELETE ON credits FOR EACH ROW EXECUTE FUNCTION reject_evidence_change();
CREATE FUNCTION reject_task_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF (OLD.snapshot IS NOT NULL AND OLD.snapshot IS DISTINCT FROM NEW.snapshot)
 OR (OLD.report IS NOT NULL AND OLD.report IS DISTINCT FROM NEW.report) THEN
  RAISE EXCEPTION 'retained snapshot/report is immutable';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER tasks_immutable BEFORE UPDATE ON tasks_v2 FOR EACH ROW EXECUTE FUNCTION reject_task_change();
