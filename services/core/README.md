# Local core APIs

v2 is the current read-only operations API; v1 below retains the original synthetic
experiment. See [operations](../../docs/operations.md) for behavior and limitations.
Commands and wire projections are generated from Rust into
[operations.schema.json](../../contracts/operations.schema.json).

| Endpoint | Behavior |
|---|---|
| `GET /v2/snapshot` | Core timestamp, worker freshness, crew, builds, targets, duties, active/recent runs |
| `GET /v2/runs?before=SEQUENCE` | Twenty historical runs; independent active feed via `active=true` |
| `GET /v2/runs/{id}` | Frozen input, source snapshot, retained report, lifecycle events |
| `POST /v2/runs` | Operator session required; stable request ID and frozen registered builds |
| `POST /v2/runs/{id}/cancel` | Fence completion, then reconcile Temporal cancellation |
| `POST /v2/duties` | Validated interval/target/profile and enabled state; generation increments |
| `POST /internal/v2/builds` | Worker bearer; immutable hashed manifest registration |
| `POST /internal/v2/heartbeat` | Worker bearer; freshness observation |
| `POST /internal/v2/runs/{id}/transition` | Worker bearer; bounded lifecycle transitions |
| `POST /internal/v2/runs/{id}/snapshot` | Worker bearer; first immutable masked source |
| `POST /internal/v2/runs/{id}/report` | Worker bearer; validation/grading plus atomic completion |
| `POST /internal/v2/duties/{id}/tick/{tick}` | Worker bearer; current pause/busy policy before dispatch |

Semantic conflicts return 409; missing/wrong write identities return 403. Body
budget is 2 MiB. The session is issued by `/`; there is no cross-origin CORS grant.
SQLite schema v2 preserves v1 records. Grading is owned here, outside Ruff.

## Legacy synthetic API v1


Owns one SQLite WAL database; the Python worker never reads its tables. This is an
unauthenticated **loopback-only synthetic experiment**, not a deployment API.

| Route | Contract / effect |
|---|---|
| `GET /v1/snapshot` | `Snapshot`: at most 100 retained missions, newest first; timestamp, schema version, simulation marker |
| `POST /v1/missions` | `MissionInput`: stable ID, frozen builds, bounded fixture delay, integration comparison flag |
| `GET /v1/missions/{id}` | One `Mission`, including immutable evidence when present |
| `POST /v1/missions/{id}/transition` | `Transition`: running heartbeat, failed, cancel_requested, cancelled; completion cannot be asserted |
| `POST /v1/missions/{id}/cancel` | JSON object; records a request and fences late completion |
| `POST /v1/missions/{id}/evidence` | `Submission`: exactly six unique case/build trials, graded and retained atomically with completion |

Commands require JSON. Unknown command fields and invalid types are rejected by
Axum/Serde. Semantic conflicts (identity drift, invalid transition, wrong builds,
changed result, unknown mission) return 409 with an error object. Oversized bodies
return 413. An exact duplicate returns 200 without changing records. Errors are
not success acknowledgements.

Generate [the wire schema](../../contracts/core.schema.json) with `just contracts`.
Rust types own the contract; Python models are generated. Snapshot readers may
ignore additive fields; unsupported schema versions cannot start work or imply
health. There is no compatibility claim for future major versions.

Environment: `STARBASE_DB` defaults to `.local/starbase.sqlite`; `STARBASE_PORT`
to 8787. The listener address is always 127.0.0.1. The initial migration is
repeatable. Evidence cannot be updated/deleted through SQL without removing its
triggers. This does not protect against a machine administrator.

Recovery: restart the core using its existing file, then compatible workers on
the same Temporal database. Preserve histories and source pins. New code may
reject an old queued build; do not silently rebind it. A fresh experiment database
is independent; never call it a restore or migration of the old one.
