"""Local HTTP failure fixtures for the native operator client; no real work dispatched."""

import json
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

posts: list[str] = []
gets: list[str] = []
errors: list[str] = []


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args):
        pass

    def respond(self, code, value, cookie=False):
        body = json.dumps(value).encode()
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        if cookie:
            self.send_header(
                "Set-Cookie", "starbase_session=fixture; HttpOnly; SameSite=Strict; Path=/"
            )
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        gets.append(self.path)
        if self.path == "/":
            self.respond(200, {}, cookie=True)
        elif self.path == "/v4/repositories":
            self.respond(
                200,
                {"repositories": [{"config": {"repository": "fixture/command", "generation": 0}}]},
            )
        elif self.path == "/v4/snapshot":
            self.respond(
                200, {"memory": [{"id": "memory-change", "revision": 1, "decision": "approve"}]}
            )
        elif self.path.endswith("/uncertain") and gets.count(self.path) == 1:
            self.respond(503, {"error": "fixture outage"})
        else:
            self.respond(200, {"input": {"id": self.path.rsplit("/", 1)[-1]}, "state": "queued"})

    def do_POST(self):
        data = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        run_id = data.get("id", "repo-change")
        posts.append(run_id)
        if self.headers.get("Cookie") != "starbase_session=fixture":
            errors.append("Missing operator cookie")
        if self.headers.get("Authorization"):
            errors.append("Client must not send worker authorization")
        origin = f"http://127.0.0.1:{server.server_port}"
        if self.headers.get("Origin") != origin:
            errors.append("Incorrect operator origin")
        if run_id in {"lost-response", "uncertain", "repo-change", "memory-change"}:
            self.close_connection = True
            return  # Simulate an accepted effect with its HTTP response lost.
        self.respond(
            403 if run_id == "forbidden" else 200, {"id": run_id, "error": "fixture denial"}
        )


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    result = subprocess.run(
        [
            "godot",
            "--headless",
            "--path",
            "apps/world",
            "--script",
            "test_commands.gd",
            "--",
            f"http://127.0.0.1:{server.server_port}",
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    print(result.stdout)
    assert result.returncode == 0 and "ERROR:" not in result.stdout, result.stdout
    assert not errors, errors
    assert posts == [
        "normal",
        "forbidden",
        "lost-response",
        "uncertain",
        "repo-change",
        "memory-change",
    ], posts
    assert gets.count("/v3/repairs/uncertain") == 2, gets
    print("HTTP fixture verified six POSTs only; reconciliation used GET; no worker identity.")
finally:
    server.shutdown()
    server.server_close()
    thread.join()
