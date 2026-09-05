# Source research and evidence

Reviewed: 2026-09-05 UTC.

These projects provide context, implementation examples, and cautionary lessons.
Their naming, service catalogs, agent taxonomies, world layouts, and plans are
not Starbase2 constraints. This is targeted source inspection, not a complete
code or security audit. No live cluster or agent benchmark was run.

## Revisions inspected

| Repository | Revision | Material inspected |
|---|---|---|
| Starbase-lite | `f7ae220a451c1e62e9a3806b39b3c58c6a6b7d5e` | README, agent definition/kernel/workflow, example agent YAML, station design, Godot outpost/crew, eval scorer, Python tooling |
| Starbase | `61ad6ccf06418bc9cee5c48f45823fe3131baa7b` | Remote README and core composition; local design/standards/ADRs and implementation at `ac9a75f7b2066e0b8ec635747221d0e4a0777213` with pre-existing uncommitted work |
| Kubani | `703cfb14528e61c18d5c7ff56b161eff459cf3e8` | Tree, README, Temporal/Postgres/FalkorDB manifests, apps inclusion, Starbase promotion README |

The Starbase local checkout differed from the remote revision and contained
substantial unrelated work. No files there were changed for this proposal.
Documentation intent is not evidence of deployed behavior.

## Useful ideas and opportunities to improve

**Small, inspectable Python agents.** Lite's definition loader validates the
configuration, adds skill bodies, and constructs PydanticAI agents. The kernel
includes effective configuration and tool schemas in a digest. Carry forward
explicit composition, but extend build identity to code, dependencies, memory,
environment, and actual model facts for comparisons.
[Definition loader](https://github.com/X-McKay/Starbase-lite/blob/f7ae220a451c1e62e9a3806b39b3c58c6a6b7d5e/services/agent/src/starbase_agent/definition.py),
[kernel](https://github.com/X-McKay/Starbase-lite/blob/f7ae220a451c1e62e9a3806b39b3c58c6a6b7d5e/services/agent/src/starbase_agent/kernel.py).

**A durable run, rather than a permanent thinking loop.** Lite integrates
PydanticAI with Temporal and retains success/failure bundles. Keep bounded work
and explicit failure records, but separate long-lived crew identity from run
configuration and avoid using workflow visibility as the entire product store.
[Workflow](https://github.com/X-McKay/Starbase-lite/blob/f7ae220a451c1e62e9a3806b39b3c58c6a6b7d5e/services/agent/src/starbase_agent/workflows.py).

**A real game-engine foundation.** Lite's outpost uses Node3D, terrain,
billboard actors, data-driven stations, camera/lighting, and crew behavior from
gateway snapshots. Its station design is explicitly a draft. The useful
principle is visible activity backed by evidence; neither its world geometry
nor class-to-character mapping needs to survive.
[Outpost](https://github.com/X-McKay/Starbase-lite/blob/f7ae220a451c1e62e9a3806b39b3c58c6a6b7d5e/starbase-ui/godot/src/world/outpost.gd),
[crew](https://github.com/X-McKay/Starbase-lite/blob/f7ae220a451c1e62e9a3806b39b3c58c6a6b7d5e/starbase-ui/godot/src/actors/crew.gd).

**Safety and durability without preserving every boundary.** Starbase's Go
composition assembles many service modules; its architecture permits initial
colocation. The complexity concern therefore includes logical contracts and
ownership, not merely pod count. Preserve testable idempotency, evidence,
authorization, and recovery properties while evaluating larger cohesive owners.
[Core composition](https://github.com/X-McKay/Starbase/blob/61ad6ccf06418bc9cee5c48f45823fe3131baa7b/cmd/starbase-core/app.go),
[service catalog](https://github.com/X-McKay/Starbase/blob/61ad6ccf06418bc9cee5c48f45823fe3131baa7b/specs/18-microservice-architecture.md).

**Evaluation aggregation needs care.** Lite's inspected scorer computes a union
of finding codes across repetitions before scoring the case. A small local
reproduction used the actual `Case` and `_score` definitions, extracted through
Python's AST without importing the model runtime:

```text
expected = {a, b}; allowed extras = {}
run 1 = {a} -> fails: missing b
run 2 = {b} -> fails: missing a
union = {a, b} -> passes
```

Observed result: both individual trials failed and the union passed. This
demonstrates an aggregation limitation, not an estimate of either project's
agent quality. Starbase2 should grade per run and aggregate distributions.
[Scorer and repetition aggregation](https://github.com/X-McKay/Starbase-lite/blob/f7ae220a451c1e62e9a3806b39b3c58c6a6b7d5e/tests/evals/scorer.py).

**Kubani already has relevant desired state.** The inspected Temporal chart
uses external PostgreSQL for default and visibility stores, defines bounded
connection pools, and configures Authentik for the web UI. PostgreSQL uses
Longhorn-backed persistence. These are reuse opportunities with finite capacity;
web login does not prove Temporal worker/API authorization.
[Temporal manifest](https://github.com/X-McKay/kubani/blob/703cfb14528e61c18d5c7ff56b161eff459cf3e8/infrastructure/gitops/apps/temporal/helmrelease.yaml),
[PostgreSQL manifest](https://github.com/X-McKay/kubani/blob/703cfb14528e61c18d5c7ff56b161eff459cf3e8/infrastructure/gitops/apps/postgresql/helmrelease.yaml).

Kubani also contains a FalkorDB deployment and several separately controlled
Starbase overlays. The base Starbase promotion README describes generated,
digest-bound inputs and activation constraints; it does not establish the
current state of every overlay or the live installation. Do not reuse those
identities or overwrite generated bundles for Starbase2.
[FalkorDB manifest](https://github.com/X-McKay/kubani/blob/703cfb14528e61c18d5c7ff56b161eff459cf3e8/infrastructure/gitops/infrastructure/falkordb/deployment.yaml),
[existing Starbase bundle](https://github.com/X-McKay/kubani/blob/703cfb14528e61c18d5c7ff56b161eff459cf3e8/infrastructure/gitops/apps/starbase/README.md).

## What remains unverified

Actual cluster health/capacity, API authentication, backups and restores,
approved object storage, Godot performance and accessibility, agent quality,
Rust-versus-Python development cost, framework compatibility at selected pins,
and clean-checkout application setup. The delivery plan contains the experiments
that must resolve these before claiming implementation or production readiness.
