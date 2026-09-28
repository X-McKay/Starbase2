"""Owned, detached local GitHub monitor. No login startup or production deployment."""

import argparse
import fcntl
import json
import os
import secrets
import signal
import socket
import sqlite3
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / ".local/github-monitor"
STATE = LOCAL / "processes.json"
SCRIPT = Path(__file__).resolve()
RESTART_DELAYS = (2, 4, 8)
HEALTH_INTERVAL = 5
HEALTH_FAILURE_LIMIT = 3


def identity(pid: int) -> dict | None:
    """Record start time and command; a recycled PID alone never grants ownership."""
    result = subprocess.run(
        ["ps", "-p", str(pid), "-o", "lstart=", "-o", "command="],
        capture_output=True,
        text=True,
        check=False,
    )
    value = result.stdout.strip()
    return {"pid": pid, "identity": value} if result.returncode == 0 and value else None


def owned(record: dict) -> bool:
    pid = record.get("pid")
    return type(pid) is int and pid > 1 and identity(pid) == record


def read_state() -> dict:
    try:
        value = json.loads(STATE.read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def write_state(value: dict) -> None:
    temporary = STATE.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.chmod(0o600)
    temporary.replace(STATE)


def available(port: int) -> None:
    with socket.socket() as probe:
        # A stopped server can leave TIME_WAIT connections. Match the server's
        # restart behavior while still rejecting another listening socket.
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            probe.bind(("127.0.0.1", port))
            probe.listen(1)
        except OSError:
            raise RuntimeError(
                f"Port {port} is occupied; no existing process was stopped"
            ) from None


def environment(owner: str) -> dict:
    env = {k: v for k, v in os.environ.items() if k in {"PATH", "LANG", "TMPDIR", "HOME"}}
    paths = [str(ROOT / "services/runtime")]
    if os.environ.get("PYTHONPATH"):
        paths.append(os.environ["PYTHONPATH"])
    env.update(
        PYTHONPATH=os.pathsep.join(paths),
        STARBASE_PORT="8787",
        STARBASE_CORE="http://127.0.0.1:8787",
        STARBASE_TEMPORAL="127.0.0.1:7244",
        STARBASE_TEMPORAL_QUEUE="starbase2-github-monitor-v1",
        STARBASE_DB=str(ROOT / ".local/starbase.sqlite"),
        STARBASE_TOKEN_FILE=str(ROOT / ".local/runtime-token"),
        STARBASE_FIELD_TARGETS_FILE=str(LOCAL / "targets.json"),
        STARBASE_GITHUB_DISCOVERY_FILE=str(LOCAL / "discovery.json"),
        STARBASE_GITHUB_DISCOVERY_OWNER=owner,
        STARBASE_FIELD_ENABLED="true",
    )
    for feature in ("LEGACY", "REPAIRS", "JOINT", "LEARNING", "INFERENCE", "MEMORY"):
        env[f"STARBASE_{feature}_ENABLED"] = "false"
    if (LOCAL / "sdlc.json").is_file():
        env["STARBASE_SDLC_CONFIG_FILE"] = str(LOCAL / "sdlc.json")
        env["STARBASE_SDLC_ENABLED"] = "true"
        env["STARBASE_SDLC_REPOSITORY"] = "x-mckay/algent"
        env["STARBASE_INFERENCE_ENABLED"] = "true"
        verification = LOCAL / "verification.json"
        if verification.is_file():
            if verification.stat().st_size > 1024 or json.loads(verification.read_text()) != {
                "repository": "x-mckay/algent",
                "enabled": True,
            }:
                raise ValueError("Invalid local verification opt-in")
            env["STARBASE_SDLC_VERIFICATION_ENABLED"] = "true"
    return env


def validate() -> str:
    config = LOCAL / "discovery.json"
    try:
        if config.stat().st_size > 8192:
            raise ValueError()
        value = json.loads(config.read_text())
        owner = value["owner"]
        credential = Path(value["token_file"])
        if not isinstance(owner, str) or not owner or not credential.is_absolute():
            raise ValueError()
        for path in (credential, ROOT / ".local/runtime-token"):
            if not path.is_file() or path.stat().st_size == 0:
                raise ValueError()
    except (OSError, ValueError, KeyError, TypeError):
        raise RuntimeError(
            "Configure discovery.json and readable nonempty credential files first"
        ) from None
    for path in (
        ROOT / ".local/tools/temporal",
        ROOT / "target/debug/starbase-core",
        ROOT / ".venv/bin/python",
    ):
        if not path.is_file() or not os.access(path, os.X_OK):
            raise RuntimeError(f"Missing executable: {path.relative_to(ROOT)}")
    return owner.lower()


def backup() -> None:
    source = ROOT / ".local/starbase.sqlite"
    if source.exists():
        destination = LOCAL / f"core-before-start-{time.time_ns()}.sqlite"
        with (
            sqlite3.connect(f"file:{source}?mode=ro", uri=True) as src,
            sqlite3.connect(destination) as dst,
        ):
            src.backup(dst)
        destination.chmod(0o600)


def service_health() -> bool:
    """Transport readiness only; never certifies worker or provider success."""
    try:
        with socket.create_connection(("127.0.0.1", 7244), timeout=1):
            pass
        with urllib.request.urlopen("http://127.0.0.1:8787/v4/snapshot", timeout=1):
            return True
    except OSError:
        return False


def wait_for_restart(delay: float, closing) -> bool:
    deadline = time.monotonic() + delay
    while not closing():
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return True
        time.sleep(min(remaining, 0.2))
    return False


def supervise(nonce: str) -> None:
    LOCAL.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (LOCAL / "supervisor.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("A monitor supervisor already owns the local lock") from None
        owner = validate()
        for port in (8787, 7244):
            available(port)
        backup()
        (LOCAL / "targets.json").write_text("[]\n")
        env = environment(owner)
        children = []
        logs = []
        closing = False
        state: dict = {
            "nonce": nonce,
            "supervisor": identity(os.getpid()),
            "phase": "starting",
            "children": {},
        }

        def stop_requested(_signum, _frame):
            nonlocal closing
            closing = True

        for sig in (signal.SIGTERM, signal.SIGINT):
            signal.signal(sig, stop_requested)

        def start(name, command):
            if closing:
                raise RuntimeError("Monitor start cancelled")
            log = (LOCAL / f"{name}.log").open("a")
            logs.append(log)
            process = subprocess.Popen(
                command,
                cwd=ROOT,
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=log,
                stderr=log,
                start_new_session=True,
            )
            children.append(process)
            state["children"][name] = identity(process.pid)
            write_state(state)

        def stop_children():
            # Popen owns unreaped children; never use a saved PID to kill a
            # potentially unrelated process. Stop worker before its dependencies.
            for child in reversed(children):
                if child.poll() is None:
                    child.terminate()
                    try:
                        child.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait()
            children.clear()
            for log in logs:
                log.close()
            logs.clear()
            state["children"] = {}

        state["recovery"] = {"restarts": 0, "limit": len(RESTART_DELAYS), "events": []}
        try:
            while not closing:
                state["phase"] = "starting"
                state["health"] = {
                    "transport_ready": False, "consecutive_failures": 0,
                    "checked_at": time.time(),
                }
                write_state(state)
                try:
                    # Recheck after every backoff; an unrelated process may have
                    # taken a port. Occupancy never authorizes stopping it.
                    for port in (8787, 7244):
                        available(port)
                    start(
                        "temporal",
                        [
                            str(ROOT / ".local/tools/temporal"), "server", "start-dev",
                            "--ip", "127.0.0.1", "--port", "7244",
                            "--db-filename", str(LOCAL / "temporal.sqlite"),
                            "--headless", "--log-level", "error",
                        ],
                    )
                    start("core", [str(ROOT / "target/debug/starbase-core")])
                    deadline = time.monotonic() + 30
                    while not service_health():
                        if closing or any(child.poll() is not None for child in children):
                            raise RuntimeError("Monitor service stopped during startup")
                        if time.monotonic() >= deadline:
                            raise RuntimeError("Monitor startup timed out")
                        time.sleep(0.2)
                    start(
                        "worker",
                        [str(ROOT / ".venv/bin/python"), "-m", "starbase_runtime.worker", "worker"],
                    )
                    state["phase"] = "running"
                    state["health"]["transport_ready"] = True
                    state["health"]["checked_at"] = time.time()
                    write_state(state)
                    next_health = time.monotonic() + HEALTH_INTERVAL
                    while not closing:
                        if any(child.poll() is not None for child in children):
                            raise RuntimeError("Owned monitor child exited")
                        if time.monotonic() >= next_health:
                            ready = service_health()
                            health = state["health"]
                            health["transport_ready"] = ready
                            health["checked_at"] = time.time()
                            health["consecutive_failures"] = (
                                0 if ready else health["consecutive_failures"] + 1
                            )
                            write_state(state)
                            if health["consecutive_failures"] >= HEALTH_FAILURE_LIMIT:
                                raise RuntimeError(
                                    "Monitor transport health repeatedly unavailable"
                                )
                            next_health = time.monotonic() + HEALTH_INTERVAL
                        time.sleep(0.5)
                except (OSError, RuntimeError) as error:
                    state["recovery"]["events"].append({
                        "at": time.time(), "reason": str(error),
                    })
                finally:
                    stop_children()
                state["health"]["transport_ready"] = False
                if closing:
                    break
                attempt = state["recovery"]["restarts"]
                if attempt >= len(RESTART_DELAYS):
                    state["phase"] = "failed"
                    break
                state["phase"] = "recovering"
                state["recovery"]["next_delay_seconds"] = RESTART_DELAYS[attempt]
                write_state(state)
                if not wait_for_restart(RESTART_DELAYS[attempt], lambda: closing):
                    break
                state["recovery"]["restarts"] += 1
                state["recovery"].pop("next_delay_seconds", None)
            if closing:
                state["phase"] = "stopped"
        finally:
            stop_children()
            state["recovery"].pop("next_delay_seconds", None)
            if state["phase"] not in {"stopped", "failed"}:
                state["phase"] = "failed"
            write_state(state)


def start_monitor() -> None:
    LOCAL.mkdir(parents=True, exist_ok=True, mode=0o700)
    previous = read_state()
    if owned(previous.get("supervisor") or {}):
        raise RuntimeError("Monitor already running; use status or stop")
    validate()
    for port in (8787, 7244):
        available(port)
    nonce = secrets.token_hex(16)
    with (LOCAL / "supervisor.log").open("a") as log:
        process = subprocess.Popen(
            [sys.executable, str(SCRIPT), "_supervise", "--nonce", nonce],
            cwd=ROOT,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=log,
            start_new_session=True,
        )
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        state = read_state()
        if state.get("nonce") == nonce and state.get("phase") == "running":
            print(
                json.dumps({"started": True, "pid": process.pid, "core": "http://127.0.0.1:8787"})
            )
            return
        if process.poll() is not None:
            raise RuntimeError(
                "Monitor did not start; inspect .local/github-monitor/supervisor.log"
            )
        time.sleep(0.2)
    process.terminate()
    raise RuntimeError("Monitor readiness timed out; shutdown requested; inspect local logs")


def stop_monitor() -> None:
    state = read_state()
    record = state.get("supervisor") or {}
    command = record.get("identity", "")
    nonce = state.get("nonce", "")
    if not owned(record) or not nonce or f"{SCRIPT} _supervise --nonce {nonce}" not in command:
        raise RuntimeError("No verified owned supervisor; no process was signalled")
    os.kill(record["pid"], signal.SIGTERM)
    deadline = time.monotonic() + 50
    while owned(record) and time.monotonic() < deadline:
        time.sleep(0.2)
    if owned(record):
        raise RuntimeError(
            "Owned supervisor is still stopping; inspect logs; no unrelated process was stopped"
        )
    print(json.dumps({"stopped": True}))


def status() -> dict:
    state = read_state()
    result = {
        "phase": state.get("phase", "not_started"),
        "recovery": state.get("recovery", {}),
        "health": state.get("health", {}),
        "supervisor": {
            "pid": state.get("supervisor", {}).get("pid"),
            "alive": owned(state.get("supervisor") or {}),
        },
        "children": {
            name: {"pid": (record or {}).get("pid"), "alive": owned(record or {})}
            for name, record in state.get("children", {}).items()
        },
    }
    if not result["supervisor"]["alive"] or not result["children"].get("core", {}).get(
        "alive", False
    ):
        result["read_error"] = "Owned monitor Core is not running; no other Core was queried"
        return result
    try:
        with urllib.request.urlopen("http://127.0.0.1:8787/v4/snapshot", timeout=3) as response:
            data = json.load(response)
        watches = data.get("repositories", [])
        result["fleet"] = {
            "watches": len(watches),
            "enabled": sum(
                bool(w.get("config", {}).get("enabled"))
                and not w.get("config", {}).get("removed", False)
                for w in watches
            ),
            "runs_in_snapshot": len(data.get("runs", [])),
            "observed_at": data.get("observed_at"),
        }
    except (OSError, ValueError, TypeError):
        result["read_error"] = "Owned Core snapshot unavailable"
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("start", "status", "stop", "_supervise"))
    parser.add_argument("--nonce", default="")
    args = parser.parse_args()
    try:
        if args.action == "start":
            start_monitor()
        elif args.action == "stop":
            stop_monitor()
        elif args.action == "status":
            print(json.dumps(status(), indent=2))
        elif args.nonce:
            supervise(args.nonce)
        else:
            parser.error("Supervisor requires a nonce")
    except (RuntimeError, OSError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
