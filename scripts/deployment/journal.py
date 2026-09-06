"""Bounded operator commands through a loopback Kubernetes port-forward."""

import http.cookiejar
import json
import time
import urllib.request

ORIGIN = "http://127.0.0.1:8787"


def drain(timeout: int = 180) -> dict:
    cookies = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookies))
    with opener.open(ORIGIN, timeout=10):
        pass

    def request(path, body=None):
        payload = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(
            ORIGIN + path,
            data=payload,
            headers={"Content-Type": "application/json", "Origin": ORIGIN},
        )
        with opener.open(req, timeout=10) as r:
            return json.load(r)

    snapshot = request("/v2/snapshot")
    for duty in snapshot["duties"]:
        request("/v2/duties", duty | {"enabled": False})
    deadline = time.monotonic() + timeout
    while True:
        runs = request("/v2/runs?active=true")["runs"]
        repairs = request("/v3/repairs")["repairs"]
        repairs = [r for r in repairs if r["state"] not in {"completed", "failed", "cancelled"}]
        if not runs and not repairs:
            return {"drained": True, "duties_paused": len(snapshot["duties"])}
        if time.monotonic() >= deadline:
            raise RuntimeError(
                "Drain timed out; retained active work must be inspected/cancelled before upgrade"
            )
        time.sleep(2)
