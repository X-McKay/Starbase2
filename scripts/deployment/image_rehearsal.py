"""Run the deployment recovery rehearsal using exact local Linux release images.

Only creates/removes uniquely named disposable Podman resources. No registry push,
Kubernetes client, production credentials, or existing containers are used.
"""

import argparse
import hashlib
import json
import re
import subprocess
import time
import uuid
from pathlib import Path

from . import rehearse
from .local_db import DIGESTS
from .render import ROOT


def verify_image(info: dict, architecture: str, revision: str | None = None) -> None:
    if info["Os"] != "linux" or info["Architecture"] != architecture:
        raise ValueError("Image does not match the requested Linux architecture")
    if (
        revision
        and info["Config"].get("Labels", {}).get("org.opencontainers.image.revision") != revision
    ):
        raise ValueError("Image source revision differs from qualification inputs")


class ImageRuntime:
    def __init__(self, inputs: Path, output: Path):
        self.data = json.loads(inputs.read_text())
        if set(self.data) != {"platform", "revision", "core", "runtime", "temporal"}:
            raise ValueError("Expected platform, revision, core, runtime and temporal inputs")
        if self.data["platform"] not in {"linux/arm64", "linux/amd64"}:
            raise ValueError("Unsupported Linux platform")
        if not re.fullmatch(r"[a-f0-9]{40}", self.data["revision"]):
            raise ValueError("Committed source revision required")
        for key in ("core", "runtime"):
            if not re.fullmatch(r"sha256:[a-f0-9]{64}", self.data[key]):
                raise ValueError("Core/runtime must use exact local image IDs, never movable tags")
        if not re.fullmatch(r"[a-zA-Z0-9./:_-]+@sha256:[a-f0-9]{64}", self.data["temporal"]):
            raise ValueError("Temporal must use a pinned registry digest")
        self.output = output.resolve()
        self.output.mkdir(mode=0o700, parents=True, exist_ok=False)
        self.engine = "podman"
        self.name = "starbase2-image-" + uuid.uuid4().hex[:12]
        self.database = self.name + "-postgres"
        self.created = False
        self.secrets: dict[str, str] = {}
        self.children: dict[int, str] = {}
        self.kinds: dict[int, str] = {}
        self.stops: list[dict] = []
        self.counter = 0
        self.images = {}
        self.provenance = {
            "inputs_sha256": hashlib.sha256(inputs.read_bytes()).hexdigest(),
            "harness_sources": {
                str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sorted((ROOT / "scripts/deployment").glob("*.py"))
            },
        }

    def call(self, *args, **kwargs):
        return subprocess.run(
            [self.engine, *args], check=True, capture_output=True, timeout=90, **kwargs
        )

    def prepare(self):
        arch = self.data["platform"].split("/")[1]
        self.data["postgres"] = "docker.io/library/postgres@sha256:" + DIGESTS[arch]
        for key in ("core", "runtime", "postgres", "temporal"):
            info = json.loads(self.call("image", "inspect", self.data[key]).stdout)[0]
            verify_image(info, arch, self.data["revision"] if key in {"core", "runtime"} else None)
            self.images[key] = {
                "id": info["Id"],
                "reference": self.data[key],
                "architecture": arch,
                "revision": info["Config"]
                .get("Labels", {})
                .get("org.opencontainers.image.revision"),
            }
        self.call(
            "pod",
            "create",
            "--name",
            self.name,
            "--publish",
            "127.0.0.1:18887:18887",
            "--publish",
            "127.0.0.1:17239:7233",
        )
        self.created = True
        # Podman port publishing targets the pod interface, whereas Core deliberately
        # binds loopback. This test-only relay models kubectl's loopback port-forward.
        relay = """
import select, socket, socketserver
class Forward(socketserver.BaseRequestHandler):
    def handle(self):
        with socket.create_connection(('127.0.0.1', 8787), timeout=10) as upstream:
            sockets = [self.request, upstream]
            while True:
                ready, _, _ = select.select(sockets, [], [], 30)
                if not ready:
                    return
                for source in ready:
                    data = source.recv(65536)
                    if not data:
                        return
                    sockets[1 - sockets.index(source)].sendall(data)
socketserver.ThreadingTCPServer(('0.0.0.0', 18887), Forward).serve_forever()
"""
        self.call(
            "run",
            "--detach",
            "--pod",
            self.name,
            "--name",
            self.name + "-relay",
            "--user",
            "10001:10001",
            "--read-only",
            "--cap-drop=ALL",
            "--security-opt=no-new-privileges",
            "--entrypoint",
            "/app/.venv/bin/python",
            self.data["runtime"],
            "-c",
            relay,
        )
        self.call(
            "run",
            "--detach",
            "--pod",
            self.name,
            "--name",
            self.database,
            "--env",
            "POSTGRES_HOST_AUTH_METHOD=trust",
            "--tmpfs",
            "/var/lib/postgresql",
            self.data["postgres"],
        )
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            result = subprocess.run(
                [self.engine, "exec", self.database, "pg_isready"], capture_output=True, timeout=5
            )
            if result.returncode == 0:
                return
            time.sleep(0.2)
        raise RuntimeError("Disposable PostgreSQL was not ready")

    def secret(self, value: str) -> str:
        digest = hashlib.sha256(value.encode()).hexdigest()
        if digest not in self.secrets:
            name = self.name + "-" + str(len(self.secrets))
            self.call("secret", "create", name, "-", input=value.encode())
            self.secrets[digest] = name
        return self.secrets[digest]

    def command(self, args: list[str], env: dict) -> tuple[list[str], str]:
        self.counter += 1
        name = f"{self.name}-{self.counter}"
        temporal = Path(args[0]).name == "temporal"
        runtime = "starbase_runtime.worker" in args
        kind = "temporal" if temporal else "runtime" if runtime else "core"
        command = [self.engine, "run", "--rm", "--pod", self.name, "--name", name]
        if temporal:
            return command + [
                self.data[kind],
                "server",
                "start-dev",
                "--ip",
                "0.0.0.0",
                "--port",
                "7233",
                "--headless",
                "--log-level",
                "error",
            ], name
        command += [
            "--user",
            "10001:10001",
            "--read-only",
            "--cap-drop=ALL",
            "--security-opt=no-new-privileges",
            "--tmpfs",
            "/tmp:rw,size=256m,mode=1777",
        ]
        allowed = {
            "STARBASE_ENV",
            "STARBASE_INSTALLATION",
            "STARBASE_TOKEN_FILE",
            "STARBASE_DATABASE_URL_FILE",
            "STARBASE_TEMPORAL_NAMESPACE",
            "STARBASE_TEMPORAL_QUEUE",
            "STARBASE_REPAIRS_ENABLED",
            "STARBASE_LEGACY_ENABLED",
            "STARBASE_FIELD_ENABLED",
            "STARBASE_MEMORY_ENABLED",
            "STARBASE_INFERENCE_ENABLED",
            "STARBASE_ACCEPT_WORK",
        }
        values = {k: v for k, v in env.items() if k in allowed}
        # Model the production localhost pod, with private host ports only for the test driver.
        values.update(
            STARBASE_PORT="8787",
            STARBASE_CORE="http://127.0.0.1:8787",
            STARBASE_TEMPORAL="127.0.0.1:7233",
            STARBASE_WORKSPACE="/app",
        )
        for key in ("STARBASE_TOKEN_FILE", "STARBASE_DATABASE_URL_FILE"):
            if runtime and key == "STARBASE_DATABASE_URL_FILE":
                values.pop(key, None)
                continue
            if key in values:
                content = Path(values[key]).read_text().replace(":55439/", ":5432/")
                secret = self.secret(content)
                target = "/run/secrets/" + key.lower()
                command += ["--secret", f"{secret},target={target},uid=10001,gid=10001,mode=0400"]
                values[key] = target
        env_path = self.output / (name + ".env")
        env_path.write_text("".join(f"{k}={v}\n" for k, v in sorted(values.items())))
        env_path.chmod(0o600)
        command += ["--env-file", str(env_path), self.data[kind]]
        if not runtime:
            command += args[1:]
        return command, name

    def run(self, args, env, **kwargs):
        command, _ = self.command(args, env)
        return subprocess.run(command, **kwargs)

    def start(self, args, env, log):
        command, name = self.command(args, env)
        child = subprocess.Popen(command, stdout=log, stderr=log, start_new_session=True)
        self.children[child.pid] = name
        self.kinds[child.pid] = (
            "temporal"
            if Path(args[0]).name == "temporal"
            else "runtime"
            if "starbase_runtime.worker" in args
            else "core"
        )
        return child

    def stop(self, child):
        was_running = child.poll() is None
        started = time.monotonic()
        if child.poll() is None:
            self.call("stop", "--time", "10", self.children[child.pid])
        result = child.wait(timeout=20)
        if was_running:
            self.stops.append(
                {
                    "kind": self.kinds[child.pid],
                    "exit_code": result,
                    "seconds": round(time.monotonic() - started, 3),
                }
            )
            if self.kinds[child.pid] != "temporal" and result != 0:
                raise RuntimeError("Application container did not stop gracefully")

    def health(self, core, worker):
        self.call("exec", self.children[core.pid], "starbase-core", "--healthcheck")
        self.call(
            "exec",
            self.children[worker.pid],
            "/app/.venv/bin/python",
            "-m",
            "starbase_runtime.health",
        )
        for child in (core, worker):
            info = json.loads(self.call("inspect", self.children[child.pid]).stdout)[0]
            assert info["Config"]["User"] == "10001:10001"
            assert info["HostConfig"]["ReadonlyRootfs"]
        self.call(
            "exec",
            self.children[worker.pid],
            "/app/.venv/bin/python",
            "-c",
            "import os; assert 'STARBASE_DATABASE_URL_FILE' not in os.environ; "
            "assert os.getuid() == 10001; "
            "assert not os.path.exists('/run/secrets/starbase_database_url_file')",
        )

    def replay(self, worker, run_ids):
        code = """
import asyncio, sys
from starbase_runtime.connection import connect
from starbase_runtime.operations_workflows import RepositoryReview
from temporalio.worker import Replayer
async def main():
    client = await connect()
    for run_id in sys.argv[1:]:
        handle = client.get_workflow_handle('starbase2-review-' + run_id)
        await handle.result()
        history = await handle.fetch_history()
        await Replayer(workflows=[RepositoryReview]).replay_workflow(history)
asyncio.run(main())
"""
        self.call("exec", self.children[worker.pid], "/app/.venv/bin/python", "-c", code, *run_ids)

    def close(self):
        if self.created:
            self.call("pod", "rm", "--force", self.name)
        for name in self.secrets.values():
            self.call("secret", "rm", name)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("inputs", type=Path)
    p.add_argument("output", type=Path, help="New private output directory; never overwritten")
    args = p.parse_args()
    driver = ImageRuntime(args.inputs, args.output)
    try:
        driver.prepare()
        rehearse.main(driver)
    except Exception as error:
        path = driver.output / "report.json"
        report = json.loads(path.read_text()) if path.exists() else {}
        report.update(
            status="failed",
            error=type(error).__name__,
            images=driver.images,
            provenance=driver.provenance,
            container_stops=driver.stops,
        )
        path.write_text(json.dumps(report, indent=2) + "\n")
        raise
    finally:
        path = driver.output / "report.json"
        try:
            driver.close()
        except Exception:
            report = json.loads(path.read_text()) if path.exists() else {}
            report.update(status="failed", cleanup="failed")
            path.write_text(json.dumps(report, indent=2) + "\n")
            raise
        if path.exists():
            report = json.loads(path.read_text())
            report["cleanup"] = "owned pod and secrets removed"
            path.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
