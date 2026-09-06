"""Small local process launcher; product durability belongs to Temporal and the core."""

import os
import secrets
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    os.chdir(ROOT)
    local = ROOT / ".local"
    local.mkdir(exist_ok=True)
    env = {key: value for key, value in os.environ.items() if key in {"PATH", "LANG", "TMPDIR"}}
    env["PYTHONPATH"] = str(ROOT / "services/runtime")
    token_file = local / "runtime-token"
    if not token_file.exists():
        token_file.write_text(secrets.token_hex(32))
    token_file.chmod(0o600)
    env["STARBASE_TOKEN_FILE"] = str(token_file)
    for key in (
        "STARBASE_INFERENCE_URL",
        "STARBASE_MODEL",
        "STARBASE_FIELD_TARGETS_FILE",
        "STARBASE_FIELD_ENABLED",
        "STARBASE_MEMORY_ENABLED",
        "STARBASE_FALKOR_HOST",
        "STARBASE_FALKOR_PORT",
        "STARBASE_FALKOR_USERNAME",
        "STARBASE_FALKOR_PASSWORD_FILE",
        "STARBASE_INSTALLATION",
    ):
        if key in os.environ:
            env[key] = os.environ[key]
    processes = []
    logs = []

    def start(name, args):
        log = (local / f"{name}.log").open("a")
        logs.append(log)
        process = subprocess.Popen(args, env=env, stdout=log, stderr=log, start_new_session=True)
        processes.append(process)
        return process

    try:
        start(
            "temporal",
            [
                str(local / "tools/temporal"),
                "server",
                "start-dev",
                "--ip",
                "127.0.0.1",
                "--db-filename",
                str(local / "temporal.sqlite"),
                "--headless",
                "--log-level",
                "error",
            ],
        )
        start("core", [str(ROOT / "target/debug/starbase-core")])
        deadline = time.monotonic() + 20
        while True:
            if any(p.poll() is not None for p in processes):
                raise RuntimeError("Local service exited; inspect .local/core.log and temporal.log")
            try:
                with urllib.request.urlopen("http://127.0.0.1:8787/v1/snapshot", timeout=1):
                    with socket.create_connection(("127.0.0.1", 7233), timeout=1):
                        break
            except (urllib.error.URLError, OSError):
                if time.monotonic() > deadline:
                    raise RuntimeError("Core did not become ready") from None
                time.sleep(0.2)
        start("worker", [str(ROOT / ".venv/bin/python"), "-m", "starbase_runtime.worker", "worker"])
        print(
            "Journal: http://127.0.0.1:8787\nQueue a review or evaluation in the journal. "
            "Run just world for the 3D view. "
            "Ctrl-C stops local processes; data stays in .local/.",
            flush=True,
        )
        while all(p.poll() is None for p in processes):
            time.sleep(0.5)
        raise RuntimeError("Local process exited; inspect .local/*.log")
    except KeyboardInterrupt:
        pass
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
        for log in logs:
            log.close()


if __name__ == "__main__":
    main()
