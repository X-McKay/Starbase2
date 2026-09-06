# Local vertical slice experiment

Status: accepted

Recorded: 2026-09-05 UTC. This is an evidence record, not production acceptance.

## What runs

`just dev` starts a Rust core, Python Temporal workers, and a persistent local
Temporal server. `just demo` creates an idempotent synthetic mission. A fake
PydanticAI Surveyor produces six paired trial outputs; the Rust grader retains
individual findings, build manifests, costs, elapsed times, gates, and comparison.
Godot and the structured journal consume the same timestamped snapshot.

One core owns missions and evidence, allowing atomic completion. This replaces
the proposed four-service starting requirement **for the local experiment**.
The decision and its trust/operating limits are in
[ADR 0002](adr/0002-local-walking-slice.md).

## Predeclared comparison

Question: does either direct PydanticAI composition or maintained Temporal
integration fail the simplest durable execution/evidence seam?

Each mode executes the same three public synthetic cases: unsafe division,
clean abstention, and source text containing an instruction injection. Baseline
is a deterministic finding-producing FunctionModel; candidate deliberately emits
no findings. One trial per build/case, alternating build order, all six retained,
no exclusions and no early stopping. Primary metric: exact findings with valid
file/line/code references. Practical tolerance: zero on these known controls.
Malformed citations are a hard gate. No model provider, tool, memory, paid
inference, or external effect is available.

Build identities cover source hashes, the dependency lock, effective prompt,
fixtures, requested fake model, Python/platform, request limit, and empty tool/memory
configuration. The worker freezes them on startup and refuses a different build.
These are local source manifests, not signed deployable images.

## Observed runtime results

The final experiment completed in **42.772 seconds** on macOS 26.6.2 ARM64,
Apple M5. Python 3.12.13, Rust 1.97.1, PydanticAI 2.40.0, Temporal SDK 1.32.0,
and CLI 1.8.3 / embedded server 1.31.2 are pinned.

| Check | Direct activity | TemporalDurability integration |
|---|---|---|
| Kill worker process during preparation; replace it | Passed | Passed |
| Stale record during six-second worker absence | Passed; last-known running, no evidence | Passed; last-known running, no evidence |
| Duplicate mission ID / same workflow run ID | Passed | Passed |
| Exact evidence retry / changed evidence rejected | Passed | Passed |
| Completed history replay | Passed, 53 events | Passed, 53 events |
| Explicit Temporal CANCELED acknowledgement | Passed | Passed |
| Per-trial fixture comparison | Baseline 3/3, candidate 1/3, regressed | Baseline 3/3, candidate 1/3, regressed |

Cancellation before dispatch, unloaded-build rejection, generated snapshot
validation, and core restart preserving all six missions/evidence also passed.
Twelve Rust tests cover grading, hard gates, duplicates, atomic completion,
immutability, cancellation fencing, failure after a stop request, stale state,
reopening, and refusing a newer database schema. Four Python tests cover the
fake model, build identity, unknown protocol rejection, and additive snapshot
compatibility. Ruff, ty, Rustfmt, Clippy, generated-contract drift, and docs checks
are part of `just check`.

Retained evidence:

- [Final experiment events](../evidence/runtime-2026-09-05/events.json)
- [Direct comparison](../evidence/runtime-2026-09-05/comparison-direct.json)
- [Integration comparison](../evidence/runtime-2026-09-05/comparison-integration.json)
- [Direct history](../evidence/runtime-2026-09-05/history-direct.json) and
  [integration history](../evidence/runtime-2026-09-05/history-integration.json)
- [Restored snapshot](../evidence/runtime-2026-09-05/snapshot.json) and
  [stale running snapshot](../evidence/runtime-2026-09-05/stale-direct.json)

The same event count is not a speed or productivity benchmark. Direct activities
are the provisional default because this one-request/no-tool case needs no finer
recovery boundary. Revisit with a meaningful multi-tool agent. The known regression
establishes grader sensitivity on these fixtures only. It establishes no real
review quality, statistical superiority, injection resistance of a real model,
qualification, or promotion. Confidence intervals are explicitly absent.

## Visual evidence

An original orthographic Godot scene has a workshop, commons, gym, three static
crew, mission selector, and evidence inspector. Only the Surveyor has operational
work; the other crew are labeled decorative. The journal exposes per-trial results,
full manifests, timestamps, and pending stop controls through ordinary DOM elements.
Keyboard Tab/Tab/Enter opened retained evidence and requested cancellation in
the live browser. A requested stop was shown pending before actual Temporal
CANCELED acknowledgement. Disconnect and reconnect with unchanged records were
observed; historical results remained inspectable and stale labels cleared.

- [Normal native evidence view](../evidence/world-inspect.png)
- [Compact native evidence view](../evidence/world-compact.png)
- [Disconnected native view](../evidence/world-disconnected.png)
- [Normal frame sample](../evidence/world-inspect.png.json)
- [Compact frame sample](../evidence/world-compact.png.json)

For these 570-frame samples, reported frame intervals had median 8.33 ms in both
sizes and p95 8.33 ms at 1280×800 / 9.69 ms at 960×720. Engine-reported startup to
first frame was 334 / 351 ms. These are short local smoke measurements with local
services and overlapping capture windows, not GPU timings, stress tests, or a
performance comparison. Steady-state/load memory, 20-task/100-update load, export download latency,
and measured time-to-evidence remain untested.

Native macOS export built with Godot 4.7.2 and its matching installed template
(after enabling the required ARM texture format). The local ZIP is about 57 MiB,
unsigned and unnotarized. The final exported executable also launched and rendered
successfully with the API offline: [launch record](../evidence/native-export.json),
[capture](../evidence/native-export.png). The archive was 59,662,431 bytes and the
single exported-process peak RSS was 220,004,352 bytes on this Mac. The 2.396-second
measurement covers launch plus a 300-frame capture, not startup alone. Web export failed before building because matching web
templates were absent; only the macOS template was installed. No conclusion about
web runtime feasibility follows. Native interaction is demonstrated, not a final
Godot selection or a polished world. Automated Godot state checks distinguish
unknown/disconnected, stale, missing completion evidence, pending, failed, blocked,
no-change, and cancelled labels. Actual assistive-technology testing remains open.

## Failures retained and corrected

- The first Python behavior test failed on the absent runtime module, confirming
  that the initial checkout had no executable slice. Dependencies were then locked.
- One initial Rust grader test failed because candidate ineligibility took
  precedence over an invalid baseline. Baseline invalidity now wins.
- [The first runtime run](../evidence/runtime-2026-09-05/first-run-events.json)
  passed its stated checks, but cancellation logs exposed activity-completion races.
- [A refinement run](../evidence/runtime-2026-09-05/cancellation-race-events.json)
  exposed that premature `CancelledError` could produce Temporal FAILED. Its
  original test falsely accepted any stopped workflow. It is not valid cancellation
  evidence. The worker now waits for Temporal cancellation, the core preserves
  failure, and the final harness asserts actual CANCELED status.
- Visual QA caught a scene behind the inspector and compact text scaling/clipping;
  camera placement, native text sizing, and compact spacing were adjusted.
- Journal reconnect could preserve disconnected labels when data was unchanged;
  failed polling now invalidates the render signature. Focus and open evidence
  survive updates; overlapping polls are suppressed.
- Godot import initially logged sandbox-denied cache writes despite exiting zero.
  The checked-in wrapper now treats logged errors as failures. Validation with
  access to the normal local Godot cache is a separate check, not a hidden rerun.

The integration path emits a Temporal warning about `annotated_types` importing
after workflow load. Replay passed with the pinned versions; this warning is
retained as an upgrade concern rather than suppressed.

## Onboarding and repository checks

A fresh source copy with a new virtualenv and target directory passed
`just bootstrap` (6.834 s) and `just check` (8.179 s). Installed toolchains and
warm dependency/download caches were reused; this is not a cold install or Linux
validation. [The onboarding record](../evidence/onboarding.json) retains the scope
and timings. `mise exec -- just doctor` resolved every pinned tool. Workflow YAML
passed actionlint 1.7.12 with shellcheck 0.11.0; the initially selected old
shellcheck binary could not run on this CPU. No remote CI run was triggered.

## Remaining gates

No PostgreSQL, production identities, hostile-code sandbox, sealed grader storage,
real model/tool execution, provider connectors, scheduling, persistent crew registry,
XP, external effects, or deployment exists. The core's unauthenticated loopback API
and trusted worker share one local administrator trust domain. A candidate cannot
submit a score through the output schema, but hostile-code separation is unproven.

The explicit 100-mission cap, synchronous SQLite store, untyped evidence envelope,
polling snapshots, and one workflow type are scoped experiment choices. A server
restart during active work, full dependency outage, mid-model/tool worker crash,
workflow upgrade compatibility, backup/restore beyond reopening, Linux onboarding,
and the complete product acceptance journey remain open. CI is configured but was
not run remotely in this task. The [roadmap](roadmap.md) assigns owners and concrete
completion conditions to this work.
