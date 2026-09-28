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

## V5 joint readiness simulations

`STARBASE_JOINT_ENABLED=true` opts a non-production installation into bounded
readiness investigations. `STARBASE_ACCEPT_WORK=false` stops admission and new
member dispatch; production always denies V5. V5 introduced SQLite schema 6 and
PostgreSQL version 4; the V6 section below documents the current schema 7/version 5.
PostgreSQL requires the explicit migration job, with checksums.
Back up and stop the installation before migration. Older binaries reject the new
schema; recovery uses a compatible binary or the backup, not a down migration.

Operator session routes expose `/v5/snapshot`, `POST /v5/missions`, mission detail
and cancellation. Worker credentials authorize immutable build registration,
member reservation, one-time claim, retained result and finish endpoints below
`/internal/v5`. See `contracts/joint.schema.json` for wire types. Snapshot retention
is bounded to 100 missions and 100 builds; reaching that limit rejects new records
without deleting historical evidence.

Core binds each mission to a registered build and inference mode, deduplicates
opportunities, and reserves one request plus the entire token grant before every
member dispatch. Duplicate task identities must carry identical inputs. Claims
cannot dispatch twice. An uncertain provider call consumes its full grant and
cannot qualify the mission. Known usage above a grant is retained but ineligible.
Reservations are never refunded. Any reported child overrun or exhausted root
accounting fences both new reservations and claims of already-reserved peers;
known overruns and failed replies remain retained. Cancellation immediately fences further dispatch,
while late replies remain recordable for accounting. A worker must reconcile every
claimed member before finishing an uncancelled mission.

Finish independently checks the public scenario, current synthetic receipt and
revision, the supported probe paths, specialist completion, deadline and accounting.
The submitted final decision must exactly match the latest retained lead response,
with its round after all specialist rounds. Malformed role output remains inspectable
but ineligible. Inference requires positive reported input and output usage; missing,
zero or overflowing usage consumes the full grant and cannot establish success.
The result is only `diagnostic-pass`, `diagnostic-fail` or `unresolved`; these public
simulations award zero XP and never authorize Git or Kubernetes effects. This is
not production repair qualification. ADR 0009 records the boundary and review
triggers for extending it.

### Trainer review opportunities

V5 snapshots include an additive `opportunities` array, derived on every read from
retained failed or unresolved public simulations. This read-only projection groups
exact build, scenario and failure category under a stable hashed identifier;
re-reading a snapshot does not create records or increment observations. Each
proposal retains source mission IDs, scoped task IDs, observed count, consumed token
accounting and the most recent source update. Separate immutable builds remain
separate groups. Successful or active investigations produce no failure proposal.

Categories distinguish a diagnostic mismatch, malformed response, unknown usage
or dispatch, a repeated task request, exhausted budget, and otherwise incomplete
work. Classification uses authoritative outcomes, retained structured task records,
accounting and recognized runtime exception types. A known child overrun or
exhausted root accounting produces `budget-stop`; unknown usage keeps its own
category. Freeform model rationale cannot
choose a category. For this profile, identical role and focus mean identical public
observation scope; rephrasing the question does not make a new investigation.
Unsupported causes remain `incomplete`; a review opportunity is
neither proof of an agent defect nor a qualification. Cancellation and infrastructure
loss may warrant review without implying deficient agent capability.

`tokens_accounted` includes consumed grants for unknown requests; `usage_unknown`
marks those amounts as accounting bounds rather than measured model usage. The
aggregate is null with `accounting_overflow=true` if it exceeds the wire integer
range; exact per-mission amounts remain retained. Stable ID ordering is not a
priority or utility ranking. These proposals inspect only the retained public
simulation population and cannot establish general reliability or training gain.

This adds no table, service, scheduler or Trainer duty. It creates no candidate,
campaign, training run, adoption decision, authority or XP. A generated V5 contract
change alters subsequent runtime build identities; prior evidence remains bound to
its original build and transfers no qualification. Automated candidate generation,
matched evaluation, prioritization and controlled adoption remain separate delivery
gates in the autonomous RPG plan.

## V6 local developmental learning

`STARBASE_LEARNING_ENABLED=true` additionally opts into the disabled-by-default
`readiness-practice` duty. Production remains denied. SQLite schema 7 and explicit
PostgreSQL migration 5 add only `learning_control` and `learning_cycles`. V5 builds
and missions retain candidates and paired trials. See ADR 0010 for the accepted
boundary and `contracts/learning.schema.json` for the generated contract.

Operator routes: `GET /v6/snapshot`, `POST /v6/duty`, `GET /v6/cycles/{id}` and
`POST /v6/cycles/{id}/cancel`. A duty write needs generation zero initially, then
the current generation plus one; exact retries return the same control record.
Ordinary duty updates name the current practice incumbent. To rebase after a local
upgrade, first disable the existing duty and reconcile/cancel its cycles and all
claimed requests. Then submit a new generation with `enabled:false` and a different
registered `joint-readiness-v1` baseline. Core increments the practice pointer,
clears `source_cycle`, and appends a `control.rebases` receipt containing
`previous_build`, `build`, `duty_generation`, `incumbent_generation`, and `at`.
Exact retries retain that receipt. Enabling is a separate next-generation write.
Rebase preserves old missions/cycles and transfers no qualification; the receipt
list retains at most 100 rebases. Scripted and inference baselines are both allowed,
with runtime source pins and inference opt-in still enforced at dispatch.
Worker-only routes
under `/internal/v6` select a bounded duty tick, claim/retain one Trainer response,
admit frozen trial slots, and finalize from Core evidence. The complete proposal
and eight trial grants reserve at admission; no model can request extra capacity.

Worker recovery uses `POST /internal/v6/cycles/{id}/reconcile-stop` with `{}` to
settle a stopped, superseded, expired or otherwise ineligible cycle even if its
Temporal workflow was never created. Core rejects this route for an eligible
active cycle. It returns the full cycle, repeats child cancellation for already
cancelled cycles, and preserves completed/failed results. Unknown or late claimed
requests still require retained accounting; cancellation does not assert they
never started. Repeated cancellation repairs an interrupted parent/child cascade.

Each cycle freezes source evidence and its original build separately from the
current baseline. The evidence fingerprint is consumed once per duty generation,
even after a practice adoption. Compatible historical failures can bootstrap a
new source-pinned baseline. Default limits are two cycles, a 60-second cooldown,
one 32,768-token Trainer request, and eight V5 trials of at most 24 requests and
384,000 tokens each. Trials follow the retained counterbalanced order. Procedure
text is limited to 12,000 bytes; no code, tools or grader permissions change.

Finalization records raw outcomes and independent comparison pass/fail/invalid
statuses. Known malformed model responses can count as failed baseline/candidate
trials; unknown/infrastructure failures, wrong parent/build/scenario, cancellations
and overruns block adoption. Exactly reaching a grant is allowed in grading but
cannot authorize another request. Core's immutable policy digest fences mixed
implementation continuation and adoption. Successful developmental policy changes
only `practice_incumbent`, atomically with the final record. It awards zero XP and
establishes no held-out qualification, statistical superiority or production
clearance. Existing V5 missions never change builds.
