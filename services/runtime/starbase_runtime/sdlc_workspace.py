"""Bounded repair tools over source text; execution belongs to an injected VM tester.

No host execution, provider access, grading or publication authority is available.
Digests use the same canonical JSON SHA256 function as other runtime artifacts.
"""

import ast
import asyncio
import copy
import difflib
import inspect
import json
import textwrap
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Any

from . import sdlc_activity
from .review import digest


@dataclass(frozen=True)
class Limits:
    calls: int = 40
    seconds: float = 180
    test_seconds: float = 45
    input_bytes: int = 48000
    output_bytes: int = 32768
    source_bytes: int = 24000
    no_progress: int = 8
    repeated_failures: int = 3


DEFAULT_LIMITS = Limits()


class WorkspaceExhausted(RuntimeError):
    """The bounded attempt must stop; another model turn cannot replenish it."""


class Workspace:
    def __init__(
        self,
        files: dict[str, str],
        capability: dict,
        tester: Callable[[dict[str, str]], Awaitable[dict]],
        guard: Callable[[], Awaitable[None] | None],
        *,
        limits: Limits = DEFAULT_LIMITS,
    ):
        if min(vars(limits).values()) <= 0:
            raise ValueError("Workspace limits must be positive")
        self._files = copy.deepcopy(files)
        self._original = copy.deepcopy(files)
        self._capability = copy.deepcopy(capability)
        self._path = capability["editable_paths"][0]
        self._symbol = capability["editable_symbol"]
        if len(capability["editable_paths"]) != 1 or self._path not in files:
            raise ValueError("Workspace requires one installed editable path")
        if sum(len(s.encode()) for s in files.values()) > limits.input_bytes:
            raise ValueError("Workspace input exceeds byte budget")
        self._node(files[self._path], self._symbol)
        self._tester, self._guard, self._limits = tester, guard, limits
        self._started = time.monotonic()
        self._calls = self._idle = 0
        self._failures: dict[str, int] = {}
        self._receipts: list[dict] = []
        self._cache: dict[str, dict] = {}
        self._seen = {self.candidate_digest}
        self._lock = asyncio.Lock()
        self._test_execution: dict | None = None

    @property
    def candidate_digest(self) -> str:
        return digest(self._files)

    @property
    def source_digest(self) -> str:
        return digest(self._files[self._path])

    @property
    def receipts(self) -> tuple[dict, ...]:
        return tuple(copy.deepcopy(self._receipts))

    def snapshot(self) -> dict[str, str]:
        return copy.deepcopy(self._files)

    def finish(self, candidate_digest: str) -> dict[str, str]:
        """Final local evidence gate; Core must still independently grade the artifact."""
        if candidate_digest != self.candidate_digest:
            raise ValueError("Submission digest is stale")
        if self._files == self._original:
            raise ValueError("Submission has no source change")
        tested = self._cache.get(candidate_digest)
        if not tested or tested.get("passed") is not True:
            raise ValueError("Submission requires passing public tests for its exact digest")
        if not any(
            r.get("ok")
            and r["tool"] == "inspect_diff"
            and r["candidate_digest"] == candidate_digest
            for r in self._receipts
        ):
            raise ValueError("Submission requires inspection of its exact diff")
        return self.snapshot()

    @staticmethod
    def _node(source: str, symbol: str) -> ast.FunctionDef:
        nodes = [
            n
            for n in ast.walk(ast.parse(source))
            if isinstance(n, ast.FunctionDef) and n.name == symbol
        ]
        if len(nodes) != 1:
            raise ValueError("Symbol is absent or ambiguous")
        return nodes[0]

    @staticmethod
    def _parts(source: str, node: ast.FunctionDef) -> tuple[str, str, str]:
        lines = source.splitlines(keepends=True)
        return (
            "".join(lines[: node.lineno - 1]),
            "".join(lines[node.lineno - 1 : node.end_lineno]),
            "".join(lines[node.end_lineno :]),
        )

    async def _authorize(self) -> None:
        try:
            result = self._guard()
            if inspect.isawaitable(result):
                await result
        except ValueError as exc:
            raise PermissionError("Workspace authority guard rejected dispatch") from exc

    async def _dispatch(self, name: str, args: dict, operation: Callable[[], Any]) -> dict:
        async with self._lock:
            self._test_execution = None
            before = self.candidate_digest
            prior_files = self.snapshot()
            started = time.monotonic()
            result: dict = {}
            sdlc_activity.note("tool_started", tool=name)
            try:
                remaining = self._limits.seconds - (started - self._started)
                if remaining <= 0:
                    raise WorkspaceExhausted("Workspace elapsed-time budget exhausted")
                async with asyncio.timeout(remaining):
                    await self._authorize()
                    if self._calls >= self._limits.calls or self._idle >= self._limits.no_progress:
                        raise WorkspaceExhausted("Workspace call or no-progress budget exhausted")
                    self._calls += 1
                    key = digest({"tool": name, "args": args, "candidate": before})
                    if self._failures.get(key, 0) >= self._limits.repeated_failures:
                        raise ValueError(
                            "Repeated failed operation stopped; inspect evidence or revise approach"
                        )
                    if len(json.dumps(args).encode()) > self._limits.input_bytes:
                        raise ValueError("Tool input exceeds byte budget")
                    try:
                        data = operation()
                        if inspect.isawaitable(data):
                            data = await data
                        await self._authorize()
                        if len(json.dumps(data).encode()) > self._limits.output_bytes:
                            raise ValueError("Tool output exceeds byte budget; narrow the request")
                        result = {"ok": True, **data}
                    except (ValueError, SyntaxError) as exc:
                        self._failures[key] = self._failures.get(key, 0) + 1
                        result = {"ok": False, "error": str(exc)}
                    self._idle = 0 if self.candidate_digest not in self._seen else self._idle + 1
                    self._seen.add(self.candidate_digest)
            except ValueError as exc:
                result = {"ok": False, "error": str(exc)}
            except BaseException as exc:
                result = {"ok": False, "error": type(exc).__name__}
                raise
            finally:
                if not result.get("ok"):
                    self._files = prior_files
                receipt = {
                    "sequence": len(self._receipts) + 1,
                    "tool": name,
                    "input_digest": digest(args),
                    "before_digest": before,
                    "candidate_digest": self.candidate_digest,
                    "source_digest": self.source_digest,
                    "elapsed_seconds": time.monotonic() - started,
                    **result,
                }
                if self._test_execution is not None:
                    receipt["execution"] = copy.deepcopy(self._test_execution)
                self._receipts.append(copy.deepcopy(receipt))
                # Only the outcome class leaves the worker; error text may quote source.
                sdlc_activity.note(
                    "tool_finished",
                    tool=name,
                    ok=bool(result.get("ok")),
                    error=None if result.get("ok") else "tool_error",
                    elapsed_ms=int(receipt["elapsed_seconds"] * 1000),
                )
            return copy.deepcopy(receipt)

    def _read_path(self, path: str) -> str:
        if path not in self._files:
            raise ValueError("Path is outside the captured source workspace")
        return self._files[path]

    async def inspect_symbol(self, path: str, symbol: str | None = None) -> dict:
        def read():
            source = self._read_path(path)
            node = self._node(source, symbol or self._symbol)
            return {
                "path": path,
                "source": self._parts(source, node)[1],
                "start_line": node.lineno,
                "end_line": node.end_lineno,
                "inspected_source_digest": digest(source),
            }

        return await self._dispatch("inspect_symbol", {"path": path, "symbol": symbol}, read)

    async def search_source(self, query: str, path: str | None = None) -> dict:
        def search():
            if not query or len(query) > 500:
                raise ValueError("Provide a nonempty literal search of at most 500 characters")
            paths = [path] if path is not None else list(self._files)
            matches = []
            for selected in paths:
                for line, value in enumerate(self._read_path(selected).splitlines(), 1):
                    if query in value:
                        matches.append({"path": selected, "line": line, "text": value[:1000]})
            return {"matches": matches[:50], "truncated": len(matches) > 50}

        return await self._dispatch("search_source", {"query": query, "path": path}, search)

    def _mutate(self, path: str, source_digest: str, old: str, new: str) -> dict:
        from . import sdlc_pilot as pilot

        if path != self._path:
            raise ValueError("Path is outside installed edit capability")
        if source_digest != self.source_digest:
            raise ValueError("Stale source digest; inspect the current symbol before editing")
        source = self._files[path]
        if not old or source.count(old) != 1:
            raise ValueError("Patch target is absent or ambiguous")
        candidate = source.replace(old, new, 1)
        if len(candidate.encode()) > self._limits.source_bytes:
            raise ValueError("Candidate exceeds source byte budget")
        try:
            before = self._parts(source, self._node(source, self._symbol))
            after = self._parts(candidate, self._node(candidate, self._symbol))
        except SyntaxError as exc:
            raise ValueError(
                f"Syntax error at line {exc.lineno}, column {exc.offset}: "
                f"{exc.msg}; workspace unchanged"
            ) from exc
        if (before[0], before[2]) != (after[0], after[2]):
            raise ValueError("Patch changed text outside the installed symbol")
        result = pilot.apply(
            self._files,
            pilot.Patch(
                rationale="Workspace edit",
                edits=[pilot.Edit.model_validate({"path": path, "old": old, "new": new})],
            ),
            self._capability,
        )
        self._files = result
        return {"changed": True, "path": path}

    async def apply_patch(self, path: str, source_digest: str, old: str, new: str) -> dict:
        """Replace one exact multiline occurrence; no guessed line numbers or fuzzy match."""
        return await self._dispatch(
            "apply_patch",
            {"path": path, "source_digest": source_digest, "old": old, "new": new},
            lambda: self._mutate(path, source_digest, old, new),
        )

    async def replace_symbol(self, path: str, source_digest: str, source: str) -> dict:
        def replace():
            original = self._read_path(path)
            node = self._node(original, self._symbol)
            old = self._parts(original, node)[1]
            indent = original.splitlines()[node.lineno - 1][: node.col_offset]
            new = textwrap.indent(textwrap.dedent(source).strip("\n"), indent)
            if old.endswith("\n"):
                new += "\n"
            return self._mutate(path, source_digest, old, new)

        return await self._dispatch(
            "replace_symbol",
            {"path": path, "source_digest": source_digest, "source": source},
            replace,
        )

    async def check_candidate(self) -> dict:
        def check():
            for source in self._files.values():
                ast.parse(source)
            return {
                "syntax": "valid",
                "scope": "installed symbol body only",
                "changed": self._files != self._original,
                "public_tests_cached": self.candidate_digest in self._cache,
            }

        return await self._dispatch("check_candidate", {}, check)

    async def inspect_diff(self) -> dict:
        def diff():
            return {
                "diff": "".join(
                    difflib.unified_diff(
                        self._original[self._path].splitlines(keepends=True),
                        self._files[self._path].splitlines(keepends=True),
                        fromfile=self._path,
                        tofile=self._path,
                    )
                )
            }

        return await self._dispatch("inspect_diff", {}, diff)

    async def run_public_tests(self) -> dict:
        async def run():
            key = self.candidate_digest
            if key in self._cache:
                return {"cached": True, "tested_digest": key, "public_results": self._cache[key]}
            self._test_execution = {"started": True, "cleanup_awaited": False}
            task = asyncio.ensure_future(self._tester(self.snapshot()))
            try:
                async with asyncio.timeout(self._limits.test_seconds):
                    while not task.done():
                        await asyncio.wait({task}, timeout=0.5)
                        await self._authorize()
                    results = await task
                await self._authorize()
            finally:
                if not task.done():
                    task.cancel()
                await asyncio.gather(task, return_exceptions=True)
                self._test_execution["cleanup_awaited"] = True
            if (
                not isinstance(results, dict)
                or len(json.dumps(results).encode()) > self._limits.output_bytes - 512
            ):
                raise ValueError("Public tester returned invalid or oversized results")
            self._cache[key] = copy.deepcopy(results)
            return {"cached": False, "tested_digest": key, "public_results": results}

        return await self._dispatch("run_public_tests", {}, run)
