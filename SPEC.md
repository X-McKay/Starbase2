# Starbase2 product proposal

Status: proposed

Owner: Al McKay (X-McKay)

Date: 2026-09-05 UTC

## Product promise

Operate an autonomous crew through a polished, inhabited 2.5D outpost. See what
each agent is doing, inspect why it acted, compare ways to improve it, and
decide which capabilities it may exercise in the real world.

The world is part of the product from the first release. Durable execution and
the evaluation loop are also part of the first release; neither is a later
backbone to retrofit beneath a decorative demo.

## The daily experience

Open the outpost in the morning. The Watchkeeper has investigated a recurring
workload failure, the Surveyor has prepared a repository review, and the Scout
has assembled a short AI-news briefing with sources. A notice in the Workshop
shows a dependency update awaiting review. The Dojo has compared a proposed
skill change against the incumbent and found the result inconclusive.

Walk up to a crew member or use the command palette. Its character sheet shows
the exact build, current assignment, observed capabilities, recent mistakes,
budget, and linked evidence. Select an assignment to follow the causal path
from observation through work, evaluation, decision, and outcome.

The user can enjoy the world passively, investigate through it, or switch to a
compact operations view without losing information or controls.

## Core entities

| Entity | Meaning |
|---|---|
| Crew member | Persistent identity, appearance, history, and active build reference |
| Build | Immutable code, model, prompt, skills, tools, memory snapshot, and settings |
| Duty | A bounded recurring responsibility with triggers, targets, and budgets |
| Finding | Evidence-backed observation that may deserve work; also called a Bounty in the UI |
| Mission | Accepted work with a goal, target, acceptance checks, and authority |
| Run | One bounded attempt; an evaluation run is presented as a Sortie |
| Scenario | Versioned task, fixtures, constraints, and evaluation contract |
| Campaign | Paired baseline/candidate trials and their analysis |
| Action plan | Exact proposed external effect, preconditions, verification, and recovery |
| Evidence | Classified, immutable artifacts and attributable observations |

Use these concepts before inventing new domain nouns. Parallax Command,
Captain's Log, and Reality Gate may remain useful UI names; they do not imply
separate services.

## Requirements

- **SBT-001:** A crew identity persists while individual runs are bounded and
  replaceable. Record the immutable build used by every run.
- **SBT-002:** Duties execute on schedules or relevant changes without an open
  client. Enforce overlap, concurrency, retry, time, and spending limits.
- **SBT-003:** Every operational world state links to timestamped backend
  evidence. Missing or stale evidence cannot appear healthy or successful.
- **SBT-004:** Every operational journey is available through a structured,
  keyboard-accessible surface independently of rendering and travel animation.
- **SBT-005:** Evaluation compares immutable candidates with an incumbent on
  identical scenario versions, reports individual trials and uncertainty, and
  distinguishes improved, regressed, equivalent-within-tolerance, inconclusive,
  invalid, and ineligible outcomes.
- **SBT-006:** Deterministic correctness, authority, isolation, and integrity
  gates cannot be outweighed by a quality score or low cost.
- **SBT-007:** Cosmetic XP, evidence of proficiency, and permission to act are
  independent. Levels and model self-assessment never grant permissions.
- **SBT-008:** External effects require deterministic authorization, exact
  targets, fresh preconditions, stable idempotency, and outcome verification.
- **SBT-009:** Worker restart, duplicate delivery, missing dependencies, and
  uncertain external outcomes preserve inspectable state and safe recovery.
- **SBT-010:** Agent improvements are proposed as new builds, evaluated in
  isolation, and promoted through a recorded policy decision. Agents cannot
  rewrite their own evaluator, permissions, or production build pointer.
- **SBT-011:** Local development and baseline tests work without Kubani access,
  production credentials, or mandatory model downloads.
- **SBT-012:** Kubani hosts an independently scoped installation through its
  GitOps configuration. Starbase2 is not the sole recovery path for itself.

## Initial roster and autonomy

| Crew | Useful duty | Initial result | Later capability |
|---|---|---|---|
| Surveyor | Review repository changes and PRs | Local review with line-level evidence | Publish an authorized review; prepare repair PRs |
| Watchkeeper | Reconcile workload and Flux health | Diagnosis and runbook proposal | Execute narrowly pre-authorized reversible operations |
| Scout | Monitor AI papers, releases, and announcements | Deduplicated briefing with sources and uncertainty | Topic research and scheduled internal digests |
| Warden | Match advisories to actual dependencies | Applicability finding and update proposal | Prepare tested dependency-update PRs |
| Trainer | Investigate recurrent agent failures | Candidate skill/tool/prompt changes | Budgeted exploration campaigns |

Implement the Surveyor first. Trainer is a role using the same runtime, not a
special self-modifying controller. Start autonomous observation and internal
analysis early. Add authority for external publication and mutation by action
class; do not equate useful autonomy with unrestricted cluster access.

## Non-goals for the first release

Multiplayer, a general agent marketplace, a custom workflow engine, distributed
world simulation, automatic model fine-tuning, unbounded agent chatter, broad
cluster repair, and rewriting every capability from either predecessor.

## Acceptance journey

A fresh local checkout launches a fixture-backed outpost. A repository finding
creates one Mission and one Python agent run. The Surveyor moves to its desk;
the operator can inspect its evidence in at most three interactions. Killing
and replacing a worker preserves the run. Duplicate delivery creates no second
Mission. Two build variants enter the Dojo; a known regression is detected, and
both trial results remain inspectable. Stale data becomes visibly stale. The
same journey works without the spatial scene and makes no external changes.

See the [architecture](docs/architecture.md), [evaluation design](docs/evaluations.md),
[experience](docs/experience.md), and [delivery gates](docs/roadmap.md) for the
proposed realization. These documents do not change either predecessor's
accepted specifications.
