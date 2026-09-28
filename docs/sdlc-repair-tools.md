# Tool-enabled repository repair

Status: accepted

Owner: runtime/evaluation. Implementation checkpoint, 2026-09-28. User authorized
all recommended improvements; checkpoint publication does not activate a build.

New immutable SDLC profiles package engineering, diagnosis/review and recovery
Procedures with PydanticAI tool sessions. `STARBASE_SDLC_AGENT_PROFILE` selects
`legacy` (default), `tools`, or `tools-thinking` at process start. Procedures,
settings, tools and source hashes enter the Build. Existing histories still need
their compatible pinned worker. No profile selection grants qualification.

Tools inspect symbols, search captured source, apply exact multiline replacements,
replace a complete function, inspect the applied diff, validate syntax/scope, and
run the fixed public suite in an isolated microVM. Digests reject stale edits;
AST and textual fences preserve signatures and unrelated source. Syntax failures
leave the last valid workspace intact. No candidate code executes on the host.
A final submission must match the exact artifact with passing public tests and
an inspected diff. Core independently regrades it and review/publication retain
their original authority gates. Read-only lead/reviewer sessions cannot edit.

The tool loop allows twelve model requests and 32 tool calls within 125 seconds
and 262144 total-token allowance. Each provider dispatch reserves bounded input
and output; provider retries remain disabled. Tool/schema feedback can lead to
another recorded request within that allowance. Guards fence dispatch and poll
during model/test execution; cancellation awaits owned coroutine cleanup without
claiming remote inference compute was recalled. Repeated failures/artifact cycles
and lack of progress stop the workspace. The fallback implementer loads a distinct
recovery Procedure, without claiming a different model or qualified proficiency.

`tools` uses Qwen non-thinking settings; `tools-thinking` is a separate candidate
configuration. The served model name and available usage are retained. An endpoint
alias or reported name does not establish immutable server weights/quantization.

## Evaluation and unattended readiness

`scripts/sdlc_tools_campaign.py` declares nine public development trials: three
families and three profiles in counterbalanced order. Each child runs in a fresh
process with publication disabled. Source/configuration hashes, all failures,
usage completeness and result classes are retained. No best-of selection or
hidden retries. This runner is implemented; its new live campaign was **not run
before this commit checkpoint**. Tool-enabled quality improvement is unproven.

The expanded rapid trial adds real-Core/trusted-adapter synthetic resilience
controls. These cover exact-head PR feedback, acknowledgement reconciliation,
head drift and cancellation during adapter waits; they do not qualify terminated
Temporal workers or live provider outages. [Readiness circuits](sdlc-unattended-readiness.md)
gate new discovery admissions while existing work keeps reconciling.
[Trainer reporting](sdlc-improvement.md) derives bounded immutable experiment
proposals once per minute from retained Core snapshots. Reports stop accumulating
at 256 files without deleting evidence. Proposals remain unbound until candidate,
fixture, grader and environment identities are supplied; they cannot promote,
change authority or award XP. There is no automatically activated experiment loop.

Before unattended rollout: complete the frozen model comparison, expand held-out
coverage, qualify the intended identity and backup/stop/recovery controls, then
run a bounded algent canary. Dedicated GitHub App provisioning still requires
owner-account setup. No live monitor restart, migration, merge or deployment is
part of this checkpoint.
