"""Explicit owner-scoped, GET-only GitHub inventory and durable local enrollment."""

import asyncio
import json
import os
import re
import time
from pathlib import Path

import httpx

from .field_sources import get_json, headers
from .operations import request


def configuration() -> dict | None:
    source = os.environ.get("STARBASE_GITHUB_DISCOVERY_FILE")
    if not source:
        return None
    try:
        path = Path(source)
        if path.stat().st_size > 8192:
            raise ValueError()
        value = json.loads(path.read_text())
        if not isinstance(value, dict) or set(value) - {
            "owner",
            "token_file",
            "interval_seconds",
            "discovery_interval_seconds",
        }:
            raise ValueError()
        owner = value.get("owner")
        token = value.get("token_file")
        if not isinstance(owner, str) or not re.fullmatch(
            r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?", owner
        ):
            raise ValueError()
        if not isinstance(token, str) or not Path(token).is_absolute():
            raise ValueError()
        result = value | {
            "owner": owner.lower(),
            "interval_seconds": value.get("interval_seconds", 900),
            "discovery_interval_seconds": value.get("discovery_interval_seconds", 3600),
        }
        for key in ("interval_seconds", "discovery_interval_seconds"):
            if type(result[key]) is not int or not 300 <= result[key] <= 86400:
                raise ValueError()
        return result
    except (OSError, ValueError, TypeError):
        raise ValueError("Invalid GitHub discovery configuration") from None


async def inventory(config: dict, client: httpx.AsyncClient) -> list[str]:
    user = await get_json(client, "/user")
    if not isinstance(user, dict) or str(user.get("login", "")).lower() != config["owner"]:
        raise ValueError("authentication")
    names: set[str] = set()
    for page in range(1, 4):
        batch = await get_json(
            client,
            "/user/repos",
            {
                "affiliation": "owner",
                "visibility": "all",
                "per_page": 100,
                "page": page,
                "sort": "full_name",
                "direction": "asc",
            },
        )
        if not isinstance(batch, list) or len(batch) > 100:
            raise ValueError("incomplete")
        for item in batch:
            if not isinstance(item, dict) or not isinstance(item.get("owner"), dict):
                raise ValueError("incomplete")
            name = item.get("name")
            if (
                str(item["owner"].get("login", "")).lower() != config["owner"]
                or not isinstance(name, str)
                or not re.fullmatch(r"[A-Za-z0-9_.-]{1,100}", name)
                or name in {".", ".."}
            ):
                raise ValueError("incomplete")
            full_name = config["owner"] + "/" + name.lower()
            if str(item.get("full_name", "")).lower() != full_name or full_name in names:
                raise ValueError("incomplete")
            names.add(full_name)
            if len(names) > 256:
                raise ValueError("incomplete")
        if len(batch) < 100:
            return sorted(names)
    raise ValueError("incomplete")


async def reconcile_discovery() -> None:
    config = configuration()
    if config is None:
        return
    records = (await request("GET", "/v4/repository-discovery"))["discoveries"]
    now = time.time()
    previous = next((r for r in records if r["owner"] == config["owner"]), None)
    if previous is not None:
        interval = config["discovery_interval_seconds"] if previous["complete"] else 300
        if now - previous["observed_at"] < interval:
            return
    body = {
        "owner": config["owner"],
        "observed_at": now,
        "interval_seconds": config["interval_seconds"],
        "complete": False,
        "repositories": [],
        "error": "unavailable",
    }
    try:
        async with asyncio.timeout(90):
            auth = headers(config)
            if not auth:
                raise ValueError("authentication")
            async with httpx.AsyncClient(
                base_url="https://api.github.com",
                headers=auth
                | {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2026-03-10"},
                timeout=15,
                follow_redirects=False,
                trust_env=False,
            ) as client:
                names = await inventory(config, client)
            body.update(complete=True, repositories=names, error=None)
    except (OSError, ValueError, httpx.HTTPError, TimeoutError) as error:
        message = str(error)
        category = (
            "authentication"
            if message in {"authentication", "Provider returned HTTP 401"}
            else "rate_limited"
            if message in {"Provider returned HTTP 429", "Provider rate limited"}
            else "incomplete"
            if message == "incomplete"
            else "unavailable"
        )
        body.update(error=category)
    # A lost response is reconciled against this durable checkpoint on the next loop.
    await request("POST", "/internal/v4/repository-discovery", body)
