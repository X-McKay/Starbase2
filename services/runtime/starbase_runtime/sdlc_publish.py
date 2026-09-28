"""Trusted, fixed-repository publication with durable one-shot effect claims.

Candidate code never receives this adapter or its credential. Immutable Git
objects are replayable; refs, PRs and reviews require reconciliation after any
uncertain response. No branch updates, merges or approval reviews are supported.
"""

import base64
import re
from datetime import UTC, datetime
from urllib.parse import quote

import httpx

from . import sdlc_families, sdlc_pilot, sdlc_regression
from .operations import request
from .review import digest

WORKFLOW_PATH = ".github/workflows/starbase-persistence.yml"
WORKFLOW = """name: Starbase persistence regression
on:
  pull_request:
    paths:
      - src/utils/persistence.py
      - src/utils/logging.py
      - tests/test_persistence_history.py
      - .github/workflows/starbase-persistence.yml
permissions:
  contents: read
jobs:
  regression:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
        with:
          persist-credentials: false
      - uses: actions/setup-python@a26af69be951a213d495a4c3e4e4022e16d87065 # v5
        with:
          python-version: '3.13.5'
      - run: python -m unittest discover -s tests -p test_persistence_history.py -v
"""
PREFIX = f"/repos/{sdlc_pilot.REPOSITORY}"


class PublicationUnknown(RuntimeError):
    """A mutable effect may have happened. Reconcile; never blindly retry it."""


def artifacts(candidatefiles: dict[str, str], capability: dict | None = None) -> dict[str, str]:
    if set(candidatefiles) - set(sdlc_pilot.FILES):
        raise ValueError("Candidate publication paths outside pilot scope")
    capability = capability or sdlc_pilot.CAPABILITY
    if capability["opportunity"] != sdlc_pilot.OPPORTUNITY:
        path = capability["editable_paths"][0]
        source = candidatefiles.get(path)
        if not isinstance(source, str) or not source or len(source.encode()) > 24000:
            raise ValueError("Missing family publication source")
        test_path, test_source = sdlc_families.public_artifact(capability["opportunity"])
        workflow_path = ".github/workflows/starbase-" + capability["opportunity"] + ".yml"
        workflow = (
            WORKFLOW.replace("test_persistence_history.py", test_path.split("/")[-1])
            .replace(WORKFLOW_PATH, workflow_path)
            .replace(
                "name: Starbase persistence regression",
                "name: Starbase " + capability["opportunity"],
            )
        )
        return {path: source, test_path: test_source, workflow_path: workflow}
    source = candidatefiles.get(sdlc_pilot.SOURCE)
    if not isinstance(source, str) or not source or len(source.encode()) > 24000:
        raise ValueError("Missing or oversized publication source")
    return {
        sdlc_pilot.SOURCE: source,
        sdlc_regression.PATH: sdlc_regression.SOURCE,
        WORKFLOW_PATH: WORKFLOW,
    }


def _sha(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{40}", value):
        raise ValueError("Invalid Git object identity")
    return value


async def _json(http, method, path, *, body=None, params=None, missing=False):
    try:
        async with http.stream(method, PREFIX + path, json=body, params=params) as response:
            if missing and response.status_code == 404:
                return None
            if not 200 <= response.status_code < 300:
                # Never retain provider bodies, credentials, URLs or arbitrary errors.
                if method == "POST" and response.status_code >= 500:
                    raise PublicationUnknown("GitHub server outcome requires reconciliation")
                raise RuntimeError(f"GitHub publication HTTP {response.status_code}")
            data = bytearray()
            async for part in response.aiter_bytes():
                data.extend(part)
                if len(data) > 2_000_000:
                    raise ValueError("GitHub publication response budget exceeded")
            import json

            return json.loads(data)
    except httpx.HTTPError:
        raise PublicationUnknown("GitHub transport outcome requires reconciliation") from None


async def publish(mission: dict, files: dict) -> dict:
    """Publish verified artifacts; caller owns lifecycle and bounded retries."""
    ident = mission["id"]
    source = mission["input"]
    if not re.fullmatch(r"[A-Za-z0-9-]{1,80}", ident):
        raise ValueError("Invalid mission identity")
    if source["repository"].lower() != sdlc_pilot.REPOSITORY:
        raise ValueError("Repository outside pilot authorization")
    revision = _sha(source["revision"])
    publication_files = artifacts(files, sdlc_pilot.contract(mission))
    authorization = {"artifact_digest": digest(publication_files), "revision": revision}
    core = f"/internal/v7/missions/{ident}"
    branch = "starbase/" + ident
    marker = f"<!-- starbase2:{ident} -->"

    async def authorize():
        await request("POST", core + "/publication", authorization)

    async def claim(kind, data):
        await authorize()
        value = await request("POST", core + "/effect", {"key": kind, "kind": kind, "data": data})
        return value["claimed"] is True

    async def receipt(kind, data):
        await request(
            "POST",
            core + "/event",
            {"key": "published-" + kind, "stage": "publishing", "data": data},
        )

    await authorize()  # Revocation also fences all replay paths.
    async with sdlc_pilot.client() as http:
        head = None
        repo = await _json(http, "GET", "")
        base = repo["default_branch"]
        if not isinstance(base, str) or not base or len(base) > 255:
            raise ValueError("Invalid default branch")

        async def fresh():
            current = await _json(http, "GET", "")
            if current.get("default_branch") != base:
                raise ValueError("Default branch changed")
            head = await _json(http, "GET", "/commits/" + quote(base, safe=""))
            if head.get("sha") != revision:
                raise ValueError("Base revision changed; re-evaluation required")

        async def write(path, body):
            await fresh()
            if head is not None and (path == "/pulls" or path.endswith("/reviews")):
                current_branch = await _json(
                    http, "GET", "/git/ref/heads/" + quote(branch, safe="/"), missing=True
                )
                if current_branch is None or current_branch.get("object", {}).get("sha") != head:
                    raise PublicationUnknown("Publication branch changed before effect")
            await authorize()
            return await _json(http, "POST", path, body=body)

        # Never replace existing tests or workflow configuration at the base.
        for path in publication_files.keys() - {sdlc_pilot.contract(mission)["editable_paths"][0]}:
            existing = await _json(
                http, "GET", "/contents/" + path, params={"ref": revision}, missing=True
            )
            if existing is not None:
                raise ValueError("Trusted publication artifact already exists at base")
        base_commit = await _json(http, "GET", "/git/commits/" + revision)
        tree = []
        for path, text in sorted(publication_files.items()):
            blob = await write(
                "/git/blobs",
                {"content": base64.b64encode(text.encode()).decode(), "encoding": "base64"},
            )
            tree.append({"path": path, "mode": "100644", "type": "blob", "sha": _sha(blob["sha"])})
        tree_object = await write(
            "/git/trees", {"base_tree": _sha(base_commit["tree"]["sha"]), "tree": tree}
        )
        at = datetime.fromtimestamp(mission["created_at"], UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
        identity = {"name": "Starbase2", "email": "starbase2@users.noreply.github.com", "date": at}
        commit = await write(
            "/git/commits",
            {
                "message": "Fix "
                + sdlc_pilot.contract(mission)["opportunity"]
                + "\n\nStarbase2 mission: "
                + ident,
                "tree": _sha(tree_object["sha"]),
                "parents": [revision],
                "author": identity,
                "committer": identity,
            },
        )
        head = _sha(commit["sha"])
        branch_path = "/git/ref/heads/" + quote(branch, safe="/")
        existing = await _json(http, "GET", branch_path, missing=True)
        if existing is None:
            allowed = await claim("branch", {"branch": branch, "head": head})
            existing = await _json(http, "GET", branch_path, missing=True)
            if existing is None:
                if not allowed:
                    raise PublicationUnknown(
                        "Claimed branch is not visible; manual reconciliation required"
                    )
                await write("/git/refs", {"ref": "refs/heads/" + branch, "sha": head})
                existing = await _json(http, "GET", branch_path, missing=True)
        if existing is None or existing.get("object", {}).get("sha") != head:
            raise PublicationUnknown("Publication branch identity mismatch")
        await receipt("branch", {"branch": branch, "head": head})

        async def find_pr():
            pulls = await _json(
                http,
                "GET",
                "/pulls",
                params={
                    "state": "all",
                    "head": "X-McKay:" + branch,
                    "base": base,
                    "per_page": 100,
                },
            )
            if not isinstance(pulls, list) or len(pulls) >= 100:
                raise PublicationUnknown("PR reconciliation coverage unavailable")
            if len(pulls) > 1:
                raise PublicationUnknown("Ambiguous publication PR")
            if not pulls:
                return None
            pull = pulls[0]
            if (
                marker not in (pull.get("body") or "")
                or pull.get("head", {}).get("sha") != head
                or pull.get("head", {}).get("ref") != branch
                or pull.get("base", {}).get("ref") != base
            ):
                raise PublicationUnknown("PR identity mismatch")
            if not isinstance(pull.get("number"), int) or pull["number"] <= 0:
                raise ValueError("Invalid PR number")
            return pull

        pull = await find_pr()
        if pull is None:
            allowed = await claim("pr", {"branch": branch, "head": head, "base": base})
            pull = await find_pr()
            if pull is None:
                if not allowed:
                    raise PublicationUnknown(
                        "Claimed PR is not visible; manual reconciliation required"
                    )
                await write(
                    "/pulls",
                    {
                        "title": "Fix " + sdlc_pilot.contract(mission)["opportunity"] + " behavior",
                        "head": branch,
                        "base": base,
                        "body": marker
                        + "\n\nConversation messages sharing a timestamp could be returned "
                        "out of order, and limited histories could omit newer entries. "
                        "This bounded "
                        "change adds deterministic ordering and a public regression suite.\n\n"
                        "An autonomous lead, implementer and separate reviewer evaluated "
                        "the change. "
                        "Independent isolated Python 3.13.5 checks demonstrated a failing "
                        "baseline and passing candidate. The included CI checks the "
                        "public regression "
                        "on the repository's Python 3.13.5 runtime. This is not application-wide "
                        "qualification. Human merge review remains required.",
                    },
                )
                pull = await find_pr()
        if pull is None:
            raise PublicationUnknown("Submitted PR is not visible")
        number = pull["number"]
        result = {
            "url": f"https://github.com/X-McKay/algent/pull/{number}",
            "number": number,
            "head": head,
            "branch": branch,
        }
        await receipt("pr", result)

        async def find_review():
            reviews = await _json(http, "GET", f"/pulls/{number}/reviews", params={"per_page": 100})
            if not isinstance(reviews, list) or len(reviews) >= 100:
                raise PublicationUnknown("Review reconciliation coverage unavailable")
            matching = [v for v in reviews if marker in (v.get("body") or "")]
            if len(matching) > 1:
                raise PublicationUnknown("Ambiguous publication review")
            if matching:
                value = matching[0]
                if value.get("commit_id") != head or value.get("state") != "COMMENTED":
                    raise PublicationUnknown("Review revision mismatch")
                if not isinstance(value.get("id"), int) or value["id"] <= 0:
                    raise ValueError("Invalid review identity")
                return value["id"]
            return None

        review_id = await find_review()
        if review_id is None:
            allowed = await claim("review", {"number": number, "head": head})
            review_id = await find_review()
            if review_id is None:
                if not allowed:
                    raise PublicationUnknown(
                        "Claimed review is not visible; manual reconciliation required"
                    )
                rationale = mission.get("evidence", {}).get("reviewing", {}).get("rationale", "")
                rationale = (
                    str(rationale)[:4000]
                    .replace("@", "＠")
                    .replace("<", "&lt;")
                    .replace(">", "&gt;")
                )
                await write(
                    f"/pulls/{number}/reviews",
                    {
                        "event": "COMMENT",
                        "commit_id": head,
                        "body": marker
                        + "\n\nStarbase2 independent crew review (not a merge approval).\n\n"
                        + rationale
                        + "\n\nTrusted verification: isolated capability cases passed "
                        "for the candidate, "
                        "with a failing baseline. Scope: "
                        + sdlc_pilot.contract(mission)["verification"]["scope"],
                    },
                )
                review_id = await find_review()
        if review_id is None:
            raise PublicationUnknown("Submitted review is not visible")
        result["review_id"] = review_id
        if sdlc_pilot.contract(mission)["opportunity"] != sdlc_pilot.OPPORTUNITY:
            result["workflow_path"] = next(
                path for path in publication_files if path.startswith(".github/workflows/")
            )
        await receipt("review", {"number": number, "head": head, "review_id": review_id})
        return result


async def followup(receipt: dict) -> dict:
    """One bounded exact-head CI observation; caller schedules any polling."""
    head = _sha(receipt["head"])
    async with sdlc_pilot.client() as http:
        data = await _json(http, "GET", "/actions/runs", params={"head_sha": head, "per_page": 100})
    runs = data.get("workflow_runs", [])
    if not isinstance(runs, list) or data.get("total_count", 0) > 100:
        return {"status": "absent", "head": head, "coverage": "incomplete", "urls": []}
    matching = [
        r
        for r in runs
        if r.get("head_sha") == head
        and r.get("path") == receipt.get("workflow_path", WORKFLOW_PATH)
        and isinstance(r.get("id"), int)
        and r["id"] > 0
    ]
    if not matching:
        return {"status": "absent", "head": head, "urls": []}
    latest = max(matching, key=lambda r: (r["id"], r.get("run_attempt", 1)))
    status = (
        "pending"
        if latest.get("status") != "completed"
        else ("passed" if latest.get("conclusion") == "success" else "failed")
    )
    return {
        "status": status,
        "head": head,
        "urls": [f"https://github.com/X-McKay/algent/actions/runs/{latest['id']}"],
    }
