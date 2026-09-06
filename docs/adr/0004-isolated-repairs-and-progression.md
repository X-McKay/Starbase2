# ADR 0004: Existing microVM runtime, bounded repairs, and verified cosmetic credit

Status: accepted

Date: 2026-09-05. Owner: Starbase2 engineering. Authorization: the owner requested
implementation of isolation, repair workflows, and progression, explicitly
asked for an open-source sandbox survey, and deferred Kubernetes deployment.

## Decision

Keep one Rust core and the trusted Python Temporal coordinator. Use pinned
microsandbox 0.6.14 through a small CLI adapter for model-authored code. Add no
sandbox control-plane service, datastore, gateway, plugin framework or effector
service. See the [landscape comparison](../sandbox-survey.md).

The first operational write boundary is a disposable synthetic `solution.py`
inside a VM. The proposal is immutable before execution. The core owns revision,
expiry, allowed action stages, attempt budgets, evidence retention, grading,
and credit. No action can address a host path or production resource. There is
no promotion to external authority. Inference happens outside the VM using only
a shipped task and its seeded source; no host credentials enter candidate code.

Temporal V3 orchestrates one proposal, baseline and candidate executions, and
core finalization. Existing V1/V2 workflow definitions remain supported. The
core authorizes each attempt immediately before dispatch. A retry first removes
its stable VM identity, then re-executes the same immutable input. This is safe
because all effects are disposable and no outbound effects are permitted. A
lost proposal response is not silently inferred or retried. An interrupted
execution may have happened even if its response was lost; attempts remain
visible. Cancellation fences future authorization and waits for cleanup.

The grader compares returned values with expected answers in Rust. Candidate
code receives input cases but no grader, expected-answer file, token, or core
connection. Successful process exit or an agent assertion cannot certify success.

Persist Mender's identity separately from builds. Award 25 cosmetic XP once per
scenario and original revision, only for an AI proposal that improves a failing
baseline and passes every check. Deterministic controls, repeats, failed and
inconclusive results receive no credit. Persist qualification by exact build
and scenario separately. Level 2 starts at 50 XP; this provisional display rule
is not an empirical proficiency threshold. No level changes permissions.

## Alternatives and consequences

Keeping a host subprocess would not isolate model-authored code. Building a VM
runner from lower-level primitives would duplicate existing maintenance work.
CubeSandbox/OpenSandbox offer deployment capabilities whose servers and fleet
machinery are unnecessary in this local scope; they remain viable alternatives.
A separate evidence or action service adds distributed transactions without
an independent owner at present.

SQLite migration 3 adds repair records, persistent crew, credits and build-scoped
qualifications; final verdict and deduplicated credit commit atomically. Older
cores reject the newer database version. Back up the local database before
rollback; no down migration is supplied. Earlier V2 data remains readable.

## Validation and review

Use `just test-repairs` for real VM/Temporal recovery and negative controls;
`just repair-pilot` additionally makes three authorized development model calls.
See [repair operations](../repairs.md) for retained evidence and limitations.
The tested boundary is disposable local synthetic work, not arbitrary repository
repair, multi-tenancy or production readiness. Revisit for real repository
inputs, additional mutation targets, Linux/Kubernetes qualification, audited
runtime requirements, or scaling pressure. Deployment requires its own scope.
