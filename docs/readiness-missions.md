# Bounded readiness crew mission

Status: proposed

Owner: runtime/evaluation. Implementation: 2026-09-25.

## Scope

This extends the [public readiness controls](readiness-scenarios.md) with a
PydanticAI Crew member that investigates synthetic readiness incidents. The [runtime module](../services/runtime/starbase_runtime/readiness.py)
owns typed decisions, model tools, evidence receipts, budgets, and a one-shot
mission journal. The [local adapter](../scripts/readiness/mission.py) supplies
observations and applies eligible changes through the existing owned lab.
[ADR 0008](adr/0008-declarative-readiness-missions.md) records the boundary.

The diagnostic baseline has no persistent memory or learned Procedure. The
[paired campaign](readiness-campaigns.md) adds a separate candidate with one
versioned Run book Procedure and four public decision scenarios. Model selection is separate from Crew identity. No active production
Crew build, qualification, authority, or XP record changes. This is a local
mission execution harness; it does not register a mission in Rust core, change
Temporal workflows, or drive Godot animations yet.

## Tool and effect contract

| Tool | Read-only result |
|---|---|
| `inspect_workload` | Current probes, readiness, published service contract, exact revision |
| `inspect_events` | At most eight events for the current workload/Pod, with bounded messages |
| `inspect_logs` | Current worker logs, at most 25 lines / 2,000 bytes |
| `check_useful_work` | Job responses through Pod and Service, independently of Ready |

No tool accepts a target, path, URL, command, credentials, or arbitrary manifest.
The target is the owned disposable `readiness-lab/readiness-fixture` workload.
Each result is at most 8,000 bytes and includes an observation ID, revision, and
freshness. All result text is untrusted. Logs cannot grant authority or instruct
the coordinator to run commands. Expected job answers and grader source are not
sent to the model.

The typed decision is `repair`, `wait`, or `abstain`, with a concise rationale.
Repair requires an explicit readiness path and liveness path from small literal
sets. A liveness route cannot replace meaningful readiness. Extra keys, arbitrary
commands, TCP checks, timeouts, images, and unrelated mutation are unavailable.
Repair/wait must cite an issued observation and revision; abstention cannot
contain mutation fields. The model has no success/verdict field.

Before effects, the coordinator independently reobserves the workload and
requires the receipt to match its revision, spec digest, generation, deployment
identity, and fresh Flux/source state. An expired receipt is ineligible. A
publication intent is saved before Git/Flux operations. An uncertain outcome
remains invalid and cannot be replayed. Repeated completion returns the retained
result; concurrent completion is serialized.

## Budgets, cancellation, and evidence

The baseline permits 8 model requests, 12 observation tools, one mutation,
2,048 output tokens per request, and a 240-second dispatch window. Evidence expires
after 90 seconds. Provider retries and model validation retries are disabled.
The endpoint must be one already permitted by the runtime's development allowlist;
no ambient API key is used. Inference is opt-in at the command line.

The owner expanded the locally hosted model allowance on 2026-09-25. The current
128,000-token budget uses a conservative UTF-8 byte reservation for serialized
messages, tool schemas, framing, and maximum output before each provider request,
plus PydanticAI's provider-reported total usage limit. Missing or unexpected usage
fences further work. The reservation is deliberately conservative and may stop a
run early; it is not an exact tokenizer proof or a monetary billing guarantee.
Provider cost stays unknown. Scripted controls explicitly record zero provider
calls/cost and cannot establish capability.

The owner's preference for this self-hosted phase is to prioritize complete
investigations over minimizing token consumption. Tokens remain a recorded
resource metric. Adjust allowances for measured local workloads in a new frozen
build; preserve prior outcomes instead of changing a running trial's limits.

The Qwen adapter declares forced-tool selection unsupported so PydanticAI sends
`tool_choice: auto` while retaining the typed final-decision tool. Effect-free
probes found that `required` reached its output cap, whereas `auto` stopped
normally. Plain text cannot replace the typed decision. Length-terminated model
responses are now retained and rejected before their tool calls can execute.
Model settings and this provider profile are included in the build identity.

Create `CANCEL` inside the run directory, or send SIGINT/SIGTERM to the mission
process, to fence subsequent dispatch. Every lab command after admission checks
the fence, including each step of publication. An already-started command may
finish; stop does not roll back completed effects. Cluster cleanup bypasses the
mission fence. Before admission the normal runner cleanup applies.

`mission.json` retains the immutable build, source/lock/configuration hashes,
output schema, decision, tool calls and errors, provider requests/responses,
requested/reported model identity, usage, timing, effect state, and independent
grade. Source snapshots are in `build-sources/`; the lab's `report.json` retains
raw observations, exact revisions, verification samples, and cleanup evidence.
The journal is created only in a new run directory and is not resumable.

Unknown, abstained, denied, cancelled, budget-limited, failed, and verified states
remain distinct. A model rationale is not an internal chain-of-thought record
or a success certificate. Every run carries zero XP. No baseline/candidate
quality comparison or qualification is inferred from this implementation.

## Running

Start the existing dedicated lab VM and run from the checkout:

```sh
just readiness-mission .local/readiness-missions/first-scripted
```

This uses an explicitly scripted model that calls all four observation tools and
proposes the known repair. The mode exists to qualify the wiring, not intelligence.
It checks fault reproduction, real Git/Flux publication, independent verification,
and cluster cleanup. Stop the lab VM after completion; its images remain cached.

For a separately authorized model-backed attempt:

```sh
just readiness-mission .local/readiness-missions/first-model --mode inference
```

This uses the existing configured development model/endpoint; a missing provider
is an invalid attempt, never a silent scripted fallback. Use a fresh directory,
retain failures, and inspect both mission and lab reports. The wrapper removes
only its owned kind cluster. If the process crashes, remove that exact owned
cluster independently; never use ambient production kubectl for lab cleanup.

## Validation and remaining work

Seventeen focused mission tests currently pass. They cover typed authority limits,
malformed tools, fabricated success, changed and expired evidence, missing Flux
freshness, abstention, duplicate completion, cancellation, request reservation,
retained invalid responses, build identity, uncertain-effect no-retry behavior,
automatic tool selection on the actual SDK wire format, and truncated responses.
The full Python suite passed **196 tests**; Ruff, ty, and documentation checks
passed. The real-cluster scripted rehearsal completed with `verified-repair`:
four observation tools, one applied proposal, four verification samples, and
verified cluster cleanup. The exact seed/proposal revisions and immutable build
are retained in the [evidence record](../evidence/readiness-mission-20260925/README.md).
There were two scripted model responses, zero provider calls, and zero XP.

The first authorized [Qwen attempt](../evidence/readiness-qwen-20260925/README.md)
stopped at `model-token-reservation-exceeded` after inspecting the workload and
events: two provider requests, 2,062 input tokens, and 37 output tokens. No
proposal or mutation occurred; cleanup was verified. The byte reservation counts
SDK bookkeeping and repeated instructions as well as prompt content, so it can
stop well below the reported usage limit. This is a retained budget-limited
result, not a repair verdict or evidence of general diagnostic competence.

The [expanded-budget attempt](../evidence/readiness-qwen-expanded-20260925/README.md)
used seven requests and 33,515 tokens, but every response was length-terminated.
It reached the mission deadline without a proposal or mutation. Two small
effect-free probes isolated the forced-tool-selection behavior, followed by the
adapter fix and offline regressions above. The
[corrected-adapter mission](../evidence/readiness-qwen-compatible-20260925/README.md)
then completed with `verified-repair`: six provider requests, 15,615 tokens,
five observation calls, one eligible proposal, independent Git/Flux/functional
verification, and verified cleanup. Earlier failures remain part of the record.
The successful public scenario establishes this execution path, not general
diagnostic competence or superiority over a baseline.

Next gates owned by runtime/evaluation:

1. The [paired public pilot harness](readiness-campaigns.md) now freezes baseline
   and Procedure candidate, task variants, order, budgets, invalidation and stopping
   rules. Add independently held-out task families and repeated pairs with measured
   uncertainty before recommending a capability qualification.
2. Integrate mission identity, dispatch authority, durable effects/reconciliation,
   and projections with core/Temporal before scheduling missions or showing live
   agent work in Godot. Require restart/cancel/unknown-effect integration tests.
3. Separately qualify executable candidates and any production GitOps target.
   Neither this declarative interface nor RPG progression grants those capabilities.

Provider-prompt accounting remains a later optimization, not a prerequisite for
local mission execution. Retain measured tokens and request/time/tool/freshness/
mutation limits when adjusting resource allowances for later workloads.
