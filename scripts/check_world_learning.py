"""Isolated loopback V6 duty/rebase/cancel fixtures; no real training dispatched."""

import copy
import json
import socket
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

writes = []
reads = []
errors = []
build = {
    "digest": "fixture-practice-build",
    "manifest": {"profile": "joint-readiness-v1", "inference": False},
}
cycle = {
    "id": "practice-http-cycle",
    "state": "evaluating",
    "baseline": build,
    "candidate": None,
    "proposal": {"state": "completed"},
    "trials": [],
    "summary": None,
}
control: dict[str, Any] | None = None
previous: dict[str, Any] | None = None
stage = "initial"
reconciles = 0
cycle_reads = 0
budget = {
    "proposal_requests": 1,
    "proposal_tokens": 32768,
    "trial_requests": 24,
    "trial_tokens": 384000,
}


class Handler(BaseHTTPRequestHandler):
    server: ThreadingHTTPServer

    def log_message(self, format: str, *args) -> None:
        pass

    def reply(self, code, value, session=False):
        raw = json.dumps(value).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        if session:
            self.send_header("Set-Cookie", "starbase_session=isolated-learning; HttpOnly")
        self.end_headers()
        self.wfile.write(raw)

    def lost(self):
        self.connection.shutdown(socket.SHUT_RDWR)
        self.connection.close()
        self.close_connection = True

    def do_GET(self):
        global reconciles, cycle_reads, stage
        reads.append(self.path)
        if self.path == "/":
            self.reply(200, {}, True)
            return
        if self.path == "/v5/snapshot":
            self.reply(
                200,
                {
                    "builds": [
                        build,
                        {"digest": "fixture-practice-upgrade", "manifest": build["manifest"]},
                    ]
                },
            )
            return
        if self.path == "/v6/snapshot":
            value = copy.deepcopy(control)
            if stage in ("enable", "stop", "rebase"):
                reconciles += 1
                if reconciles == 1:
                    if stage == "enable":
                        value = None
                    elif stage == "rebase":
                        value = copy.deepcopy(previous)
                    else:
                        assert value is not None
                        value["duty"]["generation"] += 1
                        value["duty"]["enabled"] = True
                else:
                    stage = "stable"
            self.reply(
                200,
                {
                    "schema_version": 6,
                    "enabled": control is None,
                    "control": value,
                    "cycles": [cycle],
                    "policy": {},
                },
            )
            return
        if self.path == "/v6/cycles/practice-http-cycle":
            cycle_reads += 1
            if cycle_reads >= 2:
                cycle["state"] = "cancelled"
            self.reply(200, cycle)
            return
        self.reply(404, {})

    def do_POST(self):
        global control, previous, stage, reconciles
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if (
            self.headers.get("Origin") != f"http://127.0.0.1:{self.server.server_port}"
            or self.headers.get("Cookie") != "starbase_session=isolated-learning"
        ):
            errors.append("operator session/Origin missing")
            self.reply(403, {})
            return
        if self.headers.get("Authorization"):
            errors.append("unexpected worker credential")
        writes.append({"path": self.path, "body": body})
        if self.path == "/v6/duty":
            assert body["id"] == "readiness-practice" and body["baseline"] in (
                build["digest"],
                "fixture-practice-upgrade",
            )
            assert (
                body["budget"] == budget
                and body["max_cycles"] == 2
                and body["cooldown_seconds"] == 60
            )
            assert (
                type(body["generation"]) is int
                and type(body["max_cycles"]) is int
                and type(body["cooldown_seconds"]) is int
            )
            assert all(type(body["budget"][key]) is int for key in budget)
            expected = 0 if control is None else control["duty"]["generation"] + 1
            assert body["generation"] == expected
            previous = copy.deepcopy(control)
            rebase = (
                control is not None and body["baseline"] != control["practice_incumbent"]["build"]
            )
            stage = "rebase" if rebase else "enable" if body["enabled"] else "stop"
            reconciles = 0
            if rebase:
                assert control is not None
                assert (
                    not body["enabled"]
                    and not control["duty"]["enabled"]
                    and cycle["state"] == "cancelled"
                )
            control = {
                "duty": body,
                "practice_incumbent": {
                    "build": body["baseline"],
                    "generation": 1 if rebase else 0,
                    "source_cycle": None,
                },
                "admitted_cycles": 0,
                "last_started_at": None,
            }
            self.lost()
            return
        if self.path == "/v6/cycles/practice-http-cycle/cancel":
            assert body == {}
            self.lost()
            return
        errors.append("unexpected POST")
        self.reply(404, {})


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
result = subprocess.run(
    [
        "godot",
        "--headless",
        "--resolution",
        "1280x800",
        "--log-file",
        "/tmp/starbase-learning-http.log",
        "--path",
        "apps/world",
        "--script",
        "test_learning_panel.gd",
        "--",
        f"--api=http://127.0.0.1:{server.server_port}",
    ],
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    timeout=50,
)
server.shutdown()
print(result.stdout)
print(json.dumps({"writes": writes, "reads": reads, "errors": errors}, indent=2))
assert (
    result.returncode == 0
    and "LEARNING_PANEL_PASSED" in result.stdout
    and "ERROR:" not in result.stdout
)
assert not errors and len(writes) == 4, writes
assert (
    writes[-1]["body"]["baseline"] == "fixture-practice-upgrade"
    and writes[-1]["body"]["enabled"] is False
    and writes[-1]["body"]["generation"] == 2
)
assert [w["body"].get("generation") for w in writes[:2]] == [0, 1]
assert [w["body"].get("enabled") for w in writes[:2]] == [True, False]
print(
    "LEARNING_HTTP_PASSED: exactly 4 POSTs; enable, stop, cancel and stopped-baseline rebase "
    "lost responses reconciled by GET only; exact CAS/budgets and operator session/Origin verified"
)
