# Local operations edition

Status: accepted

Implemented on 2026-09-05 under the owner's authorization to continue local
implementation and test Ollama and `llm.almckay.io`. This is a functional local
operations product, not the complete production vision in SPEC.md.
The [repair extension](repairs.md) adds isolated synthetic writes and earned
progression; repository review itself remains read-only.

## What works

Run `mise exec -- just bootstrap`, then `mise exec -- just dev` and
`mise exec -- just world`. Use Godot's Journal/Operations (`J`) for reviews,
comparisons, local review duties and history; Command (`B`) provides field
observations, repository watches, configured field duties and retained advice.
Connection (`O`) selects the private local Core endpoint. The former browser
dashboard is retired; `/` is a noninteractive API connection page. No model call
happens merely on startup; previously enabled duties continue independently.

- Start a real review of Python files in this checkout or an explicitly synthetic
  training repository. The core freezes the registered build; Temporal orchestrates
  snapshot acquisition, static analysis, optional advice, and evidence retention.
- Inspect line-level findings against retained, masked source, exact build
  manifests, timestamps, and the lifecycle journal. Retained evidence survives
  both core and worker restarts. Repeating an identical snapshot/build records
  `no_change`, with the preceding run linked; warnings remain visible.
- Compare Surveyor v1 against v2 or a deliberately regressed control in the gym.
  Six public cases produce twelve interleaved trials. Rust grades the individual
  outputs; the candidate Ruff process has no grader or core credential.
- Enable a recurring review every 30 seconds, 5 minutes, or 30 minutes. A Temporal
  workflow owns the durable timer and continues as new every 100 ticks. There is
  no browser timer or in-memory scheduler. The first review occurs after the
  interval. A busy target skips the tick instead of growing a backlog.
- Pause/resume the duty and stop individual runs. Pause changes core policy
  immediately, then the worker reconciles the durable timer. Already dispatched
  work is separate. Stops fence late report submission and await Temporal
  acknowledgement; an already started read/model request cannot be retracted.
- Browse pages of twenty historical runs independently of the active dispatch
  feed. Twenty pending runs is the current queue budget, not an archival cap.
- Godot includes structured controls and retained evidence alongside the colony.
  Keyboard navigation does not require walking to a room. Crew poses remain
  decorative projections; labels use authoritative records.

Surveyor and Trainer have stable role identities and completion counts derived
from retained records. Custom crew creation, persistent personality/memory,
build promotion and permission management are not implemented. Their counts are
completed runs, not verified security outcomes. The separate Mender identity,
cosmetic XP, achievements and exact-build repair qualifications are now persisted
by the [repair extension](repairs.md).

## Review boundary

Only `.py` files under the configured local workspace or shipped fixture root
are considered. The snapshot budget is 200 files and 1 MB of original source.
Hidden directories, virtual environments, build outputs, and symlinks are
excluded. Budget, encoding, parse, and analyzer failures remain explicit;
empty or incomplete scope cannot produce a clean certificate. All reviews are
advisory even when every configured check passes.

Python string literal contents and comments are masked before retention. Source
hashes preserve identity and line numbers support citations. This is structural
redaction, **not a general secret detector**: identifiers and numeric literals
remain. Use an authorized checkout. The local filesystem is trusted against
concurrent hostile directory replacement; this is not an arbitrary-code sandbox.
The tool process receives only masked stdin, an empty environment, isolated Ruff
configuration, no fixes, and a ten-second per-file limit. It never executes the
repository's code or follows its tool configuration. Ruff 0.16.6 is locked and
its executable hash is included in the build manifest.

The default profile checks mutable defaults, bare exception handlers, unsafe
`eval`, subprocess shell use, unsafe YAML/pickle loading, disabled certificate
verification, and missing HTTP timeouts. It does not review Rust, resolve a PR
diff, verify runtime exploitability, or establish repository safety. The training
repository is also within this checkout; its intentional warnings are naturally
visible in a whole-checkout review.

## Inference

The optional checkbox is enabled only for the training repository. The provider
receives rule codes, trusted rule meanings, file count, and incomplete-coverage
status. It receives no repository source, filenames, prompts from comments,
credentials, or tool authority. Advice is separately labeled unverified, never
used for grading, XP, or permissions. A malformed/truncated/failed response is
retained as unavailable without automatically retrying the request. Static
analysis remains usable without inference.

Default: `https://llm.almckay.io/v1`, `Qwen3.6-35B-A3B-NVFP4`, temperature 0,
800 output tokens, one call, 60-second request timeout. To use the tested Ollama
model, restart the local launcher with:

```sh
STARBASE_INFERENCE_URL=http://127.0.0.1:11434/v1 STARBASE_MODEL=qwen2.5-coder:7b mise exec -- just dev
```

Only those two development endpoints are allowed. No API key is needed by the
observed endpoints. HTTP model aliases are not immutable weight revisions;
requested/reported models, provider fingerprint, usage, latency, and unknown
monetary cost are retained. Reproducible configuration is not a guarantee of
bitwise hosted inference. The direct HTTP adapter serves a bounded explanation
request; the earlier PydanticAI Temporal experiment remains available as v1.

## Evidence and interpretation

The [first operations experiment](../evidence/operations-first/events.json)
passed real orchestration checks in 44.097 seconds: paired grading, replay,
immutable source/report retention, operator/worker credential separation,
worker-loss freshness, cancellation before dispatch, worker plus Temporal
restart during a timer, pause fencing, and core restart. It also retained a
real model factual failure: codes alone caused S307 (`eval`) to be described as
pickle/YAML deserialization. Infrastructure success was not model correctness.

The [predeclared inference pilot](../evidence/inference-pilot-1788600022164283000/protocol.json)
used three public cases per endpoint, one interleaved pair per case, twelve calls
total, no retries or discarded trials. [All outputs and grades](../evidence/inference-pilot-1788600022164283000/trials.json)
are retained. With code-only prompts the hosted model passed 2/3 and Ollama
1/3 narrow factual smoke gates. With supplied rule meanings both passed 3/3.
This supports including source-grounded meanings in the prompt. It is an
exploratory pilot with insufficient evidence for general superiority, equivalence,
or production qualification; the keyword grader is not a semantic quality judge.

The deterministic gym observed v1 5/6 versus v2 6/6 and v1 5/6 versus the
regression control 4/6. These are exact outcomes on the declared public suite,
not estimates of broader defect detection. Equal case scores are inconclusive.
Invalid infrastructure and hard-gate failures remain separate outcomes.

## Persistence and recovery

[ADR 0003](adr/0003-local-operations.md) records the local boundary. The Rust core
owns all product SQLite tables. Schema v2 migrates v1 in place and preserves old
missions/evidence; an older core rejects the newer schema. Back up both SQLite
stores using SQLite backup facilities or stop the launcher before copying the
files. Rollback requires the previous binary and a pre-migration backup; do not
force an older core to open the new schema. No destructive automatic retention
or cloud backup is configured.

Retained JSON bodies are parsed with correctly rounded float decoding
(`serde_json` `float_roundtrip`). Before 2026-09-07 a stored `f64` timestamp
could read back one ULP away from the value just written, so an exact repeated
transition or resubmission could be misjudged as a change; the Linux onboarding
record retains the failing check and the deterministic regression test.

A launcher-created 0600 token file authenticates internal v2 writes. Operator
commands require an HttpOnly, SameSite=Strict session cookie; cross-origin
browser writes are rejected. Loopback read APIs are accessible to the local user.
The v1 synthetic experiment API remains separately available and unauthenticated;
it cannot create v2 work or act on a repository. This is a single-user local
trust domain, not multi-tenant authorization or protection from a local admin.

Source/code/dependency/tool/prompt/configuration hashes distinguish new builds.
Start new work after rebuilding and restarting the worker. If an open run reaches
analysis on an incompatible worker, it fails explicitly; no silent build upgrade.
Production worker version routing and long-lived mixed-build deployment remain
unimplemented. Re-run deliberately with the current build from the inspector.

## Remaining completion gates

| Owner | Material remaining work | Completion condition |
|---|---|---|
| Runtime implementation | Active model/tool crash and ambiguous inference reconciliation | A provider-side request ID or durable request ledger proves no duplicate request after transport uncertainty |
| Agent/evaluation implementation | Useful PR-diff reasoning and hidden scenario families | Representative sanctioned diffs, calibrated independent grader, isolated candidate, powered comparison |
| World implementation | Godot web export and richer character interactions | Matching templates, same-origin serving, measured native/web comparison and operator usability evidence |
| Product/core implementation | Custom persistent crew and earned progression | Identity/configuration records, independently verified deduplicated awards, zero permission coupling |
| Platform implementation | Kubani observation deployment | Scoped identities, immutable images, resource budgets, backup/restore and emergency stop tested before deployment |

No cluster operation, repository mutation, review publication, dependency change
in another project, or external notification was performed.

Final validation: the [v2 recovery run](../evidence/operations-final/events.json)
passed in 53.968 seconds, including a real hosted explanation with the corrected
rule context. [Legacy v1 compatibility](../evidence/legacy-compatibility-final/events.json)
passed in 42.533 seconds. The final source checks passed 21 Rust and 12 Python
tests, Rustfmt/Clippy, Ruff/ty, generated contract drift, documentation validation,
JavaScript syntax validation, and workflow actionlint. GitHub CI itself was not
run remotely. Browser checks exercised actual review/comparison submission,
evidence inspection, disconnect state, and 390px layout without page overflow.
Native [normal](../evidence/world-operations.png) and
[compact](../evidence/world-operations-compact.png) captures were inspected. A
long-ID overflow found in the first capture was fixed by bounded text layout.
These are functional/visual smoke checks, not performance or accessibility
certification, cross-platform coverage, or a Godot web-export result.

## Additive installation policy metadata

The v2 snapshot now includes optional typed `installation` metadata: `id`,
`environment`, and `capabilities`. The capability keys are `accept_work`,
`review`, `evaluation`, `repair`, `field`, `memory` and `inference`; each contains
`enabled` and a human-readable `reason`. Older snapshots without metadata remain
valid. Missing metadata means unknown policy, not disabled or authorized work.

This describes the Core installation's configured flags, not worker readiness,
loaded-build compatibility, provider permission or target health. Existing
worker/build/target records retain those separate meanings. Quiescing disables
new dispatch; it does not disable cancellation, inspection or memory approval.
The `memory` capability describes configured reviewed recall and does not promise
a reachable graph. Deployment must configure Core and worker consistently.
No credential, remote authentication or additional authority is introduced.

The [shared rollout fixture](../contracts/fixtures/operations-installation.json)
shows enabled policy with an unavailable worker. Rust policy tests use injected
configuration rather than mutating process environment; Python wire tests accept
both old snapshots and additive fields.
