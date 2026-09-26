"""Read-only smart HTTP for one synthetic Git repo; upload-pack is Git's builtin.

No receive-pack, filesystem URL mapping, hooks, external repositories, or auth.
The trusted harness copies immutable Git objects in before triggering Flux.
"""

import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def serve_git(self, advertise: bool):
        length = int(self.headers.get("Content-Length", "0"))
        if not 0 <= length <= 1_048_576:
            self.send_error(413)
            return
        command = ["git", "upload-pack", "--strict", "--stateless-rpc"]
        if advertise:
            command.append("--advertise-refs")
        command.append(os.environ.get("FIXTURE_REPOSITORY", "/git/scenario.git"))
        try:
            result = subprocess.run(
                command,
                input=self.rfile.read(length),
                capture_output=True,
                timeout=15,
                check=True,
            ).stdout
        except (subprocess.SubprocessError, OSError):
            self.send_error(503)
            return
        if advertise:
            result = b"001e# service=git-upload-pack\n0000" + result
        self.send_response(200)
        suffix = "advertisement" if advertise else "result"
        self.send_header("Content-Type", "application/x-git-upload-pack-" + suffix)
        self.send_header("Content-Length", str(len(result)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(result)

    def do_GET(self):
        if self.path == "/scenario.git/info/refs?service=git-upload-pack":
            self.serve_git(True)
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path == "/scenario.git/git-upload-pack":
            self.serve_git(False)
        else:
            self.send_error(403)


if __name__ == "__main__":
    ThreadingHTTPServer(
        (os.environ.get("BIND_ADDRESS", "0.0.0.0"), int(os.environ.get("HTTP_PORT", "8000"))),
        Handler,
    ).serve_forever()
