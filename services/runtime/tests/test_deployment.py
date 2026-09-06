"""Lifecycle failure cases. All cluster/database calls are replaced by explicit fakes."""

import json

import pytest
from starbase_runtime.connection import settings

from scripts.deployment import cli, database, render


@pytest.fixture
def config(tmp_path):
    c = json.loads((render.ROOT / "deploy/production.example.json").read_text())
    c.update(
        context="test-kubani",
        core_image="registry.test/core@sha256:" + "a" * 64,
        runtime_image="registry.test/runtime@sha256:" + "b" * 64,
        source_revision="c" * 40,
    )
    p = tmp_path / "config.json"
    p.write_text(json.dumps(c))
    return render.load(p)


@pytest.mark.parametrize(
    "key,value",
    [
        ("namespace", "default"),
        ("database", "postgres"),
        ("database", "starbase2_x;DROP"),
        ("temporal_namespace", "default"),
        ("replicas", 2),
        ("retention_days", 0),
        ("core_image", "registry.test/core:latest"),
        ("source_revision", "main"),
        ("platform", "linux/386"),
        ("platform", "darwin/arm64"),
    ],
)
def test_unsafe_targets_fail_before_execution(config, tmp_path, key, value):
    config[key] = value
    p = tmp_path / "bad.json"
    p.write_text(json.dumps(config))
    with pytest.raises(ValueError):
        render.load(p)


def test_render_reproducible_private_and_separated_credentials(config, tmp_path):
    render.render(config, tmp_path)
    first = (tmp_path / "application.json").read_bytes()
    render.render(config, tmp_path)
    assert first == (tmp_path / "application.json").read_bytes()
    cli.verify_bundle(config, tmp_path)
    items = json.loads(first)["items"]
    assert not any(o["kind"] in {"Ingress", "Service", "ClusterRole", "Secret"} for o in items)
    deployment = next(o for o in items if o["kind"] == "Deployment")
    assert deployment["spec"]["replicas"] == 0
    pod = deployment["spec"]["template"]["spec"]
    assert pod["automountServiceAccountToken"] is False
    assert len(pod["containers"]) == 2
    for container in pod["containers"]:
        assert container["securityContext"]["readOnlyRootFilesystem"]
        assert {e["name"]: e["value"] for e in container["env"]}[
            "STARBASE_REPAIRS_ENABLED"
        ] == "false"
        field_env = {e["name"]: e["value"] for e in container["env"]}
        assert field_env["STARBASE_FIELD_ENABLED"] == "false"
        assert field_env["STARBASE_MEMORY_ENABLED"] == "false"
        assert field_env["STARBASE_INSTALLATION"] == config["installation"]
    worker = pod["containers"][1]
    assert "starbase2-database" not in {v["name"] for v in worker["volumeMounts"]}
    assert "migration.json" not in (tmp_path / "kustomization.yaml").read_text()
    db_access = next(o for o in items if o["metadata"].get("namespace") == "database")
    assert db_access["spec"]["ingress"][0]["from"][0]["podSelector"]["matchLabels"] == {
        render.LABEL: config["installation"]
    }
    (tmp_path / "application.json").write_text("tampered")
    with pytest.raises(ValueError, match="edited"):
        cli.verify_bundle(config, tmp_path)


def test_credentials_are_private_stable_and_cannot_be_adopted(config, tmp_path):
    p = tmp_path / "private.json"
    database.credentials(config, p)
    original = p.read_bytes()
    database.credentials(config, p)
    assert p.read_bytes() == original
    assert p.stat().st_mode & 0o077 == 0
    wrong = config | {"installation": "starbase2-other"}
    with pytest.raises(ValueError):
        database.read_credentials(wrong, p)
    p.chmod(0o644)
    with pytest.raises(ValueError, match="0600"):
        database.read_credentials(config, p)


def test_unowned_database_cannot_be_provisioned_or_dropped(config, monkeypatch):
    def fake(service, sql, env=None):
        if sql.startswith("SELECT count(*) FROM pg_database"):
            return "1"
        if sql.startswith("SELECT"):
            return "someone else"
        pytest.fail("Mutation must not occur")

    monkeypatch.setattr(database, "psql", fake)
    with pytest.raises(ValueError, match="unowned"):
        database.provision(config, {}, "admin")
    with pytest.raises(ValueError, match="unowned"):
        database.purge(config, "admin")


def test_owned_database_with_connections_cannot_be_dropped(config, monkeypatch):
    def fake(service, sql, env=None):
        if "shobj_description" in sql:
            return database.MARKER + config["installation"]
        if sql.startswith("SELECT"):
            return "1"
        pytest.fail("Must not terminate sessions or drop an active database")

    monkeypatch.setattr(database, "psql", fake)
    with pytest.raises(ValueError, match="connections"):
        database.purge(config, "admin")


def test_namespace_ownership_and_active_pod_fences(config, monkeypatch):
    ns = {"metadata": {"labels": {render.LABEL: config["installation"]}}}

    def fake(c, *args, **kw):
        if "namespace" in args:
            return json.dumps(ns)
        return json.dumps({"items": [{"status": {"phase": "Running"}}]})

    monkeypatch.setattr(cli, "kubectl", fake)
    with pytest.raises(ValueError, match="active pods"):
        cli.stopped(config)
    ns["metadata"]["labels"] = {}
    with pytest.raises(ValueError, match="not owned"):
        cli.stopped(config)


def test_secret_retry_does_not_rotate_or_adopt(config, monkeypatch):
    old = {
        "metadata": {"labels": {render.LABEL: config["installation"]}},
        "data": {"token": "eA=="},
    }
    calls = []

    def fake(c, *args, **kw):
        calls.append(args)
        return json.dumps(old)

    monkeypatch.setattr(cli, "kubectl", fake)
    cli.install_secret(config, "starbase2-worker", {"token": "x"})
    with pytest.raises(ValueError, match="differs"):
        cli.install_secret(config, "starbase2-worker", {"token": "y"})
    assert all(c[0] == "get" for c in calls)


def test_temporal_production_configuration_requires_namespace(monkeypatch):
    monkeypatch.setenv("STARBASE_ENV", "production")
    monkeypatch.delenv("STARBASE_TEMPORAL_NAMESPACE", raising=False)
    with pytest.raises(ValueError, match="dedicated"):
        settings()
    monkeypatch.setenv("STARBASE_TEMPORAL_NAMESPACE", "starbase2-prod")
    monkeypatch.setenv("STARBASE_TEMPORAL_CERT_FILE", "/missing-cert")
    monkeypatch.delenv("STARBASE_TEMPORAL_KEY_FILE", raising=False)
    with pytest.raises(ValueError, match="together"):
        settings()


def test_backup_corruption_and_other_installation_rejected(config, tmp_path):
    (tmp_path / "database.dump").write_bytes(b"data")
    manifest = {
        "installation": config["installation"],
        "database": config["database"],
        "dump_sha256": "wrong",
    }
    (tmp_path / "backup.json").write_text(json.dumps(manifest))
    with pytest.raises(ValueError, match="checksum"):
        cli.check_backup(config, tmp_path)
    manifest["installation"] = "starbase2-other"
    (tmp_path / "backup.json").write_text(json.dumps(manifest))
    with pytest.raises(ValueError, match="different"):
        cli.check_backup(config, tmp_path)


def test_temporal_refuses_foreign_namespace_and_open_history(config, monkeypatch):
    import asyncio
    from types import SimpleNamespace
    from unittest.mock import AsyncMock

    from scripts.deployment import temporal

    result = SimpleNamespace(
        namespace_info=SimpleNamespace(data={"starbase2-installation": "starbase2-other"}, state=1),
        config=SimpleNamespace(workflow_execution_retention_ttl=SimpleNamespace(seconds=2592000)),
    )
    service = SimpleNamespace(
        describe_namespace=AsyncMock(return_value=result),
        count_workflow_executions=AsyncMock(return_value=SimpleNamespace(count=1)),
    )
    operator = SimpleNamespace(delete_namespace=AsyncMock())
    monkeypatch.setattr(
        temporal,
        "connect",
        AsyncMock(
            return_value=SimpleNamespace(workflow_service=service, operator_service=operator)
        ),
    )
    with pytest.raises(ValueError, match="unowned"):
        asyncio.run(temporal.namespace(config, "delete"))
    result.namespace_info.data["starbase2-installation"] = config["installation"]
    with pytest.raises(ValueError, match="Open workflows"):
        asyncio.run(temporal.namespace(config, "delete"))
    operator.delete_namespace.assert_not_awaited()
    result.config.workflow_execution_retention_ttl.seconds = 86400
    with pytest.raises(ValueError, match="Retention"):
        asyncio.run(temporal.namespace(config, "ensure"))


def test_destructive_cli_defaults_to_no_execution(config, tmp_path, monkeypatch, capsys):
    import sys

    p = tmp_path / "config.json"
    p.write_text(json.dumps(config))
    monkeypatch.setattr(sys, "argv", ["deploy", "purge-db", "--config", str(p)])
    monkeypatch.setattr(cli, "kubectl", lambda *a, **k: pytest.fail("No remote calls allowed"))
    monkeypatch.setattr(database, "psql", lambda *a, **k: pytest.fail("No database calls allowed"))
    cli.main()
    assert "PLAN ONLY" in capsys.readouterr().out


def test_rollback_cannot_cross_installations(config, tmp_path, monkeypatch):
    import sys

    other = config | {"database": "starbase2_other"}
    previous = tmp_path / "previous"
    render.render(other, previous)
    p = tmp_path / "config.json"
    p.write_text(json.dumps(config))
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "deploy",
            "rollback",
            "--config",
            str(p),
            "--previous",
            str(previous),
            "--execute",
            "--confirm",
            config["installation"],
        ],
    )
    with pytest.raises(ValueError, match="identity differs"):
        cli.main()


def test_permanent_namespace_cleanup_refuses_foreign_resources(config, monkeypatch):
    def fake(c, *args, **kwargs):
        if args[0] == "api-resources":
            return "configmaps"
        if args[0] == "get":
            return json.dumps({"items": [{"metadata": {"name": "foreign-config"}}]})
        pytest.fail("Must not delete namespace or policy")

    monkeypatch.setattr(cli, "kubectl", fake)
    with pytest.raises(ValueError, match="Unowned"):
        cli.purge_kubernetes(config)


@pytest.mark.parametrize("platform", ["linux/amd64", "linux/arm64"])
def test_application_and_migration_schedule_only_on_qualified_architecture(config, platform):
    config["platform"] = platform
    resources = render.objects(config)
    for obj in resources:
        if obj["kind"] in {"Deployment", "Job"}:
            assert obj["spec"]["template"]["spec"]["nodeSelector"] == {
                "kubernetes.io/os": "linux",
                "kubernetes.io/arch": platform.split("/")[1],
            }


def test_image_qualification_rejects_wrong_architecture_or_revision():
    from scripts.deployment.image_rehearsal import verify_image

    info = {
        "Os": "linux",
        "Architecture": "arm64",
        "Config": {"Labels": {"org.opencontainers.image.revision": "a" * 40}},
    }
    verify_image(info, "arm64", "a" * 40)
    with pytest.raises(ValueError, match="architecture"):
        verify_image(info, "amd64", "a" * 40)
    with pytest.raises(ValueError, match="revision"):
        verify_image(info, "arm64", "b" * 40)
