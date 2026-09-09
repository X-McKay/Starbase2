"""Exercise native operator HTTP journeys against an isolated synthetic loopback Core."""

import copy
import json
import socket
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

ROOT = Path(__file__).resolve().parents[1]


def record(sequence: int, state: str = "completed") -> dict:
    return {
        "sequence": sequence,
        "input": {"request": {"id": f"run-{sequence}", "kind": "review"}},
        "state": state,
        "updated_at": sequence,
        "report": {"summary": {"coverage": "partial synthetic fixture"}},
        "detail": "Synthetic HTTP transport test; no provider work",
    }


def main() -> None:
    writes: list[dict] = []
    reads: list[str] = []
    duties: dict[str, dict] = {}
    created: dict[str, dict] = {}
    errors: list[str] = []
    snapshot = {
        "schema_version": 2,
        "observed_at": 100,
        "installation": {
            "id": "starbase2-http-test",
            "capabilities": {
                name: {"enabled": True, "reason": "Synthetic test policy"}
                for name in ("review", "evaluation", "accept_work")
            },
        },
        "worker": {"available": True, "seen_at": 100},
        "targets": [{"id": name, "label": name} for name in ("workspace", "deny")],
        "builds": [{"manifest": {"profile": name}} for name in ("baseline", "candidate")],
        "recent": [record(i) for i in range(45, 25, -1)],
        "active": [record(1, "running")],
        "duties": [],
    }

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format: str, *args: object) -> None:
            pass

        def reply(self, code: int, value: object, session: bool = False) -> None:
            payload = json.dumps(value).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            if session:
                self.send_header("Set-Cookie", "starbase_session=synthetic-only; HttpOnly")
            self.end_headers()
            self.wfile.write(payload)

        def do_GET(self) -> None:
            reads.append(self.path)
            url = urlsplit(self.path)
            if url.path == "/":
                self.reply(200, {}, session=True)
            elif url.path == "/v2/snapshot":
                current = copy.deepcopy(snapshot)
                current["duties"] = list(duties.values())
                self.reply(200, current)
            elif url.path == "/v2/runs":
                before = int(parse_qs(url.query).get("before", ["46"])[0])
                self.reply(
                    200, {"runs": [record(i) for i in range(min(45, before - 1), 0, -1)][:20]}
                )
            elif url.path.removeprefix("/v2/runs/") in created:
                self.reply(200, created[url.path.removeprefix("/v2/runs/")])
            elif url.path.startswith("/v2/runs/run-"):
                value = record(int(url.path.rsplit("-", 1)[1]))
                value["events"] = [{"sequence": 1, "state": "completed"}]
                value["snapshot"] = {"data": {"synthetic": True}}
                self.reply(200, value)
            else:
                errors.append(f"Unexpected GET: {self.path}")
                self.reply(404, {})

        def do_POST(self) -> None:
            value = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            assert isinstance(self.server, ThreadingHTTPServer)
            expected_origin = f"http://127.0.0.1:{self.server.server_port}"
            if (
                self.headers.get("Origin") != expected_origin
                or self.headers.get("Cookie") != "starbase_session=synthetic-only"
            ):
                errors.append("Missing synthetic session/origin boundary")
                self.reply(403, {"error": "Session required"})
                return
            writes.append({"path": self.path, "payload": value})
            if self.path == "/v2/runs":
                if value["target"] == "deny":
                    self.reply(403, {"error": "Synthetic target policy denies this request"})
                else:
                    created[value["id"]] = {
                        **record(100 + len(created), "queued"),
                        "input": {"request": value},
                    }
                    self.reply(200, {"id": value["id"]})
            elif self.path == "/v2/duties":
                saved = copy.deepcopy(value)
                saved["generation"] += 2 if value["id"] == "drift-duty" else 1
                duties[value["id"]] = saved
                if not value["enabled"] or value["id"] == "drift-duty":
                    # Commit then lose the response: only GET reconciliation may acknowledge it.
                    self.connection.shutdown(socket.SHUT_RDWR)
                    self.connection.close()
                    self.close_connection = True
                else:
                    self.reply(200, saved)
            else:
                errors.append(f"Unexpected POST: {self.path}")
                self.reply(404, {})

    with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
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
                    "test_operations_http.gd",
                    "--",
                    f"--api=http://127.0.0.1:{server.server_port}",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=55,
            )
            print(result.stdout, flush=True)
            if (
                result.returncode
                or "ERROR:" in result.stdout
                or "OPERATIONS_HTTP_PASSED" not in result.stdout
            ):
                raise RuntimeError("Native operations HTTP journey failed; output retained above")
            assert not errors, errors
            assert len(writes) == 6, writes
            review, evaluation, denied, save, pause, drift = writes
            assert review["payload"]["kind"] == "review"
            assert review["payload"]["target"] == "workspace"
            assert review["payload"]["candidate"] is None and not review["payload"]["inference"]
            assert evaluation["payload"]["kind"] == "evaluation"
            assert evaluation["payload"]["target"] == "sample"
            assert evaluation["payload"]["profile"] == "baseline"
            assert evaluation["payload"]["candidate"] == "candidate"
            assert not evaluation["payload"]["inference"]
            assert review["payload"]["id"] != evaluation["payload"]["id"]
            assert denied["payload"]["target"] == "deny"
            assert save["payload"]["generation"] == 0 and save["payload"]["enabled"]
            assert pause["payload"]["generation"] == 1 and not pause["payload"]["enabled"]
            assert drift["payload"]["id"] == "drift-duty"
            assert "/v2/runs?before=26" in reads and "/v2/runs/run-40" in reads
            print(
                json.dumps(
                    {
                        "scope": "synthetic loopback; no providers or credentials",
                        "writes": len(writes),
                        "reads": len(reads),
                        "checks": [
                            "review/evaluation payloads",
                            "denied response",
                            "duty lost-response generation reconciliation",
                            ">20 paging",
                            "retained selection/evidence",
                            "fixture/unknown-policy no dispatch",
                        ],
                    }
                )
            )
        finally:
            server.shutdown()
            thread.join(timeout=2)


if __name__ == "__main__":
    main()
