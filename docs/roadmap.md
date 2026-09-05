# Delivery plan

Status: proposed

Owner for initial work: Al McKay (X-McKay), with implementation assistance.
Stage boundaries are evidence gates, not time estimates. All items below remain
planned unless explicitly marked complete.

## 0. Design foundation — delivered in the initial repository

Create the private Starbase2 repository, record source research, articulate the
fresh product direction, compare architecture alternatives, and define a
playable walking skeleton. Add a short shared engineering charter and
documentation validation. This does not establish runtime or deployment readiness.

## 1. Prove the two riskiest seams

**Durability spike:** one PydanticAI agent, a fake model, Temporal, and one
typed Rust API. Kill the activity worker mid-run, retry a result submission,
cancel work, and replay retained history. Prove a stable build digest and one
logical result despite duplicates. Compare direct Python composition with the
maintained Temporal integration; select the simplest passing approach.

**Visual spike:** one small authored Godot scene, three crew, a desk, and a gym
chamber consuming fixture state. Test native and web exports, inspect the scene
at normal and compact sizes, and measure frame time, download/startup, memory,
and time to evidence. Compare an orbital cutaway and an outdoor outpost using
the same state contract. Use a browser-native prototype only if Godot's measured
costs threaten the experience.

Bound each spike to two working days, local synthetic inputs, no paid inference,
and no live credentials. Stop at the budget and report unresolved feasibility
rather than expanding it silently. Retain commands, pins, raw results, and
screenshots. Resolve the proposed foundation ADR from this evidence.

## 2. Deliver one enjoyable end-to-end slice

Build the four services only to support a repository-review Mission. A fixture
observation reaches Control, Runtime runs the Surveyor, Evidence retains a
report, and Godot shows the real journey. A compact console provides the same
inspection and stop controls. The gym compares an incumbent and a deliberately
regressed candidate.

Exit criteria: SBT-001 and SBT-003 through SBT-011 demonstrated on this journey;
duplicate ingestion, worker replacement, missing evidence, stale UI, cancellation,
and grader sensitivity covered. Clean-checkout setup works. No external effects.
Retain at least one actual UI recording and a complete comparison artifact.

## 3. Put the crew on duty

Add recurring repository reviews and source-grounded AI-news briefings, then
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
| Final world theme and web/native priority | Al | Visual spike and operator preference |
| Runtime and library version pins | Al | Durability spike with replay and cancellation evidence |
| Sandbox provider | Al | Before arbitrary-code execution; prove isolation and cleanup |
| Model defaults and budget | Al | Representative paired comparisons on permitted endpoints |
| XP curve and qualification thresholds | Al | Usability trials and grader calibration |
| Artifact storage, retention, RPO/RTO | Al | Before cluster activation; measured restore exercise |
| FalkorDB / Graphiti | Al | Demonstrated relationship or retrieval need exceeding SQL baseline |
| agentgateway | Al | Repeated routing/identity need and measured operational benefit |
| First external-action policy | Al | Named action, target, identity, verifier, recovery, and limits |

Do not implement every row speculatively. Each resolved decision removes an
uncertainty from a concrete delivery stage.
