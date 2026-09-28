"""Bounded repository metadata; provider text is never an instruction or URL target."""

import re
from urllib.parse import quote

SHA = re.compile(r"[a-f0-9]{40}")


def identity(value):
    if type(value) is not int or value < 1:
        raise ValueError("Invalid GitHub object identity")
    return value


async def observe(repo, client, get_json):
    coverage = [
        "Repository health covers bounded GitHub metadata, issues, PRs and Actions only; "
        "it does not certify repository health or review all languages."
    ]
    health = {"head": None, "issues": [], "ci": [], "issues_complete": False, "ci_complete": False}
    path = f"/repos/{repo}"

    async def optional(suffix, params=None):
        try:
            return await get_json(client, path + suffix, params)
        except ValueError as error:
            if str(error) in {
                "Provider returned HTTP 403",
                "Provider returned HTTP 404",
                "Provider returned HTTP 409",
                "Provider returned HTTP 429",
                "Provider rate limited",
            }:
                coverage.append(
                    f"GitHub {suffix or 'metadata'} unavailable ({error}); permission, "
                    "visibility or rate limit may prevent observation; state unknown"
                )
                return None
            raise

    meta = await optional("")
    if meta is not None:
        if not isinstance(meta, dict):
            raise ValueError("Malformed repository metadata")
        branch = meta.get("default_branch")
        if (
            not isinstance(branch, str)
            or not branch
            or len(branch) > 255
            or any(ord(c) < 32 for c in branch)
        ):
            raise ValueError("Invalid default branch")
        health.update(
            default_branch=branch,
            archived=meta.get("archived") is True,
            disabled=meta.get("disabled") is True,
            visibility="private" if meta.get("private") is True else "public",
        )
        revision = await optional("/commits/" + quote(branch, safe=""))
        if revision is not None:
            if not isinstance(revision, dict) or not SHA.fullmatch(str(revision.get("sha", ""))):
                raise ValueError("Invalid default branch revision")
            health["head"] = revision["sha"]
    issues = await optional(
        "/issues", {"state": "open", "sort": "updated", "direction": "desc", "per_page": 31}
    )
    if issues is not None:
        if not isinstance(issues, list) or len(issues) > 31:
            raise ValueError("Malformed issue list")
        health["issues_complete"] = len(issues) <= 30
        for issue in issues[:30]:
            if "pull_request" not in issue:
                number = identity(issue.get("number"))
                health["issues"].append(
                    {"number": number, "url": f"https://github.com/{repo}/issues/{number}"}
                )
        if len(issues) > 30:
            coverage.append(
                "Open issue coverage limited to 30 recently updated entries (including PRs)"
            )
    if health["head"]:
        payload = await optional(
            "/actions/runs",
            {"head_sha": health["head"], "branch": health["default_branch"], "per_page": 31},
        )
        if payload is not None:
            if (
                not isinstance(payload, dict)
                or not isinstance(payload.get("workflow_runs"), list)
                or len(payload["workflow_runs"]) > 31
            ):
                raise ValueError("Malformed Actions run list")
            runs = payload["workflow_runs"]
            health["ci_complete"] = len(runs) <= 30 and payload.get("total_count", len(runs)) <= 30
            seen = set()
            # GitHub lists newest runs first. Keep the latest run of each workflow.
            for run in runs[:30]:
                if (
                    run.get("head_sha") != health["head"]
                    or run.get("head_branch") != health["default_branch"]
                ):
                    raise ValueError("Actions revision does not match observed default branch")
                workflow = identity(run.get("workflow_id"))
                if workflow in seen:
                    continue
                seen.add(workflow)
                number = identity(run.get("id"))
                status = run.get("status")
                conclusion = run.get("conclusion")
                if status not in {
                    "queued",
                    "in_progress",
                    "completed",
                    "waiting",
                    "pending",
                    "requested",
                }:
                    status = "unknown"
                if conclusion not in {
                    None,
                    "success",
                    "failure",
                    "neutral",
                    "cancelled",
                    "skipped",
                    "timed_out",
                    "action_required",
                    "stale",
                    "startup_failure",
                }:
                    conclusion = "unknown"
                health["ci"].append(
                    {
                        "id": number,
                        "workflow_id": workflow,
                        "head_sha": health["head"],
                        "status": status,
                        "conclusion": conclusion,
                        "url": f"https://github.com/{repo}/actions/runs/{number}",
                    }
                )
            if not health["ci_complete"]:
                coverage.append(
                    "Actions coverage limited to 30 latest runs at the observed revision"
                )
            if not runs:
                coverage.append("No Actions runs at the observed revision; CI state unknown")
    return health, coverage
