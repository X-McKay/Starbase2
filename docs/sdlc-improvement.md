# SDLC Trainer queue and operational metrics

Status: accepted local advisory pipeline (2026-09-28).

The runtime derives an improvement backlog from Core's `/v7/snapshot`, without
reading Core SQL or calling a model. `sdlc_improvement.derive_report(snapshot)`
returns retained attempt provenance, descriptive metrics, deduplicated immutable
experiment proposals and predeclared matched pilot plans. The optional periodic
runtime hook writes reports with `write_report(directory, report)`; reports are
content-addressed and never overwritten. This is an artifact projection, not a
second mission authority or a new service.

Generate a report from retained Core snapshots or family-probe exports:

```sh
PYTHONPATH=services/runtime .venv/bin/python scripts/sdlc_improvement_report.py \
  .local/sdlc-family-probe-*/results.json --output .local/sdlc-improvement
```

The fixed classification rules propose digest-bound whole-symbol replacement
for patch rejection, verification-interpretation Procedures for reviewer
conflicts, inspect/edit/test Procedures for behavioral failure, a pinned
reasoning configuration experiment for provider/output failures, and scope
preflight checks for hard-gate failures. These are hypotheses, not diagnoses
proven by the available record. Repository text and model suggestions cannot
change these rules, the grader, a build, permissions, or XP.

Each proposal has a stable digest over the baseline, family and single changed
factor. Additional matching failures attach evidence without inventing a new
candidate. Campaign queue entries declare paired counterbalanced execution,
public scenario strata, two repetitions per task, a maximum of 20 pairs, a
five-percentage-point practical margin, explicit hard gates, retention of
invalid and failed trials, and a fixed completion/budget stop. These bounded
public pilots estimate variance; their count is not a statistical qualification
claim. Execution remains blocked until candidate, fixture, environment and
grader digests are frozen. A held-out confirmatory campaign is separately needed
before a promotion recommendation; the Trainer itself never promotes.

Agility reports recovered completed attempts divided by attempts with observed
patch failures or a Core reassignment. Speed retains invocation latency values,
median and nearest-rank p95. Constitution reports observed input plus output
tokens across successful and failed calls. Missing usage is explicitly unknown.
Repeated copies of the same call envelope in event history are deduplicated;
identical real call envelopes can therefore undercount consumption until
invocation identifiers are universally retained. The report exposes this limit.
Old raw event history does not contain independently graded intermediate
verdicts, so earlier behavioral failures are not guessed. Core's current verdict
and reviewer decision determine the narrow verified-repair indicator.

These operational measurements are dependent, incomplete development samples.
No confidence interval or capability level is fabricated. Active attempts remain
separate from completed attempts, and all reports retain record digests and
mission identities. A local report is not proof that a live worker has loaded
this code, and successful deterministic tests do not qualify model quality.

`freeze_campaign(entry, candidate_build=..., fixtures_digest=...,
grader_digest=..., environment_digest=..., task_ids=[...])` binds a queue entry
into a content-addressed executable *plan*. It validates hexadecimal identities,
requires a different candidate, bounds task count to ten, generates two
counterbalanced pairs per task, and reconstructs hard gates from trusted code
instead of accepting modified queue fields. It does not dispatch inference or
issue execution authority. A campaign runner must still enforce the independent
sandbox, budgets, and the frozen protocol.
