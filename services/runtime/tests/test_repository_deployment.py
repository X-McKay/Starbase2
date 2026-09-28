"""Discovery's deployment role stays an application role, not a migration owner."""

import re

import pytest

from scripts.deployment import database


def test_discovery_grants_are_narrow_and_require_owned_database(monkeypatch):
    calls = []
    config = {"database": "starbase2_test"}
    monkeypatch.setattr(database, "verify_database", lambda c, service: calls.append("verified"))
    monkeypatch.setattr(database, "psql", lambda service, sql: calls.append(sql))
    database.grants(config, "owner-service")
    assert calls[0] == "verified"
    sql = calls[1]
    grants = re.findall(r"GRANT (\w+) ON (.*?) TO starbase2_test_app;", sql, re.S)
    checkpoint_permissions = {
        verb
        for verb, tables in grants
        if "repository_discovery" in {table.strip() for table in tables.split(",")}
    }
    assert checkpoint_permissions == {"INSERT", "UPDATE"}
    assert "GRANT SELECT ON ALL TABLES" in sql
    assert "REVOKE ALL ON schema_version" in sql
    assert "GRANT SELECT ON schema_version" in sql
    assert "GRANT DELETE" not in sql
    assert "GRANT CREATE" not in sql

    def reject(*args):
        raise ValueError("not owned")

    monkeypatch.setattr(database, "verify_database", reject)
    calls.clear()
    with pytest.raises(ValueError, match="not owned"):
        database.grants(config, "owner-service")
    assert calls == []
