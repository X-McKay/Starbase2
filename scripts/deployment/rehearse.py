"""Disposable PostgreSQL + Temporal rehearsal; never uses kubeconfig or Kubani.

Requires the explicitly named local container created by `just deployment-test-db`.
Retains sanitized results, not credentials or unredacted histories, in evidence/.
"""

import asyncio
import hashlib
import http.cookiejar
import json
import os
import shutil
import signal
import subprocess
import time
import urllib.error
import urllib.request
from unittest.mock import patch

from . import database, render, temporal

ROOT = render.ROOT
LOCAL = ROOT / ".local/deployment-rehearsal"
DB = "starbase2_rehearsal"
CONTAINER = "starbase2-deploy-rehearsal"


def main(images=None) -> None:
    global LOCAL, CONTAINER
    if images is not None:
        LOCAL = images.output
        CONTAINER = images.database
    LOCAL.mkdir(parents=True, exist_ok=True)
    report = LOCAL / "report.json" if images else ROOT / "evidence/deployment-rehearsal.json"
    if report.exists():
        history = ROOT / "evidence/deployment-rehearsal-history"
        history.mkdir(exist_ok=True)
        shutil.copyfile(report, history / f"{time.time_ns()}.json")
    events = []
    processes = []
    logs = []
    engine = shutil.which("podman") or "/opt/homebrew/opt/podman/bin/podman"
    # Explicit private, disposable container; no discovered cluster connection.
    if images is None:
        inspected = json.loads(subprocess.check_output([engine, "inspect", CONTAINER], text=True))[
            0
        ]
        bindings = inspected["HostConfig"]["PortBindings"]["5432/tcp"]
        if bindings != [{"HostIp": "127.0.0.1", "HostPort": "55439"}]:
            raise ValueError("Unexpected test database network boundary")
    c = json.loads((ROOT / "deploy/production.example.json").read_text())
    c.update(
        installation="starbase2-rehearsal",
        namespace="starbase2-rehearsal",
        temporal_namespace="starbase2-rehearsal",
        database=DB,
        retention_days=1,
    )

    def psql(service: str, sql: str, env: dict | None = None) -> str:
        user = "postgres" if service == "admin" else DB + "_owner"
        name = "postgres" if service == "admin" else DB
        result = subprocess.run(
            [
                engine,
                "exec",
                "-i",
                "--env",
                "STARBASE_ROLE_PASSWORD",
                CONTAINER,
                "psql",
                "-X",
                "-v",
                "ON_ERROR_STOP=1",
                "-At",
                "-U",
                user,
                "-d",
                name,
            ],
            input=sql,
            capture_output=True,
            text=True,
            timeout=60,
            env=os.environ | (env or {}),
        )
        if result.returncode:
            raise RuntimeError("Rehearsal SQL failed: " + result.stderr[:500])
        return result.stdout.strip()

    psql_patch = patch.object(database, "psql", psql)
    psql_patch.start()
    creds = LOCAL / "credentials.json"
    database.credentials(c, creds)
    data = database.read_credentials(c, creds)
    base = os.environ | {
        "PYTHONPATH": str(ROOT / "services/runtime"),
        "STARBASE_PORT": "18887",
        "STARBASE_CORE": "http://127.0.0.1:18887",
        "STARBASE_ENV": "production",
        "STARBASE_REPAIRS_ENABLED": "false",
        "STARBASE_LEGACY_ENABLED": "false",
        "STARBASE_FIELD_ENABLED": "false",
        "STARBASE_MEMORY_ENABLED": "false",
        "STARBASE_INSTALLATION": c["installation"],
        "STARBASE_INFERENCE_ENABLED": "false",
        "STARBASE_ACCEPT_WORK": "true",
        "STARBASE_TEMPORAL": "127.0.0.1:17239",
        "STARBASE_TEMPORAL_NAMESPACE": c["temporal_namespace"],
        "STARBASE_TEMPORAL_QUEUE": "starbase2-rehearsal-v1",
        "STARBASE_TOKEN_FILE": str(LOCAL / "token"),
    }
    (LOCAL / "token").write_text(data["worker_token"])
    (LOCAL / "token").chmod(0o600)
    owner_url = f"postgres://{DB}_owner@127.0.0.1:55439/{DB}?sslmode=disable"
    app_url = f"postgres://{DB}_app@127.0.0.1:55439/{DB}?sslmode=disable"
    url_file = LOCAL / "url"
    base["STARBASE_DATABASE_URL_FILE"] = str(url_file)

    def start(name, args, env):
        log = (LOCAL / (name + ".log")).open("w")
        logs.append(log)
        child = (
            images.start(args, env, log)
            if images
            else subprocess.Popen(
                args, cwd=ROOT, env=env, stdout=log, stderr=log, start_new_session=True
            )
        )
        processes.append(child)
        return child

    def run_command(args, env, **kwargs):
        return (
            images.run(args, env, **kwargs) if images else subprocess.run(args, env=env, **kwargs)
        )

    def stop(child):
        if images:
            images.stop(child)
            return
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
            child.wait(timeout=75)

    def record(name):
        events.append({"check": name, "passed": True})
        print(name, flush=True)

    def core():
        url_file.write_text(app_url)
        url_file.chmod(0o600)
        child = start("core", [str(ROOT / "target/debug/starbase-core")], base)
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            try:
                with urllib.request.urlopen(base["STARBASE_CORE"] + "/v2/snapshot", timeout=1):
                    return child
            except (OSError, urllib.error.URLError):
                time.sleep(0.2)
        raise RuntimeError("Core did not start; inspect .local/deployment-rehearsal/core.log")

    try:
        version = psql("admin", "SHOW server_version;")
        if not version.startswith("18.3"):
            raise ValueError("Final rehearsal requires pinned PostgreSQL 18.3")
        database.provision(c, data, "admin")
        database.provision(c, data, "admin")
        record("fresh database/roles provisioned; identical provisioning is idempotent")
        url_file.write_text(owner_url)
        run_command(
            [str(ROOT / "target/debug/starbase-core"), "--migrate"],
            env=base,
            check=True,
            timeout=30,
        )
        run_command(
            [str(ROOT / "target/debug/starbase-core"), "--migrate"],
            env=base,
            check=True,
            timeout=30,
        )
        database.grants(c, "owner")
        record("fresh schema migration, repeat migration and least-privilege grants")
        # Runtime cannot change schema or erase evidence, even with direct DB access.
        for statement in (
            "CREATE TABLE forbidden(id INT)",
            "DELETE FROM evidence",
            "DELETE FROM agent_memory",
            "UPDATE field_builds SET at=0",
            "UPDATE memory_reviews SET body='{}'",
            "UPDATE schema_version SET version=99",
        ):
            attempt = subprocess.run(
                [
                    engine,
                    "exec",
                    CONTAINER,
                    "psql",
                    "-X",
                    "-v",
                    "ON_ERROR_STOP=1",
                    "-U",
                    DB + "_app",
                    "-d",
                    DB,
                    "-c",
                    statement,
                ],
                capture_output=True,
                timeout=30,
            )
            assert attempt.returncode != 0
        record("runtime role denied DDL, evidence deletion and schema-version mutation")
        temporal_process = start(
            "temporal",
            [
                str(ROOT / ".local/tools/temporal"),
                "server",
                "start-dev",
                "--ip",
                "127.0.0.1",
                "--port",
                "17239",
                "--headless",
                "--log-level",
                "error",
            ],
            base,
        )
        os.environ.update(
            {k: base[k] for k in ("STARBASE_TEMPORAL", "STARBASE_TEMPORAL_NAMESPACE")}
        )

        async def provision_temporal():
            from starbase_runtime.connection import connect

            deadline = time.monotonic() + 20
            while True:
                try:
                    await connect()
                    break
                except RuntimeError:
                    if time.monotonic() > deadline:
                        raise
                    await asyncio.sleep(0.2)
            await temporal.namespace(c, "ensure")
            await temporal.namespace(c, "ensure")

        asyncio.run(provision_temporal())
        record("dedicated Temporal namespace create, ownership and retention verification")
        core_process = core()
        competitor = run_command(
            [str(ROOT / "target/debug/starbase-core"), "--migrate"],
            env=base,
            capture_output=True,
            timeout=20,
        )
        assert competitor.returncode != 0
        record("competing authoritative core refused by database advisory lock")
        cookies = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookies))

        def request(path, body=None):
            req = urllib.request.Request(
                base["STARBASE_CORE"] + path,
                data=json.dumps(body).encode() if body is not None else None,
                headers={
                    "Content-Type": "application/json",
                    "Origin": "http://127.0.0.1:8787" if images else base["STARBASE_CORE"],
                },
            )
            with opener.open(req, timeout=10) as r:
                return json.load(r) if path != "/" else r.read()

        request("/")
        worker = start(
            "worker",
            [str(ROOT / ".venv/bin/python"), "-m", "starbase_runtime.worker", "worker"],
            base,
        )
        deadline = time.monotonic() + 20
        while not request("/v2/snapshot")["builds"]:
            if time.monotonic() > deadline:
                raise RuntimeError("Worker build registration unavailable")
            time.sleep(0.2)
        run_id = "deploy-review-" + str(time.time_ns())
        request(
            "/v2/runs",
            {
                "id": run_id,
                "kind": "review",
                "target": "sample",
                "profile": "surveyor-v2",
                "inference": False,
            },
        )
        deadline = time.monotonic() + 45
        while True:
            run = request("/v2/runs/" + run_id)
            if run["state"] in {"completed", "failed", "cancelled"}:
                break
            if time.monotonic() > deadline:
                raise RuntimeError("Review did not complete")
            time.sleep(0.3)
        assert run["state"] == "completed", run["detail"]
        before = run["report"]
        record("real Temporal review retained in PostgreSQL through runtime role")
        if images:
            images.health(core_process, worker)
            record("image probes, non-root/read-only execution and worker database isolation")
        # Exercise both verdicts, and replay with the implementation inside the release image.
        for profile, outcome in (("surveyor-v2", "improved"), ("surveyor-regressed", "regressed")):
            evaluation_id = run_id + "-" + outcome
            request(
                "/v2/runs",
                {
                    "id": evaluation_id,
                    "kind": "evaluation",
                    "target": "sample",
                    "profile": "surveyor-v1",
                    "candidate": profile,
                    "inference": False,
                },
            )
            deadline = time.monotonic() + 90
            while True:
                evaluated = request("/v2/runs/" + evaluation_id)
                if evaluated["state"] in {"completed", "failed", "cancelled"}:
                    break
                if time.monotonic() > deadline:
                    raise RuntimeError("Image evaluation did not complete")
                time.sleep(0.3)
            assert evaluated["state"] == "completed", evaluated["detail"]
            assert evaluated["report"]["summary"]["outcome"] == outcome
            assert len(evaluated["report"]["evidence"]["trials"]) == 12
            (LOCAL / (outcome + ".json")).write_text(json.dumps(evaluated, indent=2) + "\n")
        record("paired evaluation distinguishes improvement and regression with 12 trials each")
        if images:
            images.replay(worker, [run_id, run_id + "-improved", run_id + "-regressed"])
            record("completed Temporal histories replay with the exact release worker image")
        stop(worker)
        cancel_id = run_id + "-cancel"
        request(
            "/v2/runs",
            {
                "id": cancel_id,
                "kind": "review",
                "target": "sample",
                "profile": "surveyor-v2",
                "inference": False,
            },
        )
        request("/v2/runs/" + cancel_id + "/cancel", {})
        queued_id = run_id + "-queued"
        queued_input = {
            "id": queued_id,
            "kind": "review",
            "target": "sample",
            "profile": "surveyor-v2",
            "inference": False,
        }
        request("/v2/runs", queued_input)
        request("/v2/runs", queued_input)
        time.sleep(5.5)
        assert not request("/v2/snapshot")["worker"]["available"]
        worker = start(
            "worker-restarted",
            [str(ROOT / ".venv/bin/python"), "-m", "starbase_runtime.worker", "worker"],
            base,
        )
        deadline = time.monotonic() + 30
        while request("/v2/runs/" + cancel_id)["state"] != "cancelled":
            if time.monotonic() > deadline:
                raise RuntimeError("Cancelled work failed to reconcile after restart")
            time.sleep(0.3)
        assert request("/v2/runs/" + cancel_id)["report"] is None
        deadline = time.monotonic() + 45
        while request("/v2/runs/" + queued_id)["state"] != "completed":
            if time.monotonic() > deadline:
                raise RuntimeError("Queued review failed to resume after worker restart")
            time.sleep(0.3)
        assert request("/v2/snapshot")["worker"]["available"]
        record("worker loss becomes stale; restart reconciles cancellation without executing work")
        record("duplicate queued intent completes after worker restart")
        for path, body in (
            ("/v1/missions", {}),
            ("/v3/repairs", {"id": "disabled", "scenario": "sum-positive", "mode": "fixture"}),
        ):
            try:
                request(path, body)
                raise AssertionError("Disabled API accepted request")
            except urllib.error.HTTPError as e:
                assert e.code in {404, 503}
        record("legacy and unqualified repair entry points disabled")
        stop(worker)
        stop(core_process)
        dump = subprocess.check_output(
            [
                engine,
                "exec",
                CONTAINER,
                "pg_dump",
                "-U",
                DB + "_owner",
                "-d",
                DB,
                "--format=custom",
                "--no-owner",
                "--no-acl",
            ],
            timeout=60,
        )
        # Verify software restart before simulating database loss in this disposable server.
        core_process = core()
        assert request("/v2/runs/" + run_id)["report"] == before
        stop(core_process)
        record("core restart preserves retained result")
        database.purge(c, "admin")
        database.provision(c, data, "admin")
        restored = subprocess.run(
            [
                engine,
                "exec",
                "-i",
                CONTAINER,
                "pg_restore",
                "-U",
                DB + "_owner",
                "-d",
                DB,
                "--exit-on-error",
                "--single-transaction",
                "--no-owner",
                "--no-acl",
            ],
            input=dump,
            capture_output=True,
            timeout=60,
        )
        if restored.returncode:
            raise RuntimeError("Restore rehearsal failed: " + restored.stderr.decode()[:500])
        database.grants(c, "owner")
        core_process = core()
        assert request("/v2/runs/" + run_id)["report"] == before
        stop(core_process)
        record("pg_dump, owned purge/reprovision, transactional restore preserve evidence")
        export = LOCAL / f"export-{time.time_ns()}"
        export.mkdir(mode=0o700)
        asyncio.run(temporal.export_histories(c, export))
        exported = json.loads((export / "temporal/manifest.json").read_text())
        assert exported["files"]
        from .cli import check_history_export

        check_history_export(c, export)
        record("closed Temporal histories exported and checksums verified")
        asyncio.run(temporal.namespace(c, "delete"))
        database.purge(c, "admin")
        record("dedicated Temporal namespace and owned database/roles removed")
        stop(temporal_process)
        report.write_text(
            json.dumps(
                {
                    "status": "passed",
                    "postgres_version": version,
                    "temporal_cli": "pinned image" if images else "1.8.3",
                    "scope": (
                        "local Linux images; no registry publish or Kubernetes deployment"
                        if images
                        else "local PostgreSQL/Temporal; no Kubernetes deployment or image build"
                    ),
                    "images": images.images if images else None,
                    "source_revision": images.data["revision"] if images else None,
                    "platform": images.data["platform"] if images else None,
                    "provenance": images.provenance if images else None,
                    "container_stops": images.stops if images else None,
                    "dump_sha256": hashlib.sha256(dump).hexdigest(),
                    "checks": events,
                },
                indent=2,
            )
            + "\n"
        )
    except Exception as e:
        report.write_text(
            json.dumps({"status": "failed", "error": type(e).__name__, "checks": events}, indent=2)
            + "\n"
        )
        raise
    finally:
        psql_patch.stop()
        for child in reversed(processes):
            stop(child)
        for log in logs:
            log.close()


if __name__ == "__main__":
    main()
