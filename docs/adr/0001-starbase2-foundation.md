# ADR 0001: an independent, evidence-driven agent world

Status: proposed

Date: 2026-09-05 UTC

Decision owner: Al McKay (X-McKay)

Participants: repository owner and implementation assistant.

## Decision question

What initial architecture gives Starbase2 an enjoyable autonomous world,
Python agent experimentation, durable execution, and understandable service
ownership without inheriting the complexity of either predecessor?

## Context and drivers

The owner requested a new private repository named Starbase2 and a fresh
perspective with no inherited conceptual commitments. The desired priorities
are a polished 2.5D UI, useful continuous agents, measurable improvement,
Python for agents, extensive Temporal use, a predominantly Rust remainder,
maintainable microservices, and straightforward local tooling.

Repository creation is authorized. Architecture acceptance, provider access,
cluster deployment, data migration, and live execution are separate decisions.
Source evidence and its limits are recorded in [research](../research.md).

## Proposed decision

1. Start a new product monorepo. Preserve predecessor installations and history
   independently; import selected ideas or code only after fit and provenance
   review. No mandatory old vocabulary, taxonomy, or map layout.
2. Separate persistent crew identity from immutable evaluated builds. Treat
   cosmetic progression, measured proficiency, and authority as distinct.
3. Begin with Control, Runtime, Evidence, and Connectors as the four service
   owners in [architecture](../architecture.md). Use Rust for three services and
   Python/PydanticAI with Temporal for Runtime, subject to the durability spike.
4. Keep PostgreSQL authoritative within each owner. Use protected artifacts for
   large evidence. Defer graph memory and gateway infrastructure until useful
   queries or repeated integration work justify them.
5. Prototype Godot 2.5D as the primary world and retain a compact structured
   operations view. Choose final theme and export priority through a bounded
   visual comparison. No game loop owns operational state.
6. Make the evaluation loop part of the first useful slice. Use per-run evidence,
   baseline comparisons, hard gates, and explicit inconclusive results.
7. Add a separately privileged Effector before any external write capability;
   do not merge execution credentials into observation to minimize pod count.
8. Use native ecosystem tooling through a small shared command surface and
   concise Codex/Claude procedures, introduced with real implementation paths.

## Viable alternatives

| Alternative | Advantage | Main cost / reason not preferred initially |
|---|---|---|
| Continue Starbase and simplify it | Reuses existing Go implementation and assurance | Conflicts with the requested independent reimagining and retains migration coupling |
| Extend Lite's Python architecture | Shortest route to its agent/game model | Would retain storage and workflow-visibility assumptions that need reevaluation; less Rust |
| Python-only product backend | One backend ecosystem, fastest framework integration | Viable fallback if the Rust boundary adds more cost than value; less alignment with stated preference |
| One Rust core plus Python workers | Fewer deployments and transactions | Evidence integrity and provider identities benefit from independent boundaries |
| Four owners with Rust APIs and Python runtime | Honors language preferences and separates evidence/provider trust | Multiple toolchains and contracts; larger Control failure domain |
| Rust workflows and APIs, Python activities | More backend consistency in Rust | Another language seam inside agent orchestration; needs SDK/integration proof |
| Browser-native world without Godot | Simpler web delivery and DOM integration | More custom scene/character tooling; remains viable if export tests favor it |
| Defer architecture until broad benchmarks | Avoids premature commitments | Delays learning from the one end-to-end journey; bounded spikes are more useful |

The recommendation is a tradeoff, not a measured performance claim. Rust does
not itself make the design simpler or agents better. If the first API/workflow
seam is awkward, compare the simpler Python alternative rather than building a
framework to defend the language split.

## Consequences

Control has broader ownership and outage impact than any one predecessor
module. Rust and Python require separate locks/builds and cross-language
contract checks. Evidence storage and the operator projection are eventually
consistent. Four service owners may require more worker deployment identities
for isolation; service count is not a pod-count guarantee.

Benefits expected, not yet measured: fewer logical APIs and lifecycle handoffs,
clear source navigation, direct agent experimentation, and a world with evidence
behind its progression. Additions must prove more value than operational cost.

## Security, reliability, data, and privacy

Separate candidate, coordinator, verifier, observation, and effect identities.
Run untrusted code with enforced isolation and no production credentials. Store
redacted operational summaries, not raw private reasoning. Classify evidence
and require an approved provider policy before sending private content to models.

Use bounded retries, owner outboxes, idempotent commands, explicit uncertainty,
and a stop path independent of the renderer and normal control service. Each
stateful owner defines retention, backup and recovery objectives before live
use. Shared Kubani services provide infrastructure, not shared table ownership.

## Rollout, rollback, and exit

Follow the [delivery stages](../roadmap.md): bounded seams, fixture-backed world,
continuous observation, gym, separate Kubani installation, then named external
actions. No in-place language conversion or automatic old-data migration.

Keep old deployments untouched. Transfer a duty only after equivalent behavior
and exclusive ownership of its external effects are verified. Retain old
read-only history through links or an explicit later import. Open Temporal
histories drain on compatible old workers; never point them at new workflow
code based only on a matching name. Roll back new dispatch to the previous
qualified build while preserving existing run versions and action ledgers.

Godot can be replaced behind the projection contract. A graph projection can
be removed and rebuilt. Python or Rust service implementations can be replaced
through versioned APIs. Do not promise cost-free migration; preserve these
specific seams and test them.

## Validation and review triggers

Evidence so far: targeted repository inspection and a deterministic reproduction
of the inherited eval aggregation limitation. No runtime, performance, isolation,
or deployment claims have been verified. Proposed decision acceptance follows
the two bounded spikes and owner review of their tradeoffs.

Revisit when Godot misses usability/export budgets, the Rust/Python boundary
slows ordinary changes, Control needs a different failure/credential boundary,
SQL cannot serve a demonstrated relationship query, tool routing is duplicated,
or workload scale invalidates the local-first design.

Follow-up work is owned in [roadmap](../roadmap.md). This ADR supersedes no
decision in either predecessor repository and is not yet an accepted mandate.
