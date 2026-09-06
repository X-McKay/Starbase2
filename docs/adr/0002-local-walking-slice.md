# ADR 0002: one local core and Python Temporal workers

Status: accepted

Date: 2026-09-05 UTC

Owner: Al McKay; implementation assistant acting under the request to choose and
implement routine local development decisions. Scope: the local experiment only.
This accepts no deployment, production storage choice, or external authority.

## Decision and reason

Implement one Rust core owning missions, dispatch intent, fixture grading,
retained evidence, and the operator snapshot. Use Python Temporal workers and a
Godot native scene with an independently usable HTML journal. A queued mission
row is the dispatch intent; a stable workflow ID reconciles ambiguous starts.
Evidence and completion commit in one transaction.

Use SQLite WAL for this single-process, fixture-only core and the persistent
Temporal development server. This removes database provisioning from the first
experiment. SQLite is not selected for Kubani or multi-replica operation.

Start with direct PydanticAI calls inside bounded Temporal activities. Keep a
small integration comparison path using PydanticAI's maintained
`TemporalDurability` capability, not the deprecated wrapper. Both paths passed
worker replacement and replay on the same deterministic campaign. Neither has
an established advantage for a multi-tool or real-model agent.

## Alternatives considered

- The proposed four services would add three product stores and cross-owner
  evidence/completion reconciliation before there are provider identities or
  independently operated candidate workers. That complexity does not answer
  the first experiment's questions.
- A Python-only core would remove a toolchain and remains a viable option.
  The typed Rust/Python seam now works, but no productivity or performance
  superiority has been measured. Keep the boundary small.
- One core plus Python workers retains the requested language fit and makes
  evidence/completion atomic. Its shared failure and administration domain
  is acceptable only for the scoped local experiment.

## Trust and recovery

The core grader never accepts candidate-supplied scores. That is a code boundary,
not qualified hostile-code isolation: the Python worker is trusted, the API is
unauthenticated loopback, fixtures are public, and the machine owner can edit
SQLite. There are no model endpoints, runtime tools, arbitrary-code loading,
production credentials, external effects, promotion, or XP.

Before untrusted candidates or external providers, qualify separate identities,
sandboxing, authenticated API roles, and verifier access. Independent deployment
may then be necessary; the first experiment does not prove otherwise.

Keep the local database and compatible workflow code when restarting. Do not
reuse a mission ID with changed input. Worker builds are frozen at process start;
a different loaded build is rejected. Results are append-only through the API
and SQL triggers. A fresh database is a separate experiment, not a migration.

## Evidence, limits, and review triggers

See [experiment record](../local-slice.md) for exact results and preserved
failures. Godot native rendering and export work; web templates, load testing,
accessibility beyond the structured journal, and visual theme comparison remain
unresolved. This is a runnable experiment, not the full acceptance journey.

Revisit storage before multi-process core use or Kubani deployment; service
boundaries before provider credentials or untrusted candidate execution; direct
agent composition when a multi-tool run needs fine-grained model/tool recovery.
ADR 0001 remains a broader proposal. This ADR replaces its four-owner requirement
only for the local implementation scope.
