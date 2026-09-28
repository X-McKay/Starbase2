# Durable joint readiness investigations

Status: proposed

Owner: Core/runtime. Implementation date: 2026-09-27.

## Implemented behavior

V5 adds a bounded joint investigation to the existing Core and Temporal worker.
A lead requests workload and service specialist findings, can run those tasks in
parallel, and can ask for additional diagnostic evidence before proposing an
outcome. Each role is a separate PydanticAI agent with a typed output contract.
The workload role can inspect overview or diagnostic observations; the service
role checks actual response values, separately from Ready status.

This path currently uses **public sanitized simulation observations**. It does
not observe a running cluster, publish a Git change, establish useful-work
recovery, earn XP or qualify a build. The preexisting
[owned-lab mission](readiness-missions.md) remains the real kind/Flux path.
[ADR 0009](adr/0009-durable-readiness-coordination.md) records the boundary.

## Durable identity and limits

Core owns the immutable build, opportunity and mission identities. The current
build inventory pins all top-level runtime modules, worker composition, the shared
Core request adapter and nested readiness resources, plus dependency locks.
Changed input
under an existing identity is rejected. An exact repeated start returns its
existing mission; changing the mission ID under the same opportunity conflicts.
Before dispatch, each member task reserves one request and a
32,768-token grant against its root allowance. Reservations are not refunded;
actual usage is retained separately. Unknown usage consumes the whole grant.
The lead is charged through the same ledger as its specialists. A reported
child overrun fences all later reservations and claims, including a peer that
was reserved but has not started. Accounting retains the reported overrun;
stopping subsequent calls cannot undo provider usage already incurred.

Default integration missions have 12 requests, 384,000 reserved tokens, four
coordination rounds and a ten-minute deadline. Each call has a 2,048 output-token
limit and a 65-second activity-side deadline. A conservative serialized-input
check includes the output schema and framing before provider dispatch. These are
resource fences, not a cost estimate or claim of optimal budget calibration.

A member dispatch claim is one-shot. Retry after a saved reply reads that reply;
retry after a claim with no saved reply records an unknown outcome and cannot
silently make another model call. The workflow records failures and ends without
success when the evidence or budget is insufficient. Cancellation stops new
claims immediately; already-started calls may finish and report usage. Terminal
workflow reconciliation accounts for claims with no retained reply as unknown.

Temporal V5 retains sequencing and replay history; Core retains product intent
and accepted results. Existing V1–V4 histories remain supported. Candidate models
receive sanitized observations and role findings, never worker credentials or
an effect tool. Findings and even a correctly shaped final decision are not a
verdict: the Core independently grades the public diagnostic contract. A result
of `diagnostic-pass` means that diagnostic contract passed, not that a service
was repaired. A failed or unknown member prevents a passing mission.

The model-facing lead schema chooses an action first, then normalizes it to the
persisted plan/decision contract. Native JSON schema constrains each specialist
role to its supported evidence scopes. Trusted task contracts define what each
scope can establish; a lead's question cannot broaden it. A repeated role/scope
request ends the simulation because it would inspect unchanged observations,
even if the lead rephrases the question. Models may still misunderstand evidence
or choose a wrong action. Schema validation does not establish diagnostic quality.

## Trainer review and game presentation

The snapshot derives read-only Trainer opportunities from retained terminal
failures. Exact build, public scenario and evidence-backed category determine a
stable group identity; repeated reads do not create new observations. Groups
retain source mission/task IDs, accounting (including unknown-usage grants),
timestamps and a proposed investigation. Unsupported failure causes stay
`incomplete`, rather than being guessed from model-written rationale.

This is automatic failure discovery from durable records, not a Trainer duty:
there is no prioritization, scheduler, candidate generation, campaign, training
or adoption. Groups are reconstructed from the retained mission window, not a
separate permanent backlog. The local ledger admits at most 100 missions and
100 builds; reaching either cap requires an explicit retention/migration design,
not silent eviction. [Joint operations](joint-operations-view.md) exposes
the mission evidence and proposed review in the native game.

## Measured development evidence

The real Core/Temporal scripted controls passed all four public scenarios,
duplicate/conflicting starts, bounded exhaustion, worker/Core replacement after
a retained reply, cancellation and replay. The final frozen Qwen development
build passed one of four cases; one was unresolved and two failed the independent
diagnostic check. All four used model-selected lead/specialist coordination.
The supported readiness fault produced a correct repair proposal in four calls.
The other outcomes prevent any claim of reliable live action selection.

[The retained evidence](../evidence/autonomous-rpg-20260927/README.md) includes
every development build and failed/incomplete cohort, per-task resource use and
the final 18,486-token four-case result. These public trials had no paired solo
baseline or unseen holdout. Subsequent source changes create new builds and do
not inherit this evidence as qualification.

## Running local checks

`just test-joint` launches isolated loopback Core/Temporal processes and a test
worker. It checks four public scenarios, duplicate/conflicting starts, a root
budget stop, Core/worker replacement after a saved reply, cancellation before
dispatch and workflow replay. It retains histories, mission records, logs and
failures under `.local/joint-integration-*`. The production worker registers the
same workflow and activities when local joint work is enabled.

`just joint-pilot` explicitly uses the configured local Qwen endpoint on the same
four public scenarios, one trial each. Its declaration freezes the build and
allowance before calls. It retains every outcome, response, usage and latency.
This is an exploratory coordination smoke, without a solo baseline or hidden
qualification cases; it cannot establish superiority or promotion eligibility.
No automatic fallback changes a failed inference trial into a scripted one.

V5 admission requires `STARBASE_JOINT_ENABLED=true` and an installation accepting
work. Production always rejects it. `STARBASE_INFERENCE_ENABLED=false` fences
inference admission. Operator commands use the existing session identity;
internal dispatch uses the existing worker credential. See the
[Core API reference](../services/core/README.md) and
[generated schema](../contracts/joint.schema.json).

The worker's V5 flag controls build registration and reconciliation participation;
it is not an emergency-stop substitute. Stop admission at Core or cancel the
mission through the operator API, and retain a worker for accounting and terminal
reconciliation. Disabling only worker reconciliation can leave records pending.

## Storage and rollout

SQLite migrates to schema 6; PostgreSQL has a separate checksum-verified migration
4. The production migration bundle and runtime SQL grants include the new ledger,
while the feature remains disabled. No production migration or deployment is part
of these local checks. Back up existing data; rollback requires a compatible Core
or restoration into a separate database. There is no destructive down migration.
PostgreSQL migration execution still needs its isolated database rehearsal.

The [full delivery plan](autonomous-rpg-delivery.md) keeps live lab sources and
uncertain Git publication reconciliation, continuous improvement, paired learning
campaigns, qualification/adoption, and the remaining Commander experience open.
