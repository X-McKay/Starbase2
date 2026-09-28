# Autonomous RPG delivery contract

Status: proposed

Owner: Al McKay (product and standing policy); Core/runtime, evaluation, and world
implementation own the work below. Updated 2026-09-27.

The [research plan](autonomous-rpg-research.md) records the selected product
choices. This document tracks delivery against actual code. **The objective is a
crew that autonomously coordinates useful work, finds improvement opportunities,
learns through independent evaluation, and makes that process playable.** A
packaged agent, scripted team, attractive Crew sheet, or one successful repair
alone does not complete it. Technical details and uncalibrated thresholds remain
design work, even where the product choice is settled.

## What exists now

“Implemented” below means source exists at the stated scope. It is not a blanket
test, deployment, qualification or production-readiness claim. Pending checks
must acquire their own retained evidence before a gate is closed.

| Surface | Status and actual boundary | Source/evidence |
|---|---|---|
| Bounded single-agent readiness | Implemented local harness: typed observations/proposals, owned disposable Kubernetes/Flux lab, independent useful-work verification. Separate from durable Core missions. | [Mission contract](readiness-missions.md), [adapter](../scripts/readiness/mission.py), [runtime](../services/runtime/starbase_runtime/readiness.py) |
| Immutable Procedure comparison | Implemented public pilot harness and baseline/candidate Run book builds. Prior real Qwen pilot is inconclusive; no capability qualification, promotion or XP. New builds do not inherit old evidence. | [Campaign and prior results](readiness-campaigns.md), [readiness package](../services/runtime/starbase_runtime/agents/readiness/agent.json) |
| V5 joint diagnostics | Implemented source for lead + workload/service specialists, adaptive rounds, typed findings, root reservations, claims/results, deduplicated opportunity input, cancellation and Core grading. Public sanitized simulations only; zero XP, no Git/Kubernetes effects. Real Temporal controls passed restart/replay, cancellation and exhaustion. A frozen Qwen development build passed 1/4 public cases; this is not live action qualification. | [ADR 0009](adr/0009-durable-readiness-coordination.md), [Core](../services/core/src/joint.rs), [workflow](../services/runtime/starbase_runtime/joint_workflow.py), [activities](../services/runtime/starbase_runtime/joint_activities.py), [integration harness](../scripts/joint_integration.py) |
| Observation and recurring work | Partial: existing field duties and bounded workflows supply observations and retained results. Core now derives stable Trainer review opportunities from retained V5 failures, with source records and proposed investigations. V6 adds a bounded local readiness duty: automatic selection/deduplication, one Procedure proposal, paired public practice and a Core-owned practice incumbent. Cross-domain ranking and curriculum remain open. | [Field workflow](../services/runtime/starbase_runtime/field_workflow.py), [field contract](field-agents.md) |
| Progression | Partial historical prototype: Mender has synthetic repair credit, exact-build fixture qualifications and a level display. This is not the selected field-only XP economy, Level 20 milestone system or calibrated eight-stat model. | [Repair ledger](../services/core/src/repair.rs), [ADR 0004](adr/0004-isolated-repairs-and-progression.md) |
| Playable presentation | Partial: inhabited colony, existing structured work/evidence routes, station markers, authored equipment/work animation, restrained crew attention, Crew sheet cards, actionable Joint operations and a separate Practice view. Rivet has grounded Equipment pickup/use/stow with two review treatments; other rigs retain existing poses. Stats/ranks remain unassessed where records are absent; permanent Class assignment is not inferred from role names. | [Experience](experience.md), [Crew sheet](crew-sheet.md), [crew attention](crew-work-attention.md) |
| V6 local learning, skill graph and adoption | Partial: bounded failure → Procedure candidate → paired public comparison → practice-only decision is implemented. Held-out qualification, operational adoption and reassessment remain open. | [Evaluation contract](evaluations.md), [coordination delivery detail](playbooks-alignment.md) |

## Current implementation priority

The Commander has prioritized complete local cycles, interaction and production-quality
visual work **before Kubernetes/Flux deployment**. V6 local practice and the
[local cycle contract](local-learning-cycles.md) now implement a bounded developmental
loop. Native action recovery, readable Mission bridge/Technical ledger alternatives,
Practice inspection and cast motion quality precede resuming gates 2 and 9. Both
mission views remain available; the Technical ledger is being formatted for reading.
The [motion review](crew-work-motion-options.md) provides actual A/B captures, with
art-direction sign-off kept separate from mechanical tests.

The deployment sequence below describes dependencies and remaining product scope;
it does not authorize or prioritize a cluster rollout during this local iteration.

## Ordered implementation gates

Core owns product records and deterministic admission/effects; runtime owns
Temporal execution; evaluation owns independent protocols/graders; world owns
faithful spatial and structured presentation. These are implementation owners,
not new services. Al owns exceptions to standing policy and the product choices
explicitly reserved for the Commander. Each row closes only with its acceptance
evidence; UI work can proceed alongside the corresponding record contract.

| Order / status | Owner and concrete work | Completion evidence |
|---|---|---|
| 1 · Partial — durable team execution | Core/runtime: qualify current V5, preserve one lead, complementary specialist roles and bounded adaptive follow-up. | Local real Temporal replacement/replay and public controls are retained; unit checks cover malformed/late reply, unknown usage and no progress. Finish qualification across failure checkpoints and connect live evidence. Public controls prove wiring only. |
| 2 · Open — live owned-lab team | Runtime/evaluation: replace sanitized snapshots with scoped owned-lab observation receipts; compose the trusted existing GitOps effector and independent verifier. | Local Qwen team finds a supported readiness fault, requests new evidence, publishes one exact lab revision, observes Flux applying it, and verifies useful work without manual step-by-step coordination. Include healthy, incorrect-work, unsupported and disagreement cases, lost-publication reconciliation and cleanup. Compare matched single-agent/team trials; retain failures and cost. |
| 3 · Open — standing policy and capacity | Core/runtime; Al owns policy: persist target/action qualification requirements, grants, priorities, capacity and recovery limits. Support crew proposals resolved by Mission Control, shadow/support roles, safe-checkpoint preemption, and lead replacement. | Deny precedence and fresh target/revision/expiry/qualification/budget checks at effects; routine authorized work needs no extra approval. Priority work displaces exploration only after started effects are reconciled; resumed missions revalidate. Exception and emergency-stop journeys work independently of renderer. |
| 4 · Partial — continuous opportunity and curriculum | Runtime/evaluation: V6 now executes bounded failure → Procedure → eight public paired trials → practice decision without an open client. Continue durable observation → deduplication → prioritized opportunity → reserved mission/campaign. Crew and Trainer both propose; operational needs and priority training precede spare-capacity exploration. | A retained failure automatically produces a bounded hypothesis and selected practice, without an open client. Duplicate signals coalesce, unchanged evidence causes no repeated model work, unsuccessful hypotheses cool down, deadlines/caps stop dispatch, and disabling the duty reconciles started work. Briefing explains selection, cost and outcome. |
| 5 · Open — useful learned Procedure | Evaluation/runtime: freeze provenance, candidate lineage, Run book artifact and discovery/development/qualification cohorts. Compare incumbent, curated Procedure and autonomously proposed Procedure. | Predeclared readiness-family campaign establishes diagnostic reliability/transfer under policy and regression gates, or honestly remains inconclusive. Track holdout exposure, validate generated cases independently, retain every trial and candidate overhead. A public scenario win cannot establish held-out improvement. |
| 6 · Open — qualification and adoption | Core/evaluation: persist exact-build, skill, scenario-version, workload/resource-context qualifications; bounded candidate portfolio; policy decisions; incumbent and active-build pointers. | Unsupported qualifications become unassessed after equipment change. Eligible improvement is automatically equipped inside standing policy while existing runs retain their builds. Regression, expired qualification, uncertain evidence or out-of-policy change prevents adoption; rollback and drift-triggered reassessment preserve history. Candidate/Trainer cannot edit grader, clearance, credit or production pointer. |
| 7 · Open — progression and skill tree | Core/evaluation/world: implement the selected economy and capability contracts below, with a documented transition from synthetic prototype credit. | Ledger replay cannot duplicate XP; simulations/failed/blocked/cancelled work earn none; equal team shares conserve the fixed pool. Level/milestone/banked-XP gates, build replacement, incompatible bests, five skill ranks and qualified between-mission Subclass switching have behavioral tests and inspectable evidence. |
| 8 · Partial — playable autonomous operations | World/Core: project mission summaries, dependency events, comparisons, briefing, objectives, Crew sheet, Map and detailed work/handoff animation. | The Commander opens Starbase, understands changes and uncertainty, inspects why specialists acted, compares candidate/incumbent and reaches decisions/evidence by both spatial and keyboard routes. Native wide/compact/reduced-motion/stale/reconnect checks; no invented handoff, animation delay, automatic success or authority from cosmetics. |
| 9 · Open — selected Kubani production journey | Core/runtime/evaluation; Al/Kubani owners govern activation: qualify narrow repository publication/merge and independent observation/verification identities under GitOps. | Authorized change is merged into Flux's tracked branch; fresh evidence ties the exact revision through applicable Kustomize/Helm reconciliation to intended resources; independent functional/regression checks pass over the declared window. Revert/fix-forward rationale, lost-response recovery and independent emergency stop are retained. Lab success cannot substitute for this endpoint or activate production authority. |
| 10 · Open — second domain and meta-improvement | Domain/evaluation owners: begin with Engineer SDLC or Researcher work, then evaluate Trainer variants. | A second domain shows useful transfer or specialization without readiness regressions, using reproducible artifacts/held-out checks. A candidate Trainer must improve downstream unseen campaigns relative to a frozen Trainer at a declared total budget including optimization overhead. No perpetual-improvement claim follows from one campaign. |

The first end-to-end autonomy milestone combines gates 1–2 with one genuine
multi-specialist investigation and adaptive follow-up. Do not postpone it while
packaging every older agent. The first **learning** delivery claim additionally
requires gates 4–6 to demonstrate a reusable gain on fresh cases. The full selected
walkthrough still requires gate 9; the broader RPG remains open until its relevant
capability and Commander journeys are delivered. Production activation is a
separate authorized action, not an automatic consequence of implementing code.

## Accepted progression contracts to preserve

| Contract | Selected behavior and remaining implementation |
|---|---|
| Eight stats | Agility: fault recovery; Speed: verified latency; **Constitution: endurance over longer sequences**; **Efficiency: tokens/resources per comparable verified outcome**; Perception: detection/localization; Wisdom: calibration/abstention/escalation; Precision: correctness/regressions/scope; Cooperation: useful handoffs and team outcomes against a solo baseline. Finalize and independently calibrate measurement-to-rating thresholds before displaying scores. |
| Ratings and history | All eight use 1–20, higher better, or explicit unassessed. Show current plus compatible personal best; preserve build, workload, evaluation version, raw units, sample size, uncertainty and date. Periodic and signal-triggered evaluations update current evidence; historical best does not grant current qualification. Zero successful outcomes cannot display zero cost per success. |
| One lifetime Level | Initial cap 20, qualification milestones at 5/10/15/20, gradually increasing XP requirements. Bank valid field XP while capped or awaiting qualification. Preserve earned Level across build/stat changes. Trainer proposes meaningful cap expansion; Commander approves. XP thresholds and milestone trials require calibration, not arbitrary invented numbers. |
| Mission credit | Predeclare difficulty-based fixed XP pool and success criteria. Only independently successful field work earns XP; simulations train/qualify without XP. Split the pool equally among members whose assigned roles were fulfilled; observation alone earns none. Deduplicate the underlying outcome, define rounding and append corrections rather than erasing history. Record how historical synthetic prototype credit is represented without silently reclassifying it as field work. |
| Classes and Subclasses | Permanent Engineer, Operator, Researcher, Trainer or Security Class; one active qualified Subclass, automatically switchable between missions inside policy. Preserve active mission configuration. Milestones require shared Class foundations plus one complete currently qualified Subclass path, which need not be active; do not combine incomplete paths. Cast/Class mapping and Subclass catalogs remain open. |
| Skill tree | Authored shared foundations plus Class-specific advanced branches, ranks I–V independently of XP. Independently validated new branches may be admitted automatically inside policy; exceptions go to Commander. Admission, personal qualification and clearance remain separate. Qualification needs coverage, uncertainty and reassessment rules. |
| Equipment and recruitment | Models, tools, Procedures, Run book, memory and settings freeze into immutable builds. Qualify before equipping; retain incumbent recovery and a bounded candidate portfolio. Crew proposes persistent recruitment with role/resource rationale; Commander approves. Temporary parallel workers do not create new crew identities or authority. |

## Commander and visual completion contract

Gate 8 includes the selected living-world opening with a compact dismissible
**Since your last visit** briefing: required decisions and urgent issues first,
then verified outcomes and development. Persist the last-visit boundary, coverage
and freshness; dismissing the briefing does not acknowledge incidents. Routine
achievements belong in the briefing, not repeated interruptions. The current
bounded historical snapshot is only a foundation.

Walking and strategy views must remain freely switchable. A compact docked crew
inspector leads to the full Crew sheet and every actual concurrent assignment.
Mission inspection is summary first, with exact timeline, outcome/blocker,
deliverable and evidence. Improvement inspection compares incumbent and candidate
side by side, including failures, uncertainty, per-trial cost and recorded adoption.
The new mission actions, readable ledger, Practice controls and Precise Rivet
handling are partial improvements. V5/V6 spatial handoffs still require explicit
role-to-crew assignments; matching role names are not authority to animate a
particular crew member as the performer.

Mission Control and direct crew conversation share persistent editable structured
objectives. Clear instructions activate inside standing policy without a second
confirmation; ambiguous intent needs clarification and policy exceptions need a
Commander decision. Discussion is not silently activated. Proposed, active and
awaiting-decision states remain distinct, and conversation cannot bypass admission.

The Map uses space destinations with technical drill-down, real target identities,
scope and freshness. Routine remote missions remain at starbase workstations;
selected expeditions use authored destination templates shaped by actual records.
Do not invent dependencies or make scenery imply clearance. Grounded expressive
work, Equipment handling and dependency-backed handoffs accompany compact markers;
celebrations require verified achievements. Preserve stale/unknown distinctions,
coalesce obsolete motion and retain reduced-motion/structured equivalents.
Authored districts and Commander customization can show accumulated history, but
furniture, cosmetics, travel and construction never gate operational controls.

## Evidence and closure

For each gate, retain source/build identities, commands actually run, failure
cases, independent outcomes and native artifacts where relevant. Update this
record when evidence changes; a test harness or a pending run is not a passed
result. Current implementation evidence remains linked through the scoped
contracts above. No deployment, current cluster health, live multi-agent effect,
new rating, qualification, learned superiority or operational adoption is asserted
by this delivery document.

The [2026-09-27 implementation evidence](../evidence/autonomous-rpg-20260927/README.md) retains all seven Qwen development cohorts, including an interrupted harness cohort, final per-trial failures and resource use, deterministic lifecycle controls and native visual evidence. The final tested Qwen build achieved one correct diagnostic proposal in four public cases; no build was promoted.


The [local-cycle evidence](../evidence/local-cycles-20260927/README.md) adds the
first complete autonomous public Procedure cycle: candidate 2/4 versus baseline
0/4, inconclusive, no adoption or XP. It also retains full restart/replay,
claimed-call cancellation, stopped-without-workflow recovery and UI command
reconciliation. Commander selected Precise motion; default gameplay now frames crew 44% larger outdoors and 20% larger indoors,
with compact chrome corrected in response to visual review. Cast-wide equipment actions and independent
held-out reliability remain concrete next completion gates before deployment.


Before operational activation, World owns a durable pending-command journal:
preserve the origin, exact request identity and reconciliation intent across app
restart without storing worker credentials. Completion is a killed-client / lost
reply test that recovers the same Core record without duplicate POSTs. Current
V5/V6 UI reconciliation survives panel navigation but not a full app restart;
Core execution, idempotency and workflow records remain durable independently.

World's current visual acceptance slice is [surface detail and visual coherence](surface-detail-polish.md):
stable moving-camera shadows, dimensional foliage, temporary soil impressions,
and unobstructed interior sightlines. The same record owns the broader app-review
follow-ups (label hierarchy, furniture detail, water and reading-surface contrast)
with concrete completion conditions. A qualified earlier export is a baseline,
not evidence that subsequent visual changes are already qualified.

The [combined detail pass](../evidence/world/production-polish-20260928/README.md)
passed native comparisons, integrated world checks and unsigned macOS export
qualification. The next recommended art slices are contextual world labels and
shared furniture/material consistency; owner acceptance remains separate.

World has implemented [environment contact interactions](crew-environment-interactions.md)
locally: physically precise workstation arrival, supported keyboards and displays,
shared typing/read/gesture actions and role-specific mannerisms. Wes and Prism
now require seated Command work at the large displays, with fitted chairs,
reachable keyboards and grounded sit/stand transitions. Focused verification
passed all five real home/work/home journeys, state interruption gates, after-frame
rig checks and native contact review. Full world and unsigned macOS export qualification passed; see the
[combined interaction evidence](../evidence/world/environment-interactions-20260928/README.md). Individually skinned fingers and the further
ambient/tool actions in that contract remain separately owned completion gates.


## Repository monitoring follow-up · 2026-09-28

Core/runtime now implement [bounded GitHub fleet observation](github-monitoring.md),
with owner-scoped discovery, 256 watches, shared 20-run admission, per-watch
evidence, and pause/remove preservation. This is observation and local findings;
it does not close autonomous repair/publication or production deployment gates.
Synthetic integration and replay pass; live provider acceptance is separate.

Core/runtime own the next storage qualification: implement indexed latest-run and
last-admission lookup plus an explicit, operator-reviewed retention/archive bound.
Completion requires a declared worst-case fleet/history fixture (256 watches at
the shortest supported fleet interval over at least 30 days), measured snapshot
and admission latency before/after indexing, a documented byte/row retention
budget, and reopen/replay tests proving that archival preserves inference
reservations, referenced evidence, memory provenance and idempotency identities.
Do not silently prune evidence or reset reservations to satisfy the bound. Until
that gate passes, local monitoring remains useful but storage growth and sustained
unattended throughput are unqualified.

## Bounded SDLC pilot · 2026-09-28

The [algent pilot](repository-sdlc-pilot.md) implements standing opportunity
admission, Qwen specialist handoffs, independent microVM verification, bounded
patch correction, reconciled PR/review publication and exact-head CI observation.
Its owned completion gates cover PR-feedback repair, broader capability families,
GitHub App identity, full live crew-journey capture and independent qualification.
Publication alone earns no XP and does not close general autonomy or deployment
gates. The first live blocked attempt is preserved rather than silently retried.

The [live algent evidence](../evidence/sdlc-pilot-20260928/README.md) records an
actual Qwen-authored PR and published review after autonomous patch correction.
Both isolated behavior checks and the downloaded public regression pass; GitHub
Actions is blocked before execution by account billing/spending settings. Two
preceding blocked builds remain retained. No merge or promotion occurred.


## External verification and correction · 2026-09-28

Core/runtime implement an opt-in verifier for exact algent PR heads, independent
GitHub statuses, and bounded, independently reviewed corrections. World projects
nested verification evidence and stage assignments without implying Actions
success or merge. See [ADR 0012](adr/0012-independent-pr-verification.md) and the
[pilot contract](repository-sdlc-pilot.md). Three bounded capability families and exact-head advisory PR feedback are now
implemented locally. Indefinite retention, held-out reliability and qualified
crew selection remain owned gates; development probes do not close them.

## Repository coordination and rapid iteration · 2026-09-28

Core/runtime now implement three bounded algent families, durable prioritized
candidate/no-change/unavailable discovery, dependency handoffs, one recorded
fallback assignment, exact-head advisory PR feedback, independent reverification
and bounded local process recovery. The game exposes those contracts and retained
assignments. [Implementation and completion gates](repository-capabilities.md)
distinguish installed compatible crews from independently qualified builds.
The default [iteration trial](autonomy-trials.md) is one control cycle with a
15-minute maximum; optional two-hour soak is separate. All attempts and source
digests are retained. The live monitor was not restarted; qualification, merge,
XP and deployment are not inferred from local controls.
