"""Generate the synthetic round-2 transparency fixture (mission sdlc-42).

Run from the repository root:
    python3 fixtures/world/transparency/generate_round2.py

All content is invented for tests and captures. The full record follows Core's
V7 shape (services/core/src/sdlc.rs): events keep the worker-submitted data,
evidence.testing carries Core's verdict and grading for the current round only,
and a revision clears evidence.testing and evidence.reviewing. The summary is
derived from the record the way services/core/src/sdlc_summary.rs derives it.
"""

import json
import pathlib

OUT = pathlib.Path(__file__).resolve().parent
LABEL = (
    "SYNTHETIC FIXTURE: invented mission 42 'Fix cache eviction' round 2 on "
    "X-McKay/algent for tests and captures. Not real Core, worker, model or "
    "repository activity."
)
PATH = "algent/cache.py"
CASES = [
    "evict_oldest",
    "get_refreshes",
    "capacity_zero",
    "update_existing",
    "size_limit",
    "empty_get",
]
BASELINE_FAILED = {"get_refreshes", "capacity_zero"}


def run(failed):
    return {
        "exit_code": 1 if failed else 0,
        "cases": [
            {"id": c, "actual": ("synthetic-wrong-" if c in failed else "synthetic-expected-") + c}
            for c in CASES
        ],
    }


def graded(failed):
    return {
        "passed": [c for c in CASES if c not in failed],
        "failed": [c for c in CASES if c in failed],
    }


SOURCE = """class Cache:
    def __init__(self, capacity):
        self.capacity = capacity
        self._store = OrderedDict()

    def get(self, key):
        return self._store.get(key)

    def set(self, key, value):
        if len(self._store) >= self.capacity:
            self._store.popitem(last=True)
        self._store[key] = value
"""
DIFF1 = """--- algent/cache.py
+++ algent/cache.py
@@ -9,4 +9,5 @@ class Cache:
     def set(self, key, value):
         if len(self._store) >= self.capacity:
-            self._store.popitem(last=True)
+            self._store.popitem(last=False)
         self._store[key] = value
+        self._store.move_to_end(key)
"""
DIFF2 = """--- algent/cache.py
+++ algent/cache.py
@@ -6,7 +6,11 @@ class Cache:
     def get(self, key):
+        if key in self._store:
+            self._store.move_to_end(key)
         return self._store.get(key)

     def set(self, key, value):
-        if len(self._store) >= self.capacity:
-            self._store.popitem(last=True)
+        if self.capacity == 0:
+            return
+        if key not in self._store and len(self._store) >= self.capacity:
+            self._store.popitem(last=False)
         self._store[key] = value
+        self._store.move_to_end(key)
"""


def receipt(seq, tool, ok, seconds, extra=None):
    item = {
        "sequence": seq,
        "tool": tool,
        "input_digest": f"{seq:02d}" + "a" * 62,
        "before_digest": "b" * 64,
        "candidate_digest": "c" * 64,
        "source_digest": "d" * 64,
        "elapsed_seconds": seconds,
        "ok": ok,
    }
    if not ok:
        item["error"] = "Synthetic tool failure"
    item.update(extra or {})
    return item


def member(role, requests, tools, output, elapsed):
    rows = [
        {
            "request": i + 1,
            "status": "returned",
            "model": "synthetic-model",
            "finish_reason": "stop",
            "elapsed_ms": ms,
            "input_tokens": a,
            "output_tokens": b,
        }
        for i, (a, b, ms) in enumerate(requests)
    ]
    return {
        "role": role,
        "output": output,
        "model": "synthetic-model",
        "usage": {
            "input_tokens": sum(r[0] for r in requests),
            "output_tokens": sum(r[1] for r in requests),
        },
        "usage_complete": True,
        "elapsed_ms": elapsed,
        "model_requests": rows,
        "tools": tools,
        "profile": "synthetic-profile",
        "strategy": "engineering",
    }


T0 = 1789999100.0
baseline = run(BASELINE_FAILED)
plan_output = {
    "decision": "implement",
    "task": "Fix cache eviction so the least recently used entry leaves first",
    "rationale": "Synthetic: the eviction loop removes the newest entry when the cache is full.",
}
lead = member(
    "lead",
    [(2600, 410, 9100), (1800, 380, 7400)],
    [receipt(1, "inspect_symbol", True, 0.1), receipt(2, "search_source", True, 0.2)],
    plan_output,
    19800,
)
round1 = member(
    "implementer",
    [(2900, 620, 11200), (2300, 540, 9800)],
    [
        receipt(1, "inspect_symbol", True, 0.1),
        receipt(2, "apply_patch", True, 0.3),
        receipt(3, "run_public_tests", True, 21.4, {"cached": False}),
        receipt(4, "inspect_diff", True, 0.1),
    ],
    {
        "status": "submit",
        "rationale": "Synthetic: evict from the front of the ordered store and move written "
        "keys to the end.",
        "artifact_digest": "1" * 64,
    },
    44100,
)
findings = [
    {
        "path": PATH,
        "line": 7,
        "problem": "get() does not refresh access order",
        "evidence": "get_refreshes case; reads never move a key",
    },
    {
        "path": PATH,
        "line": 10,
        "problem": "Capacity 0 pops from an empty store",
        "evidence": "capacity_zero case raises KeyError",
    },
]
review_output = {
    "status": "revise",
    "rationale": "Synthetic: the write path now evicts the oldest entry, but reads never refresh "
    "recency and capacity 0 raises instead of storing nothing.",
    "findings": findings,
    "missing_evidence": "No public test reads a key between two writes.",
}
review1 = member(
    "reviewer",
    [(3400, 520, 12600)],
    [receipt(1, "inspect_diff", True, 0.1), receipt(2, "check_candidate", True, 0.2)],
    review_output,
    15200,
)
review1 = review1 | review_output
round2 = member(
    "implementer",
    [(3100, 690, 12100), (2400, 600, 10400), (2200, 480, 8900)],
    [
        receipt(1, "inspect_symbol", True, 0.1),
        receipt(2, "apply_patch", True, 0.4),
        receipt(3, "run_public_tests", False, 22.0, {"cached": False}),
        receipt(4, "apply_patch", True, 0.3),
        receipt(5, "run_public_tests", True, 21.1, {"cached": False}),
        receipt(6, "inspect_diff", True, 0.1),
        receipt(7, "check_candidate", True, 0.1),
    ],
    {
        "status": "submit",
        "rationale": "Synthetic: taking both findings. get() now refreshes recency, capacity 0 "
        "returns before eviction, and updates no longer evict.",
        "artifact_digest": "2" * 64,
    },
    58700,
)


def testing(diff, candidate_failed, patch, digest):
    return {
        "baseline": baseline,
        "candidate": run(candidate_failed),
        "candidate_files": {PATH: "synthetic candidate source"},
        "patch": patch,
        "diff": diff,
        "artifact_digest": digest,
        "validation_error": None,
    }


testing1 = testing(DIFF1, BASELINE_FAILED, round1, "1" * 64)
testing2 = testing(DIFF2, set(), round2, "2" * 64)
revise = {"role": "reviewer", "feedback": review1, "verdict": "improved"}
investigating = {
    "sources": {PATH: SOURCE},
    "source_digest": "e" * 64,
    "baseline": baseline,
    "opportunity": "Cache eviction keeps least recently used entries",
    "scope": "Six synthetic cache behaviours",
}
EVENTS = [
    ("source-baseline", "investigating", investigating, T0 + 60),
    ("lead-handoff", "implementing", lead, T0 + 200),
    ("testing-1", "testing", testing1, T0 + 400),
    ("review-1", "reviewing", review1, T0 + 550),
    ("revise-1", "implementing", revise, T0 + 552),
    ("testing-2", "testing", testing2, T0 + 850),
]
assignments = [
    {
        "task": "diagnose",
        "role": "lead",
        "crew": "moss",
        "requires": [],
        "evidence": "investigating",
    },
    {
        "task": "implement",
        "role": "implementer",
        "crew": "rivet",
        "requires": ["diagnose"],
        "evidence": "implementing",
        "fallback_crews": ["moss"],
    },
    {
        "task": "review",
        "role": "reviewer",
        "crew": "prism",
        "requires": ["implement"],
        "evidence": "testing",
    },
]
grading2 = {"verdict": "improved", "baseline_pass": False, "candidate_pass": True}
record = {
    "_fixture": LABEL,
    "id": "sdlc-42",
    "retry_of": None,
    "input": {
        "id": "sdlc-42",
        "repository": "X-McKay/algent",
        "revision": "3f9c2e1a7b5d40c8a1e2f3b4c5d6e7f8a9b0c1d2",
        "opportunity": "cache-eviction",
        "build": {"digest": "f" * 64},
    },
    "policy_generation": 7,
    "capability": {
        "id": "synthetic-cache-eviction-v1",
        "objective": "Fix cache eviction",
        "digest": "9" * 64,
        "editable_paths": [PATH],
        "limits": {"max_rounds": 3},
        "assignments": assignments,
    },
    "coordination": {
        "assignments": assignments,
        "max_rounds": 3,
        "reservation": "x-mckay/algent:cache-eviction",
    },
    "state": "testing",
    "events": [
        {"key": k, "event": {"key": k, "stage": s, "data": d}, "at": at} for k, s, d, at in EVENTS
    ],
    "evidence": {
        "investigating": investigating,
        "implementing": revise,
        "testing": testing2 | {"verdict": "improved", "grading": grading2},
        "reviewing": None,
    },
    "publication": None,
    "cancel_requested": False,
    "revision_loops": 1,
    "created_at": T0,
    "updated_at": T0 + 850,
}


def label(stage, data):
    out = stage
    if data.get("role"):
        out += " · " + data["role"]
    output = data.get("output") or {}
    status = (
        data.get("status")
        or output.get("decision")
        or output.get("status")
        or data.get("verdict")
        or data.get("outcome")
    )
    if status:
        out += " · " + status
    return out


summaries = [
    {"key": k, "stage": s, "at": at, "label": label(s, d), "role": d.get("role")}
    for k, s, d, at in EVENTS
]
summary = {
    "id": "sdlc-42",
    "state": "testing",
    "repository": "X-McKay/algent",
    "objective": "Fix cache eviction",
    "current_stage": "testing",
    "revision_count": 1,
    "assigned_crew": {"implementer": "rivet", "lead": "moss", "reviewer": "prism"},
    "created_at": T0,
    "updated_at": T0 + 850,
    "latest_event": summaries[-1],
    "recent_events": summaries[-3:],
    "event_count": len(EVENTS),
    "verdict": "improved",
    "publication": {
        "state": "none",
        "branch": None,
        "pr_number": None,
        "pr_url": None,
        "pr_state": None,
        "pr_observed_at": None,
    },
    "cancel_requested": False,
    "policy_generation": 7,
    "retry_of": None,
    "input": {
        "id": "sdlc-42",
        "repository": "X-McKay/algent",
        "revision": record["input"]["revision"],
        "opportunity": "cache-eviction",
        "build_digest": "f" * 64,
        "capability_digest": None,
    },
    "verifications": [],
    "stage_evidence": {
        "plan": {"role": "lead"} | plan_output,
        "testing": {
            "verdict": "improved",
            "grading": grading2,
            "baseline_cases": graded(BASELINE_FAILED),
            "candidate_cases": graded(set()),
            "diff": {"files": 1, "additions": 7, "deletions": 2},
            "artifact_digest": "2" * 64,
            "validation_error": None,
        },
        "reviewing": None,
    },
}
snapshot = {
    "_fixture": LABEL,
    "schema_version": 7,
    "view": "summary",
    "enabled": True,
    "verification_enabled": False,
    "policy": {
        "repository": "X-McKay/algent",
        "enabled": True,
        "publish": True,
        "generation": 7,
        "max_missions": 3,
        "expires_at": 1790225000.0,
    },
    "coordination": {
        "admission": "active_mission",
        "can_discover": False,
        "reserved_opportunities": [],
        "resolution": "Mission 42 is active; new admission waits for it to finish.",
    },
    "capability_catalog": {"schema_version": 1, "capabilities": []},
    "discovery_count": 0,
    "missions": [summary],
    "page": {
        "order": "created_at_desc",
        "limit": 25,
        "total": 1,
        "returned": 1,
        "next_before": None,
    },
}

EPOCH = "fx0000000000b742"
frames = [
    {
        "fixture": "synthetic",
        "description": LABEL,
        "reference_time": 1790000000.0,
        "world_snapshot": "world-snapshot.json",
        "v7_snapshot": "round2-v7-snapshot.json",
        "v7_missions": {"sdlc-42": "round2-mission-sdlc-42.json"},
    }
]
sequence = [200]
event_at = {k: at for k, _, _, at in EVENTS}
event_label = {s["key"]: s["label"] for s in summaries}


def record_frame(t, kind, at, payload, retained=True):
    sequence[0] += 1
    ident = f"{EPOCH}-{sequence[0]}"
    frames.append(
        {
            "t": t,
            "event": "record",
            "id": ident,
            "data": {
                "id": ident,
                "epoch": EPOCH,
                "seq": sequence[0],
                "type": kind,
                "family": "v7_mission",
                "record_id": "sdlc-42",
                "at": at,
                "retained": retained,
                "payload": payload,
            },
        }
    )


def stage(t, key, name, state, role, revision, verdict):
    payload = {
        "key": key,
        "stage": name,
        "state": state,
        "label": event_label[key],
        "role": role,
        "revision_count": revision,
        "verdict": verdict,
    }
    record_frame(t, "mission.stage", event_at[key], payload)


def note(t, at, **payload):
    payload.setdefault(
        "state", "implementing" if payload.get("role") == "implementer" else "testing"
    )
    record_frame(t, "mission.activity", at, payload, retained=False)


def heartbeat_raw(t, at):
    body = json.dumps(
        {"type": "heartbeat", "epoch": EPOCH, "cursor": f"{EPOCH}-{sequence[0]}", "at": at}
    )
    frames.append({"t": t, "raw": ": keepalive\nevent: heartbeat\ndata: " + body + "\n\n"})


# Replayed retained records (resume), then ready.
stage(0.0, "testing-1", "testing", "testing", None, 0, "improved")
stage(0.1, "review-1", "reviewing", "reviewing", "reviewer", 0, "improved")
stage(0.2, "revise-1", "implementing", "implementing", "reviewer", 1, None)
ready = {
    "type": "ready",
    "epoch": EPOCH,
    "cursor": f"{EPOCH}-{sequence[0]}",
    "at": T0 + 560,
    "oldest_retained": f"{EPOCH}-1",
    "replayed": 3,
    "heartbeat_seconds": 5,
    "retained_capacity": 1000,
}
frames.append(
    {
        "t": 0.4,
        "raw": f"retry: 3000\nevent: ready\nid: {EPOCH}-{sequence[0]}\n"
        f"data: {json.dumps(ready)}\n\n",
    }
)
A = T0 + 560
for t, at, payload in [
    (
        0.8,
        A + 10,
        dict(
            kind="model_request_finished",
            request=1,
            ok=True,
            input_tokens=3100,
            output_tokens=690,
            elapsed_ms=12100,
        ),
    ),
    (1.0, A + 14, dict(kind="tool_finished", tool="inspect_symbol", ok=True, elapsed_ms=100)),
    (1.2, A + 30, dict(kind="tool_finished", tool="apply_patch", ok=True, elapsed_ms=400)),
    (
        1.5,
        A + 55,
        dict(
            kind="tool_finished",
            tool="run_public_tests",
            ok=False,
            error="tool_error",
            elapsed_ms=22000,
        ),
    ),
    (
        1.8,
        A + 70,
        dict(
            kind="model_request_finished",
            request=2,
            ok=True,
            input_tokens=2400,
            output_tokens=600,
            elapsed_ms=10400,
        ),
    ),
    (2.0, A + 80, dict(kind="tool_finished", tool="apply_patch", ok=True, elapsed_ms=300)),
    (2.3, A + 105, dict(kind="tool_finished", tool="run_public_tests", ok=True, elapsed_ms=21100)),
    (2.5, A + 110, dict(kind="tool_finished", tool="inspect_diff", ok=True, elapsed_ms=100)),
    (
        2.8,
        A + 125,
        dict(
            kind="model_request_finished",
            request=3,
            ok=True,
            input_tokens=2200,
            output_tokens=480,
            elapsed_ms=8900,
        ),
    ),
]:
    note(t, at, role="implementer", **payload)
stage(3.2, "testing-2", "testing", "testing", None, 1, "improved")
note(3.8, T0 + 860, kind="model_request_started", request=1, role="reviewer")
note(
    4.6,
    T0 + 874,
    kind="model_request_finished",
    request=1,
    ok=True,
    input_tokens=3600,
    output_tokens=410,
    elapsed_ms=13800,
    role="reviewer",
)
heartbeat_raw(5.0, T0 + 880)
note(5.6, T0 + 890, kind="tool_started", tool="inspect_diff", role="reviewer")
frames.append(
    {
        "t": 6.2,
        "event": "heartbeat",
        "data": {
            "type": "heartbeat",
            "epoch": EPOCH,
            "cursor": f"{EPOCH}-{sequence[0]}",
            "at": 1790000000.0,
        },
    }
)

(OUT / "round2-mission-sdlc-42.json").write_text(
    json.dumps(record, indent=2, ensure_ascii=False) + "\n"
)
(OUT / "round2-v7-snapshot.json").write_text(
    json.dumps(snapshot, indent=2, ensure_ascii=False) + "\n"
)
(OUT / "round2-stream.jsonl").write_text(
    "".join(json.dumps(f, ensure_ascii=False) + "\n" for f in frames)
)
