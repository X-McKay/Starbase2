"""Best-effort transient activity notes for Core's live stream (`/v8/events`).

Notes tell an observer that a model request, tool call or sandbox run started or
finished inside a long stage. They are not evidence: Core broadcasts them without
storing them in the mission record. Posting never blocks, slows or fails the
calling activity: each note is a detached task with a short timeout, failures are
logged and dropped, and excess notes are dropped while too many are in flight.
"""

import asyncio
import contextvars
import logging
import os
from contextlib import contextmanager
from pathlib import Path

import httpx

TIMEOUT_SECONDS = 1.0
MAX_IN_FLIGHT = 16
KINDS = {
    "model_request_started",
    "model_request_finished",
    "tool_started",
    "tool_finished",
    "sandbox_boot",
    "sandbox_finished",
}

_mission: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "sdlc_activity_mission", default=None
)
_verification: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "sdlc_activity_verification", default=None
)
_role: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "sdlc_activity_role", default=None
)
_pending: set[asyncio.Task] = set()
_log = logging.getLogger(__name__)


def credential() -> str:
    path = os.environ.get("STARBASE_TOKEN_FILE")
    return Path(path).read_text().strip() if path else ""


def bind(mission_id: str, verification_id: str | None = None) -> None:
    """Attribute later notes in this activity task to one V7 mission."""
    _mission.set(mission_id)
    _verification.set(verification_id)


@contextmanager
def role(name: str):
    token = _role.set(name)
    try:
        yield
    finally:
        _role.reset(token)


def note(kind: str, **fields) -> None:
    """Schedule one note; returns immediately and never raises."""
    try:
        mission = _mission.get()
        token = credential()
        if mission is None or not token or kind not in KINDS:
            return
        if len(_pending) >= MAX_IN_FLIGHT:
            return
        body = {"kind": kind, **{k: v for k, v in fields.items() if v is not None}}
        if _role.get() and "role" not in body:
            body["role"] = _role.get()
        if _verification.get():
            body["verification_id"] = _verification.get()
        task = asyncio.get_running_loop().create_task(_post(mission, token, body))
        _pending.add(task)
        task.add_done_callback(_pending.discard)
    except Exception as error:  # noqa: BLE001 - observation must never break work
        _log.debug("Activity note skipped (%s)", type(error).__name__)


async def _post(mission: str, token: str, body: dict) -> None:
    url = os.environ.get("STARBASE_CORE", "http://127.0.0.1:8787")
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT_SECONDS, trust_env=False) as client:
            response = await client.post(
                f"{url}/internal/v7/missions/{mission}/activity",
                json=body,
                headers={"Authorization": "Bearer " + token},
            )
            if response.status_code != 200:
                _log.info("Activity note not accepted (HTTP %s)", response.status_code)
    except Exception as error:  # noqa: BLE001 - best effort by design
        _log.info("Activity note unavailable (%s)", type(error).__name__)


async def drain(seconds: float = TIMEOUT_SECONDS + 0.5) -> None:
    """Test/shutdown helper: wait briefly for in-flight notes; never raises."""
    if _pending:
        await asyncio.wait(set(_pending), timeout=seconds)
