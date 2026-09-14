"""Exercise real Core/session routes on the isolated Web fixture (no browser claims)."""

import argparse
import http.client
import json
import os
import re
import selectors
import signal
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    shell = output / "shell"
    shell.mkdir()
    (shell / "index.html").write_text("<!doctype html><title>Fixture routing check</title>")
    (shell / "index.wasm").write_bytes(b"\x00asm")
    (shell / "private.json").write_text('{"not":"a game asset"}')
    process = subprocess.Popen(
        [str(ROOT / "target/debug/examples/web_fixture"), str(shell)],
        env={k: v for k, v in os.environ.items() if k in {"PATH", "HOME", "TMPDIR"}},
        stdout=subprocess.PIPE,
        stderr=(output / "fixture-stderr.log").open("w"),
        text=True,
    )
    records = []
    try:
        assert process.stdout is not None
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            if not selector.select(timeout=15):
                raise RuntimeError("fixture did not start within 15 seconds")
        line = process.stdout.readline()
        (output / "fixture.log").write_text(line)
        match = re.search(r"http://127\.0\.0\.1:(\d+)/game/", line)
        assert match, line
        port = int(match[1])
        origin = f"http://127.0.0.1:{port}"

        def request(method, path, headers=None, body=None, expected=200):
            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            try:
                connection.request(method, path, body=body, headers=headers or {})
                response = connection.getresponse()
                data = response.read()
                assert response.status == expected, (path, response.status, data)
                assert response.getheader("Access-Control-Allow-Origin") is None
                records.append({"method": method, "path": path, "status": response.status})
                return response, data
            finally:
                connection.close()

        response, _ = request("GET", "/")
        cookie = response.getheader("Set-Cookie")
        assert cookie and "HttpOnly" in cookie and "SameSite=Strict" in cookie
        cookie = cookie.split(";", 1)[0]
        response, body = request("GET", "/game/")
        assert b"Fixture routing check" in body
        assert response.getheader("Set-Cookie") is None
        response, _ = request("GET", "/game/index.wasm")
        assert response.getheader("Content-Type") == "application/wasm"
        for path in ["/game/private.json", "/game/../Cargo.toml", "/game/%2e%2e%2fCargo.toml"]:
            request("GET", path, expected=404)
        request("GET", "/v2/snapshot")
        command = json.dumps(
            {
                "id": "web-fixture-check",
                "kind": "review",
                "target": "sample",
                "profile": "surveyor-v1",
                "inference": False,
            }
        )
        headers = {
            "Content-Type": "application/json",
            "Origin": origin,
            "Sec-Fetch-Site": "same-origin",
            "Cookie": cookie,
        }
        for denied in [
            {k: v for k, v in headers.items() if k != "Cookie"},
            {**headers, "Origin": "https://other.invalid"},
            {**headers, "Sec-Fetch-Site": "cross-site"},
        ]:
            request("POST", "/v2/runs", denied, command, expected=403)
        request("POST", "/v2/runs", headers, command)
        _, body = request("GET", "/v2/runs/web-fixture-check")
        assert json.loads(body)["state"] == "queued"
        request("POST", "/v2/runs/web-fixture-check/cancel", headers, "{}")
        _, body = request("GET", "/v2/runs/web-fixture-check")
        assert json.loads(body)["state"] == "cancel_requested"
        (output / "result.json").write_text(
            json.dumps(
                {
                    "passed": True,
                    "scope": "HTTP client routing and actual Core authorization; not browser Fetch",
                    "requests": records,
                },
                indent=2,
            )
            + "\n"
        )
        print(f"Web fixture checks passed; {output / 'result.json'}")
    finally:
        process.send_signal(signal.SIGINT)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
        if process.returncode != 0:
            raise RuntimeError(
                f"fixture exited with {process.returncode}; inspect fixture-stderr.log"
            )


if __name__ == "__main__":
    main()
