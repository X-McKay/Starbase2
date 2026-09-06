# ADR 0003: Read-only local operations in the existing core

Status: accepted

Date: 2026-09-05. Owner: Al McKay. Local implementation authorized in this task;
no production deployment or external-action authority is implied.

## Decision

Keep one Rust owner for runs, immutable snapshots/reports, public conformance
grading, duty configuration, and journal projections. Extend its SQLite schema
with an additive v2 migration while retaining the v1 experiment API and Temporal
workflow implementation. Python coordinates versioned Temporal review workflows
and durable recurring timers. The fixed analyzer is a subprocess of pinned Ruff
with masked stdin, isolated configuration, no environment credentials, and no
repository execution. A separate bounded model explanation is advisory only.

Introduce distinct local operator-cookie and worker-bearer identities for v2
writes. Keep loopback binding and explicitly retain the single-user/local-admin
trust assumption. Fixed targets and read-only tools provide the useful workflow;
MCP, agentgateway, Postgres, FalkorDB, an Effector, and a separate Evidence service
have no demonstrated requirement in this milestone.

## Alternatives and tradeoffs

Keeping only the fake campaign would not establish useful repository behavior.
Adding an LLM coding loop plus a sandbox would greatly widen the current trust
boundary before we can grade it. Fixed structural analysis is useful, bounded,
and reproducible, but it is not general PR reasoning or an exploitability verdict.
A model may explain trusted findings, with factual errors visible and separately
retained. The observed S307 hallucination justified adding authoritative rule
meanings; it did not justify accepting the model as a verifier.

Temporal Schedules are viable for calendar schedules and operational schedule
management. For one editable periodic duty, an ordinary durable workflow with
server timers, core policy checks, and continue-as-new is the smaller current
implementation. It skips busy targets and does not replay missed ticks in a
burst. Move to Schedules when calendar semantics, catch-up policies, or schedule
visibility become requirements.

The structured web journal supplies an immediately accessible command surface.
Godot remains a native projection and design candidate. The journal illustration
is authored SVG, not a second simulation engine. Neither view owns task state.
Godot web delivery still needs a measured implementation before selection.

## Evidence, rollout, and review triggers

See [operations evidence](../operations.md). Tests cover v1 migration, immutable
completion, idempotency, late-result fencing, paging, malformed/incomplete scope,
credential boundaries, real analysis, replay, timer recovery after Temporal and
worker restart, and no-change retention. Two permitted inference endpoints were
exercised with all pilot attempts retained; general quality remains inconclusive.

Build manifests pin effective source/tool/configuration inputs, not a hosted
provider's weights. Open work requires a compatible worker; production version
routing is not implemented. Migration is additive and preserves v1 records;
rollback uses a pre-migration backup, not SQL downgrades. Split owners or replace
SQLite when independent trust, concurrent deployment, measured storage/throughput,
or operational recovery requirements demand it. Arbitrary code, production
credentials, and write effects require a separately implemented isolation boundary.
