"""Bounded polling of changed feedback; advisory records never dispatch effects."""

import asyncio
import time

from . import sdlc_feedback, sdlc_pilot
from .operations import request


async def poll_feedback(parent: dict) -> dict | None:
    """At most one classification per new digest, 20s model / 25s total ceiling.

    Caller must limit parents per discovery tick. Model failure is retained as
    unknown evidence, preventing repeated calls for the same unchanged comments.
    Transport failures before a capture remain retryable on a later bounded poll.
    """
    if len(parent.get("feedback", [])) >= 16 or not parent.get("evidence", {}).get("submitted"):
        return None
    async with asyncio.timeout(25):
        captured = await sdlc_feedback.capture(parent)
        if any(record.get("digest") == captured["digest"] for record in parent.get("feedback", [])):
            return None
        capability = sdlc_pilot.contract(parent)
        if not captured["comments"]:
            result = {
                "role": "feedback",
                "model": None,
                "usage": None,
                "elapsed_ms": 0,
                "output": sdlc_feedback.classify(
                    captured,
                    {
                        "state": "no-change",
                        "rationale": "No comments were captured.",
                        "comment_ids": [],
                        "paths": [],
                        "task": "",
                    },
                    capability,
                ),
            }
        else:
            try:
                async with asyncio.timeout(20):
                    result = await sdlc_feedback.propose(captured, capability)
            except (TimeoutError, sdlc_pilot.MemberFailure, ValueError) as error:
                result = {
                    "role": "feedback",
                    "model": None,
                    "usage": None,
                    "error_type": type(error).__name__,
                    "failure": error.evidence
                    if isinstance(error, sdlc_pilot.MemberFailure)
                    else None,
                    "output": sdlc_feedback.classify(
                        captured,
                        {
                            "state": "unknown",
                            "rationale": "Classification unavailable; no action authorized.",
                            "comment_ids": [comment["id"] for comment in captured["comments"]],
                            "paths": [],
                            "task": "",
                        },
                        capability,
                    ),
                }
        return await request(
            "POST",
            f"/internal/v7/missions/{parent['id']}/feedback",
            {
                "head": captured["head"],
                "digest": captured["digest"],
                "captured": captured,
                "proposal": result,
                "observed_at": time.time(),
            },
        )
