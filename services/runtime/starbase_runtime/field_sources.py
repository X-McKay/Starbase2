"""Bounded GET-only provider adapters. No source checkout, shell, log or secret access."""

import base64
import hashlib
import json
import re
import ssl
from pathlib import Path
from urllib.parse import quote

import httpx

from .review import digest, redact, scan_sources

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_TARGETS = [
    {
        "id": "cluster-fixture",
        "agent": "watchkeeper",
        "kind": "fixture",
        "fixture": "cluster",
        "allow_inference": False,
    },
    {
        "id": "pr-fixture",
        "agent": "reviewer",
        "kind": "fixture",
        "fixture": "pr",
        "allow_inference": True,
    },
]


def validate_target(target: dict) -> None:
    if not re.fullmatch(r"[a-zA-Z0-9-]{1,100}", target["id"]):
        raise ValueError("Invalid target identity")
    kind = target["kind"]
    allowed = {"id", "agent", "kind", "allow_inference"} | {
        "fixture": {"fixture"},
        "github": {"repository", "pull", "token_file"},
        "github_repository": {"repository", "token_file"},
        "kubernetes": {"api", "namespaces", "token_file", "ca_file"},
    }.get(kind, set())
    if set(target) - allowed or type(target.get("allow_inference", False)) is not bool:
        raise ValueError("Unknown target fields; credentials must use credential files")
    if target["agent"] not in {"watchkeeper", "reviewer"}:
        raise ValueError("Unknown agent")
    if kind in {"github", "github_repository"}:
        if (
            target["agent"] != "reviewer"
            or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", target["repository"])
            or (kind == "github" and (type(target.get("pull")) is not int or target["pull"] < 1))
            or any(p in {".", ".."} for p in target["repository"].split("/"))
        ):
            raise ValueError("A GitHub target requires an explicit repository and PR")
    elif kind == "kubernetes":
        url = httpx.URL(target["api"])
        if (
            target["agent"] != "watchkeeper"
            or url.scheme != "https"
            or url.username
            or url.password
            or url.path != "/"
            or not url.host
            or url.query
            or url.fragment
        ):
            raise ValueError("Cluster target requires a verified HTTPS API origin")
        if not 1 <= len(target["namespaces"]) <= 10 or not all(
            len(n) <= 63 and re.fullmatch(r"[a-z0-9]([-a-z0-9]*[a-z0-9])?", n)
            for n in target["namespaces"]
        ):
            raise ValueError("Cluster namespaces must be explicitly scoped")
    elif (
        kind != "fixture"
        or target.get("fixture") != {"watchkeeper": "cluster", "reviewer": "pr"}[target["agent"]]
    ):
        raise ValueError("Unknown connector or mismatched fixture")


def public_target(target: dict) -> dict:
    return {k: v for k, v in target.items() if not k.endswith("_file")}


async def get_json(client: httpx.AsyncClient, path: str, params: dict | None = None):
    async with client.stream("GET", path, params=params) as response:
        if response.status_code != 200:
            # Provider error bodies can contain tokens, source or private messages.
            raise ValueError(f"Provider returned HTTP {response.status_code}")
        data = bytearray()
        async for part in response.aiter_bytes():
            data.extend(part)
            if len(data) > 2_000_000:
                raise ValueError("Provider response budget exceeded")
        return json.loads(data)


def headers(target: dict) -> dict:
    token = Path(target["token_file"]).read_text().strip() if target.get("token_file") else ""
    return {"Authorization": "Bearer " + token} if token else {}


async def cluster(target: dict, client: httpx.AsyncClient) -> dict:
    records, coverage = [], []
    for namespace in target["namespaces"]:
        for resource, base in [("pods", "/api/v1"), ("deployments", "/apis/apps/v1")]:
            continuation = ""
            for _ in range(5):
                payload = await get_json(
                    client,
                    f"{base}/namespaces/{namespace}/{resource}",
                    {"limit": 100, "continue": continuation},
                )
                if not isinstance(payload.get("items"), list):
                    raise ValueError("Malformed Kubernetes list")
                for item in payload["items"]:
                    meta, status = item["metadata"], item.get("status", {})
                    record = {
                        "kind": resource,
                        "namespace": namespace,
                        "name": meta["name"],
                        "uid": meta["uid"],
                        "version": meta["resourceVersion"],
                    }
                    if resource == "pods":
                        record["phase"] = status.get("phase", "Unknown")
                        record["containers"] = [
                            {
                                "name": s["name"],
                                "ready": s.get("ready", False),
                                "restarts": s.get("restartCount", 0),
                                "waiting": s.get("state", {}).get("waiting", {}).get("reason"),
                            }
                            for s in status.get("containerStatuses", [])
                        ]
                    else:
                        record.update(
                            desired=item.get("spec", {}).get("replicas", 1),
                            available=status.get("availableReplicas", 0),
                            generation=meta.get("generation"),
                            observed_generation=status.get("observedGeneration"),
                        )
                    records.append(record)
                continuation = payload.get("metadata", {}).get("continue", "")
                if not continuation:
                    break
            if continuation:
                coverage.append(f"{namespace}/{resource}: pagination budget exhausted")
    return {
        "kind": "cluster",
        "resources": records,
        "coverage": coverage,
        "scope": target["namespaces"],
        "simulation": False,
    }


def added_lines(patch: str) -> list[int]:
    line, added = 0, []
    for text in patch.splitlines():
        if text.startswith("@@"):
            match = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", text)
            if not match:
                raise ValueError("Malformed diff hunk")
            line = int(match[1])
        elif text.startswith("+") and not text.startswith("+++"):
            added.append(line)
            line += 1
        elif not text.startswith(("-", "\\")):
            line += 1
    return added


async def github(
    target: dict, client: httpx.AsyncClient, source_budget: int = 1_000_000, file_budget: int = 100
) -> dict:
    repo, number = target["repository"], target["pull"]
    path = f"/repos/{repo}/pulls/{number}"
    before = await get_json(client, path)
    head = before["head"]["sha"]
    if not re.fullmatch("[a-f0-9]{40}", head):
        raise ValueError("Invalid PR revision")
    files, coverage, total = [], [], 0
    entries = []
    for page in range(1, 4):
        batch = await get_json(client, path + "/files", {"per_page": 100, "page": page})
        if not isinstance(batch, list):
            raise ValueError("Malformed GitHub file list")
        entries.extend(batch)
        if len(batch) < 100:
            break
    if len(entries) != before["changed_files"]:
        coverage.append("PR file list incomplete; budget 300 files")
    for item in entries:
        name = item["filename"]
        if item["status"] == "removed":
            coverage.append("Deleted file omitted: " + name)
            continue
        if not name.endswith(".py"):
            coverage.append("Unsupported language: " + name)
            continue
        if not item.get("patch"):
            coverage.append("Missing/truncated patch: " + name)
            continue
        blob_sha = item["sha"]
        if not re.fullmatch("[a-f0-9]{40}", blob_sha):
            raise ValueError("Invalid blob identity")
        blob = await get_json(client, f"/repos/{repo}/git/blobs/{quote(blob_sha)}")
        if blob.get("encoding") != "base64" or blob.get("size", 2_000_000) > 100_000:
            coverage.append("Unsupported/oversized blob: " + name)
            continue
        raw = base64.b64decode(blob["content"], validate=False)
        total += len(raw)
        if total > source_budget or len(files) >= file_budget:
            coverage.append("Source budget exhausted")
            break
        if hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest() != blob_sha:
            raise ValueError("Git blob content identity mismatch")
        if len(added_lines(item["patch"])) != item.get("additions", -1):
            coverage.append("Incomplete diff hunks: " + name)
        source = raw.decode("utf-8")
        files.append(
            {
                "path": name,
                "sha256": digest(source),
                "source": redact(source),
                "added_lines": added_lines(item["patch"]),
            }
        )
    after = await get_json(client, path)
    if after["head"]["sha"] != head or after["base"]["sha"] != before["base"]["sha"]:
        raise ValueError("PR changed during capture; no mixed-revision review")
    return {
        "kind": "pr",
        "repository": repo,
        "number": number,
        "head": head,
        "base": before["base"]["sha"],
        "files": files,
        "coverage": coverage,
        "simulation": False,
    }


async def capture(target: dict) -> dict:
    validate_target(target)
    if target["kind"] == "fixture":
        return json.loads((ROOT / "fixtures/field" / (target["fixture"] + ".json")).read_text())
    verify = ssl.create_default_context(cafile=target.get("ca_file"))
    origin = target.get("api", "https://api.github.com")
    async with httpx.AsyncClient(
        base_url=origin,
        headers=headers(target)
        | {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2026-03-10"},
        verify=verify,
        timeout=15,
        follow_redirects=False,
        trust_env=False,
    ) as client:
        return (
            await cluster(target, client)
            if target["kind"] == "kubernetes"
            else await repository(target, client)
            if target["kind"] == "github_repository"
            else await github(target, client)
        )


def finding(code: str, subject: str, summary: str, recommendation: str, line: int = 0) -> dict:
    return {
        "key": digest([code, subject, line]),
        "code": code,
        "subject": subject,
        "line": line,
        "summary": summary,
        "recommendation": recommendation,
    }


def analyze(data: dict) -> tuple[list, list]:
    coverage = list(data["coverage"])
    findings = []
    if data["kind"] == "repository":
        for pr in data["pulls"]:
            child_findings, child_coverage = analyze(pr)
            prefix = f"{data['repository']}#{pr['number']} / "
            for f in child_findings:
                f["subject"] = prefix + f["subject"]
                f["key"] = digest([f["code"], f["subject"], f["line"]])
            findings.extend(child_findings)
            coverage.extend(prefix + c for c in child_coverage)
    elif data["kind"] == "cluster":
        for item in data["resources"]:
            subject = f"{item['namespace']}/{item['kind']}/{item['name']}"
            if item["kind"] == "deployments":
                if item.get("observed_generation") != item.get("generation"):
                    coverage.append(subject + ": controller status is not current")
                if item["available"] < item["desired"]:
                    findings.append(
                        finding(
                            "replicas-unavailable",
                            subject,
                            "Available replicas are below desired replicas.",
                            "Inspect rollout conditions and scheduling before a restart.",
                        )
                    )
            else:
                if item["phase"] in {"Failed", "Pending", "Unknown"}:
                    findings.append(
                        finding(
                            "pod-" + item["phase"].lower(),
                            subject,
                            "Pod phase is " + item["phase"] + ".",
                            "Inspect scheduling, resource limits and recent deployment changes.",
                        )
                    )
                for container in item["containers"]:
                    if container["waiting"] in {
                        "CrashLoopBackOff",
                        "ImagePullBackOff",
                        "ErrImagePull",
                    }:
                        findings.append(
                            finding(
                                container["waiting"],
                                subject + "/" + container["name"],
                                "Container cannot enter a stable running state.",
                                "Inspect the image, startup configuration and restart history.",
                            )
                        )
                    elif not container["ready"] and item["phase"] == "Running":
                        findings.append(
                            finding(
                                "container-not-ready",
                                subject + "/" + container["name"],
                                "Running container is not ready.",
                                "Inspect readiness probes and dependencies.",
                            )
                        )
        if not data["resources"]:
            coverage.append("No workload objects returned; no cluster health conclusion")
    else:
        snapshot = {
            "digest": digest(data),
            "files": [{k: f[k] for k in ("path", "source", "sha256")} for f in data["files"]],
            "skipped": [],
        }
        report = scan_sources(snapshot, "surveyor-v2")
        changed = {f["path"]: set(f["added_lines"]) for f in data["files"]}
        for item in report["findings"]:
            if item["line"] in changed[item["file"]]:
                findings.append(
                    finding(
                        item["code"],
                        item["file"],
                        item["message"],
                        "Review this added line against the PR intent.",
                        item["line"],
                    )
                )
        coverage.extend(str(e) for e in report["errors"])
        if not data["files"]:
            coverage.append("No supported changed Python source; no clean-review conclusion")
    if len(findings) > 100:
        coverage.insert(0, "Finding budget reached; additional findings omitted")
    if len(coverage) > 100:
        coverage = coverage[:99] + ["Additional coverage exclusions omitted"]
    return findings[:100], coverage


async def repository(target: dict, client: httpx.AsyncClient) -> dict:
    """One bounded repository observation, reusing the pinned PR verifier.

    Always disclose the coverage cap. Do not imply a full review of every open PR.
    No GitHub writes, source execution, model calls or arbitrary URL fetching.
    """
    repo = target["repository"]
    items = await get_json(
        client,
        f"/repos/{repo}/pulls",
        {
            "state": "open",
            "sort": "updated",
            "direction": "desc",
            "per_page": 11,
        },
    )
    if not isinstance(items, list) or len(items) > 11:
        raise ValueError("Malformed open PR list")
    coverage, pulls = [], []
    if len(items) > 10:
        coverage.append(
            "Only the 10 most recently updated open PRs reviewed; additional PRs omitted"
        )
    seen = set()
    for item in items[:10]:
        number = item.get("number")
        if type(number) is not int or number < 1 or number in seen:
            raise ValueError("Invalid or duplicate PR identity")
        seen.add(number)
        pr = await github(target | {"pull": number}, client, source_budget=80_000, file_budget=10)
        if pr["head"] != item["head"]["sha"] or pr["base"] != item["base"]["sha"]:
            raise ValueError("Repository changed during capture; retry a fresh observation")
        pulls.append(pr)
    return {
        "kind": "repository",
        "repository": repo,
        "pulls": pulls,
        "listed_open_prs": len(items),
        "list_complete": len(items) <= 10,
        "coverage": coverage,
        "simulation": False,
    }
