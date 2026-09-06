"""Deterministic, offline Kubani bundle renderer. JSON is valid Kubernetes YAML."""

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LABEL = "starbase2.io/installation"


def load(path: Path) -> dict:
    c = json.loads(path.read_text())
    expected = {
        "installation",
        "context",
        "namespace",
        "database",
        "postgres_host",
        "postgres_namespace",
        "temporal_address",
        "temporal_namespace",
        "temporal_kubernetes_namespace",
        "temporal_queue",
        "retention_days",
        "core_image",
        "runtime_image",
        "source_revision",
        "platform",
        "replicas",
        "accept_work",
    }
    if set(c) != expected:
        raise ValueError("Configuration keys differ from production.example.json")
    for key in ("installation", "namespace", "temporal_namespace", "temporal_queue"):
        if not re.fullmatch(r"starbase2-[a-z0-9][a-z0-9-]{0,38}", c[key]):
            raise ValueError(f"Invalid installation-scoped {key}")
    if not re.fullmatch(r"starbase2_[a-z0-9_]{1,32}", c["database"]):
        raise ValueError("Invalid dedicated database name")
    if c["namespace"] != c["installation"] or c["temporal_namespace"] != c["installation"]:
        raise ValueError("Installation, Kubernetes namespace and Temporal namespace must match")
    for key in ("postgres_namespace", "temporal_kubernetes_namespace"):
        if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", c[key]):
            raise ValueError(f"Invalid dependency namespace: {key}")
    if not re.fullmatch(r"[a-z0-9][a-z0-9.-]{0,250}", c["postgres_host"]):
        raise ValueError("PostgreSQL host must be a DNS name")
    if not re.fullmatch(r"[a-z0-9][a-z0-9.-]{0,250}:7233", c["temporal_address"]):
        raise ValueError("Temporal service must use a DNS name and the permitted gRPC port 7233")
    for key in ("core_image", "runtime_image"):
        if not re.fullmatch(r"[a-zA-Z0-9./:_-]+@sha256:[a-f0-9]{64}", c[key]):
            raise ValueError(f"{key} requires an immutable published digest")
    if not re.fullmatch(r"[a-f0-9]{40}", c["source_revision"]):
        raise ValueError("source_revision requires a committed revision")
    if c["platform"] not in {"linux/amd64", "linux/arm64"}:
        raise ValueError("platform must match a qualified Linux image architecture")
    if not c["context"] or "REPLACE" in c["context"]:
        raise ValueError("An explicit verified Kubernetes context is required")
    if type(c["retention_days"]) is not int or not 1 <= c["retention_days"] <= 90:
        raise ValueError("Retention must be 1–90 days")
    if type(c["replicas"]) is not int or c["replicas"] not in (0, 1):
        raise ValueError("Only zero or one authoritative pod is supported")
    if type(c["accept_work"]) is not bool:
        raise ValueError("accept_work must be boolean")
    return c


def objects(c: dict) -> list[dict]:
    ns = c["namespace"]
    labels = {LABEL: c["installation"]}

    def obj(kind, name, spec=None, api="v1", namespace=True, **extra):
        value = {
            "apiVersion": api,
            "kind": kind,
            "metadata": {"name": name, "labels": labels.copy()},
        }
        if namespace:
            value["metadata"]["namespace"] = ns
        if spec is not None:
            value["spec"] = spec
        value.update(extra)
        return value

    def secret_volume(name):
        return {
            "name": name,
            "secret": {"secretName": name, "defaultMode": 0o440},
        }

    def mount(name):
        return {"name": name, "mountPath": f"/secrets/{name}", "readOnly": True}

    security = {
        "allowPrivilegeEscalation": False,
        "readOnlyRootFilesystem": True,
        "capabilities": {"drop": ["ALL"]},
    }
    common = {
        "STARBASE_ENV": "production",
        "STARBASE_INSTALLATION": c["installation"],
        "STARBASE_TOKEN_FILE": "/secrets/starbase2-worker/token",
        "STARBASE_REPAIRS_ENABLED": "false",
        "STARBASE_LEGACY_ENABLED": "false",
        "STARBASE_FIELD_ENABLED": "false",
        "STARBASE_MEMORY_ENABLED": "false",
        "STARBASE_INFERENCE_ENABLED": "false",
        "STARBASE_ACCEPT_WORK": str(c["accept_work"]).lower(),
    }

    def env(d):
        return [{"name": k, "value": v} for k, v in sorted(d.items())]

    core = {
        "name": "core",
        "image": c["core_image"],
        "securityContext": security,
        "env": env(common | {"STARBASE_DATABASE_URL_FILE": "/secrets/starbase2-database/url"}),
        "volumeMounts": [
            mount("starbase2-worker"),
            mount("starbase2-database"),
            {"name": "core-tmp", "mountPath": "/tmp"},
        ],
        "resources": {
            "requests": {"cpu": "100m", "memory": "128Mi"},
            "limits": {"cpu": "1", "memory": "512Mi"},
        },
        "readinessProbe": {
            "exec": {"command": ["starbase-core", "--healthcheck"]},
            "timeoutSeconds": 15,
            "periodSeconds": 20,
        },
        "livenessProbe": {
            "exec": {"command": ["starbase-core", "--healthcheck"]},
            "timeoutSeconds": 15,
            "periodSeconds": 30,
            "failureThreshold": 5,
        },
        "startupProbe": {
            "exec": {"command": ["starbase-core", "--healthcheck"]},
            "timeoutSeconds": 15,
            "periodSeconds": 5,
            "failureThreshold": 24,
        },
    }
    runtime = {
        "name": "runtime",
        "image": c["runtime_image"],
        "securityContext": security,
        "env": env(
            common
            | {
                "STARBASE_TEMPORAL": c["temporal_address"],
                "STARBASE_TEMPORAL_NAMESPACE": c["temporal_namespace"],
                "STARBASE_TEMPORAL_QUEUE": c["temporal_queue"],
                "STARBASE_WORKSPACE": "/app",
            }
        ),
        "volumeMounts": [mount("starbase2-worker"), {"name": "runtime-tmp", "mountPath": "/tmp"}],
        "resources": {
            "requests": {"cpu": "250m", "memory": "256Mi"},
            "limits": {"cpu": "2", "memory": "1Gi"},
        },
        "readinessProbe": {
            "exec": {"command": ["/app/.venv/bin/python", "-m", "starbase_runtime.health"]},
            "timeoutSeconds": 8,
            "periodSeconds": 15,
        },
    }
    pod = {
        "nodeSelector": {
            "kubernetes.io/os": "linux",
            "kubernetes.io/arch": c["platform"].split("/")[1],
        },
        "serviceAccountName": "starbase2",
        "automountServiceAccountToken": False,
        "securityContext": {
            "runAsNonRoot": True,
            "runAsUser": 10001,
            "runAsGroup": 10001,
            "fsGroup": 10001,
            "seccompProfile": {"type": "RuntimeDefault"},
        },
        "terminationGracePeriodSeconds": 90,
        "containers": [core, runtime],
        "volumes": [
            secret_volume("starbase2-worker"),
            secret_volume("starbase2-database"),
            {"name": "core-tmp", "emptyDir": {"sizeLimit": "32Mi"}},
            {"name": "runtime-tmp", "emptyDir": {"sizeLimit": "256Mi"}},
        ],
    }
    namespace = obj("Namespace", ns, namespace=False)
    namespace["metadata"]["labels"].update(
        {
            "pod-security.kubernetes.io/enforce": "restricted",
            "pod-security.kubernetes.io/enforce-version": "v1.34",
        }
    )
    result = [
        namespace,
        obj("ServiceAccount", "starbase2", automountServiceAccountToken=False),
        obj(
            "Deployment",
            "starbase2",
            {
                "replicas": c["replicas"],
                "strategy": {"type": "Recreate"},
                "revisionHistoryLimit": 3,
                "selector": {"matchLabels": labels},
                "template": {
                    "metadata": {
                        "labels": labels,
                        "annotations": {"starbase2.io/source": c["source_revision"]},
                    },
                    "spec": pod,
                },
            },
            "apps/v1",
        ),
    ]

    def peers(name):
        return [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": name}}}]

    result.append(
        obj(
            "NetworkPolicy",
            "starbase2-boundary",
            {
                "podSelector": {},
                "policyTypes": ["Ingress", "Egress"],
                "ingress": [],
                "egress": [
                    {
                        "to": peers("kube-system"),
                        "ports": [{"protocol": "UDP", "port": 53}, {"protocol": "TCP", "port": 53}],
                    },
                    {
                        "to": peers(c["postgres_namespace"]),
                        "ports": [{"protocol": "TCP", "port": 5432}],
                    },
                    {
                        "to": peers(c["temporal_kubernetes_namespace"]),
                        "ports": [{"protocol": "TCP", "port": 7233}],
                    },
                ],
            },
            "networking.k8s.io/v1",
        )
    )
    database_access = obj(
        "NetworkPolicy",
        c["installation"] + "-postgres",
        {
            "podSelector": {"matchLabels": {"app.kubernetes.io/name": "postgresql"}},
            "policyTypes": ["Ingress"],
            "ingress": [
                {
                    "from": [
                        {
                            "namespaceSelector": {
                                "matchLabels": {"kubernetes.io/metadata.name": ns}
                            },
                            "podSelector": {"matchLabels": labels},
                        }
                    ],
                    "ports": [{"protocol": "TCP", "port": 5432}],
                }
            ],
        },
        "networking.k8s.io/v1",
    )
    database_access["metadata"]["namespace"] = c["postgres_namespace"]
    result.append(database_access)
    # The one-shot migrator is deliberately outside the Flux application bundle.
    # It requires a separately supplied owner credential and cannot overlap a running core.
    migration = obj(
        "Job",
        "starbase2-migrate-" + hashlib.sha256(c["core_image"].encode()).hexdigest()[:10],
        {
            "backoffLimit": 0,
            "activeDeadlineSeconds": 180,
            "template": {
                "metadata": {"labels": labels},
                "spec": {k: v for k, v in pod.items() if k not in {"containers", "volumes"}}
                | {
                    "restartPolicy": "Never",
                    "containers": [
                        {
                            "name": "migrate",
                            "image": c["core_image"],
                            "args": ["--migrate"],
                            "securityContext": security,
                            "env": env(
                                {"STARBASE_DATABASE_URL_FILE": "/secrets/starbase2-migrator/url"}
                            ),
                            "volumeMounts": [mount("starbase2-migrator")],
                            "resources": core["resources"],
                        }
                    ],
                    "volumes": [secret_volume("starbase2-migrator")],
                },
            },
        },
        "batch/v1",
    )
    return result + [migration]


def render(c: dict, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    resources = objects(c)
    # Do not overwrite another installation's generated bundle.
    lock_path = output / "release.json"
    if (
        lock_path.exists()
        and json.loads(lock_path.read_text())["config"]["installation"] != c["installation"]
    ):
        raise ValueError("Output directory belongs to another installation")
    files = {}
    for name, items in (("application.json", resources[:-1]), ("migration.json", resources[-1:])):
        content = json.dumps({"apiVersion": "v1", "kind": "List", "items": items}, indent=2) + "\n"
        (output / name).write_text(content)
        files[name] = hashlib.sha256(content.encode()).hexdigest()
    (output / "kustomization.yaml").write_text(
        "apiVersion: kustomize.config.k8s.io/v1beta1\nkind: "
        "Kustomization\nresources:\n  - application.json\n"
    )
    files["kustomization.yaml"] = hashlib.sha256(
        (output / "kustomization.yaml").read_bytes()
    ).hexdigest()
    lock_path.write_text(
        json.dumps(
            {
                "config": c,
                "files": files,
                "repository_schema_sha256": hashlib.sha256(
                    (ROOT / "services/core/repository-schema.sql").read_bytes()
                ).hexdigest(),
                "field_schema_sha256": hashlib.sha256(
                    (ROOT / "services/core/field-schema.sql").read_bytes()
                ).hexdigest(),
                "postgres_schema_sha256": hashlib.sha256(
                    (ROOT / "services/core/postgres-v1.sql").read_bytes()
                ).hexdigest(),
            },
            indent=2,
        )
        + "\n"
    )
