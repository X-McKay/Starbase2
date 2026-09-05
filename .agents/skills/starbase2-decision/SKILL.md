---
name: starbase2-decision
description: Reconsider or record consequential Starbase2 service, language, datastore, trust-boundary, or migration choices. Use for architectural tradeoffs; ordinary implementation choices and small refactors do not need an ADR.
---

# Make the important choice explicit

Start with the user's desired outcome, constraints, current evidence, and
decision being made. Predecessor plans and Starbase2 proposals are hypotheses,
not proof that a specific architecture must survive. Read only the relevant
existing decision and [architecture](../../../docs/architecture.md).

Compare maintaining the current approach, the simplest sufficient change, and
a materially different viable option. Include uncertainty, operating cost,
developer effort, compatibility, recovery, and an exit path. Do not manufacture
numeric scores or straw alternatives. Rust, Godot, graphs, and microservices
must be useful in context; novelty is not evidence.

When uncertainty decides the outcome, propose or run an authorized bounded
experiment with a representative workload, success threshold, budget, and stop
condition. Prefer disposable local evidence to production experimentation.

Record a concise ADR only when the choice is consequential or expensive to
reverse. Include owner, status, date, decision, rationale, viable alternatives,
tradeoffs, validation limits, rollout/exit, and review trigger. Reserve the next
identifier at creation; do not rewrite accepted history.

Reconcile affected product docs when a decision changes. Distinguish draft,
proposed, and accepted status without demanding redundant permission already
present in the conversation. Record owner authorization for acceptance; an ADR
alone grants no live deployment, migration, spending, or external action.

Handoff: recommendation or decision, the evidence that could change it, material
tradeoffs, and concrete next implementation or experiment. Do not turn the ADR
into another copy of the engineering charter.
