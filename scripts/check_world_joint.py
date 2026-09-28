"""Isolated loopback V5 operator fixtures; no real Core, model, or cluster work."""

import copy
import json
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

records = {}
writes = []
reads = []
lookups = {}
cancel_wait = set()
errors = []
build = {
    "digest": "fixture-joint-scripted",
    "manifest": {"profile": "joint-readiness-v1", "inference": False},
}


def mission(data, state="running"):
    now = time.time()
    return {
        "input": data,
        "state": state,
        "deadline": now + 600,
        "created_at": now,
        "updated_at": now,
        "tasks": [],
        "budget": {
            "requests_reserved": 0,
            "tokens_reserved": 0,
            "tokens_accounted": 0,
            "requests_limit": data["budget"]["requests"],
            "tokens_limit": data["budget"]["tokens"],
        },
        "decision": None,
        "outcome": None,
        "reason": None,
        "simulation": True,
        "xp": 0,
    }


records["race-terminal"] = mission(
    {
        "id": "race-terminal",
        "opportunity": "race-terminal",
        "build": build["digest"],
        "scenario": "route-mismatch",
        "inference": False,
        "budget": {"requests": 6, "tokens": 131072},
    }
)


class Handler(BaseHTTPRequestHandler):
    server: ThreadingHTTPServer

    def log_message(self, format: str, *args) -> None:
        pass

    def reply(self, code, data, session=False):
        raw = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        if session:
            self.send_header("Set-Cookie", "starbase_session=isolated-joint-actions; HttpOnly")
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        reads.append(self.path)
        if self.path == "/":
            self.reply(200, {}, True)
            return
        if self.path == "/v5/snapshot":
            self.reply(
                200,
                {
                    "schema_version": 5,
                    "enabled": True,
                    "simulation": True,
                    "observed_at": time.time(),
                    "builds": [build],
                    "missions": list(records.values()),
                    "opportunities": [],
                },
            )
            return
        id = self.path.removeprefix("/v5/missions/")
        lookups[id] = lookups.get(id, 0) + 1
        if id not in records:
            self.reply(404, {})
            return
        result = copy.deepcopy(records[id])
        if id in cancel_wait:
            if lookups[id] >= 4:
                records[id]["state"] = "cancelled"
                result = records[id]
        elif result["input"]["scenario"] == "route-mismatch" and lookups[id] == 1:
            self.reply(404, {})
            return
        elif result["input"]["scenario"] == "persistent-dependency" and lookups[id] == 1:
            result["input"]["build"] = "different-build"
        self.reply(200, result)

    def do_POST(self):
        raw = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        origin = f"http://127.0.0.1:{self.server.server_port}"
        if (
            self.headers.get("Origin") != origin
            or self.headers.get("Cookie") != "starbase_session=isolated-joint-actions"
        ):
            errors.append("operator boundary missing")
            self.reply(403, {})
            return
        if self.headers.get("Authorization"):
            errors.append("unexpected worker identity")
        writes.append({"path": self.path, "body": raw})
        if self.path == "/v5/missions":
            assert type(raw["budget"]["requests"]) is int and type(raw["budget"]["tokens"]) is int
            assert raw["build"] == build["digest"] and raw["inference"] is False
            if raw["scenario"] == "healthy":
                self.reply(403, {"error": "Synthetic policy denies this scenario"})
                return
            records[raw["id"]] = mission(raw)
            self.connection.shutdown(socket.SHUT_RDWR)
            self.connection.close()
            self.close_connection = True
            return
        id = self.path.removeprefix("/v5/missions/").removesuffix("/cancel")
        assert raw == {}
        if id == "race-terminal":
            records[id]["state"] = "completed"
            self.reply(200, records[id])
            return
        cancel_wait.add(id)
        self.connection.shutdown(socket.SHUT_RDWR)
        self.connection.close()
        self.close_connection = True


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
result = subprocess.run(
    [
        "godot",
        "--headless",
        "--resolution",
        "1280x800",
        "--log-file",
        "/tmp/starbase-joint-actions-http.log",
        "--path",
        "apps/world",
        "--script",
        "test_joint_actions.gd",
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
    and "JOINT_ACTIONS_PASSED" in result.stdout
    and "ERROR:" not in result.stdout
)
assert not errors
assert len(writes) == 5, writes
assert sum(w["path"] == "/v5/missions" for w in writes) == 3
assert writes[0]["body"]["budget"] == {"requests": 6, "tokens": 131072}
print(
    "JOINT_ACTION_HTTP_PASSED: 3 launch POSTs (one rejected), 2 cancellation POSTs; "
    "lost responses reconciled by GET only; session/Origin and no worker credential verified"
)
