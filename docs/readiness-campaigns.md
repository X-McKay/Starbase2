# Readiness Run book comparison

Status: proposed

Implemented: local pilot harness. Capability qualification remains open.

Owner: runtime/evaluation. The development owner authorized local Qwen inference,
isolated cluster tests, and generous local token allowances.

## What this adds

The [campaign runner](../scripts/readiness/campaign.py) compares two immutable
Crew builds against real disposable Kubernetes/Flux fixtures. The baseline uses
the existing diagnostic prompt. The candidate adds one versioned
[Readiness diagnosis Procedure](../services/runtime/starbase_runtime/agents/readiness/runbooks/readiness-v1.md)
to its Run book. Their model, settings, provider profile, tools, typed output,
authority, memory policy, and budgets are identical.

The Procedure separates route repair from dependency and functional failures.
It asks the Crew member to check useful work, preserve correct probes, and stop
when enough evidence supports a decision. Both builds receive the published job
contract, `value * value + 1`; expected grader answers stay outside the model.
These builds extend the previous single-route baseline with a broader task prompt
and service-contract projection. The historical Qwen success remains a different
build, not an interchangeable trial in this comparison.

| Public scenario | Appropriate decision | Independent evidence required |
|---|---|---|
| Incorrect HTTP probe routes | Repair | Exact Git/Flux revision, stable Ready, correct jobs through Pod and Service |
| Healthy workload | Wait without mutation | Unchanged manifest and stable useful work through both paths |
| Persistent dependency failure | Abstain | Correct probes, unchanged manifest, fresh stable unresolved failure beyond the observation deadline |
| Ready but incorrect job results | Abstain | Correct probes, unchanged manifest, fresh stable Ready with incorrect functional results |

An abstention is a Crew decision, not a mission success verdict. The evaluator
collects a fixed 45-second observation window after the Crew stops and independently
checks whether abstention was appropriate. A healthy workload gets no credit for
unnecessary abstention. Missing or stale observations invalidate the trial. These
local evaluations award zero XP.

## Frozen protocol and execution

Before cluster creation or inference, `plan.json` records the question, complete
build manifests, Procedure content, source hashes, toolchain, metric, practical
margin, trial order, invalidation, and stopping rules. Source copies are retained
alongside it. Every trial must match that declaration at admission. Existing
directories cannot be reused or resumed; no failed trial is silently replaced.

The pilot has four task strata, one pair each, for eight trials. Baseline runs
first in alternate pairs; candidate runs first in the others. Each trial gets
a fresh cluster, Git repository, observation receipts, model conversation, and
mission journal. No mutable agent memory carries between trials. Trials execute
serially on the same dedicated VM; image caches and unmeasured provider cache/load
are shared environmental limitations. Requested and reported model identities
are retained; the served weights digest is unresolved.

The primary metric is the candidate-minus-baseline difference in appropriate
verified decisions. The predeclared practical margin is ten percentage points,
but this small public pilot cannot establish that margin or equivalence. One
pair per stratum does not estimate within-task stochastic variance. Reports
therefore remain **inconclusive**, **invalid**, or **ineligible**. No confidence
interval is fabricated. Per-trial failures, complete-pair differences, token and
latency distributions, and inference calls remain visible.

Budget-limited or malformed model outputs are candidate failures. Environment,
missing-evidence, and incomplete runs invalidate the comparison. Scope and
integrity failures are hard gates. Cleanup failure stops later trials; cancellation
and build drift also stop dispatch. Other failures remain recorded while the
declared trial schedule continues. Analysis produces evidence-linked improvement
opportunities and always retains the baseline. It neither edits the Procedure
nor changes a live build, qualification, memory, or permission record.

## Commands and recovery

With the dedicated `starbase2-readiness-lab` VM running:

```sh
just readiness-campaign .local/readiness-campaigns/new-scripted
just readiness-campaign .local/readiness-campaigns/new-qwen --mode inference
```

Scripted mode supplies known authored decisions for wiring checks and has zero
provider calls. Inference mode uses the authorized development endpoint; it never
falls back to a scripted model. Eight trials permit at most 64 provider requests
and 1,024,000 reported tokens across individual 128,000-token limits. Actual usage
is retained; monetary cost is unknown. See [mission limits](readiness-missions.md).

A single scenario/build can also be exercised:

```sh
just readiness-mission .local/readiness-missions/healthy-control --scenario healthy
just readiness-mission .local/readiness-missions/dependency-candidate --scenario persistent-dependency --variant runbook-v1 --mode inference
```

Create `CANCEL` in the campaign directory to fence subsequent model and lab
commands and stop later trials. A trial-local `CANCEL` fences that Crew session;
its cancelled result also stops the campaign. Already-started commands may finish.
Cleanup bypasses cancellation and removes only the owned cluster. The campaign
does not start or stop the VM itself: the operator or supervising process must
stop it after execution. The original `kz-eval` VM and its workloads are preserved.

`campaign.json` is an atomic local progress/analysis record. Each trial retains
`mission.json`, `report.json`, raw observations, exact revisions, and source copies.
A crash leaves its active trial inspectable and does not authorize replay. Use
the existing independent cleanup path for that exact cluster. Never use the
ambient Kubani kubeconfig for this lab.

## First Qwen pilot · 2026-09-25

The [retained eight-trial pilot](../evidence/readiness-pilot-20260925/README.md)
completed with baseline **3/4** and Procedure candidate **4/4** appropriate decisions.
The baseline incorrectly accepted wrong job outputs as healthy; independent
verification rejected that trial. The candidate identified the functional defect
and abstained. The observed paired difference was +25 percentage points, with
40 total provider requests and 98,957 reported tokens. All eight clusters were
cleaned up. No trials were excluded or replaced.

The declared comparison remains **inconclusive** and retains the baseline. These
public single pairs do not establish general improvement or a qualification.
The runner recorded the failed baseline trial as a concrete improvement opportunity.
Supplemental rationale review also identified unsupported root-cause speculation,
which needs its own diagnostic-grounding checks in a later protocol.

Thirteen campaign tests cover expected decisions, fresh evidence, unsupported
abstention, scope/cleanup gates, immutable build differences, paired scheduling,
retained failures, interrupted campaigns, cancellation, and rejection of claimed
success when observations disagree. The existing mission and fixture controls
remain part of the full Python verification suite. The final suite passed **209
tests**; Ruff, ty, documentation validation, and `git diff --check` also passed.

## Remaining gates

Runtime/evaluation owns transient-recovery, stale-evidence, adversarial, and
independently held-out task families. Complete that gate with a fresh protocol,
repeated paired trials and uncertainty estimates before capability qualification
or promotion. Public development cases cannot become hidden tests by relabeling.

Runtime/core owns durable mission and campaign integration. Complete that gate
with core-owned immutable builds and dispatch/effect records, additive workflow
contracts, restart/cancellation reconciliation, and independent grading. Local
JSON journals are not the product ledger and should not drive the game directly.

Runtime/world owns the Crew sheet and Engineering comparison journey after durable
integration: display Procedure/build differences, each trial, uncertainty, and
recommended next work through both spatial and keyboard-accessible interfaces.
That journey requires authoritative projections and native interaction evidence.

Trainer automation remains a later owned step: use retained failure evidence to
propose a new immutable candidate, budget its campaign, and record a recommendation.
Completion requires duplicate-safe scheduling and reviewable provenance; no agent
may alter its grader, promote itself, or turn practice success into field XP.

## Product integration handoff

Inspection of the current owners found that
[`FieldObservationV4`](../services/runtime/starbase_runtime/field_workflow.py)
coordinates read-only work and
[core repair actions](../services/core/src/repair.rs) authorize bounded synthetic
code execution. Neither contract currently represents a Git/Flux readiness effect.
Reusing their existing success or XP fields for these lab trials would imply
capabilities they do not own. Extend the same core and worker with additive records;
a new service is unnecessary for the next local slice.

| Current lab evidence | Durable owner / later presentation |
|---|---|
| Frozen plan and build manifests | Core Campaign and Build records; Engineering comparison detail |
| Tool observations and decision | Worker evidence artifacts referenced by core Run; Crew sheet activity/history |
| Publication intent, target and revision | Core Action plan and attempt ledger; explicit pending/uncertain state |
| Independent revision/functional checks | Trusted verification receipt; outcome distinct from model rationale |
| Complete paired trials and uncertainty | Core Campaign analysis; per-trial results and recommendation |
| Failure-linked opportunities | Trainer findings with provenance and deduplication; proposed next campaign |

Before wiring the first live animation, exercise crash points before publication,
after Git push but before acknowledgement, during Flux reconciliation, and during
verification. An uncertain push must be reconciled against the exact repository
and revision before another dispatch. Exercise stop and duplicate delivery at each
boundary. Replay old workflow histories unchanged. These are implementation
acceptance criteria, not claims about today's standalone JSON runner.

The pilot's primary outcome measures the appropriateness and verified effect of
an action. It does not score every sentence in the model's rationale. Diagnostic
specificity and explanation grounding need separate checks before a capability
claim: a correct abstention can still contain an unsupported root-cause guess.
Preserve such observations as supplemental findings without changing a running
campaign's declared metric or selectively rescoring its trials.

A trial's `outcome` grades the decision; its nested `grade` retains the underlying
workload check. These can differ deliberately: safe abstention on a broken service
passes the decision check while the service remains unresolved. In the current
public grader, dependency failure is `blocked`; the Ready-but-wrong-output case
fails the dependency-escalation check and is separately recognized from its fresh
functional observations. Neither should appear as a repaired or healthy workload
in a future game projection.
