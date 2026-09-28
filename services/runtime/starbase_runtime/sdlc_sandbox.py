"""Pinned, disposable Python 3.13 execution for the algent persistence pilot.

Only four validated source-text files cross the VM boundary. The observation
harness contains inputs, never expected results; Core owns comparison/grading.
"""

import asyncio
import json
import platform
import tempfile
import time
from pathlib import Path

from .sandbox import VERSION, command, environment, executable, remove

IMAGES = {
    "aarch64": "python@sha256:40c7f36cc642a93b74e1de68f4c1b137db04b5fc2ca8eefe83846015bc129974",
    "x86_64": "python@sha256:f1a962d8ffa50b2006b72b4713a09a89e57def2d28ac28a36900bc070a00db61",
}


def image_for(machine: str) -> str:
    key = {"arm64": "aarch64", "amd64": "x86_64"}.get(machine, machine)
    if key not in IMAGES:
        raise RuntimeError(f"No qualified sandbox image for architecture {machine!r}")
    return IMAGES[key]


IMAGE = image_for(platform.machine())
POLICY: dict = {
    "runtime": "microsandbox",
    "version": VERSION,
    "image": IMAGE,
    "python": "3.13.5",
    "cpus": 1,
    "memory_mib": 256,
    "root_disk_mib": 256,
    "tmp_mib": 16,
    "command_seconds": 10,
    "lifetime_seconds": 30,
    "output_bytes": 32768,
    "network": "none",
    "user": "65534:65534",
    "host_mounts": [],
}
FILES = frozenset(
    {
        "src/__init__.py",
        "src/utils/__init__.py",
        "src/utils/logging.py",
        "src/utils/persistence.py",
    }
)
CASE_IDS = (
    "history_all",
    "history_last3",
    "history_last1",
    "history_zero",
    "history_empty",
    "history_context",
    "history_mixed",
)
PREFIX = "STARBASE_ALGENT_OBSERVATIONS_V1="
HARNESS = r"""
import json, os, sqlite3, sys, tempfile
from pathlib import Path
with tempfile.TemporaryDirectory(prefix="algent-") as work:
    os.chdir(work)
    for name, contents in SOURCE_FILES.items():
        path = Path(name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
    sys.path.insert(0, work)
    from src.utils.persistence import SimplePersistence
    store = SimplePersistence("history.sqlite")
    for index in range(5):
        store.add_conversation_history("agent", "ties", {"index": index})
    store.add_conversation_history("agent", "other", {"index": 9})
    for index in range(5):
        store.add_conversation_history("agent", "mixed", {"index": index})
    with sqlite3.connect(store.db_path) as connection:
        connection.execute(
            "UPDATE conversation_history SET timestamp = ?", ("2026-01-01 00:00:00",)
        )
        for index in range(5):
            connection.execute(
                "UPDATE conversation_history SET timestamp = ? WHERE context_id = ? "
                "AND json_extract(message, '$.index') = ?",
                ("2026-01-01 00:00:0" + str(index // 2), "mixed", index),
            )
    cases = []
    for case_id, context, limit in (
        ("history_all", "ties", 100), ("history_last3", "ties", 3),
        ("history_last1", "ties", 1), ("history_zero", "ties", 0),
        ("history_empty", "absent", 100), ("history_context", "other", 100),
        ("history_mixed", "mixed", 100),
    ):
        actual = [row["message"]["index"] for row in store.get_conversation_history(context, limit)]
        cases.append({"id": case_id, "actual": actual})
    print("STARBASE_ALGENT_OBSERVATIONS_V1=" + json.dumps({"cases": cases}, separators=(",", ":")))
"""


def program(files: dict[str, str]) -> str:
    if not isinstance(files, dict) or set(files) != FILES:
        raise ValueError("Exactly the four permitted source files are required")
    if any(not isinstance(value, str) or "\x00" in value for value in files.values()):
        raise ValueError("Source files must be text without NUL bytes")
    if sum(len(value.encode()) for value in files.values()) > 24000:
        raise ValueError("Source file budget exceeded")
    return "SOURCE_FILES = " + repr(files) + "\n" + HARNESS


def observations(stdout: str) -> list[dict]:
    lines = [line[len(PREFIX) :] for line in stdout.splitlines() if line.startswith(PREFIX)]
    if len(lines) != 1:
        raise ValueError("Missing or duplicate observation envelope")
    body = json.loads(lines[0])
    if not isinstance(body, dict) or set(body) != {"cases"}:
        raise ValueError("Invalid observation envelope")
    cases = body["cases"]
    if not isinstance(cases, list) or len(cases) != len(CASE_IDS):
        raise ValueError("Incomplete observations")
    for case, case_id in zip(cases, CASE_IDS, strict=True):
        if not isinstance(case, dict) or set(case) != {"id", "actual"} or case["id"] != case_id:
            raise ValueError("Invalid observation identity")
        if not isinstance(case["actual"], list) or len(case["actual"]) > 100:
            raise ValueError("Invalid observation values")
        if any(type(value) is not int for value in case["actual"]):
            raise ValueError("Invalid observation value type")
    return cases


async def run(name: str, files: dict[str, str]) -> dict:
    result = await _execute(name, program(files))
    result["cases"] = observations(result["stdout"]) if result["exit_code"] == 0 else []
    return result


async def _execute(name: str, source: str, *, seconds: int = 10) -> dict:
    """Execute a supplied Python program; callers must grade the returned bytes."""
    if len(source.encode()) > 64000 or not 1 <= seconds <= 10:
        raise ValueError("Sandbox input budget exceeded")
    started = time.monotonic()
    version = await command("--version")
    if version[0] or version[1].decode().strip().split()[-1].lstrip("v") != VERSION:
        raise RuntimeError("Unqualified microsandbox version")
    await remove(name)  # Reconcile an interrupted attempt before recreating its VM.
    with tempfile.TemporaryDirectory(prefix="starbase-input-") as directory:
        path = Path(directory) / "program.py"
        await asyncio.to_thread(path.write_text, source)
        p = await asyncio.create_subprocess_exec(
            executable(),
            "run",
            "--name",
            name,
            "--no-tty",
            "--pull",
            "never",
            "--net",
            "none",
            "--security",
            "restricted",
            "--user",
            POLICY["user"],
            "--cpus",
            "1",
            "--memory",
            "256M",
            "--root-disk",
            "256M",
            "--tmpfs",
            "/tmp:16M",
            "--timeout",
            f"{seconds}s",
            "--max-duration",
            "30s",
            "--rlimit",
            "nofile=64",
            "--rlimit",
            "nproc=32",
            "--rlimit",
            "fsize=8388608",
            "--rlimit",
            "as=134217728",
            "--copy-file",
            f"{path}:/program.py",
            "--workdir",
            "/tmp",
            IMAGE,
            "--",
            "python3",
            "-I",
            "-B",
            "/program.py",
            env=environment(),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        async def read(stream: asyncio.StreamReader | None) -> bytes:
            assert stream is not None
            data = bytearray()
            while chunk := await stream.read(4096):
                data.extend(chunk)
                if len(data) > POLICY["output_bytes"]:
                    raise ValueError("Sandbox output budget exceeded")
            return bytes(data)

        try:
            stdout, stderr, _ = await asyncio.wait_for(
                asyncio.gather(read(p.stdout), read(p.stderr), p.wait()), 40
            )
            result = {
                "exit_code": p.returncode,
                "stdout": stdout.decode(errors="replace"),
                "stderr": stderr.decode(errors="replace"),
                "policy": POLICY,
                "elapsed_ms": int((time.monotonic() - started) * 1000),
            }
        finally:
            if p.returncode is None:
                p.kill()
                await p.wait()
            # Cleanup errors must prevent a verified completion.
            await asyncio.shield(remove(name))
    return result
