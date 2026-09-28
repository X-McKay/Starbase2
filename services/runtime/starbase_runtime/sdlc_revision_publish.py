"""Fixed-repository verification statuses and independently gated PR corrections.

Only the selected capability source can change. Non-force branch updates and comments
have one-shot Core claims; uncertain responses are reconciled before any retry.
"""

import base64
import json
import re
from datetime import UTC, datetime
from urllib.parse import quote

import httpx

from . import sdlc_pilot
from .operations import request
from .review import digest
from .sdlc_publish import PREFIX, PublicationUnknown, _sha

CONTEXT = "starbase/persistence-regression"


def context(mission):
    opportunity = mission["input"].get("opportunity", sdlc_pilot.OPPORTUNITY)
    cap = sdlc_pilot.contract(mission)
    return (
        CONTEXT
        if opportunity == sdlc_pilot.OPPORTUNITY
        else f"starbase/{cap['opportunity']}-regression"
    )


def _identity(mission):
    mid = mission["id"]
    if not isinstance(mid, str) or not re.fullmatch(r"[A-Za-z0-9-]{1,80}", mid):
        raise ValueError("Invalid mission identity")
    if mission["input"]["repository"].lower() != sdlc_pilot.REPOSITORY:
        raise ValueError("Repository outside correction scope")
    receipt = mission["evidence"]["submitted"]
    number, branch = receipt["number"], receipt["branch"]
    if type(number) is not int or number <= 0 or branch != "starbase/" + mid:
        raise ValueError("Invalid retained PR identity")
    return mid, number, branch


def _verification(mission, verification):
    mid, number, branch = _identity(mission)
    vid = verification["id"]
    if not isinstance(vid, str) or not re.fullmatch(r"[A-Za-z0-9-]{1,80}", vid):
        raise ValueError("Invalid verification identity")
    head = _sha(verification["input"]["head"])
    return f"/internal/v7/missions/{mid}/verifications/{vid}", number, branch, head, vid


async def _json(http, method, path, *, body=None, params=None):
    mutable = method in {"POST", "PATCH"}
    try:
        async with http.stream(method, PREFIX + path, json=body, params=params) as response:
            if not 200 <= response.status_code < 300:
                if mutable and response.status_code >= 500:
                    raise PublicationUnknown("GitHub revision effect requires reconciliation")
                raise RuntimeError(f"GitHub revision HTTP {response.status_code}")
            raw = bytearray()
            async for part in response.aiter_bytes():
                raw.extend(part)
                if len(raw) > 2_000_000:
                    raise PublicationUnknown("GitHub revision response exceeded bounded coverage")
            try:
                return json.loads(raw)
            except (ValueError, UnicodeError):
                raise PublicationUnknown(
                    "GitHub revision response requires reconciliation"
                ) from None
    except httpx.HTTPError:
        raise PublicationUnknown("GitHub revision transport requires reconciliation") from None


async def _observe(http, mission):
    _, number, branch = _identity(mission)
    pull = await _json(http, "GET", f"/pulls/{number}")
    repo = await _json(http, "GET", "")
    if (
        pull.get("number") != number
        or pull.get("head", {}).get("ref") != branch
        or pull.get("head", {}).get("repo", {}).get("full_name", "").lower()
        != sdlc_pilot.REPOSITORY
        or pull.get("base", {}).get("repo", {}).get("full_name", "").lower()
        != sdlc_pilot.REPOSITORY
        or not isinstance(repo.get("default_branch"), str)
        or pull.get("base", {}).get("ref") != repo["default_branch"]
    ):
        raise ValueError("PR identity outside retained repository/branch scope")
    if pull.get("state") not in {"open", "closed"} or type(pull.get("merged")) is not bool:
        raise ValueError("Unknown PR lifecycle state")
    if pull["state"] == "open" and pull["merged"]:
        raise ValueError("Inconsistent PR lifecycle state")
    return {
        "state": "merged" if pull["merged"] else pull["state"],
        "head": _sha(pull["head"]["sha"]),
        "open": pull.get("state") == "open" and pull.get("merged") is False,
        "branch": branch,
    }


async def observe(mission: dict) -> dict:
    """Read the current head of the one retained PR, without provider mutations."""
    async with sdlc_pilot.client() as http:
        return await _observe(http, mission)


async def _fresh(http, mission, heads):
    value = await _observe(http, mission)
    if not value["open"]:
        raise ValueError("PR is closed or merged")
    if value["head"] not in heads:
        raise ValueError("PR head changed; verification must restart")
    return value


async def _authorize(core):
    return await request("POST", core + "/authorize", {})


async def _claim(core, kind, data):
    await _authorize(core)
    result = await request("POST", core + "/effect", {"key": kind, "kind": kind, "data": data})
    return result["claimed"] is True


async def status(mission: dict, verification: dict, pending: bool) -> dict:
    core, number, _, head, vid = _verification(mission, verification)
    status_context = context(mission)
    authorized = await _authorize(core)
    if authorized.get("input", {}).get("head") != head:
        raise ValueError("Verification head does not match Core authority")
    if pending:
        state, kind = "pending", "status_pending"
    else:
        outcome = authorized.get("evidence", {}).get("verified", {}).get("outcome")
        states = {
            "passed": "success",
            "failed": "failure",
            "infrastructure_blocked": "error",
        }
        if outcome not in states:
            raise ValueError("Core has no publishable independent verification outcome")
        state, kind = states[outcome], "status_result"
    description = f"Starbase verification {vid}: {state}"
    async with sdlc_pilot.client() as http:
        await _fresh(http, mission, {head})

        async def found():
            values = await _json(http, "GET", f"/commits/{head}/statuses", params={"per_page": 100})
            if not isinstance(values, list) or len(values) >= 100:
                raise PublicationUnknown("Status reconciliation coverage incomplete")
            matches = [
                v
                for v in values
                if v.get("context") == status_context
                and v.get("description") == description
                and v.get("state") == state
            ]
            if len(matches) > 1:
                raise PublicationUnknown("Ambiguous verification status")
            if not matches:
                return None
            value = matches[0]
            if type(value.get("id")) is not int or value["id"] <= 0:
                raise ValueError("Invalid status identity")
            return value["id"]

        claimed = await _claim(
            core, kind, {"head": head, "state": state, "context": status_context}
        )
        status_id = await found()
        if status_id is None:
            status_id = await found()
            if status_id is None:
                if not claimed:
                    raise PublicationUnknown("Claimed status is not visible; reconcile manually")
                await _fresh(http, mission, {head})
                await _authorize(core)
                await _json(
                    http,
                    "POST",
                    f"/statuses/{head}",
                    body={
                        "state": state,
                        "context": status_context,
                        "description": description,
                        "target_url": f"https://github.com/X-McKay/algent/pull/{number}",
                    },
                )
                status_id = await found()
        if status_id is None:
            raise PublicationUnknown("Published status is not visible")
    return {"id": status_id, "head": head, "state": state, "context": status_context}


def _candidate(authorized, files, capability=None):
    capability = capability or sdlc_pilot.CAPABILITY
    paths = capability["source_paths"]
    source = capability["editable_paths"][0]
    if set(files) != set(paths) or any(
        not isinstance(v, str) or len(v.encode()) > 24000 for v in files.values()
    ):
        raise ValueError("Correction source paths or sizes outside scope")
    evidence = authorized.get("evidence", {})
    baseline = evidence.get("verified", {}).get("sources", {})
    if set(baseline) != set(paths):
        raise ValueError("Missing retained verification source")
    if any(files[path] != baseline[path] for path in files if path != source):
        raise ValueError("Correction changed an unrelated source file")
    if files[source] == baseline[source]:
        raise ValueError("Unchanged correction")
    artifact_digest = digest(files)
    if evidence.get("testing", {}).get("artifact_digest") != artifact_digest:
        raise ValueError("Correction does not match Core tested artifact")
    if evidence.get("reviewing", {}).get("status") != "accept":
        raise ValueError("Correction has no independent acceptance")
    return artifact_digest


def _previous_candidate(authorized):
    values = [
        e["input"]["data"].get("candidate_head")
        for e in authorized.get("effects", [])
        if e.get("input", {}).get("kind") == "branch_update"
    ]
    if len(values) > 1:
        raise ValueError("Ambiguous retained branch update")
    return _sha(values[0]) if values else None


async def update(mission: dict, verification: dict, files: dict) -> dict:
    core, number, branch, head, vid = _verification(mission, verification)
    authorized = await _authorize(core)
    if authorized.get("input", {}).get("head") != head:
        raise ValueError("Verification head does not match Core authority")
    cap = sdlc_pilot.contract(mission)
    source = cap["editable_paths"][0]
    artifact_digest = _candidate(authorized, files, cap)
    previous = _previous_candidate(authorized)
    allowed_heads = {head} | ({previous} if previous else set())
    branch_path = "/git/ref/heads/" + quote(branch, safe="/")
    marker = f"<!-- starbase2-verification:{vid} -->"
    async with sdlc_pilot.client() as http:
        await _fresh(http, mission, allowed_heads)

        async def immutable(path, body):
            await _fresh(http, mission, allowed_heads)
            await _authorize(core)
            return await _json(http, "POST", path, body=body)

        parent = await _json(http, "GET", "/git/commits/" + head)
        blob = await immutable(
            "/git/blobs",
            {
                "content": base64.b64encode(files[source].encode()).decode(),
                "encoding": "base64",
            },
        )
        tree = await immutable(
            "/git/trees",
            {
                "base_tree": _sha(parent["tree"]["sha"]),
                "tree": [
                    {
                        "path": source,
                        "mode": "100644",
                        "type": "blob",
                        "sha": _sha(blob["sha"]),
                    }
                ],
            },
        )
        at = datetime.fromtimestamp(verification["created_at"], UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
        identity = {"name": "Starbase2", "email": "starbase2@users.noreply.github.com", "date": at}
        commit = await immutable(
            "/git/commits",
            {
                "message": "Correct "
                + (
                    "persistence"
                    if cap["opportunity"] == sdlc_pilot.OPPORTUNITY
                    else cap["opportunity"]
                )
                + " regression\n\nStarbase2 verification: "
                + vid,
                "tree": _sha(tree["sha"]),
                "parents": [head],
                "author": identity,
                "committer": identity,
            },
        )
        candidate_head = _sha(commit["sha"])
        if previous is not None and previous != candidate_head:
            raise ValueError("Correction commit conflicts with retained effect")
        claimed = await _claim(
            core,
            "branch_update",
            {
                "expected_head": head,
                "candidate_head": candidate_head,
                "artifact_digest": artifact_digest,
            },
        )
        ref = await _json(http, "GET", branch_path)
        current = ref.get("object", {}).get("sha")
        if current != candidate_head:
            if not claimed:
                raise PublicationUnknown(
                    "Claimed branch correction not visible; reconcile manually"
                )
            if current != head:
                raise ValueError("Branch changed before correction")
            await _fresh(http, mission, {head})
            await _authorize(core)
            await _json(
                http,
                "PATCH",
                "/git/refs/heads/" + quote(branch, safe="/"),
                body={"sha": candidate_head, "force": False},
            )
            ref = await _json(http, "GET", branch_path)
            if ref.get("object", {}).get("sha") != candidate_head:
                raise PublicationUnknown("Branch correction outcome not visible")
        await _fresh(http, mission, {candidate_head})

        async def found_review():
            values = await _json(http, "GET", f"/pulls/{number}/reviews", params={"per_page": 100})
            if not isinstance(values, list) or len(values) >= 100:
                raise PublicationUnknown("Correction review coverage incomplete")
            matches = [v for v in values if marker in (v.get("body") or "")]
            if len(matches) > 1:
                raise PublicationUnknown("Ambiguous correction review")
            if not matches:
                return None
            value = matches[0]
            if (
                value.get("commit_id") != candidate_head
                or value.get("state") != "COMMENTED"
                or type(value.get("id")) is not int
                or value["id"] <= 0
            ):
                raise PublicationUnknown("Correction review identity mismatch")
            return value["id"]

        claimed = await _claim(core, "review", {"candidate_head": candidate_head})
        review_id = await found_review()
        if review_id is None:
            review_id = await found_review()
            if review_id is None:
                if not claimed:
                    raise PublicationUnknown(
                        "Claimed correction review not visible; reconcile manually"
                    )
                await _fresh(http, mission, {candidate_head})
                authorized = await _authorize(core)
                rationale = str(authorized["evidence"]["reviewing"].get("rationale", ""))[:4000]
                rationale = rationale.replace("@", "＠").replace("<", "&lt;").replace(">", "&gt;")
                await _json(
                    http,
                    "POST",
                    f"/pulls/{number}/reviews",
                    body={
                        "event": "COMMENT",
                        "commit_id": candidate_head,
                        "body": marker + "\n\nStarbase2 independent correction review. "
                        "The exact candidate passed the scoped capability checks and independent "
                        "crew review. No merge approval or application-wide qualification "
                        "is implied.\n\n" + rationale,
                    },
                )
                review_id = await found_review()
        if review_id is None:
            raise PublicationUnknown("Published correction review is not visible")
    return {
        "url": f"https://github.com/X-McKay/algent/pull/{number}",
        "number": number,
        "branch": branch,
        "head": candidate_head,
        "previous_head": head,
        "artifact_digest": artifact_digest,
        "review_id": review_id,
    }
