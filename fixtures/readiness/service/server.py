"""Credential-free fixture; the dependency really refuses TCP until its timer fires."""

import json
import os
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from fixture_worker import work

DEPENDENCY_PORT = int(os.environ.get("DEPENDENCY_PORT", "9090"))


def dependency() -> None:
    delay = float(os.environ.get("DEPENDENCY_DELAY", "0"))
    if delay < 0:
        return
    time.sleep(delay)
    with socket.socket() as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", DEPENDENCY_PORT))
        listener.listen()
        while True:
            connection, _ = listener.accept()
            connection.close()


def connected() -> bool:
    try:
        with socket.create_connection(("127.0.0.1", DEPENDENCY_PORT), timeout=0.2):
            return True
    except OSError:
        return False


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        request = urlparse(self.path)
        status, body = 404, {"error": "route-not-found"}
        if request.path == "/live":
            status, body = 200, {"alive": True}
        elif request.path in {"/ready", "/work"}:
            if not connected():
                status, body = 503, {"error": "dependency-connection-refused"}
            elif request.path == "/ready":
                status, body = 200, {"ready": True}
            else:
                try:
                    value = int(parse_qs(request.query)["value"][0])
                    if abs(value) > 1000:
                        raise ValueError("input budget")
                    result = work(value)
                    if os.environ.get("BROKEN_WORK") == "True":
                        result += 1
                    status, body = 200, {"value": value, "result": result}
                except (KeyError, ValueError):
                    status, body = 400, {"error": "invalid-input"}
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


if __name__ == "__main__":
    threading.Thread(target=dependency, daemon=True).start()
    ThreadingHTTPServer(
        (os.environ.get("BIND_ADDRESS", "0.0.0.0"), int(os.environ.get("HTTP_PORT", "8080"))),
        Handler,
    ).serve_forever()
