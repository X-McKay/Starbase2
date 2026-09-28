# Rapid autonomy iteration trials

Status: accepted local validation procedure, 2026-09-28. Owner: evaluation/runtime.

The default iteration window is **at most 15 minutes**, replacing the proposed
72-hour first trial. Finish as soon as the predeclared control cycle completes;
there is no idle wait to make a short run look like sustained operation. An
optional two-hour repeated-control soak follows stable iterations. Neither
window establishes general agent reliability or grants publication authority.

## Run the local controls

Build the compatible Core and install the pinned Python environment and local
Temporal CLI before running. The existing integration scripts require free
loopback ports and start their own Core/Temporal/worker processes. They do not
use the running monitor or its database. Their provider, model and sandbox
adapters are synthetic; no real GitHub effects or model requests occur.

```bash
cargo build -p starbase-core
.venv/bin/python scripts/autonomy_trial.py
```

Use `--duration-seconds 180` for a shorter hard execution budget. The script
writes an immutable-input manifest before dispatch and a cumulative result after
each control under a fresh private `.local/autonomy-trial-*` directory. The
manifest records source, fixture, contract, dependency-lock and Core binary
hashes, Python version, scenario coverage, budgets, stopping and failure rules.
Changes during the trial invalidate the run. Existing evidence is never replaced.
The child controls retain their own workflow histories and raw records, linked
from the trial results. Logs can contain repository evidence; keep them local.

```bash
.venv/bin/python scripts/autonomy_trial.py --profile soak
```

Soak repeats the complete control sequence within a two-hour maximum. It does
not retry a failure until green: the first failure stops the run and remains in
the report. A deadline during an unfinished control is a nonpassing truncation,
not an assumed successful remainder. It is a synthetic restart/replay soak,
not an unattended live repository or local-model qualification campaign.

On timeout or interruption, SIGINT gives the control's cleanup blocks up to
45 additional seconds to stop owned processes. A forced termination is marked
`requires_inspection`; inspect the retained control logs and its owned processes
before another run. Never stop unrelated processes to clear a port conflict.

## What the current control cycle establishes

| Scenario | Executable evidence | Remaining limitation |
|---|---|---|
| Discovery to PR | Synthetic persistence finding runs through real Core/Temporal | One known family |
| Restart | Core and worker restart; workflow histories replay | Not host reboot or always-on service recovery |
| Duplicate effects | Lost status acknowledgement reconciled with bounded effect counts | Not broad provider outage recovery |
| Changed published head | Failed old head and passed corrected head verified separately | Not a competing writer race |
| Healthy/no-change | Corrected source rules create three no-change observations and zero new missions | Synthetic discovery controls, not repository health certification |
| PR feedback | Explicitly `not_covered` | Needs actionable and conflicting comment journeys |
| Provider interruption | Discovery interruption retains unavailable findings, then recovers without duplicate missions | Does not cover interrupted publication or prolonged outage escalation |
| Concurrent head drift | Explicitly `not_covered` | Needs external-writer rejection/reconciliation journey |
| Cancellation | Explicitly `not_covered` | Needs interrupted full-workflow cancellation journey |
| Multi-family discovery | Three prioritized families run through product activities and Core grading | Synthetic provider/model/VM; missions explicitly cancelled before publishing |
| Bounded reassignment | Invalid memory proposal is retained and not executed; Core reassigns Rivet to Moss | One authored fallback, not dynamic team formation |

A passing exit code means only `wiring_result=passed`. The report always preserves
`autonomy_qualification=not_qualified` and `model_qualification=not_attempted`.
Missing gates cannot become successful because time elapsed or another scenario
passed. The coordination control deliberately makes three local operator cancellations
after verified candidates, before publication. Those are declared interventions;
it does not claim completed PRs or an intervention-free trial. Core restart
preservation is exercised there; Temporal replay belongs to the other controls.

Each control must exit successfully and provide matching, explicitly
synthetic completion evidence. Failed, missing, malformed and source-contaminated
evidence remain distinguishable. No promotion, XP, permission, merging or
live policy/configuration changes are performed.

## Next live iteration gate

The runtime owner must add executable journeys for the missing matrix rows,
then freeze the supported task population and real model/build identities before
a separate bounded algent operating trial. Record all human interventions,
model attempts and invalid trials; changing code during a trial invalidates it.
Report verified useful PR outcomes, false successes, duplicate effects, losses
of cancellation and unresolved effects separately. Keep human merge decisions
separate. A 15-minute live pilot is exploratory; expand to the optional two-hour
window only when enough representative work occurs to justify it. Statistical
capability comparisons follow the [evaluation protocol](evaluations.md), not
elapsed-time targets. Repository rollout remains subject to the
[capability completion gates](repository-capabilities.md).
