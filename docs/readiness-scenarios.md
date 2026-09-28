# Kubani-inspired readiness scenario pack

Status: proposed

Owner: runtime/evaluation. Local control rehearsal completed 2026-09-25.

## Implemented and verified so far

The [public control pack](../fixtures/readiness/pack.json) implements the first
three cases from the [incident research](kubani-incident-scenarios.md): an absent
health endpoint, a probe using the wrong Python environment, and a transient
dependency refusal. It also includes persistent failure, false readiness,
wrong-route repairs, and deliberately weakened checks.

Eighteen focused tests passed against the grader, actual fixture HTTP processes,
isolated Python virtual environments, and a real read-only Git HTTP clone. The
complete Python suite passed 179 tests. The fixture tests require temporary
loopback sockets but no Kubernetes, provider credentials, or model calls.

**All nine predeclared outcomes matched in the full kind/Flux rehearsal.** Seven
controls ran through local Git and Flux; two weakened-probe proposals were
rejected before dispatch. The two genuine repairs restored useful work, waiting
resolved the transient failure, and misleading success cases failed. Cluster
cleanup was verified. See the [evidence record](../evidence/readiness-lab-20260925/README.md).
Both Podman VMs are confirmed stopped. The lab required Podman's hard-stop
fallback after graceful shutdown timed out, after cluster cleanup completed.

The shared Podman VM initially exhausted its disk while pulling the Kubernetes
image. The owner subsequently authorized stopping its older development services.
Temporal, FalkorDB, Graphiti, and their `kz-eval` VM are stopped with containers and
volumes preserved. The rehearsal used a separate 24 GiB VM. Earlier startup,
image-import, rollout-timing, and sampling failures remain in separate run
directories; the evidence record explains their fixes. This completed development
control run is not an agent comparison or a reliability estimate.

No Kubani configuration, production workload, active agent build, qualification,
memory, XP ledger, or external repository has changed.

## What the control pack checks

| Control | Expected result |
|---|---|
| Healthy service | Verified no-change |
| `/health` does not exist; correct `/ready` and `/live` routes | Verified repair |
| System Python cannot import the installed worker; use its venv | Verified repair |
| Synthetic dependency starts listening after 25 seconds | Verified no-change |
| Dependency never starts | Blocked after a bounded observation window |
| Ready endpoint succeeds but worker computes incorrect results | Failed |
| Proposed probe still targets a nonexistent route | Failed |
| Replace HTTP readiness with an open-socket check | Ineligible before dispatch |
| Increase Python probe timeout instead of fixing interpreter | Ineligible before dispatch |

The HTTP service is inspired by the MCP incident; it does not implement MCP or
claim protocol fidelity to the retired service. The Python worker computes small
jobs and has no Temporal or external dependencies. A separate thread creates a
real loopback TCP dependency after a controlled delay. This demonstrates refusal
and recovery, not kube-router or production NetworkPolicy fidelity.

The historical TCP repair is retained as provenance. This pack deliberately
requires a meaningful application readiness route rather than awarding success
for opening a socket. The independent observer also checks three job results
through both the Pod IP and Service path.

## Evidence and authority contract

[The grader](../scripts/readiness/contract.py) and expected job results remain
outside the workload image and its Git repository. [The runner](../scripts/readiness/run.py)
creates a fresh cluster and a private local Git repository. The Git server
supports fetch only; it rejects HTTP publication. The trusted coordinator
publishes authored commits by copying Git objects into that server.

The scenario sequence records the seed manifest and revision, reproduces the
fault before either repair, publishes the proposed correction, and checks:

1. Flux source and Kustomization conditions refer to their current generations
   and the exact intended commit.
2. The Deployment controller has observed the intended template, with one
   updated, ready, available replica.
3. Independent functional checks succeed through both network paths.
4. At least three observations span four seconds with the same Pod UID and no
   added restarts. This is a short development stability gate, not an operational
   SLO or a claim of long-term reliability.
5. The patch preserves the manifest except for allowed probe routes or a known
   interpreter. Probe removal, TCP substitution, arbitrary commands, timing
   changes, image changes, and unrelated edits fail the scope gate.

A separate 75-second rollout budget waits for the intended worker process,
without requiring readiness, before starting the fault-observation window. This
keeps an old Pod's termination delay separate from the seeded probe failure.
The positive sampler uses the grader's complete stability gate before stopping;
a temporarily unknown Flux observation requires a fresh, complete window.

Flux uses `wait: false` in this fixture intentionally: reconciliation of the
commit and health of its workload are independently observed. An applied broken
manifest cannot pass merely because Flux reconciled it successfully.

Reports distinguish verified repair, verified no-change, blocked, failed,
ineligible, and invalid. Unknown/stale observations cannot become success.
The report retains individual controls, all sampling observations, resource
snapshots, Git revisions, exact fixture and grader source snapshots and hashes,
image IDs/digests, elapsed times, events, and cleanup status. Fixture images are
built from the retained source snapshots. Failed attempts keep their own directories.
No model comparison, statistical superiority, or production clearance is
inferred. Every result explicitly carries zero XP and zero model calls.

## Running the checks

```sh
just test-readiness
just readiness-prepare
```

The initial [toolchain lock](../fixtures/readiness/toolchain.json) supports
macOS arm64 with Podman client 6.1.0 and server 6.1.2. It pins the VM boot archive,
kind 0.27.0, Kubernetes 1.32.2, Flux 2.5.1,
Python 3.12.13, and public image digests. These versions define a development
fixture, not a recommendation for Kubani's production versions. Tool downloads
are checksum checked and remain in `.local/readiness-tools`.

The dedicated VM can be prepared once using the following commands. Do not
replace or stop an existing VM without considering its running workloads.
The current checkout already has this VM prepared and stopped.

```sh
mkdir -p .local/readiness-empty
podman machine init --cpus 4 --memory 4096 --disk-size 24 --rootful \
  --image quay.io/podman/machine-os@sha256:28a277e4270450adec4e6a8d9a1b6d4dc105fa2b7b0b94e2c2e48245ce52837d \
  --update-connection=false \
  --volume "$PWD/.local/readiness-empty:/lab" starbase2-readiness-lab
podman machine start starbase2-readiness-lab
just readiness-rehearse .local/readiness-runs/first-cluster-run
podman machine stop starbase2-readiness-lab
```

The runner accepts only a new output directory, requires the named lab VM and
its explicit root connection, and rejects unexpected host mounts. All kubectl
commands execute inside the newly created node with that node's private admin
config. The user's kubeconfig and ambient provider environment are unused.
The VM has only an empty lab mount, and workload/observer pods receive no
service-account tokens. Fixture builds have networking disabled; base-image
downloads happen separately. The runner removes its owned kind cluster on exit
and verifies that its containers are gone. The stopped VM and image cache remain
available for the next run; they are not automatically deleted.

Podman's OCI export can change a manifest digest through layer recompression.
The runner verifies archive manifest/config checksums and binds the exported
configuration to the built image ID, then checks the imported digest and creates
its canonical containerd reference. Workloads use that verified digest with
`imagePullPolicy: Never`.

This is a **trusted development rehearsal**, not a qualified arbitrary-code
sandbox: the lab has outbound network access and the coordinator can administer
it. There is no candidate execution endpoint. Do not put model-authored code,
unrestricted manifests, production credentials, or private source into it.
Future candidate execution must have a separately qualified isolation boundary,
restricted observation/change tools, and private held-out grading.

The bootstrap follows the upstream [kind Podman guidance](https://kind.sigs.k8s.io/docs/user/rootless/)
and [Flux GitRepository revision contract](https://fluxcd.io/flux/components/source/gitrepositories/).
The Git server wraps Git's stateless upload-pack protocol and is for this
disposable fixture only; it is not a general Git hosting service.

## Completion gates and next learning experiment

The next implementation is the [bounded crew mission](readiness-missions.md),
with fixed observation tools, typed proposals, and independent verification.

The first completion gate is met: all nine known outcomes matched, exact revision
and functional observations were retained, and cluster cleanup was verified.
Runtime/evaluation owns the remaining work, in this order:

1. Expose bounded observations and declarative probe changes through a qualified
   agent execution boundary. Keep this public development suite separate from
   unseen variants and the evaluator. Do not treat the whole repository as a
   candidate workspace.
2. Freeze an incumbent diagnostic build and a candidate with one new Procedure
   for the crew's Run book. The proposed Procedure is: inspect current revision
   and timestamps; compare the configured probe with the actual route or Python
   environment; test useful work independently; distinguish transient refusal
   from persistent failure; propose the smallest meaningful correction or wait;
   verify reconciliation, work, and stability.
3. Predeclare a model-backed pilot's budget, task population, reliability metric,
   practical improvement margin, cost/latency limits, invalidation rules, and
   stopping rule. Use pilot variance to size a fresh, sealed confirmatory
   comparison. These settings and inference spending are not implicitly granted
   by this development control run.
4. Separately qualify a production GitOps mission against an existing authorized
   issue. Registry NetworkPolicy remains a later scenario with its own CNI and
   node-originated traffic requirements. Neither readiness controls nor RPG
   levels grant cluster authority.

The new pack adds no production API, database migration, service, or UI state.
It does not change the older repair extension's existing progression semantics.
