# ADR 0008: Declarative readiness missions in the local evaluation lab

Status: accepted

Date: 2026-09-25. Owner: runtime/evaluation. The owner authorized implementing
one bounded readiness mission after the public kind/Flux controls passed.
This decision grants no production access or inference spending.

## Decision

Keep the existing PydanticAI runtime and trusted local rehearsal coordinator.
The model receives only bounded JSON observations and can return a typed
proposal containing two HTTP probe routes, a wait decision, or abstention.
It has no filesystem, shell, arbitrary URL, manifest upload, credential, grader,
Git, or Kubernetes execution tool. Do not execute model-authored code in this lab.

Four fixed-target observation tools cover workload probes, workload events,
current worker logs, and independent job responses. Each response includes a
coordinator-issued observation identity and exact revision. Model instructions
and schema are part of the immutable build; observed text grants no authority.
A receipt is evidence provenance, not a bearer credential or permission token.

The coordinator accepts at most one proposal per new local run directory.
Before publication it rechecks cancellation, expiry, receipt freshness, exact
revision, workload generation and complete live spec digest. Only probe paths
can change. The separate verifier checks Flux and source freshness, the exact
published revision, useful work through both network paths, and stability.
The model cannot supply a verdict, XP, qualification, or a different target.

Model input/output is the candidate-controlled surface. Trusted Python tool
implementations run outside it. This is a constrained declarative boundary,
not a qualified environment for arbitrary candidate Python, plugins, tools,
repository execution, or multitenancy. The lab retains outbound networking.

## Alternatives and tradeoffs

Keeping authored controls alone verifies the lab but cannot exercise model tool
selection or diagnosis. Allowing arbitrary candidate scripts in the existing
lab would expose its coordinator and grading boundary. Extending the pinned
microsandbox boundary with a narrow RPC interface is viable when executable
candidate behavior is required, but adds guest transport and separate identity
qualification that this two-field proposal does not require.

Use PydanticAI's tool validation and usage limits, with a small trusted journal
and existing lab adapter. Add no service, database, production API, Temporal
workflow version, or world projection yet. The local journal is not the core's
mission ledger. Port this flow into core-owned durable records before any
scheduled operation or product/UI claims.

## Recovery and validation

Persist publication intent before effects. A lost publication result is marked
uncertain; the directory cannot be resumed and the proposal is not retried.
Commands check the cancellation/deadline fence before dispatch. Already-started
commands can finish; cancellation cannot undo a started local Git publication.
Owned cluster cleanup remains available after cancellation and expiry. A
coordinator crash requires independent owned-cluster cleanup and evidence review;
there is no automatic recovery scheduler in this development slice.

Use fake-model controls first, including injection-shaped observations, malformed
arguments, fabricated success, stale evidence, changed state, duplicate finish,
unknown publication outcome, and cancellation. The real cluster scripted test
checks wiring, not agent competence. Model-backed testing needs explicit inference
scope; retain every attempt and actual model/usage metadata. No lab run earns XP.
See [mission operations](../readiness-missions.md) for results and remaining gates.

Review this decision before arbitrary candidate code, production effects, shared
workers, durable scheduling, credentialed inference, or held-out comparisons.
