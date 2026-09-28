-- Durable owner inventory checkpoint; failure never removes or re-enables watches.
CREATE TABLE repository_discovery (owner TEXT PRIMARY KEY, body TEXT NOT NULL);
