"""Bounded operator commands through a loopback Kubernetes port-forward."""

import http.cookiejar
import json
import re
import time
import urllib.request

ORIGIN = "http://127.0.0.1:8787"


def drain(installation: str, origin: str = ORIGIN, timeout: int = 180) -> dict:
    match = re.fullmatch(r"http://127\.0\.0\.1:([1-9][0-9]{0,4})", origin)
    if match is None or int(match[1]) > 65535:
        raise ValueError("Core address must be canonical http://127.0.0.1:<port>")
    if not installation:
        raise ValueError("Expected installation identity is required")
    cookies = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookies))
    with opener.open(origin, timeout=10):
        pass

    def request(path, body=None):
        payload = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(
            origin + path,
            data=payload,
            headers={"Content-Type": "application/json", "Origin": origin},
        )
        with opener.open(req, timeout=10) as r:
            return json.load(r)

    snapshot = request("/v2/snapshot")
    if snapshot.get("installation", {}).get("id") != installation:
        raise ValueError("Core installation identity mismatch; no drain mutations dispatched")
    for duty in snapshot["duties"]:
        if duty["enabled"]:
            request("/v2/duties", duty | {"enabled": False})
    field = request("/v4/snapshot")
    configured = [d for d in field["duties"] if not d["id"].startswith("repo-")]
    for duty in configured:
        if duty["enabled"]:
            request(
                "/v4/duties",
                duty | {"enabled": False, "generation": duty["generation"] + 1},
            )
    for repository in field["repositories"]:
        config = repository["config"]
        if config["enabled"] and not config["removed"]:
            request(
                "/v4/repositories",
                config | {"enabled": False, "generation": config["generation"] + 1},
            )
    deadline = time.monotonic() + timeout
    while True:
        runs = request("/v2/runs?active=true")["runs"]
        repairs = request("/v3/repairs")["repairs"]
        repairs = [r for r in repairs if r["state"] not in {"completed", "failed", "cancelled"}]
        field = request("/v4/snapshot")
        field_runs = [
            r for r in field["runs"] if r["state"] not in {"completed", "failed", "cancelled"}
        ]
        # Verify retained schedules too: another operator may have reenabled or
        # created one. Never silently overwrite a newer generation while draining.
        scheduled = any(d["enabled"] for d in request("/v2/snapshot")["duties"])
        scheduled = scheduled or any(d["enabled"] for d in field["duties"])
        scheduled = scheduled or any(
            r["config"]["enabled"] and not r["config"]["removed"] for r in field["repositories"]
        )
        if not runs and not repairs and not field_runs and not scheduled:
            return {
                "drained": True,
                "duties_paused": len(snapshot["duties"]),
                "field_duties_paused": len(configured),
                "repository_watches_paused": len(field["repositories"]),
            }
        if time.monotonic() >= deadline:
            raise RuntimeError(
                "Drain timed out; retained active work must be inspected/cancelled before upgrade"
            )
        time.sleep(2)
