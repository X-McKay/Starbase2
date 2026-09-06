"""Preparation and explicit lifecycle actions. No cluster mutations by default."""

import argparse
import asyncio
import base64
import hashlib
import json
import os
import subprocess
from pathlib import Path

from . import database, journal, render, temporal


def run(args: list[str], *, body: str | None = None) -> str:
    result = subprocess.run(args, input=body, capture_output=True, text=True, timeout=240)
    if result.returncode:
        raise RuntimeError(
            f"{args[0]} operation failed (exit {result.returncode}); inspect target securely"
        )
    return result.stdout


def kubectl(c: dict, *args: str, body: str | None = None) -> str:
    return run(
        ["kubectl", "--context", c["context"], "--namespace", c["namespace"], *args], body=body
    )


def ownership(c: dict) -> None:
    value = json.loads(kubectl(c, "get", "namespace", c["namespace"], "-o", "json"))
    if value["metadata"].get("labels", {}).get(render.LABEL) != c["installation"]:
        raise ValueError("Kubernetes namespace is not owned by this installation")


def stopped(c: dict) -> None:
    ownership(c)
    pods = json.loads(kubectl(c, "get", "pods", "-o", "json"))["items"]
    if any(p["status"].get("phase") not in {"Succeeded", "Failed"} for p in pods):
        raise ValueError("Namespace still has active pods; stop through GitOps and wait")


def verify_bundle(c: dict, directory: Path) -> dict:
    lock = json.loads((directory / "release.json").read_text())
    if lock["config"] != c:
        raise ValueError("Bundle configuration differs from the selected target")
    if set(lock["files"]) != {"application.json", "migration.json", "kustomization.yaml"}:
        raise ValueError("Release inventory is incomplete")
    for name, checksum in lock["files"].items():
        if name not in {"application.json", "migration.json", "kustomization.yaml"}:
            raise ValueError("Unexpected bundle path")
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != checksum:
            raise ValueError("Rendered bundle was edited; regenerate and review")
    expected = hashlib.sha256(
        (render.ROOT / "services/core/postgres-v1.sql").read_bytes()
    ).hexdigest()
    if lock["postgres_schema_sha256"] != expected:
        raise ValueError("Schema differs from the release's migration input")
    return lock


def install_secret(c: dict, name: str, data: dict) -> None:
    existing = kubectl(c, "get", "secret", name, "--ignore-not-found", "-o", "json")
    encoded = {k: base64.b64encode(v.encode()).decode() for k, v in data.items()}
    if existing:
        old = json.loads(existing)
        if (
            old["metadata"].get("labels", {}).get(render.LABEL) != c["installation"]
            or old["data"] != encoded
        ):
            raise ValueError("Existing secret differs or is unowned; explicit rotation is required")
        return
    value = {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {
            "name": name,
            "namespace": c["namespace"],
            "labels": {render.LABEL: c["installation"]},
        },
        "type": "Opaque",
        "data": encoded,
    }
    kubectl(c, "create", "-f", "-", body=json.dumps(value))


def snapshot_backup(c: dict, service: str, destination: Path, bundle: Path) -> None:
    stopped(c)
    database.verify_database(c, service)
    destination.mkdir(mode=0o700, parents=True, exist_ok=False)
    target = destination / "database.dump"
    fd = os.open(target, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, "wb") as f:
        result = subprocess.run(
            ["pg_dump", "--no-password", "--format=custom", "--no-owner", "--no-acl"],
            stdout=f,
            stderr=subprocess.PIPE,
            timeout=240,
            env=os.environ | {"PGSERVICE": service},
        )
    if result.returncode:
        raise RuntimeError("Backup failed; partial directory retained, do not use it")
    release = verify_bundle(c, bundle)
    manifest = {
        "installation": c["installation"],
        "database": c["database"],
        "release": release,
        "dump_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
        "temporal": (
            "Not included; retain platform PostgreSQL backup of Temporal persistence and visibility"
        ),
    }
    database.private_write(destination / "backup.json", json.dumps(manifest, indent=2))


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "action",
        choices=[
            "render",
            "drain",
            "preflight",
            "credentials",
            "connections",
            "export-temporal",
            "purge-kubernetes",
            "provision-db",
            "grants",
            "secrets",
            "temporal-ensure",
            "temporal-check",
            "migrate",
            "status",
            "backup",
            "restore",
            "rollback",
            "teardown",
            "purge-db",
            "purge-temporal",
            "emergency-stop",
        ],
    )
    p.add_argument("--config", required=True, type=Path)
    p.add_argument("--bundle", type=Path, default=Path(".local/deploy/bundle"))
    p.add_argument("--credentials", type=Path, default=Path(".local/deploy/credentials.json"))
    p.add_argument("--backup", type=Path)
    p.add_argument("--previous", type=Path)
    p.add_argument("--service", default="starbase2-admin", help="libpq service name, not a URL")
    p.add_argument("--temporal-address", help="Operator connection, usually a local port-forward")
    p.add_argument("--connection-dir", type=Path, default=Path(".local/deploy/libpq"))
    p.add_argument("--postgres-port", type=int, default=54329)
    p.add_argument("--execute", action="store_true")
    p.add_argument("--confirm", help="Installation name for mutations")
    p.add_argument(
        "--gitops-detached",
        action="store_true",
        help="Affirm the application was removed/suspended in Kubani GitOps",
    )
    args = p.parse_args()
    c = render.load(args.config)
    a = args.action
    if a == "render":
        render.render(c, args.bundle)
        print(f"Rendered inactive/reviewable bundle: {args.bundle}")
        return
    if a == "credentials":
        database.credentials(c, args.credentials)
        print(f"Private credentials retained at {args.credentials}; no values printed")
        return
    if a == "connections":
        database.connection_files(
            c,
            database.read_credentials(c, args.credentials),
            args.connection_dir,
            args.postgres_port,
        )
        print(f"Private libpq connection files created in {args.connection_dir}")
        return
    if a not in {"preflight", "status", "temporal-check"}:
        if not args.execute:
            print(
                f"PLAN ONLY: {a} for {c['installation']} on {c['context']}. "
                "No external changes. See docs/deployment.md."
            )
            return
        if args.confirm != c["installation"]:
            p.error("Mutation requires --execute --confirm INSTALLATION")
    if a.startswith("temporal") or a in {"purge-temporal", "export-temporal"}:
        os.environ["STARBASE_TEMPORAL_NAMESPACE"] = c["temporal_namespace"]
        if not args.temporal_address:
            p.error("An explicit --temporal-address is required; no default server")
        os.environ["STARBASE_TEMPORAL"] = args.temporal_address
    if a == "preflight":
        verify_bundle(c, args.bundle)
        existing = kubectl(
            c, "get", "namespace", c["namespace"], "--ignore-not-found", "-o", "json"
        )
        if existing:
            ownership(c)
        print(kubectl(c, "version", "-o", "json"))
        print(kubectl(c, "auth", "can-i", "get", "pods"))
        # Namespace may not exist on the first preflight. Server dry-run validates schemas.
        print(kubectl(c, "apply", "--dry-run=server", "-f", str(args.bundle / "application.json")))
    elif a == "provision-db":
        database.provision(c, database.read_credentials(c, args.credentials), args.service)
    elif a == "grants":
        database.grants(c, args.service)
    elif a == "secrets":
        ownership(c)
        data = database.read_credentials(c, args.credentials)
        install_secret(c, "starbase2-worker", {"token": data["worker_token"]})
        install_secret(c, "starbase2-database", {"url": data["runtime_url"]})
        install_secret(c, "starbase2-migrator", {"url": data["owner_url"]})
    elif a in {"temporal-ensure", "temporal-check", "purge-temporal"}:
        if a == "purge-temporal":
            stopped(c)
            if not args.gitops_detached or not args.backup:
                p.error("Purge requires --gitops-detached and --backup")
            check_backup(c, args.backup)
            check_history_export(c, args.backup)
        op = {"temporal-ensure": "ensure", "temporal-check": "check", "purge-temporal": "delete"}[a]
        print(json.dumps(asyncio.run(temporal.namespace(c, op)), indent=2))
    elif a == "export-temporal":
        stopped(c)
        if not args.backup:
            p.error("--backup is required")
        check_backup(c, args.backup)
        asyncio.run(temporal.export_histories(c, args.backup))
    elif a == "purge-kubernetes":
        stopped(c)
        if not args.gitops_detached or not args.backup:
            p.error("Namespace purge requires --gitops-detached and --backup")
        check_backup(c, args.backup)
        purge_kubernetes(c)
    elif a == "migrate":
        stopped(c)
        verify_bundle(c, args.bundle)
        doc = json.loads((args.bundle / "migration.json").read_text())
        name = doc["items"][0]["metadata"]["name"]
        existing = kubectl(c, "get", "job", name, "--ignore-not-found", "-o", "json")
        if existing and json.loads(existing).get("status", {}).get("failed"):
            raise ValueError(
                "Migration job previously failed; retain logs, "
                "investigate, then explicitly delete that job to retry"
            )
        kubectl(c, "apply", "-f", str(args.bundle / "migration.json"))
        kubectl(c, "wait", "--for=condition=complete", f"job/{name}", "--timeout=180s")
        print("Migration job completed; apply runtime grants before starting the application")
    elif a == "drain":
        ownership(c)
        print(json.dumps(journal.drain(), indent=2))
    elif a == "status":
        ownership(c)
        print(kubectl(c, "get", "deployment,pods,jobs,networkpolicy", "-o", "wide"))
    elif a == "backup":
        if not args.backup:
            p.error("--backup requires a new private directory")
        snapshot_backup(c, args.service, args.backup, args.bundle)
    elif a == "restore":
        stopped(c)
        if not args.backup:
            p.error("--backup is required")
        manifest = check_backup(c, args.backup)
        database.verify_database(c, args.service)
        if (
            database.psql(
                args.service,
                "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';",
            )
            != "0"
        ):
            raise ValueError(
                "Restore requires an empty dedicated database; never overwrites production evidence"
            )
        result = subprocess.run(
            [
                "pg_restore",
                "--no-password",
                "--exit-on-error",
                "--single-transaction",
                "--no-owner",
                "--no-acl",
                "--dbname",
                f"service={args.service}",
                str(args.backup / "database.dump"),
            ],
            capture_output=True,
            timeout=240,
        )
        if result.returncode:
            raise RuntimeError("Restore failed; no automatic restart")
        print(
            f"Restored database from {manifest['dump_sha256']}; "
            "grants and Temporal reconciliation required before restart"
        )
    elif a == "rollback":
        if not args.previous:
            p.error("--previous requires a retained release directory")
        old = json.loads((args.previous / "release.json").read_text())["config"]
        for key in (
            "installation",
            "context",
            "database",
            "namespace",
            "temporal_namespace",
            "temporal_queue",
        ):
            if old[key] != c[key]:
                raise ValueError("Rollback target identity differs")
        verify_bundle(old, args.previous)
        # Render a stopped rollback for review; Kubani owns its activation.
        render.render(old | {"replicas": 0, "accept_work": False}, args.bundle / "rollback")
        print(
            "Prepared stopped rollback bundle. Promote it through "
            "Kubani after checking open workflow/build compatibility."
        )
    elif a in {"teardown", "emergency-stop", "purge-db"}:
        ownership(c)
        if not args.gitops_detached:
            p.error(
                "First suspend/remove the owning Kubani Flux "
                "reference; --gitops-detached is required"
            )
        if a == "emergency-stop":
            kubectl(c, "scale", "deployment/starbase2", "--replicas=0")
            print("Stop requested; verify pods terminate. Histories and database retained.")
        elif a == "purge-db":
            stopped(c)
            if not args.backup:
                p.error("Purge requires --backup")
            check_backup(c, args.backup)
            database.purge(c, args.service)
        else:
            stopped(c)
            # Retain namespace, secrets, Temporal and database.
            # Shared platform objects are never deleted.
            kubectl(c, "delete", "deployment", "starbase2", "--ignore-not-found")
            kubectl(c, "delete", "jobs", "-l", f"{render.LABEL}={c['installation']}")
            print(
                "Workloads removed. Namespace, policies, "
                "credentials, PostgreSQL and Temporal retained."
            )


def check_backup(c: dict, directory: Path) -> dict:
    m = json.loads((directory / "backup.json").read_text())
    if (m["installation"], m["database"]) != (c["installation"], c["database"]):
        raise ValueError("Backup belongs to a different installation")
    if hashlib.sha256((directory / "database.dump").read_bytes()).hexdigest() != m["dump_sha256"]:
        raise ValueError("Backup checksum differs")
    return m


def check_history_export(c: dict, backup: Path) -> None:
    directory = backup / "temporal"
    data = json.loads((directory / "manifest.json").read_text())
    if data["installation"] != c["installation"] or data["namespace"] != c["temporal_namespace"]:
        raise ValueError("History export belongs to another installation")
    for name, checksum in data["files"].items():
        if Path(name).name != name or not name.endswith(".json"):
            raise ValueError("Invalid history export path")
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != checksum:
            raise ValueError("History export is corrupt")


def purge_kubernetes(c: dict) -> None:
    # Inspect all discoverable namespaced resource kinds, failing closed on API errors.
    kinds = kubectl(c, "api-resources", "--verbs=list", "--namespaced=true", "-o", "name").split()
    for kind in kinds:
        for obj in json.loads(kubectl(c, "get", kind, "-o", "json"))["items"]:
            meta = obj["metadata"]
            if (
                (kind == "serviceaccounts" and meta["name"] == "default")
                or (kind == "configmaps" and meta["name"] == "kube-root-ca.crt")
                or kind in {"events", "events.events.k8s.io"}
            ):
                continue
            # ReplicaSets/Pods inherit installation labels from the deployment.
            if meta.get("labels", {}).get(render.LABEL) != c["installation"]:
                raise ValueError(f"Unowned {kind}/{meta['name']} remains; namespace not deleted")
    policy = c["installation"] + "-postgres"
    existing = kubectl(
        c,
        "get",
        "networkpolicy",
        policy,
        "-n",
        c["postgres_namespace"],
        "--ignore-not-found",
        "-o",
        "json",
    )
    if existing:
        if (
            json.loads(existing)["metadata"].get("labels", {}).get(render.LABEL)
            != c["installation"]
        ):
            raise ValueError("Platform access policy is unowned")
        kubectl(c, "delete", "networkpolicy", policy, "-n", c["postgres_namespace"])
    kubectl(c, "delete", "namespace", c["namespace"], "--wait=false")
    print("Namespace deletion requested; PostgreSQL and Temporal require separate purge commands")


if __name__ == "__main__":
    main()
