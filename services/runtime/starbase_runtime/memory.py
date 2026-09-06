"""Reviewed, scoped episodic memory using Graphiti on FalkorDB.

The core ledger is canonical. Graph data is a rebuildable projection, not authority.
No transcript extraction, model calls, embeddings or automatic belief acceptance.
"""

import asyncio
import json
import os
from datetime import UTC, datetime
from pathlib import Path
from uuid import NAMESPACE_URL, uuid5

from graphiti_core.driver.falkordb_driver import FalkorDriver
from graphiti_core.errors import NodeNotFoundError
from graphiti_core.nodes import EpisodeType, EpisodicNode

from .review import digest

POLICY: dict = {
    "version": 1,
    "acceptance": "operator-reviewed",
    "scope": "installation-agent-and-target",
    "limit": 30,
    "comparison": "frozen-revisions",
    "rollback": "revoke-and-reapprove",
    "graphiti": "0.30.1",
    "extraction": "structured-episodes-no-llm",
}


def scope(agent: str, target: str) -> str:
    return (
        "starbase2_"
        + digest([os.environ.get("STARBASE_INSTALLATION", "development"), agent, target])[:32]
    )


def episode(memory: dict) -> EpisodicNode:
    return EpisodicNode(
        uuid=str(uuid5(NAMESPACE_URL, f"starbase2/{memory['id']}/{memory['revision']}")),
        name=memory["finding"]["code"],
        group_id=scope(memory["agent"], memory["target"]),
        source=EpisodeType.json,
        source_description="Reviewed field observation /v4/runs/" + memory["source_run"],
        content=json.dumps(memory, sort_keys=True, separators=(",", ":")),
        created_at=datetime.fromtimestamp(memory["observed_at"], UTC),
        valid_at=datetime.fromtimestamp(memory["observed_at"], UTC),
    )


def driver(agent: str, target: str) -> FalkorDriver:
    secret = os.environ.get("STARBASE_FALKOR_PASSWORD_FILE")
    return FalkorDriver(
        host=os.environ.get("STARBASE_FALKOR_HOST", "127.0.0.1"),
        port=int(os.environ.get("STARBASE_FALKOR_PORT", "6379")),
        username=os.environ.get("STARBASE_FALKOR_USERNAME"),
        password=Path(secret).read_text().strip() if secret else None,
        database=scope(agent, target),
    )


async def recall(agent: str, target: str, memories: list[dict], graph=None) -> dict:
    if not memories:
        return {"status": "empty", "records": [], "policy": POLICY}
    if os.environ.get("STARBASE_MEMORY_ENABLED") != "true" and graph is None:
        return {"status": "disabled", "records": [], "policy": POLICY}
    if len(memories) > POLICY["limit"] or any(
        m["agent"] != agent or m["target"] != target or m["decision"] != "approve" for m in memories
    ):
        raise ValueError("Memory scope or approval violation")
    owned = graph is None
    graph = graph or driver(agent, target)
    try:
        async with asyncio.timeout(15):
            result = []
            for memory in memories:
                expected = episode(memory)
                try:
                    stored = await EpisodicNode.get_by_uuid(graph, expected.uuid)
                except NodeNotFoundError:
                    await expected.save(graph)
                    stored = await EpisodicNode.get_by_uuid(graph, expected.uuid)
                if stored.group_id != expected.group_id or stored.content != expected.content:
                    raise ValueError("Memory provenance mismatch")
                result.append(json.loads(stored.content))
            return {"status": "available", "records": result, "policy": POLICY}
    finally:
        if owned:
            await graph.close()
