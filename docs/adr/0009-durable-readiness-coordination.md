# ADR 0009: Durable bounded readiness coordination

Status: accepted

Date: 2026-09-27. Owner: Core/runtime. Authorization: Al requested implementation
of the autonomous RPG plan, with autonomous multi-agent coordination as a required
outcome. This authorizes local implementation, not production activation.

## Decision

Extend the existing Core ledger and Temporal worker with an additive V5 readiness
investigation. One lead selects workload and service specialist tasks, consumes
their typed findings, and chooses follow-up work or a bounded proposal. Specialist
findings are evidence-bearing advice, never verification or operational clearance.

Core owns immutable input/build identity, opportunity deduplication, child budget
reservations, dispatch claims, retained replies, cancellation and final diagnostic
grading. Temporal owns sequencing and replay. Reserve against the root before
fan-out; account for every failed or uncertain request. Never retry an uncertain
provider request under a fresh budget. A resumed activity uses its saved reply or
records an unknown outcome. It cannot silently repeat the provider call.

The first implemented code path is an explicitly labeled public simulation using
sanitized observations. It has no Git/Kubernetes write adapter, grants zero XP,
and cannot qualify a crew member. The existing owned lab remains the place to
validate actual Flux and useful-work effects. Completion of a diagnostic simulation
does not complete the proposed production repair mission.

## Alternatives and tradeoffs

Keeping only the local one-shot journal cannot support durable product intent or
shared worker recovery. A new coordination service or generic swarm framework
would add ownership and operational cost without a new trust boundary. Extending
Core and Temporal reuses existing authentication, migrations and recovery tools.
Conservative reservations may leave tokens unused; this is preferable to treating
lost usage as free. A failed member may consume its whole grant.

## Compatibility and recovery

V1–V4 workflows and APIs remain unchanged. V5 is opt-in and production admission
is disabled. The additive schema requires an explicit PostgreSQL migration;
SQLite migrates locally. Older binaries reject newer schemas. Recovery uses a
compatible binary or a backed-up database, never a destructive down migration.
Cancellation fences new claims immediately and preserves late usage/results.

## Validation and review triggers

Exercise duplicate and conflicting inputs, root overcommit, dispatch loss,
malformed output, late replies after cancellation, worker replacement and replay.
Use fake models before local Qwen. Public scripted controls establish wiring,
not learned competence. Review this decision before live sources, external effects,
qualification/adoption, shared mutable memory or arbitrary candidate code.
