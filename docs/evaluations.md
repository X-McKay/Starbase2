# Evaluations and agent improvement

Status: proposed

## Implemented local repair extension · 2026-09-05

The [repair extension](repairs.md) executes baseline and candidate code in separate disposable VMs. The core grades six exact input/output cases per stage and retains all observations, hard gates and narrow qualifications. The three-call repair pilot is a functional smoke and duplicate-credit check, not a statistical quality comparison or a general repair benchmark.

The implemented v2 gym and the two-endpoint inference pilot are documented in
[operations](operations.md). Static conformance improvement/regression is measured
on six public cases; the twelve-call model pilot is exploratory and does not
qualify a build. The original v1 fake campaign below remains a regression control.

Implemented subset: the [local experiment](local-slice.md) grades six public
synthetic trials in Rust and retains each output, exact builds, latency, fake-model
provenance, hard gates, and comparison. A known regression is detected; equal
controls are inconclusive for real quality. There are no sealed holdouts, qualified
process isolation, stochastic confidence estimates, or promotions yet.

## What we can promise

For a defined workload and budget, Starbase2 should reliably detect meaningful
regressions and improvements, retain the evidence, and say when it cannot tell.
It cannot prove that an arbitrary stochastic agent change is universally better.
Even a deterministic test suite establishes behavior only over what it covers.

Separate three questions:

1. Does the software still work? Unit, contract, integration, workflow replay,
   authorization, and UI tests answer this.
2. Does this agent build perform better on representative tasks? Paired
   scenario trials and independent graders answer this.
3. May this build or its output act on this target now? Policy and deployment
   verification answer this. Test results do not grant authority.

## Immutable builds

An agent Build digest covers code revision, dependency lock, container digest,
model/provider identifier and resolved version where available, prompt, skills,
tool implementations and schemas, sampling and reasoning settings, context
policy, memory/retrieval snapshot, and policy profile reference. Store requested
and actually served model facts separately. Provider aliases can change;
unresolved provenance is a limitation, not a reproducibility claim.

Every run binds its build, scenario version, fixture digest, grader revision,
environment, budgets, cache state, and intervention history. Different memory
or tool configuration is a different experimental condition. Freeze it rather
than letting a shared live memory store contaminate comparisons.

## The gym loop

1. Select a capability and a concrete failure hypothesis.
2. Freeze the current production build as baseline.
3. Create a candidate branch changing one factor for an interpretable trial;
   use deliberate factorial comparisons when interactions are the hypothesis.
4. Run cheap deterministic checks and public development scenarios.
5. Run a predeclared paired campaign on sealed, held-out task families.
6. Verify artifacts in a clean environment outside the candidate's control.
7. Inspect quality, reliability, cost, latency, interventions, and uncertainty.
8. Recommend the candidate, retain the baseline, or request more evidence.
9. A separately authorized promotion changes the active build reference for
   new runs; existing runs keep their original build.

Trainer may generate candidate patches and choose public practice tasks within
its exploration budget. It cannot read hidden tests, alter the final grader,
change the active build, grant tools, or keep retrying until it finds a lucky
pass. An improvement attempt may produce a useful failure report and no change.

## Scenario families

| Duty | Deterministic evidence | Supplemental quality assessment |
|---|---|---|
| PR review | Seeded bugs, valid file/line references, false positives on clean changes, injection resistance | Actionability and explanation quality |
| Kubernetes diagnosis | Disposable/synthetic failures, root-cause and target matching, no-action controls, denied-operation tests | Quality of a recovery proposal |
| Dependency update | Reproducing vulnerable condition where feasible, applicability, patch scope, compatibility and clean tests | Maintainability of the repair |
| AI-news monitoring | Citation resolution, timestamp correctness, deduplication, claim-to-source checks, no-news cases | Relevance, completeness, and calibrated uncertainty |

A valid citation alone does not prove a claim. News evaluators check whether the
source supports the assertion and whether an announcement, result, and opinion
are distinguished. Freeze source snapshots for offline comparison. Evaluate
freshness against live sources separately under an approved read-only policy.

Use easy, typical, ambiguous, adversarial, and recovery cases. A family is the
unit of diversity; many repetitions of one trivial task do not certify a role.

## Comparison protocol

Declare the primary metric, task population, minimum useful improvement,
regression tolerance, sample budget, stopping rule, and invalidation rules
before running. Pilot measurements estimate variance and determine the final
sample size. Do not encode an unexplained universal "three runs is enough" rule.

As an illustrative PR-review campaign, use 40 independent task cases across
several defect families with five repetitions per build and case: 400 total
baseline/candidate runs. This is an initial budget example, not a power claim.
Pair inputs, randomize/interleave candidate order, isolate caches and memory,
and record shared model-server load. Seeds cannot guarantee deterministic
behavior from hosted providers.

Score every run independently. Compute per-case averages and uncertainty over
independent cases, using a paired cluster bootstrap when repeated runs are
nested within cases; do not treat all 400 runs as independent tasks. For a
binary primary outcome, a predeclared paired method must respect the same
clustering. Retain raw data, analysis code, exclusions, and interval bounds.

Example decision rule: recommend a quality improvement only when the 95%
interval for the paired delta lies above the predeclared practical threshold,
all hard gates pass, and cost and latency remain within their limits. Recommend
a cheaper build through a separately declared non-inferiority quality margin.
Claim equivalence only when the whole interval lies within the equivalence
margin. Otherwise report inconclusive. Failure to detect a difference is not
proof of equivalence. Critical workload strata have separate regression limits.

Correct for planned multiple comparisons or use exploratory results only to
select candidates for a fresh confirmatory set. Repeated tuning against a final
holdout exhausts its independence; rotate and protect holdouts with an explicit
exposure ledger. Do not stop early only because the favored candidate is ahead.

Hard policy, isolation, secret, integrity, and mandatory correctness failures
make a candidate ineligible. Cost cannot compensate. Keep candidate errors,
timeouts, budget exhaustion, provider failures, grader errors, and invalid or
contaminated trials separate. Retain valid failures. Infrastructure exclusions
must follow the predeclared rule and remain visible in the report.

## Graders must earn trust too

Prefer executable checks and reproduced artifacts. Test the graders against
known positive, negative, boundary, and malicious submissions. A candidate's
"tests passed" message is never the test result.

For subjective rubrics, blind model judges to candidate identity/order, validate
their agreement with human-reviewed examples, and show disagreement. Judges
see candidate output as untrusted quoted data. Use independent execution and
access permissions even when one maintainer owns both codebases.

The inherited scorer is a cautionary example: unioning finding sets from
repetitions can allow collectively complete but individually incomplete runs
to pass. The [research record](research.md) includes a local reproduction.
Starbase2 will preserve each trial rather than port this aggregation.

## Progression is derived evidence

The cosmetic ledger awards XP only for uniquely attributable, independently
verified useful outcomes. Use idempotent award IDs; a rerun cannot repeatedly
earn the same achievement. Bound repeat-task rewards and distinguish practice
from field accomplishments. Correct no-change and safe abstention can earn
recognition; churn, tool-call volume, tokens, and invented work cannot.

Proficiency is scoped to capability, build digest, scenario version, diversity,
sample size, uncertainty, and recency. A crew member can keep its lifetime
history when switching builds, but the new build begins unqualified for claims
not supported by applicable evidence. Expired qualifications remain historical
achievements with visibly stale current evidence.

Permission is a separate policy record. Neither XP nor a qualification creates
an automatic promotion, changes memory, or increases production authority.

## CI and operations

Run deterministic fake-model regression tests on every affected change. Run
small model-backed smoke campaigns on relevant agent changes under explicit
budgets; use broader scheduled or release campaigns for statistical claims.
Infrastructure failures must not randomly turn a merge green or red without a
distinguishable result. Do not purchase inference or run campaigns by virtue of
this proposal.

Retain private evidence under scoped access and declared retention; store
large traces outside workflow histories. Keep evaluator reliability,
inconclusive rate, test leakage, cost, and sandbox cleanup failures visible.
