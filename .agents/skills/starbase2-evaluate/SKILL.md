---
name: starbase2-evaluate
description: Design, run, or interpret Starbase2 scenarios and baseline-versus-candidate evaluations, including prompt, tool, skill, model, and performance comparisons. Do not use for ordinary deterministic unit tests.
---

# Produce a defensible comparison

Use [the evaluation protocol](../../../docs/evaluations.md). Determine whether
the user requested design, analysis of existing results, or execution. Preserve
the authorized scope and budget; a design request does not start paid trials.

Before execution record the question, immutable baseline/candidate, scenario
population, fixtures, grader/environment versions, primary metric, practical
margin, hard gates, sample/stopping rule, and treatment of invalid trials.
Use a pilot to estimate variance rather than asserting an arbitrary repetition
count is sufficient. Validate graders with known good/bad controls.

Keep hidden cases and evaluator credentials outside candidate access. Isolate
workspaces and mutable memory/cache state. Pair task inputs, interleave or
randomize order, and retain actual model/provider facts and resource contention.
Hosted-model seeds are not a determinism guarantee.

Grade each run independently. Never union findings across repetitions, report
only the best run, discard valid failures, or stop when the preferred result
appears. Repeated runs within one task are clustered; use uncertainty methods
that respect that dependency. Preserve per-task outcomes and important strata.

Hard correctness, policy, privacy, or integrity failures make a candidate
ineligible. Distinguish candidate failure, budget truncation, infrastructure
failure, grader failure, and contamination. Missing evidence is not a low score.
Subjective model judges supplement executable checks and calibrated rubrics.

Report improved, regressed, equivalent within a predeclared margin, inconclusive,
invalid, or ineligible as supported. Failure to detect improvement is not proof
of equivalence. Exploratory multiple comparisons require a fresh confirmatory
evaluation or a declared correction before superiority claims.

Return revisions, counts, exclusions, distributions, uncertainty, hard gates,
cost/time, analysis artifacts, and recommendation. A recommendation changes no
active build, memory, XP, or permission by itself. Inspect existing authorization
before requesting any additional approval for a separately requested promotion.
