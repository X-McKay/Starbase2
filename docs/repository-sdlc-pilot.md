# Autonomous repository SDLC pilot

Status: accepted

Implemented locally; bounded to `X-McKay/algent`. See
[ADR 0011](adr/0011-bounded-repository-sdlc-pilot.md) for authority and boundaries.
This is the first publication capability, not qualification for arbitrary
repository repair, security review, automatic merge or production operations.

## Executable cycle

Every five minutes the worker can inspect the authorized default revision for
one opportunity: nondeterministic SQLite conversation-history ordering.
Core admits at most one active mission, with a policy limit of one to three
missions per generation and a maximum seven-day expiry. Source, runtime build,
model configuration and policy generation are frozen at admission.

Separate Qwen lead, implementer and reviewer calls exchange retained evidence.
Python 3.13.5 executes the baseline and candidate in disposable microsandbox
0.6.14 microVMs with no network, host mounts or credentials. Core compares seven
raw behavior outputs against its own oracle. Candidates cannot alter the grader.
A rejected patch is retained without execution and sent through the bounded
review/correction loop. There are at most three implementation/review rounds;
model requests are not automatically repeated after an uncertain failure.

A passing candidate and accepting reviewer permit publication of exactly three
files: the scoped persistence change, trusted public regression tests and a
pinned GitHub Actions workflow. The adapter rechecks policy and source revision
before effects. Durable one-shot claims precede branch, PR and COMMENT review
creation. An uncertain response requires provider reconciliation; it cannot
cause a blind duplicate POST. The initial publication adapter cannot merge or update existing refs; the
separately enabled correction adapter below can advance the retained pilot branch.
CI observation follows the exact submitted head for up to five minutes. The
terminal `awaiting_review` state means a human merge decision remains; it does
not award XP or imply a verified deployment.

## Local operation and interface

The existing detached monitor recognizes private `.local/github-monitor/sdlc.json`
with `repository: x-mckay/algent` and an absolute `token_file` path. This enables
V7 and local inference while leaving legacy, repair, joint, learning and memory
execution disabled. Existing fleet watch configurations remain observation-only.
The initial pilot uses the existing CLI identity through the narrow adapter;
a dedicated GitHub App is required for broader operational rollout.

Core V7 owns policy, missions, events, independent grading, cancellation and
publication claims. `/v7/snapshot` exposes bounded, typed mission summaries
(see [Bounded V7 snapshot](#bounded-v7-snapshot)); `GET /v7/missions/{id}` returns
one full retained record. The native Command Board's **SDLC missions** tab lists
summaries, reads the selected mission's full record when its summary changes, and
shows policy, stage, role handoffs, test and publication evidence, cancellation
and a full technical ledger. Unknown,
blocked and stale states remain distinct. The panel does not dispatch on travel.
Moss, Rivet and Prism project retained lead, implementation and review assignments
through the existing workstation motions. Waiting, cancellation, stale data and
revoked authority hold motion; crew inspection opens the exact V7 mission.

Operator-cookie requests can set `/v7/policy` and cancel a mission through
`/v7/missions/{id}/cancel`. A blocked, failed or cancelled mission with no
publication/effect claims may be retried explicitly using
`POST /v7/missions/{id}/retry` with a new `id` and immutable `build`. Core preserves
the parent, copies its source identity and records `retry_of`; a different build
and current capacity/authority are required. Discovery does not retry failures
or erase deduplication records automatically.

`scripts/github_monitor.py stop` stops only verified owned local processes.
Disable policy to fence new effects; already-started provider requests may still
complete and must be reconciled. Do not delete a mission or reset its claims to
retry an uncertain publication. Restart requires the same pinned build for
in-progress missions. The monitor is a local development supervisor, not a login
service or an always-on production installation.

## Validation and migration

`scripts/sdlc_integration.py` runs actual Core, Temporal and the product worker
with explicitly synthetic provider/model/VM controls. It verifies automatic
admission, independent grading, one-shot effects, hard worker/Core restart during
a durable CI timer, deduplication and workflow replay. These controls do not
establish model competence or live GitHub success; live evidence is recorded
separately under `evidence/sdlc-pilot-20260928`.

SQLite schema 9 and PostgreSQL migration 7 add the policy/mission tables.
The local supervisor takes a consistent backup before startup. An older binary
cannot open the newer database; rollback requires a compatible database backup
and reconciliation of any external effects. PostgreSQL deployment grants were
updated, but no live PostgreSQL migration or Kubernetes/Flux rollout was executed.

## Owned completion gates

- Core/runtime: add PR-comment interpretation and broader failed-check repair.
  Exact-head persistence verification/correction is implemented below; complete
  this next gate with independently tested responses to actionable comments,
  no-change/abstention cases, conflicting feedback and cancelled revisions.
- Core/runtime: generalize opportunity discovery through explicit capability
  packages and per-repository test environments. Complete with held-out positive
  and negative cases across more than this single persistence defect family.
- Runtime/operator: provision the narrow GitHub App identity and qualify continuous
  scheduling, quotas, storage retention and recovery before unattended rollout.
- World: capture a complete live multi-role physical journey through the new V7
  projection and qualify the updated export. Motion-intent, navigation, authority
  and stale-state tests pass; a live in-flight typing sequence remains uncaptured.
- Evaluation: measure multiple independent trials and held-out outcomes before
  assigning skill levels, XP, promotion or claims of general autonomous quality.


## Independent verification and PR correction

[ADR 0012](adr/0012-independent-pr-verification.md) adds an independent external
verifier while GitHub Actions remains blocked by account settings. It is enabled
locally only when private `.local/github-monitor/verification.json` contains
`{"repository":"x-mckay/algent","enabled":true}`. The supervisor sets
`STARBASE_SDLC_VERIFICATION_ENABLED=true`; other installations default off.

Every 30 seconds, the worker can inspect the current head of a retained open
pilot PR. Each head/build pair receives a durable child verification with current
policy authority. At most sixteen children per parent and one active verification
are permitted. A changed head is reverified; results from its predecessor never
count for it. A repeated unchanged head/build is not executed again. Existing
parent evidence remains unchanged, and no new schema migration is required.

The verifier downloads the pinned sources and checks the public test artifact
against its trusted version. Independent raw behavior checks and public tests run
in separate disposable VMs. Core derives passed, failed or infrastructure_blocked.
`starbase/persistence-regression` is published as a separate pending then
success/failure/error commit status, with a one-shot claim and read reconciliation.
It covers seven persistence cases, not full application CI. A GitHub Actions
failure remains separately visible and is never overwritten or relabelled passed.

An observed code failure can trigger a diagnostic lead handoff and up to three
implementation/review rounds. Implementers use pinned source line numbers; the
adapter preserves indentation and validates method scope and syntax.
Invalid proposals are retained and corrected without execution. A candidate must
improve the independent result, pass the public suite and obtain independent
review. The adapter changes only persistence source, checks the current PR head,
advances the branch without force, then publishes a COMMENT review. A new child
subsequently verifies the new published head. Infrastructure/configuration errors
stop this path without requesting a code patch. No merge or XP follows.

Full nested child records are available on `/v7/missions/{id}`; `/v7/snapshot`
carries a compact summary of each child (id, state, head, build digest, outcome).
Operator cancellation uses
`/v7/missions/{id}/verifications/{verification_id}/cancel`. Worker-only admission,
events, authorization and effect claims use the matching internal V7 paths.
The native panel shows independent verification separately from Actions, including
exact head, stage, outcome, receipts and cancellation. Prism handles verification
assignments and Rivet repairs; authority, stale, waiting and stop states hold.

Tests cover malformed evidence, public-suite failure, duplicate/uncertain effects,
changed heads, closed PRs, policy revocation, cancellation, hard restart and replay.
The [external verification evidence](../evidence/external-verification-20260928/README.md)
records synthetic controls separately from actual provider/model/VM operations.

Worker build identity is captured at module load and returned as a defensive
copy. Changing the checkout cannot relabel a running worker; new code requires a
worker restart. Failed diagnostic/implementation requests retain available usage and a bounded response
excerpt; unknown usage remains unknown rather than being assigned zero.

## Capability contracts and coordinator reservations

The [repository contract foundation](repository-capabilities.md) adds pinned
capability digests, retained crew assignment plans, dependency checks and explained
admission holds. A published/uncertain PR reserves the capability across source
revisions until a fresh closed/merged observation; active verification also holds
initial admission. Read-only PR lifecycle reconciliation never merges or awards
credit. Existing builds/histories remain distinct from new contract-aware work.
The generated V7 schema and snapshot additions require compatible Core and worker
for new admissions, with no storage migration. General discovery and multi-family
qualification remain open gates.


## Multi-family coordination update · 2026-09-28

The executable pilot now also includes memory-key and logging-level repairs, each
with six independent behavior cases and a separate trusted public regression.
[Repository capabilities](repository-capabilities.md) records current discovery,
assignment, feedback, reservation and schema behavior. History-specific details
above describe the original package, not the scope of every installed family.
[Rapid trials](autonomy-trials.md) replace the proposed 72-hour initial wait with
one control cycle capped at 15 minutes. Local validation does not activate the
monitor or expand publication authority.

## Bounded V7 snapshot

Implemented 2026-10-04. Before this change `/v7/snapshot` returned every retained
mission body unpaged, including captured sources, all stage evidence and up to 100
events of up to 128 KB each, and the native client polled it every five seconds.

`GET /v7/snapshot?limit=N&before=ID` (public loopback read, like before) now returns
the `SdlcSnapshot` type in [the V7 contract](../contracts/sdlc.schema.json):

- `schema_version: 7`, `view: "summary"`, `enabled`, `verification_enabled`,
  `policy`, `coordination` (admission state), `capability_catalog` and
  `discovery_count`;
- `missions`: at most `limit` `SdlcMissionSummary` records (default 25, 1-100;
  100 equals mission retention), ordered newest admission first by immutable
  `created_at` with id descending on ties;
- `page`: `order`, `limit`, `total`, `returned` and `next_before`. Pass
  `next_before` as `before` for the next older page. An invalid `limit` or unknown
  `before` id returns HTTP 400 rather than restarting at the first page.

A mission summary carries `id`, `state`, `repository`, `objective`, `current_stage`
(stage of the latest retained event), `revision_count`, `assigned_crew` (role to
crew from the retained plan), `created_at`, `updated_at`, `latest_event` and the
last three `recent_events` (`key`, `stage`, `at`, `label`, `role`), `event_count`,
the Core testing `verdict`, `publication` (`state` none/claimed/submitted/
awaiting_review, branch, PR number/URL and last observed PR lifecycle),
`cancel_requested`, `policy_generation`, `retry_of`, a compact `input` (no build
manifest), compact `verifications`, and `stage_evidence`:

- `plan`: the latest lead `decision`, `rationale` and `task`;
- `testing`: Core `verdict`, `grading` (`baseline_pass`, `candidate_pass`), per-case
  `baseline_cases`/`candidate_cases` (`passed` and `failed` case ids, recomputed
  against the trusted family oracle), `diff` stats (`files`, `additions`,
  `deletions`), `artifact_digest` and `validation_error`;
- `reviewing`: `status`, `rationale`, up to five `findings` with
  `findings_truncated`, and `missing_evidence`.

Null always means not recorded, not run or not interpretable; it is never an empty
success. For example `candidate_cases: null` means the candidate was not executed
or its observation was malformed, while `{"passed":[],"failed":[]}` means it ran
with no cases; `findings: null` means the reviewer did not report findings while
`[]` means it reported none. A stage is null until Core retains it for the current
revision round (a revision clears testing and reviewing). Text fields are clipped
(800 characters for rationale/task, 400 for other fields) with a trailing `…`.
Summaries are derived on read from the same record; no storage, migration or
authority changed.

Sources, raw observations, diffs, events, effects, feedback and the pinned
capability contract stay on `GET /v7/missions/{id}`. The trusted worker reads the
previous full shape from `GET /internal/v7/snapshot` (worker bearer token required)
for reconciliation, discovery, verification and Trainer reports. Deploy Core before
a worker that uses that route; an older Core returns 404 to it. The full internal
view is still unpaged and bounded only by retention (100 missions); that is a known
limit of the worker path, not of the polling clients.

