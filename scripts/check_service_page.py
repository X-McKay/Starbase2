"""Exercise the native session bootstrap against an isolated real Core process."""

import os
import socket
import subprocess
import tempfile
import time
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="starbase2-service-page-") as directory:
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        env = {key: value for key, value in os.environ.items() if key in {"PATH", "TMPDIR"}}
        env.update(STARBASE_PORT=str(port), STARBASE_DB=f"{directory}/core.sqlite")
        with Path(directory, "core.log").open("w+") as log:
            core = subprocess.Popen(
                [str(ROOT / "target/debug/starbase-core")], env=env, stdout=log, stderr=log
            )
            try:
                with httpx.Client(base_url=f"http://127.0.0.1:{port}", trust_env=False) as http:
                    for _ in range(100):
                        try:
                            ready = http.get("/v2/snapshot")
                            ready.raise_for_status()
                            break
                        except httpx.ConnectError:
                            time.sleep(0.05)
                    else:
                        raise AssertionError("Isolated Core did not start")
                    assert http.post("/v2/runs/absent/cancel", json={}).status_code == 403
                    page = http.get("/")
                    assert page.status_code == 200
                    assert "starbase_session=" in page.headers["set-cookie"]
                    assert "HttpOnly; SameSite=Strict; Path=/" in page.headers["set-cookie"]
                    assert "Godot" in page.text
                    assert "<script" not in page.text and "<form" not in page.text
                    for path in ("/console.js", "/console.css", "/field.js"):
                        assert http.get(path).status_code == 404, path
                    # Valid session reaches the existing handler, which rejects an absent run.
                    assert http.post("/v2/runs/absent/cancel", json={}).status_code == 409
                    assert (
                        http.post(
                            "/v2/runs/absent/cancel",
                            json={},
                            headers={"Origin": "https://other.invalid"},
                        ).status_code
                        == 403
                    )
                    for path in ("/v2/snapshot", "/v4/snapshot", "/v3/repairs"):
                        assert http.get(path).status_code == 200, path
                print("PASS: service page, native session, API reads and mutation boundary")
            finally:
                core.terminate()
                core.wait(timeout=10)


if __name__ == "__main__":
    main()
