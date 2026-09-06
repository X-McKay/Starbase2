# Delivery plan

Status: proposed

## Implemented local repair extension · 2026-09-05

Completed local extension: surveyed six sandbox options, selected and exercised pinned microsandbox, implemented durable bounded synthetic repair missions, independent per-case grading, inspectable diffs and action attempts, and duplicate-safe cosmetic progression. See [retained repair evidence](../evidence/repairs-first/events.json). Kubernetes deployment is the next separately scoped milestone requested by the owner; actual Linux sandbox qualification, identities, persistence and recovery decisions precede deployment. Broader repository repair and progression calibration remain future product work, not deployment prerequisites silently claimed complete.

Owner for initial work: Al McKay (X-McKay), with implementation assistance.
Stage boundaries are evidence gates, not time estimates. All items below remain
planned unless explicitly marked complete.

## Playable world refinement — first pass implemented

The user prioritized a clean space-themed mini-world before deployment scoping.
[Aster outpost](world-playable.md) now supports walking, contextual inspection,
synthetic native repair dispatch and retained outcomes. Original art and actual
normal/compact/failure captures establish a concrete direction for review.
The [space-adventure pass](world-adventure.md) now supplies higher-detail crew
appearances and a stronger frontier-station silhouette. Remaining owned gates are interiors and authoritative work gestures, richer art
and sound, direct gym configuration/replay, decoration persistence, comfort and
platform validation; their completion conditions are in the world experiment record.
The [planetary colony](world-colony.md) now adds a larger walkable basin, landing
and habitat districts, reserved sites, camera follow and a map overview. Actual
construction/resource mechanics remain deferred until their relationship to
useful agent work and persistent state is agreed.
The [red-planet surface pass](world-surface.md) refines materials, cliff strata
and landscape landmarks; pool/stone collisions are exercised. Elevation traversal,
dynamic weather and resource mechanics remain unimplemented.
The [cliff shelf](world-cliff.md) now replaces the enclosing rock barriers with
a continuous drop, depth scenery and rear wall. Navigation and physical movement
share the shelf boundary; lower-canyon traversal remains unimplemented.
No building introduces a service, and cosmetic progression grants no authority.

The [geology and paths pass](world-geology.md) adds painted rock detail, irregular
cliff masses, localized ground erosion and connected curved walking corridors.
Native overview/walking/overlook evidence and corridor safety checks are retained.
The next environment gate is an authored cliff kit and lighting/composition review
at the spring and overlook (see the geology record for acceptance) before further biome
or terrain expansion; climbing and dynamic weather remain unimplemented.

The [modular PNG kit](art-production.md) is now [rolled into the colony](world-rollout.md)
with three textured main buildings and playable room variants, doorway entry/exit,
immediate cutaway cameras and authoritative console inspection. Owner: Al with
implementation assistance. Next gate: in-game review of all three journeys,
production texture-scale and prop refinement, then expansion. Reference-level
polish remains open. Keep art refinement separate from deployment readiness.

The [building catalog milestone](building-catalog.md) adds an illustrated hangar,
shared scene-based interiors, single-source building placement/collision and a
searchable place directory. The 50-instance experiment uses shared artwork; a
50-unique-art content budget remains unqualified. All five colony buildings now
have unique illustrated exteriors, larger footprints and separated districts,
including catalog-based habitat and greenhouse scenery. Shared tiled foundations
and walkways now connect those buildings and a separated, marked landing apron;
the ambiguous blockout shuttle is removed. Buildings now have separate dark
rectangular pads, linked by two-tile light-grey streets with yellow centre dashes.
The next owned art gate
is consistent interior/exterior texture scale and grounded entrance/shadow layers,
then measurement of the next real content batch. New static buildings still need
artwork, metadata and placement without another rendering branch.

## 0. Design foundation — delivered in the initial repository

Create the private Starbase2 repository, record source research, articulate the
fresh product direction, compare architecture alternatives, and define a
playable walking skeleton. Add a short shared engineering charter and
documentation validation. This does not establish runtime or deployment readiness.

## 1. Prove the two riskiest seams — partially demonstrated

The [local slice](local-slice.md) implements a Rust core, Python/PydanticAI,
a persistent Temporal development server, six per-trial results, and a native
Godot scene plus journal. Direct activities and maintained Temporal integration
were compared on identical public fake-model controls. Worker SIGKILL, duplicates,
core restart, cancellation, and retained-history replay were exercised.

The experiment justified collapsing the proposed four owners to one core plus
Python workers for local development. [ADR 0002](adr/0002-local-walking-slice.md)
records the scope and exit path. Neither real agent quality nor hostile-code
isolation was established. Native Godot rendering/export work; web export and
comparative visual/performance budgets remain open.

## 2. Useful local operations — implemented and exercised

The [operations edition](operations.md) connects real bounded Python review,
retained masked sources and citations, typed v2 records, pagination, lifecycle
history, operator/worker write boundaries, controlled gym comparisons, and optional
model explanations. The journal supplies all commands; the native Godot inspector
consumes the same records. The original v1 experiment remains compatible.

The core owns these capabilities without another service. Local migration,
completion/cancellation invariants, genuine analyzer output, and replay were
tested. Both permitted inference endpoints were exercised; retained failures
showed that codes alone were insufficient context. Supplying rule meanings fixed
the observed cases, with no claim of general model qualification.

Remaining stage-2 gates are owned in [operations](operations.md): representative
PR reasoning and hidden evaluation, arbitrary-code isolation, rich crew identity
and progression, Godot web/native validation, and production onboarding. The full
SPEC acceptance suite is not complete and is not implied by passing local tests.

## 3. Put the crew on duty — periodic local reviews implemented

Recurring local Python reviews now survive worker and Temporal restarts. Add
source-grounded AI-news briefings, then
cluster observation and advisory applicability. Use read-only credentials only
for explicitly selected targets. Deduplicate changes, reconcile missed events,
bound queues, and enforce model budgets. Exercise provider outage and recovery.

Exit criteria: SBT-002 demonstrated without an open client; overnight observation
and a morning briefing are useful; source freshness, silent-monitor failure,
backlog, cost, and no-change outcomes are visible. Add initial cosmetic XP only
after trusted outcome recording is in place.

## 4. Make the gym useful for development

Introduce sealed scenario families, paired analysis, model/tool/prompt/skill
variants, and a capability tree. Trainer may propose improvements within a
fixed budget. Verify hidden-case isolation and rotate exposed holdouts.

Exit criteria: a useful improvement, a known regression, and an inconclusive
comparison are all classified correctly with retained evidence. Changing builds
preserves crew identity but does not silently transfer qualifications. A failed
candidate cannot edit its grader, award itself XP, or promote itself.

## 5. Deploy observation on Kubani

Prepare a separate Starbase2 overlay and identities in Kubani after inspecting
live readiness under a separately scoped deployment task. Resolve artifact
storage, worker/API authentication, resource budgets, and backup objectives.
Deploy the same immutable images tested locally; observe before enabling duties.

Exit criteria: SBT-012 demonstrated, manifests and policy validated, restore and
out-of-band stop exercised, old Starbase unaffected. Cutover is per duty, with
duplicate external effects disabled. This proposal does not authorize deployment.

## 6. Introduce useful, bounded external action

Add the Effector with its own ledger and identity. Start with publishing a
review or opening a tested dependency-update PR; then assess a single reversible
cluster operation. Show exact targets and verification before granting a standing
policy. Keep self-upgrades and shared-platform changes under stronger review.

Exit criteria: expired approval, target drift, duplicate dispatch, ambiguous
timeout, denied scope, failed verification, and rollback are tested. Successful
training alone cannot activate the capability. Maintain a tested incumbent
build and per-duty rollback until observation confirms the replacement.

## Decisions deliberately deferred

| Decision | Owner | Resolve when / required evidence |
|---|---|---|
| World polish and web/native priority | Al | Space-outpost direction implemented; playtest art/interaction and measure web delivery |
| Runtime and library version pins | Al | Pinned and exercised locally; production upgrade/version-routing evidence remains |
| Sandbox provider | Al | Before arbitrary-code execution; prove isolation and cleanup |
| Model defaults and budget | Al | Representative paired comparisons on permitted endpoints |
| XP curve and qualification thresholds | Al | Usability trials and grader calibration |
| Artifact storage, retention, RPO/RTO | Al | Before cluster activation; measured restore exercise |
| FalkorDB / Graphiti | Runtime/evaluation owner | Structured persistence and review implemented; paired evidence must justify richer retrieval over SQL |
| agentgateway | Al | Repeated routing/identity need and measured operational benefit |
| First external-action policy | Al | Named action, target, identity, verifier, recovery, and limits |

Do not implement every row speculatively. Each resolved decision removes an
uncertainty from a concrete delivery stage.

## Fresh Kubani deployment preparation

The [setup, rollback, recovery and teardown playbook](deployment.md) prepares a fresh
PostgreSQL-backed installation. Local SQLite and local Temporal histories are
development-only and are not imported. The private deployment bundle starts
stopped, with provider inference, legacy fixture API and unqualified sandbox
repairs disabled. Local arm64 image qualification is complete; target cluster
qualification and platform backup restoration remain required before activation.
No Kubani deployment has been performed.

## Read-only field crew and memory

Watchkeeper and PR Reviewer now have V4 durable duties, bounded provider adapters,
retained evidence, Godot characters and a browser review interface. Graphiti on
FalkorDB stores reviewed, scoped episodes with revocation and rebuildable
provenance. See [implemented scope and qualification gates](field-agents.md) and
[ADR 0006](adr/0006-field-agents-and-reviewed-memory.md). This advances stage 3;
cluster mutation, GitHub publication, autonomous memory promotion and general
review-quality certification are still outside the implemented boundary.

## Command District follow-through · 2026-09-06

Implemented the native observation/evidence/memory board, repository-watch CRUD
and durable bounded GitHub polling, shared entrance grounding and optional foley.
See [scope, evidence and limits](command-district.md). The runtime owner’s next
watch milestone is an explicit coverage/retention policy for repositories above
the ten-PR window, with outage/rate-limit qualification on selected real targets.
The captain now has clean pivot-aligned illustrated walks in all four directions;
the other crew still need authored cycles. These gates require observed results,
not extra buildings or services. Kubani activation remains a separate review.

## Character animation gate · 2026-09-06

The [shared character pipeline](character-production.md) is implemented, including
real-displacement gait, contact-driven foley, asset validation and two rigged
technical prototypes. The user rejected the prototypes' 3D visual style. Keep the
approved illustrated crew in production. The illustrated captain has all four walking directions enabled and tested in
the colony/interior and packaged macOS game. Next: all EVA 2D walk frames that
preserve that look, pass shared checks, and receive native visual acceptance. Owner: implementation
assistant with Al reviewing art. Fifty distinct character textures remain unmeasured.


## Packaged world qualification · 2026-09-06

`just check-world-export` validates the actual unsigned macOS archive outside the
checkout and retains an artifact manifest and native captures. Development test
and import scripts are excluded; catalog JSON is explicitly included. Editor
checks alone do not qualify an export. The application is now committed and the
Linux arm64 Core/worker images passed [local release qualification](../evidence/linux-release/README.md).
The remaining release owner tasks are authorized publication, registry digest
recording, explicit Kubani target verification, and activation through Kubani
GitOps. Native amd64 qualification remains required for an amd64 target. No cluster deployment is implied by a
passing local UI archive. Other crew’s animation and 50-texture performance remain
separate art/performance work with the existing owner and native review gate.
