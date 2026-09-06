"""psql-based lifecycle for a dedicated database. No password in argv or logs."""

import json
import os
import secrets
import subprocess
from pathlib import Path
from urllib.parse import quote

MARKER = "starbase2 installation: "


def private_write(path: Path, body: str) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    # Exclusive creation prevents accidentally rotating an existing installation credential.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(body)


def credentials(c: dict, path: Path) -> None:
    if path.exists():
        read_credentials(c, path)
        return
    db = c["database"]
    data = {
        "installation": c["installation"],
        "database": db,
        "owner_password": secrets.token_urlsafe(48),
        "runtime_password": secrets.token_urlsafe(48),
        "worker_token": secrets.token_hex(32),
    }
    for kind in ("owner", "runtime"):
        user = db + ("_owner" if kind == "owner" else "_app")
        # Kubani currently uses private, non-TLS PostgreSQL. NetworkPolicy is required;
        # switch to verify-full with a CA when the platform enables database TLS.
        data[kind + "_url"] = (
            f"postgres://{user}:{quote(data[kind + '_password'], safe='')}@"
            f"{c['postgres_host']}:5432/{db}?sslmode=disable"
        )
    private_write(path, json.dumps(data, indent=2) + "\n")


def read_credentials(c: dict, path: Path) -> dict:
    if path.stat().st_mode & 0o077:
        raise ValueError("Credential file must be mode 0600")
    data = json.loads(path.read_text())
    if (data["installation"], data["database"]) != (c["installation"], c["database"]):
        raise ValueError("Credentials belong to another installation")
    return data


def psql(service: str, sql: str, env: dict | None = None) -> str:
    # PGSERVICEFILE/PGPASSFILE are supplied by the operator, never discovered from Kubani secrets.
    result = subprocess.run(
        ["psql", "-X", "--no-password", "-v", "ON_ERROR_STOP=1", "-At"],
        input=sql,
        text=True,
        capture_output=True,
        timeout=180,
        env=os.environ | {"PGSERVICE": service} | (env or {}),
    )
    if result.returncode:
        raise RuntimeError(
            "psql failed; inspect server diagnostics securely (credentials are not printed)"
        )
    return result.stdout.strip()


def provision(c: dict, data: dict, admin: str) -> None:
    db = c["database"]  # Validated identifier, never a user-supplied SQL fragment.
    expected = MARKER + c["installation"]
    info = psql(
        admin,
        f"SELECT COALESCE(shobj_description(oid,'pg_database'),'') FROM pg_database "
        f"WHERE datname='{db}';",
    )
    exists = psql(admin, f"SELECT count(*) FROM pg_database WHERE datname='{db}';") == "1"
    if exists and info != expected:
        raise ValueError("Refusing to adopt an unowned database")
    for suffix, kind in (("owner", "owner"), ("app", "runtime")):
        role = f"{db}_{suffix}"
        role_exists = psql(admin, f"SELECT count(*) FROM pg_roles WHERE rolname='{role}';") == "1"
        if role_exists:
            owner = psql(
                admin,
                f"SELECT COALESCE(shobj_description(oid,'pg_authid'),'') FROM pg_roles "
                f"WHERE rolname='{role}';",
            )
            if owner != expected:
                raise ValueError("Refusing to adopt an unowned database role")
        else:
            psql(
                admin,
                f"""\n\\getenv password STARBASE_ROLE_PASSWORD
CREATE ROLE {role} LOGIN PASSWORD :'password' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
COMMENT ON ROLE {role} IS '{expected}';
""",
                {"STARBASE_ROLE_PASSWORD": data[kind + "_password"]},
            )
    if not exists:
        psql(
            admin,
            f"CREATE DATABASE {db} OWNER {db}_owner;\nCOMMENT ON DATABASE {db} IS '{expected}';",
        )
    psql(
        admin,
        f"REVOKE ALL ON DATABASE {db} FROM PUBLIC; GRANT CONNECT ON DATABASE {db} TO {db}_app;",
    )


def grants(c: dict, owner_service: str) -> None:
    db = c["database"]
    verify_database(c, owner_service)
    psql(
        owner_service,
        f"""
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO {db}_app;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO {db}_app;
GRANT INSERT ON missions,evidence,builds_v2,tasks_v2,events_v2,duties_v2,
runtime_v2,repair_builds,repairs,credits,qualifications TO {db}_app;
GRANT UPDATE ON missions,tasks_v2,duties_v2,runtime_v2,repairs,
field_runs,field_duties,agent_memory,repository_watches TO {db}_app;
GRANT INSERT ON field_builds,field_runs,field_duties,agent_memory,memory_reviews,
repository_watches TO {db}_app;
GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO {db}_app;
REVOKE ALL ON schema_version FROM {db}_app;
GRANT SELECT ON schema_version TO {db}_app;
""",
    )


def purge(c: dict, admin: str) -> None:
    db = c["database"]
    expected = MARKER + c["installation"]
    exists = psql(admin, f"SELECT count(*) FROM pg_database WHERE datname='{db}';") == "1"
    if exists:
        if (
            psql(
                admin,
                f"SELECT shobj_description(oid,'pg_database') FROM pg_database "
                f"WHERE datname='{db}';",
            )
            != expected
        ):
            raise ValueError("Refusing to drop an unowned database")
        if psql(admin, f"SELECT count(*) FROM pg_stat_activity WHERE datname='{db}';") != "0":
            raise ValueError("Database still has connections; stop workloads first")
        # No FORCE, no termination of other sessions, no shared schemas touched.
        psql(admin, f"DROP DATABASE {db};")
    for role in (db + "_app", db + "_owner"):
        if psql(admin, f"SELECT count(*) FROM pg_roles WHERE rolname='{role}';") == "0":
            continue
        if (
            psql(
                admin,
                f"SELECT shobj_description(oid,'pg_authid') FROM pg_roles WHERE rolname='{role}';",
            )
            != expected
        ):
            raise ValueError("Refusing to drop an unowned role")
        psql(admin, f"DROP ROLE {role};")


def connection_files(c: dict, data: dict, directory: Path, port: int) -> None:
    if not 1024 <= port <= 65535:
        raise ValueError("Invalid loopback PostgreSQL port-forward")
    directory = directory.resolve()
    password_file = directory / "pgpass"
    services = []
    passwords = []
    for kind, suffix in (("owner", "owner"), ("runtime", "app")):
        role = c["database"] + "_" + suffix
        passwords.append(f"127.0.0.1:{port}:{c['database']}:{role}:{data[kind + '_password']}")
        services.append(
            f"[{c['installation']}-{suffix}]\nhost=127.0.0.1\nport={port}\n"
            f"dbname={c['database']}\nuser={role}\npassfile={password_file}\nsslmode=disable\n"
        )
    private_write(password_file, "\n".join(passwords) + "\n")
    private_write(directory / "pg_service.conf", "\n".join(services))


def verify_database(c: dict, service: str) -> None:
    if psql(service, "SELECT current_database();") != c["database"]:
        raise ValueError("Connection service targets a different database")
    marker = psql(
        service,
        "SELECT shobj_description(oid,'pg_database') FROM pg_database "
        "WHERE datname=current_database();",
    )
    if marker != MARKER + c["installation"]:
        raise ValueError("Connection service targets an unowned database")
