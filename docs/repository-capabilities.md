# Repository capability contracts and coordination

Status: accepted

Implemented locally, 2026-09-28. Owners: Core/runtime. Extends the
[SDLC pilot](repository-sdlc-pilot.md), [independent verification](adr/0012-independent-pr-verification.md)
and [durable opportunity decision](adr/0013-repository-opportunity-coordination.md).
No new repository write target, merge permission or deployment authority.

## Installed capabilities and handoffs

The Core-owned [catalog](../contracts/repository-capabilities.json) now supplies
three executable algent packages:

| Opportunity | Priority | Bounded repair | Independent coverage |
| --- | --- | --- | --- |
| Persistence history | 100 | Chronological history and latest-limit selection | Seven behaviors |
| Memory key | 80 | Explicit empty key differs from omitted key | Six behaviors, including agent isolation |
| Logging level | 60 | Existing logger honors a supplied level without duplicating handlers | Six behaviors |

Each package pins source/function scope, public regression, isolated environment,
round/effect limits and assignments. Core embeds the catalog. Runtime includes
catalog, source, trusted checks and coordination code in its immutable build.
Monitored source, model replies and comments cannot install capabilities or authority.
New missions freeze the contract digest, build and dependency plan. A new build
never silently retries an already attempted repository/revision/family.

Moss diagnoses captured observations; Rivet implements after that handoff; Prism
reviews after independent Core grading. A failed candidate gate permits one
recorded Rivet-to-Moss reassignment within the existing three-round bound.
This selects an installed compatible role, **not independently qualified proficiency**.
No candidate can certify itself or gain authority. The new families use bounded
numbered block edits with indentation normalization and an AST fence around the
selected function body; invalid patches are retained and never executed.

## Discovery and reservations

Every 60 seconds, the worker captures one default revision and records each
installed family's candidate, no-change or unavailable observation. No matching
source pattern means no candidate; it does not certify application correctness.
Core persists exact source/build/capability fingerprints and stable identities.
The worker orders eligible findings by authored priority, then observation time
and identity. Core rechecks freshness, policy, deduplication and reservations at
admission. Duplicate discovery and restart do not create another mission.

Execution remains serial: one initial mission or verifier at a time. An unresolved
publication reserves its family across revisions; other families may proceed.
Snapshot `reserved_opportunities` exposes those holds. A fresh provider observation
of closure/merge releases a hold; open, unknown, stale and uncertain effects retain
it. Checkpoints have a 60-second ingestion freshness limit. Retained lifecycle
changes are bounded to 100 per mission; unchanged observations refresh timestamps.
Closure never erases deduplication or awards XP.

Discovery records are bounded to 256, with 16 outcome transitions each. Candidate
admission requires an observation within five minutes. An outage records
unavailable evidence without erasing the immutable source identity. Discovery
has a 30-second deadline and cannot starve workflow cancellation/reconciliation.

## PR feedback and recovery

The worker polls one retained PR per discovery tick, round-robin. Reads bracket
comments with exact open-head observations. Complete, bounded issue/review comment
captures are immutable evidence. A typed, tool-free model proposes a classification:
current, stale, unknown, no-change, conflicting or out-of-scope. Only exact-head
review comments targeting installed source paths can be actionable; issue comments
without revision identity remain unknown. Conflicting or stale feedback stays
visible and does not authorize a repair.

Core retains up to 16 feedback snapshots and validates their digest, head, scope
and freshness. A new current digest can trigger a separately frozen verifier;
duplicate feedback cannot. The verifier must still reproduce an independent
regression before a repair, review it independently, and recheck the exact head
before effects. Comments alone cannot bypass a passing regression or expand scope.
Model failure is retained as unknown; unchanged failed captures are not retried
until they happen to pass. Read/model polling has a 25-second outer deadline.

The local monitor supervisor now checks Core/Temporal health and owned processes,
with three bounded group restarts and interruptible 2/4/8-second backoff. Explicit
stop prevents restart. Recovery attempts remain visible. This is process recovery,
not permission to repeat uncertain provider writes. See [monitoring](github-monitoring.md).

## World and compatibility

The [operating view](sdlc-operating-view.md) exposes installed contracts, actual
assignments, dependencies, admission reasons and PR lifecycle alongside both
readable and technical ledgers. Keyboard, compact, legacy, stale and reconnect
states have native fixture evidence. Presentation never invents execution or success.

SQLite schema 10 / PostgreSQL migration 8 adds Core-owned discoveries. Mission
plans, feedback and lifecycle remain additive JSON. Generated V7 contracts include
optional capability/feedback digests and discovery/feedback commands. Legacy
histories retain their old input format; new histories require compatible pinned
Core/runtime builds. Back up and drain before upgrade. Old binaries reject newer
schemas; restore a pre-migration backup only after reconciling external effects.
No live database, running monitor or GitHub resource was changed by this slice.
Live PostgreSQL and container rollout remain unqualified.

## Short iteration and remaining gates

[Iteration trials](autonomy-trials.md) now stop after one declared control cycle,
with a **15-minute maximum**, replacing the proposed 72-hour first trial. Optional
two-hour repeated-control soak is separate. Inputs are fingerprinted; source drift,
failed controls and truncation cannot count as success. Synthetic controls exercise
wiring; real Qwen/microVM development probes retain every attempt separately.
Neither grants qualified-build promotion or establishes general reliability.

Remaining work has explicit owners and completion conditions:

- **Operator/runtime — narrow identity and activation:** provision a dedicated
  GitHub App with the intended repository installation; verify observation,
  execution and status identities, then qualify a compatible backed-up rollout.
- **Evaluation/runtime — reliability and qualified assignment:** freeze a held-out
  multi-family campaign with feedback, concurrent head drift and interrupted work;
  retain per-trial costs/failures and require independent gates before promoting
  builds or using proficiency for assignment. Installed fallback is not this gate.
- **Runtime/operator — sustained workload:** qualify retention and policy budgets
  for the declared workload. Existing limits remain 100 missions, three admissions
  per policy generation, sixteen verifier children and finite expiry. Do not
  silently enlarge them or delete evidence to make a soak pass.
- **World/release — live journeys and deployment:** qualify actual live crew
  journeys and standalone exports on the deployed build; native fixture success
  does not close this gate. Human merge decisions remain separate.

See [implementation evidence](../evidence/autonomy-iteration-20260928/README.md).
