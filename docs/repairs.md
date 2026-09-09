# Isolated repairs and verified progression

Status: accepted

Implemented 2026-09-05. This extends the [local operations edition](operations.md)
with real isolated code execution, two synthetic repair missions, and persistent
cosmetic progression. Kubernetes deployment is deferred by owner instruction.

## Run it

Use the existing bootstrap and dev commands. Install **microsandbox 0.6.14** from
its [upstream release](https://github.com/superradcompany/microsandbox/releases/tag/v0.6.14)
if absent; Starbase does not run an installer or change your global sandbox setup.
The pinned guest image is a per-architecture manifest digest (arm64 and x86_64).
Then:

```sh
mise exec -- just sandbox-prepare
mise exec -- just sandbox-doctor
mise exec -- just dev
```

Open the journal's Workshop section. Choose clamp or order-preserving duplicate
removal, then AI repair or a clearly labeled deterministic control. Startup makes
no model calls. AI repair uses one call, a 1,600-token output limit and a 60-second
request timeout at the configured authorized development endpoint. Only the
shipped specification and seeded Python source are sent. There is no model tool
loop, repository access, installed skill authority, or automatic external action.

The UI exposes the immutable before/after code, unified diff, inference usage and
provider identity, action attempts, raw VM outputs, six per-case judgments for
each of baseline and candidate, and the core verdict. Evidence is also available
through `/v3/repairs/{id}` and `/v3/repairs/{id}/patch`. The full record remains
available for failed and stopped missions. A missing observation remains missing;
it is never interpreted as a passing test.

The Godot terrace displays repair records and Mender's retained level/XP. The
journal provides keyboard-accessible mission creation, inspection and stop
controls. Scene poses remain decorative; no animation certifies an outcome.

## Ownership and budgets

The Rust core owns SQLite migration 3 and the versioned repair contract.
`solution.py` is the only proposed artifact; the runtime packages it with a small
input/output harness for execution in a disposable VM. It does not write into
this checkout, accept model-supplied host paths, publish a PR, or mutate a cluster.
The candidate receives case inputs, not grader code or expected answers. Only
Rust computes the result. Assertions such as `{"success": true}` fail the output
protocol instead of granting credit.

Each mission freezes its build, original revision, proposal and sandbox policy.
The admission limit is four active repairs. Authority expires after ten minutes.
Each baseline/candidate stage has at most two attempts; every attempt rechecks
core policy and reconciles its stable VM identity before execution. Model
proposal activities have one attempt; an uncertain provider response does not
trigger another billed request. Final evidence retention is idempotent.

VM limits and qualification are documented in the [sandbox survey](sandbox-survey.md).
No networking, host mounts, forwarded ports, vsock or secrets enter the VM. A
sandbox timeout or malformed output is an execution hard-gate failure. A
coordinator or provider failure leaves a failed mission, with no inferred
completion. Stops first fence new authorization, then cancel Temporal activity
and remove owned VMs. Already started execution is acknowledged honestly;
process loss is additionally bounded by the runtime's thirty-second VM lifetime.

## Progression

Mender's identity is persisted independently of immutable agent builds. The core
atomically commits the verdict and 25 cosmetic XP for a distinct scenario and
original revision when an AI proposal improves the failing baseline and passes
all six cases. Repeated runs, changed builds solving the same issue, controls,
no-change, regression, failure, and insufficient evidence cannot farm credit.

The first credit unlocks “First verified repair.” Two distinct repairs unlock
“Two distinct repairs” and level 2 at 50 XP. The journal links every credit to its
run and build. Qualifications have a separate `(build, scenario)` identity;
new builds do not inherit them. These are narrow fixture qualifications, not
professional proficiency or operational permissions. No automatic build
promotion, credential issuance or authority change exists.

## Validation

- `just test-sandbox`: real boundary, resource, timeout, cleanup and crash probes.
- `just test-repairs`: local Temporal plus microVM execution, worker/server restart,
  replay, cancellation, known-good/regressed/unchanged controls, persistent ledger.
- `just repair-pilot`: the same checks plus three explicit model calls: two distinct
  repairs and one repeat. It retains every result, including failed attempts.
- `just check` and `just check-world`: affected deterministic contracts and checks.

[Retained repair experiment](../evidence/repairs-first/events.json): killed both
worker and Temporal during baseline execution; recovered the same workflow run,
reconciled and retried the first action, and replayed its history. The known-good
control improved, the bad control regressed, unchanged code produced no-change,
and active cancellation produced no verified completion or XP. Three hosted
model proposals passed their six case checks; awards were 25, 25 and 0 XP. A core
restart retained 50 XP, two credits and level 2. Total observed integration time:
31.024 seconds on this machine. Two further missions populate the local
journal with actual repair evidence and 50 XP; those two model calls are retained
separately as `workshop-*` records in the same evidence directory. This is one integration observation, not a
throughput or latency benchmark.

These are two small fixed synthetic tasks, with one proposal per run. The repeat
is a duplicate-credit check, not an independent task sample. We have insufficient
evidence for general repair quality, stochastic improvement, security hardening,
or arbitrary-repository readiness. Monetary cost is unknown; token usage and
provider facts are retained. The model alias is not a pinned weight revision.

Existing V2 integration passed again in 44.625 seconds; legacy V1 direct and
PydanticAI paths passed in 43.808 seconds, including recovery/replay and cancellation.
Repository checks passed with 27 Rust and 16 Python tests, lint/type checks and
three generated contract versions. Godot state checks include the synthetic repair
label and unavailable-worker projection. Detailed visual observations are retained
with the repair evidence; these are not broad accessibility or performance claims.

## Recovery and next scope

V1/V2 histories remain supported. The core rejects newer database schemas;
rolling back the binary requires restoring a pre-migration local database copy.
Stop `just dev` before taking/restoring that copy. Do not erase the database to
hide failures. The image cache is separate from retained evidence.

Before deploying, separately qualify the runtime and OCI digest on the actual
Linux architecture, decide ingress/identity/storage and sandbox placement, and
exercise backup and emergency-stop procedures. Real repository patch application,
PR publication, cluster mutation, larger repair benchmarks, multi-tenancy,
ledger correction workflows and custom crew authoring remain separately scoped
product work. These do not follow automatically from progression.
