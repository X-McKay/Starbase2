# Local operations edition

Status: accepted

Implemented on 2026-09-05 under the owner's authorization to continue local
implementation and test Ollama and `llm.almckay.io`. This is a functional local
operations product, not the complete production vision in SPEC.md.
The [repair extension](repairs.md) adds isolated synthetic writes and earned
progression; repository review itself remains read-only.

## What works

Run `mise exec -- just bootstrap`, then `mise exec -- just dev` and
`mise exec -- just world`. Use Godot's Journal/Operations (`J`) for reviews,
comparisons, local review duties and history; Command (`B`) provides field
observations, repository watches, configured field duties and retained advice.
Connection (`O`) selects the private local Core endpoint. The former browser
dashboard is retired; `/` is a noninteractive API connection page. No model call
happens merely on startup; previously enabled duties continue independently.

- Start a real review of Python files in this checkout or an explicitly synthetic
  training repository. The core freezes the registered build; Temporal orchestrates
  snapshot acquisition, static analysis, optional advice, and evidence retention.
- Inspect line-level findings against retained, masked source, exact build
  manifests, timestamps, and the lifecycle journal. Retained evidence survives
  both core and worker restarts. Repeating an identical snapshot/build records
  `no_change`, with the preceding run linked; warnings remain visible.
- Compare Surveyor v1 against v2 or a deliberately regressed control in the gym.
  Six public cases produce twelve interleaved trials. Rust grades the individual
  outputs; the candidate Ruff process has no grader or core credential.
- Enable a recurring review every 30 seconds, 5 minutes, or 30 minutes. A Temporal
  workflow owns the durable timer and continues as new every 100 ticks. There is
  no browser timer or in-memory scheduler. The first review occurs after the
  interval. A busy target skips the tick instead of growing a backlog.
- Pause/resume the duty and stop individual runs. Pause changes core policy
  immediately, then the worker reconciles the durable timer. Already dispatched
  work is separate. Stops fence late report submission and await Temporal
  acknowledgement; an already started read/model request cannot be retracted.
- Browse pages of twenty historical runs independently of the active dispatch
  feed. Twenty pending runs is the current queue budget, not an archival cap.
- Godot includes structured controls and retained evidence alongside the colony.
  Keyboard navigation does not require walking to a room. Crew poses remain
  decorative projections; labels use authoritative records.

Surveyor and Trainer have stable role identities and completion counts derived
from retained records. Custom crew creation, persistent personality/memory,
build promotion and permission management are not implemented. Their counts are
completed runs, not verified security outcomes. The separate Mender identity,
cosmetic XP, achievements and exact-build repair qualifications are now persisted
by the [repair extension](repairs.md).

## Review boundary

Only `.py` files under the configured local workspace or shipped fixture root
are considered. The snapshot budget is 200 files and 1 MB of original source.
Hidden directories, virtual environments, build outputs, and symlinks are
excluded. Budget, encoding, parse, and analyzer failures remain explicit;
empty or incomplete scope cannot produce a clean certificate. All reviews are
advisory even when every configured check passes.

Python string literal contents and comments are masked before retention. Source
hashes preserve identity and line numbers support citations. This is structural
redaction, **not a general secret detector**: identifiers and numeric literals
remain. Use an authorized checkout. The local filesystem is trusted against
concurrent hostile directory replacement; this is not an arbitrary-code sandbox.
The tool process receives only masked stdin, an empty environment, isolated Ruff
configuration, no fixes, and a ten-second per-file limit. It never executes the
repository's code or follows its tool configuration. Ruff 0.16.6 is locked and
its executable hash is included in the build manifest.

The default profile checks mutable defaults, bare exception handlers, unsafe
`eval`, subprocess shell use, unsafe YAML/pickle loading, disabled certificate
verification, and missing HTTP timeouts. It does not review Rust, resolve a PR
diff, verify runtime exploitability, or establish repository safety. The training
repository is also within this checkout; its intentional warnings are naturally
visible in a whole-checkout review.

## Inference

The optional checkbox is enabled only for the training repository. The provider
receives rule codes, trusted rule meanings, file count, and incomplete-coverage
status. It receives no repository source, filenames, prompts from comments,
credentials, or tool authority. Advice is separately labeled unverified, never
used for grading, XP, or permissions. A malformed/truncated/failed response is
retained as unavailable without automatically retrying the request. Static
analysis remains usable without inference.

Default: `https://llm.almckay.io/v1`, `Qwen3.6-35B-A3B-NVFP4`, temperature 0,
800 output tokens, one call, 60-second request timeout. To use the tested Ollama
model, restart the local launcher with:

```sh
STARBASE_INFERENCE_URL=http://127.0.0.1:11434/v1 STARBASE_MODEL=qwen2.5-coder:7b mise exec -- just dev
```

Only those two development endpoints are allowed. No API key is needed by the
observed endpoints. HTTP model aliases are not immutable weight revisions;
requested/reported models, provider fingerprint, usage, latency, and unknown
monetary cost are retained. Reproducible configuration is not a guarantee of
bitwise hosted inference. The direct HTTP adapter serves a bounded explanation
request; the earlier PydanticAI Temporal experiment remains available as v1.

## Evidence and interpretation

The [first operations experiment](../evidence/operations-first/events.json)
passed real orchestration checks in 44.097 seconds: paired grading, replay,
immutable source/report retention, operator/worker credential separation,
worker-loss freshness, cancellation before dispatch, worker plus Temporal
restart during a timer, pause fencing, and core restart. It also retained a
real model factual failure: codes alone caused S307 (`eval`) to be described as
pickle/YAML deserialization. Infrastructure success was not model correctness.

The [predeclared inference pilot](../evidence/inference-pilot-1788600022164283000/protocol.json)
used three public cases per endpoint, one interleaved pair per case, twelve calls
total, no retries or discarded trials. [All outputs and grades](../evidence/inference-pilot-1788600022164283000/trials.json)
are retained. With code-only prompts the hosted model passed 2/3 and Ollama
1/3 narrow factual smoke gates. With supplied rule meanings both passed 3/3.
This supports including source-grounded meanings in the prompt. It is an
exploratory pilot with insufficient evidence for general superiority, equivalence,
or production qualification; the keyword grader is not a semantic quality judge.

The deterministic gym observed v1 5/6 versus v2 6/6 and v1 5/6 versus the
regression control 4/6. These are exact outcomes on the declared public suite,
not estimates of broader defect detection. Equal case scores are inconclusive.
Invalid infrastructure and hard-gate failures remain separate outcomes.

## Persistence and recovery

[ADR 0003](adr/0003-local-operations.md) records the local boundary. The Rust core
owns all product SQLite tables. Schema v2 migrates v1 in place and preserves old
missions/evidence; an older core rejects the newer schema. Back up both SQLite
stores using SQLite backup facilities or stop the launcher before copying the
files. Rollback requires the previous binary and a pre-migration backup; do not
force an older core to open the new schema. No destructive automatic retention
or cloud backup is configured.

Retained JSON bodies are parsed with correctly rounded float decoding
(`serde_json` `float_roundtrip`). Before 2026-09-07 a stored `f64` timestamp
could read back one ULP away from the value just written, so an exact repeated
transition or resubmission could be misjudged as a change; the Linux onboarding
record retains the failing check and the deterministic regression test.

A launcher-created 0600 token file authenticates internal v2 writes. Operator
commands require an HttpOnly, SameSite=Strict session cookie; cross-origin
browser writes are rejected. Loopback read APIs are accessible to the local user.
The v1 synthetic experiment API remains separately available and unauthenticated;
it cannot create v2 work or act on a repository. This is a single-user local
trust domain, not multi-tenant authorization or protection from a local admin.

Source/code/dependency/tool/prompt/configuration hashes distinguish new builds.
Start new work after rebuilding and restarting the worker. If an open run reaches
analysis on an incompatible worker, it fails explicitly; no silent build upgrade.
Production worker version routing and long-lived mixed-build deployment remain
unimplemented. Re-run deliberately with the current build from the inspector.

## Remaining completion gates

| Owner | Material remaining work | Completion condition |
|---|---|---|
| Runtime implementation | Active model/tool crash and ambiguous inference reconciliation | A provider-side request ID or durable request ledger proves no duplicate request after transport uncertainty |
| Agent/evaluation implementation | Useful PR-diff reasoning and hidden scenario families | Representative sanctioned diffs, calibrated independent grader, isolated candidate, powered comparison |
| World implementation | Godot web export and richer character interactions | Matching templates, same-origin serving, measured native/web comparison and operator usability evidence |
| Product/core implementation | Custom persistent crew and earned progression | Identity/configuration records, independently verified deduplicated awards, zero permission coupling |
| Platform implementation | Kubani observation deployment | Scoped identities, immutable images, resource budgets, backup/restore and emergency stop tested before deployment |

No cluster operation, repository mutation, review publication, dependency change
in another project, or external notification was performed.

Final validation: the [v2 recovery run](../evidence/operations-final/events.json)
passed in 53.968 seconds, including a real hosted explanation with the corrected
rule context. [Legacy v1 compatibility](../evidence/legacy-compatibility-final/events.json)
passed in 42.533 seconds. The final source checks passed 21 Rust and 12 Python
tests, Rustfmt/Clippy, Ruff/ty, generated contract drift, documentation validation,
JavaScript syntax validation, and workflow actionlint. GitHub CI itself was not
run remotely. Browser checks exercised actual review/comparison submission,
evidence inspection, disconnect state, and 390px layout without page overflow.
Native [normal](../evidence/world-operations.png) and
[compact](../evidence/world-operations-compact.png) captures were inspected. A
long-ID overflow found in the first capture was fixed by bounded text layout.
These are functional/visual smoke checks, not performance or accessibility
certification, cross-platform coverage, or a Godot web-export result.

## Additive installation policy metadata

The v2 snapshot now includes optional typed `installation` metadata: `id`,
`environment`, and `capabilities`. The capability keys are `accept_work`,
`review`, `evaluation`, `repair`, `field`, `memory` and `inference`; each contains
`enabled` and a human-readable `reason`. Older snapshots without metadata remain
valid. Missing metadata means unknown policy, not disabled or authorized work.

This describes the Core installation's configured flags, not worker readiness,
loaded-build compatibility, provider permission or target health. Existing
worker/build/target records retain those separate meanings. Quiescing disables
new dispatch; it does not disable cancellation, inspection or memory approval.
The `memory` capability describes configured reviewed recall and does not promise
a reachable graph. Deployment must configure Core and worker consistently.
No credential, remote authentication or additional authority is introduced.

The [shared rollout fixture](../contracts/fixtures/operations-installation.json)
shows enabled policy with an unavailable worker. Rust policy tests use injected
configuration rather than mutating process environment; Python wire tests accept
both old snapshots and additive fields.

## Live event stream (v8)

Implemented 2026-10-04. Clients previously learned about every change by polling,
and nothing inside a long SDLC stage (model calls and sandbox runs of two to three
minutes) was visible until the activity posted its stage event.
`GET /v8/events` is a loopback, unauthenticated Server-Sent Events stream
(`text/event-stream`) like the other public GET routes. It reports **that** a
record changed and when; the record routes stay authoritative and a client must
refetch them (`/v7/snapshot`, `/v7/missions/{id}`) rather than rebuild state from
events. The stream adds no service, datastore or authority.

Every frame's `data:` is one JSON object. Record frames use SSE `event: record` and
an `id:`; their data is the `StreamEvent` type in
[the V7 contract](../contracts/sdlc.schema.json):

```json
{"id":"18f0c2a7d3e4b5a6-42","epoch":"18f0c2a7d3e4b5a6","seq":42,
 "type":"mission.stage","family":"v7_mission","record_id":"sdlc-0123abcd",
 "at":1790000000.25,"retained":true,
 "payload":{"key":"review-1","stage":"reviewing","state":"reviewing",
            "label":"reviewing · reviewer · accept","role":"reviewer",
            "revision_count":0,"verdict":"improved"}}
```

| `family` | `type` | `payload` |
|---|---|---|
| `v7_mission` | `mission.admitted` | `state`, `opportunity`, `retry_of` |
| `v7_mission` | `mission.stage` | `key`, `stage`, `state`, `label`, `role`, `revision_count`, `verdict` |
| `v7_mission` | `mission.cancel_requested` | `state` |
| `v7_mission` | `mission.publication` | `state`, `publication: "claimed"`, `branch` |
| `v7_mission` | `mission.effect` | `kind`, `key` |
| `v7_mission` | `mission.pr_observation` | `pr_state`, `changed` |
| `v7_mission` | `mission.feedback` | `head` |
| `v7_mission` | `verification.admitted`, `.stage`, `.effect`, `.cancel_requested` | `verification_id` plus stage/state/outcome/kind |
| `v7_mission` | `mission.activity` (transient) | an activity note plus the mission `state` |
| `v7_policy` | `policy.changed` (`record_id: "pilot"`) | `generation`, `enabled`, `publish`, `max_missions`, `expires_at` |
| `v7_discovery` | `discovery.observed` | `opportunity`, `outcome` |

Other families (v2-v6) are not yet emitted; their clients keep polling.
Events are published only after the corresponding write commits, and only when
something changed (an idempotent replay emits nothing). Payloads over 4 KB are
replaced by `{"truncated":true}`.

Control frames have `event:` equal to their `type`:

- `ready`: sent once per connection after any replay, with `id:` set to the current
  cursor and `{"type":"ready","epoch","cursor","at","oldest_retained","replayed",
  "heartbeat_seconds":5,"retained_capacity":1000}`. It also sets `retry: 3000`.
- `reset`: `{"type":"reset","reason","epoch","cursor","at"}` with `id:` set to the
  cursor. The client cannot be brought up to date from the buffer and must refetch
  its snapshots. Reasons: `buffer_exceeded`, `epoch_changed` (Core restarted),
  `unknown_position`, `invalid_id` and `lagged` (a slow client overflowed the
  256-event live channel).
- `heartbeat`: every 5 seconds, with no `id:`, `{"type":"heartbeat","epoch",
  "cursor","at"}`. Use `at` and arrival time to measure freshness; three missed
  heartbeats should be treated as a disconnected or stale stream.

Ids are `<epoch>-<seq>`. `seq` increases by one for every published event,
including transient ones, so gaps are normal. The epoch is chosen when Core starts.
Resume with the standard `Last-Event-ID` header (sent automatically by reconnecting
EventSource clients) or `?after=<id>`; the header wins when both are present. Core
replays retained record events newer than that id, then sends `ready`. With no id,
the stream starts live from `ready`. The buffer keeps the newest 1,000 record events
in memory only. A Core restart, an evicted position or an id from another epoch
produces `reset`, never a silent gap. Graceful Core shutdown closes open streams.

### Worker activity notes

`POST /internal/v7/missions/{id}/activity` (worker bearer token, like other
internal routes) accepts one typed `ActivityNote`:
`kind` (`model_request_started`, `model_request_finished`, `tool_started`,
`tool_finished`, `sandbox_boot`, `sandbox_finished`) and optional `role`,
`verification_id`, `tool`, `label` (sandbox name), `request`, `ok`, `error`
(`tool_error`, `truncated` or an exception class name, never message text), `input_tokens`,
`output_tokens` and `elapsed_ms`. Text fields are limited to 80 printable ASCII
characters and unknown fields are rejected. Core returns 409 for an unknown or
stopped mission. A note is broadcast as `mission.activity` with `retained: false`.
It is never written to the mission record or its 100-entry `events[]`, and it is
not replayed on resume. Notes are observations, not evidence; retained receipts
and Core grading remain the evidence.

The SDLC runtime binds the mission when an activity first reads its record and
posts notes at model request boundaries (`agents/sdlc/factory.py` and the legacy
single-request path in `sdlc_pilot.py`), at workspace tool dispatch
(`sdlc_workspace.py`) and around microVM execution (`sdlc_sandbox.py`). Posting
is best effort: each note is a detached task with a 1-second timeout, failures are
logged at INFO and dropped, at most 16 notes are in flight, and a worker without a
token file posts nothing. A note can never fail, block or retry the activity.

Limits: the buffer is per Core process and not persisted; a single local Core is
assumed (no multi-replica fan-out); the stream has no per-client authorization
beyond the loopback boundary; and the native client does not consume it yet.

