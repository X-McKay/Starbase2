# Field crew and persistent memory

Status: accepted

## Implemented behavior

| Character | Work | Boundaries |
|---|---|---|
| Watchkeeper | GET scoped Kubernetes pods/deployments; identify unavailable replicas, failed/pending pods, image/startup failures and readiness issues; retain maintenance advice | No logs/secrets retained, shell, restart, patch or delete. Observed workload status is not a cluster-wide health certification. |
| PR Reviewer | Capture one configured GitHub PR head/base and changed Python blobs; verify Git blob identities; run pinned Ruff checks on added lines; retain local draft | No checkout, candidate code execution, GitHub publication or approval. Other languages, deleted files and incomplete diffs remain explicit coverage exclusions. |

Both have Godot characters, keyboard directory/inspectors and authoritative
queued/running/findings/incomplete/no-record/offline states. The new sprites are
palette variants of existing crew art. They share the existing Survey Command
area. The browser journal supports starting/stopping runs, recurring duties,
source inspection and memory review. Model explanations are optional, unverified,
limited to one provider attempt and never the source of operational authority.
They receive masked source/normalized observations and approved memories only;
redaction is best effort, so private-source inference requires explicit target
opt-in. Default recurring duties never request inference.

Polling responses contain compact summaries; full source and report evidence is
fetched separately when inspected. A V4 run retains its immutable build, source snapshot, deterministic findings,
coverage, reviewed-memory revisions, optional advisory and state events. A stable
Temporal workflow ID prevents duplicate dispatch; bounded captures retry safely.
Cancellation fences completion and future publication of memory proposals. A
30–86400 second recurring duty survives worker restarts. Pausing prevents future
dispatch; already queued/running observations must be stopped separately. Missed
intervals do not create an unbounded backlog. At most 20 duties and 20 active runs
are accepted. Editing a duty requires the next generation; stale edits fail.

## Repository watch controls

The [Command District guide](command-district.md) describes native and browser
repository add/pause/remove/restore, durable polling, bounded multi-PR capture,
credential binding and additive migrations. Single-PR target files remain supported.

## Local setup

Use the locked project environment (`just bootstrap` / `uv sync --locked`). In
separate terminals, run:

```sh
just memory-dev
STARBASE_MEMORY_ENABLED=true STARBASE_FALKOR_PORT=16379 just dev
just world
```

`memory-dev` binds FalkorDBLite to loopback and persists `.local/memory/memory.rdb`.
Ctrl-C closes the server cleanly. The local developer database and graph are
separate from the fresh production installation. Start in the browser journal's
**Watchkeeper & PR Reviewer** section; default targets are conspicuously synthetic.
Approving a finding makes it eligible for the next matching run's recall. No
approval is needed to inspect a proposal. Revoke it to prevent later use.

For real provider reads, copy [the target example](../config/field-targets.example.json)
to an ignored local path, set actual verified endpoints/namespaces/PR numbers and
credential-file paths, then set `STARBASE_FIELD_TARGETS_FILE` on the worker before
starting. An explicit file replaces fixture targets. Omit `token_file` for public
GitHub data. Token/CA paths are not included in builds or inference inputs. Use
short-lived, least-privilege identities. This does not read the user's kubeconfig,
discover arbitrary repositories, or grant access to the entire cluster.

Required Kubernetes RBAC verbs are `get,list` for core `pods` and apps
`deployments` in **each named namespace**. A fine-grained GitHub identity needs
contents and pull-request read permission for the selected repository. Live
provider configuration is operator-owned, not model-generated. Both adapters
reject redirects, preserve TLS verification and cap response size and duration. Kubernetes requests use `Accept: application/json`; GitHub vendor
media types and API-version headers are sent only to GitHub.
PR head/base drift fails capture; unsupported or truncated coverage is not a
clean-review result. Namespaced list pagination is bounded to five pages per
resource, and PR capture to 300 metadata entries / 100 Python files / 1 MB source.

## Memory contract

Set `STARBASE_MEMORY_ENABLED=true`, `STARBASE_FALKOR_HOST`, `STARBASE_FALKOR_PORT`,
and, when required, `STARBASE_FALKOR_USERNAME` and
`STARBASE_FALKOR_PASSWORD_FILE`. Set a unique `STARBASE_INSTALLATION` for any
non-development installation. Defaults are development / loopback / port 6379.
The current adapter uses Redis transport without a configured TLS mode; only use
an explicitly trusted private path until transport qualification is completed.

The SQL ledger is authoritative. Each finding proposes a sourced observation;
only operator approval makes it available. Runs freeze at most 30 approved
records from the recent 500-record ledger window, matching agent, target ID and
full public target digest. Reassigning a target ID to another origin/scope does
not transfer its memory. Memory revisions are checked again before recall, so
revoked queued memory is excluded. A revocation after an activity has already
read its evidence cannot erase that historical input; the run retains its exact
snapshot. Review revisions reject stale edits.

Graphiti writes and retrieves structured episodes in an installation/agent/target
FalkorDB graph. Exact content/provenance must match SQL. Missing entries rebuild
on recall; mismatches are reported as unavailable, never silently overwritten.
No raw credentials, full transcripts or automatically extracted model beliefs
enter memory. Graph failure does not invent past experience or block a basic
observation; the report says memory unavailable. Repeated finding keys indicate
recurrence, not causality or verified learning. Neither agent earns XP for these
observations. Existing Surveyor, Mender and Trainer have not been converted to
this memory path.

Back up SQL and Temporal as documented in the [deployment playbook](deployment.md).
The graph is rebuildable from reviewed SQL records; a full graph backup is useful
for continuity but is not authority. Revoke memory to roll back its future use.
Do not restore a graph as a replacement for the ledger. Permanent cleanup must
target only graphs belonging to this installation; never flush a shared FalkorDB.
No graph purge script or shared-service mutation runs automatically.

## Validation and remaining work

```sh
just check
just check-world
just test-field        # actual Temporal + actual FalkorDB, synthetic providers
just test-memory       # persistence, cross-agent rejection, tamper rejection
just field-pilot       # explicit one-call model test on synthetic PR data
just test-sandbox      # run on each intended platform with pinned msb/image
```

Use `python -m pytest`, not the `pytest` executable: FalkorDBLite puts its module
binary in the environment's bin directory, where it can shadow the Python
`falkordb` package for console-script entry points. No dependency files are patched.

Retained evidence lives in [field-agents](../evidence/field-agents). Local integration
covers changed-line review, cluster fixtures, approval/recall, core/worker/graph
restart, revocation, cancellation, recurring duty pause and Temporal replay.
A real Qwen model response was retained from `llm.almckay.io` on a synthetic PR;
it remains unverified. The real GitHub adapter also captured public Graphiti PR
1814, verified the blob identities and reviewed two changed Python files without
credentials, execution or inference. It found no configured-rule warnings; that
is not a correctness or security certification of the PR. These are functional checks, not a comparative quality
benchmark or production readiness claim.

Linux host qualification was recorded on 2026-09-07: the x86_64 host with KVM
passed the same six probes and both crash probes (process-group loss 0.31 s,
coordinator-only loss 12.3 s) under [the Linux-host evidence](../evidence/sandbox-qualification/linux),
after the sandbox image pin was corrected to the x86_64 manifest digest; the
first run's `Exec format error` is retained in [the onboarding record](../evidence/linux-onboarding/README.md).
This qualifies that host and image, not Kubernetes.
The qualification probes use a real host-only canary on either OS. All six local
Linux-guest probes passed on this Mac: file/credential/network isolation,
memory/file limits, timeout, background cleanup and cancellation. Crash probes
confirmed termination after process-group loss and after coordinator-only loss
(10.533 seconds in this run). Results are under
[the Darwin-host evidence](../evidence/sandbox-qualification/darwin). This verifies
the local Linux guest boundary on that Mac.

Before activation, the runtime owner must qualify real selected provider targets,
restricted credentials, outages and overnight duty behavior; qualify sandbox
execution and cleanup on the intended deployment host/image; and prepare a Kubani
FalkorDB/identity/network-policy overlay. The generated deployment still disables
field/memory features and sandbox repairs. Before claiming improved agent quality,
the evaluation owner must compare approved-memory and memory-off builds on paired,
held-out cases, including misleading/revoked memories and cost. Semantic Graphiti
extraction/search remains a later experiment, not implemented behavior.
