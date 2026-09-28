"""Declarative lab mission: model data never becomes code or cluster credentials."""

import asyncio
import copy
import hashlib
import json
import platform
import threading
import time
from collections.abc import Callable
from pathlib import Path
from typing import Protocol

from pydantic_ai import Agent
from pydantic_ai.messages import (
    ModelMessage,
    ModelRequest,
    ModelResponse,
    ToolCallPart,
    ToolReturnPart,
)
from pydantic_ai.models import Model
from pydantic_ai.models.function import AgentInfo, FunctionModel
from pydantic_ai.usage import UsageLimits

from .agents.readiness.definition import (
    MODEL_SETTINGS,
    POLICY,
    PROVIDER_PROFILE,
    instructions,
    load_definition,
    procedure,
)
from .agents.readiness.factory import make_agent as assemble_agent
from .agents.readiness.factory import make_qwen_model as make_qwen_model
from .agents.readiness.models import Decision, View

ROOT = Path(__file__).resolve().parents[3]


def digest(value: object) -> str:
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


class LabPort(Protocol):
    async def observe(self, view: View) -> dict: ...
    async def apply(self, proposal: Decision) -> dict: ...
    async def verify(self, action: str) -> dict: ...


class FenceError(RuntimeError):
    pass


class MissionSession:
    """Trusted one-shot dispatch journal. No resume/retry of uncertain effects."""

    def __init__(self, port: LabPort, path: Path, build: dict):
        if path.exists():
            raise ValueError("Existing mission journal cannot be reused")
        self.port, self.path = port, path
        self.clock: Callable[[], float] = time.monotonic
        self.started = self.clock()
        self.deadline = self.started + POLICY["mission_seconds"]
        self.cancelled = threading.Event()
        self.cancel_paths = [path.parent / "CANCEL"]
        self.receipts: dict[str, dict] = {}
        self.finalize_lock = asyncio.Lock()
        self.record: dict = {
            "version": POLICY["version"],
            "build": copy.deepcopy(build),
            "policy": POLICY,
            "state": "investigating",
            "effect": "not-started",
            "tools": [],
            "decision": None,
            "grade": None,
            "xp": 0,
            "interventions": [],
        }
        self.save()

    def save(self):
        self.record["elapsed_ms"] = round((self.clock() - self.started) * 1000)
        temporary = self.path.with_suffix(".tmp")
        temporary.write_text(json.dumps(self.record, indent=2) + "\n")
        temporary.replace(self.path)

    def guard(self):
        if self.cancelled.is_set() or any(path.exists() for path in self.cancel_paths):
            raise FenceError("cancelled")
        if self.clock() >= self.deadline:
            raise FenceError("budget-exceeded")

    async def observe(self, view: View) -> dict:
        self.guard()
        if self.record["state"] != "investigating":
            raise FenceError("mission-closed")
        if len(self.record["tools"]) >= POLICY["tool_calls"]:
            raise FenceError("tool-budget-exceeded")
        entry = {"view": view, "started_ms": round((self.clock() - self.started) * 1000)}
        self.record["tools"].append(entry)
        self.save()
        try:
            observation = await self.port.observe(view)
            self.guard()
            receipt_id = digest({"sequence": len(self.receipts), "observation": observation})
            payload = {
                "observation_id": receipt_id,
                "revision": observation["precondition"]["revision"],
                "fresh": observation["precondition"]["fresh"],
                **observation["data"],
            }
            if len(json.dumps(payload).encode()) > POLICY["tool_result_bytes"]:
                raise FenceError("observation-budget-exceeded")
            self.receipts[receipt_id] = {"at": self.clock(), **copy.deepcopy(observation)}
            entry["result"] = payload
            return payload
        except BaseException as error:
            entry["error"] = type(error).__name__
            raise
        finally:
            entry["finished_ms"] = round((self.clock() - self.started) * 1000)
            self.save()

    async def finish(self, decision: Decision):
        async with self.finalize_lock:
            await self._finish(decision)

    async def _finish(self, decision: Decision):
        # Finalization is idempotent even for failures and uncertain publication.
        if self.record["state"] != "investigating":
            return
        self.record["decision"] = decision.model_dump()
        try:
            self.guard()
            if decision.action == "abstain":
                self.record["state"] = "abstained"
                return
            receipt = self.receipts.get(decision.observation_id or "")
            if (
                not receipt
                or self.clock() - receipt["at"] > POLICY["evidence_seconds"]
                or not receipt["precondition"]["fresh"]
                or receipt["precondition"]["revision"] != decision.revision
            ):
                raise FenceError("ineligible")
            current = await self.port.observe("manifest")
            self.guard()
            if current["precondition"] != receipt["precondition"]:
                raise FenceError("ineligible")
            if decision.action == "repair":
                self.record["state"] = "applying"
                # Durable intent precedes the effect. A crash/timeout cannot cause replay.
                self.record["effect"] = "uncertain"
                self.save()
                self.guard()
                self.record["publication"] = await self.port.apply(decision)
                self.record["effect"] = "applied"
            self.guard()
            self.record["state"] = "verifying"
            self.save()
            self.record["grade"] = await self.port.verify(decision.action)
            self.guard()
            self.record["state"] = self.record["grade"]["verdict"]
        except FenceError as error:
            self.record["state"] = str(error)
        except asyncio.CancelledError:
            self.cancelled.set()
            self.record["state"] = "cancelled"
            raise
        except Exception as error:
            self.record["state"] = "invalid"
            self.record["error"] = type(error).__name__
        finally:
            self.save()


def make_agent(model: Model, variant: str = "baseline") -> Agent[MissionSession, Decision]:
    return assemble_agent(model, MissionSession, variant)


def scripted_model(action: str = "repair") -> FunctionModel:
    """Known positive tool-routing control. No inference or capability claim."""

    def respond(messages: list[ModelMessage], info: AgentInfo) -> ModelResponse:
        results = [
            p.content
            for m in messages
            if isinstance(m, ModelRequest)
            for p in m.parts
            if isinstance(p, ToolReturnPart)
        ]
        if not results:
            return ModelResponse(
                [
                    ToolCallPart(name, {})
                    for name in (
                        "inspect_workload",
                        "inspect_events",
                        "inspect_logs",
                        "check_useful_work",
                    )
                ]
            )
        last = results[-1]
        assert isinstance(last, dict)
        return ModelResponse(
            [
                ToolCallPart(
                    info.output_tools[0].name,
                    {
                        "action": action,
                        "observation_id": last["observation_id"],
                        "revision": last["revision"],
                        **(
                            {"readiness_path": "/ready", "liveness_path": "/live"}
                            if action == "repair"
                            else {}
                        ),
                        "rationale": "Authored positive routing control",
                    },
                )
            ],
            model_name="readiness-scripted-v1",
        )

    return FunctionModel(respond, model_name="readiness-scripted-v1")


def build_manifest(model: dict, variant: str = "baseline") -> dict:
    paths = [Path(__file__), ROOT / "uv.lock", ROOT / "pyproject.toml"]
    paths += sorted((ROOT / "scripts/readiness").glob("*.py"))
    paths += [Path(__file__).parent / "agents/__init__.py"]
    paths += [
        p
        for p in sorted((Path(__file__).parent / "agents/readiness").rglob("*"))
        if p.is_file() and p.suffix in {".py", ".json", ".md"}
    ]

    paths += [
        p
        for p in sorted((ROOT / "fixtures/readiness").rglob("*"))
        if p.is_file() and "__pycache__" not in p.parts
    ]
    manifest = {
        "profile": "readiness-crew-v2",
        "agent_definition": load_definition().model_dump(mode="json"),
        "model": model,
        "prompt": instructions(variant),
        "procedure": procedure(variant),
        "policy": POLICY,
        "model_settings": MODEL_SETTINGS,
        "provider_profile": PROVIDER_PROFILE,
        "output_schema": Decision.model_json_schema(),
        "python": platform.python_version(),
        "sources": {
            str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths
        },
    }
    return {"digest": digest(manifest), "manifest": manifest}


LIMITS = UsageLimits(
    request_limit=POLICY["model_requests"],
    total_tokens_limit=POLICY["total_tokens"],
    tool_calls_limit=POLICY["tool_calls"],
)
