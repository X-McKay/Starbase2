"""Versioned fixture manifests and independent evidence gates.

This public grader is deliberately outside the service image and Git repository.
It is a development control pack, not a sealed agent qualification suite.
"""

import copy
import hashlib
import json
import math
from dataclasses import dataclass

VERSION = "readiness-v1"
CASES = (
    "route-mismatch",
    "python-environment",
    "transient-dependency",
    "persistent-dependency",
    "listening-but-broken",
    "healthy",
)


def digest(value: object) -> str:
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def manifest(case: str, image: str) -> dict:
    if case not in CASES:
        raise ValueError("Unknown versioned readiness case")
    probe = {"periodSeconds": 2, "timeoutSeconds": 1, "failureThreshold": 3}
    readiness: dict = {**probe, "httpGet": {"path": "/ready", "port": "http"}}
    liveness: dict = {**probe, "httpGet": {"path": "/live", "port": "http"}}
    if case == "route-mismatch":
        readiness["httpGet"]["path"] = liveness["httpGet"]["path"] = "/health"
    elif case == "python-environment":
        for target, path in ((readiness, "/ready"), (liveness, "/live")):
            del target["httpGet"]
            target["exec"] = {
                "command": [
                    "/usr/local/bin/python3",
                    "-I",
                    "-B",
                    "-c",
                    f"from fixture_worker import check; check('{path}')",
                ]
            }
    delay = {"transient-dependency": "25", "persistent-dependency": "-1"}.get(case, "0")
    return {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {"name": "readiness-fixture", "namespace": "readiness-lab"},
        "spec": {
            "replicas": 1,
            "strategy": {"type": "Recreate"},
            "selector": {"matchLabels": {"app": "readiness-fixture"}},
            "template": {
                "metadata": {"labels": {"app": "readiness-fixture"}},
                "spec": {
                    "automountServiceAccountToken": False,
                    "securityContext": {
                        "runAsNonRoot": True,
                        "runAsUser": 10001,
                        "runAsGroup": 10001,
                        "seccompProfile": {"type": "RuntimeDefault"},
                    },
                    "containers": [
                        {
                            "name": "worker",
                            "image": image,
                            "imagePullPolicy": "Never",
                            "ports": [{"name": "http", "containerPort": 8080}],
                            "env": [
                                {"name": "DEPENDENCY_DELAY", "value": delay},
                                {
                                    "name": "BROKEN_WORK",
                                    "value": str(case == "listening-but-broken"),
                                },
                            ],
                            "resources": {
                                "requests": {"cpu": "50m", "memory": "32Mi"},
                                "limits": {"cpu": "500m", "memory": "96Mi"},
                            },
                            "securityContext": {
                                "allowPrivilegeEscalation": False,
                                "readOnlyRootFilesystem": True,
                                "capabilities": {"drop": ["ALL"]},
                            },
                            "readinessProbe": readiness,
                            "livenessProbe": liveness,
                            "startupProbe": {
                                "httpGet": {"path": "/live", "port": "http"},
                                "periodSeconds": 1,
                                "failureThreshold": 15,
                            },
                        }
                    ],
                },
            },
        },
    }


def repair(seed: dict, case: str) -> dict:
    proposed = copy.deepcopy(seed)
    container = proposed["spec"]["template"]["spec"]["containers"][0]
    if case == "route-mismatch":
        container["readinessProbe"]["httpGet"]["path"] = "/ready"
        container["livenessProbe"]["httpGet"]["path"] = "/live"
    elif case == "python-environment":
        for key in ("readinessProbe", "livenessProbe"):
            container[key]["exec"]["command"][0] = "/opt/worker/bin/python3"
    else:
        raise ValueError("This control has no authored probe repair")
    return proposed


def scope_errors(seed: dict, proposed: dict) -> list[str]:
    """Allow only probe routes or a known interpreter, preserving assertions/timing.

    Invalid changes are rejected before Git publication; no candidate shell/code
    or general Kubernetes manifests are executed by this harness.
    """
    normalized = copy.deepcopy(proposed)
    try:
        before = seed["spec"]["template"]["spec"]["containers"][0]
        after = normalized["spec"]["template"]["spec"]["containers"][0]
        for name in ("readinessProbe", "livenessProbe"):
            old, new = before[name], after[name]
            if "httpGet" in old:
                correct = "/ready" if name == "readinessProbe" else "/live"
                if new["httpGet"]["path"] not in {old["httpGet"]["path"], correct, "/missing"}:
                    return ["probe-route-outside-fixture"]
                new["httpGet"]["path"] = old["httpGet"]["path"]
            else:
                if new["exec"]["command"][0] not in {
                    "/usr/local/bin/python3",
                    "/opt/worker/bin/python3",
                }:
                    return ["probe-interpreter-outside-fixture"]
                new["exec"]["command"][0] = old["exec"]["command"][0]
    except (KeyError, IndexError, TypeError):
        return ["probe-removed-or-replaced"]
    return [] if normalized == seed else ["mutation-outside-probe-contract"]


@dataclass
class Observation:
    elapsed_seconds: float
    revision: str
    flux_current: bool
    workload_current: bool
    ready: bool
    pod_uid: str
    restarts: int
    functional: bool | None


def ready_window(observations: list[Observation], revision: str) -> bool:
    """The sampler and grader share the complete positive evidence gate."""
    times = [o.elapsed_seconds for o in observations]
    return (
        len(observations) >= 3
        and all(math.isfinite(t) for t in times)
        and times == sorted(set(times))
        and times[-1] - times[0] >= 4
        and len({o.pod_uid for o in observations}) == 1
        and len({o.restarts for o in observations}) == 1
        and all(
            o.revision == revision
            and o.flux_current
            and o.workload_current
            and o.pod_uid
            and o.ready
            and o.functional is True
            for o in observations
        )
    )


def grade(
    seed: dict, proposed: dict, revision: str, observations: list[Observation], action: str
) -> dict:
    result = {"contract": VERSION, "xp": 0, "verdict": "invalid", "reasons": []}

    def finish(verdict: str, *reasons: str) -> dict:
        return {**result, "verdict": verdict, "reasons": list(reasons)}

    errors = scope_errors(seed, proposed)
    if errors:
        return finish("ineligible", *errors)
    if action not in {"repair", "wait", "escalate"}:
        return finish("invalid", "unknown-action")
    if len(observations) < 3:
        return finish("invalid", "missing-stability-evidence")
    times = [o.elapsed_seconds for o in observations]
    if (
        not all(math.isfinite(t) for t in times)
        or times != sorted(set(times))
        or times[-1] - times[0] < 4
    ):
        return finish("invalid", "invalid-stability-window")
    if any(
        o.revision != revision
        or not o.flux_current
        or not o.workload_current
        or o.functional is None
        or not o.pod_uid
        for o in observations
    ):
        return finish("invalid", "missing-or-stale-observation")
    stable = ready_window(observations, revision)
    changed = seed != proposed
    if action == "escalate":
        if observations[-1].elapsed_seconds < 30:
            return finish("invalid", "observation-deadline-not-reached")
        if not changed and all(not o.ready and o.functional is False for o in observations):
            return finish("blocked", "unresolved-dependency")
        return finish("failed", "escalation-not-supported")
    if not stable:
        return finish("failed", "functional-or-stability-gate")
    if action == "wait" and not changed:
        return finish("verified-no-change")
    if action == "repair" and changed:
        return finish("verified-repair")
    return finish("failed", "action-does-not-match-change")
