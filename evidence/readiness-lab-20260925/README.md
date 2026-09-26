# Readiness lab rehearsal · 2026-09-25

All nine predeclared public controls matched their expected outcomes in
`cluster-20260925-08`. Seven executed through a synthetic local Git repository
and Flux in a disposable kind cluster; two were rejected before dispatch.
The cluster was removed and absence of its containers verified.

| Control | Observed verdict |
|---|---|
| Healthy service, wait | Verified no-change |
| Incorrect probe routes, repair | Verified repair |
| Wrong Python environment, repair | Verified repair |
| Transient dependency, wait | Verified no-change |
| Persistent dependency, escalate | Blocked |
| Ready endpoint with incorrect job results | Failed |
| Repair still targets an absent route | Failed |
| Substitute a TCP readiness check | Ineligible before dispatch |
| Widen timeout without repairing interpreter | Ineligible before dispatch |

The repairs reproduced the original fault before publication. Positive results
required fresh Flux/source generations at the intended Git revision, current
workload state, correct independent job results through both Pod and Service,
and a stable Pod/restart count across at least three observations spanning four
seconds. The transient case includes observed failure before recovery.

## Retained artifacts

- [Summary](summary.json): outcomes, dispatches, exact revisions, observation
  counts, exported image digests, validation results, and full-report checksum.
- [Full report](report.json): manifests, per-observation resource state and job
  answers, fault reproduction, events, grades, provenance, and cluster cleanup.
- [Source snapshots](sources/scripts/readiness/run.py): exact fixture, runner,
  toolchain, and grader inputs copied at run start. Their hashes were verified
  against both retained and current sources after completion.
- [Earlier development attempts](development-attempts.json): failures remain
  recorded; original reports and diagnostics stay under `.local/readiness-runs`.
- [Final machine state](final-machine-state.json): both VMs stopped and the
  original `kz-eval` default connection preserved. Podman used a hard stop after
  the lab VM's graceful shutdown timed out; cluster cleanup had already passed.

Only non-private evidence is copied here. The disposable administrator config,
local Git repositories, and transport archives remain in the run's private
directory. This selected evidence bundle is tracked explicitly; other local
evidence and private run artifacts remain ignored by Git.

## Development failures and corrections

These were harness-development attempts, not agent trials or benchmark repeats.
Each fix used a new output directory under the pack's declared stopping rule.

| Attempt | Finding and correction |
|---|---|
| Preflight / 01 | Refused a stopped lab VM. No shared cluster was used. |
| VM startup before 03 | Ignition failed while creating its user; retained console log. Recreated only the empty task-owned lab VM. Root cause of the initial boot failure is unproven. |
| 03 | Detected client/server version mismatch; pinned observed Podman client 6.1.0 and server 6.1.2 separately. |
| 04 | Fixture Pods could not resolve digest references; added explicit containerd digest aliases. |
| 05 | Image identity check exposed OCI export recompression; bound the verified export to the built image configuration and checked the imported digest. |
| 06 | Fault sampling started before the old Pod finished terminating; added a bounded process-activation barrier without waiting for readiness. |
| 07 | Sampler stopped with a temporarily unknown Flux observation; grader correctly returned invalid. Added a regression and shared the complete positive evidence gate between sampler and grader. |
| 08 | All nine expected outcomes matched; cluster cleanup verified. |

## Checks and limits

The full Python suite passed **179 tests**, including 18 readiness contract and
real-process fixture tests. Ruff formatting/lint and ty checks passed for the
Python service and scripts, with fixture sources checked by Ruff as well.
The suite retains one existing Graphiti/Pydantic deprecation warning.
Documentation links/status checks passed for 225 Markdown files and 12
requirement IDs; `git diff --check` passed.

This run used zero model calls and awarded zero XP. It does not compare agent
builds, estimate stochastic reliability, qualify arbitrary candidate execution,
or authorize production access. The local lab has outbound network access and a
trusted coordinator. No Kubani configuration or external repository changed.

The owner-authorized older Temporal, FalkorDB, and Graphiti containers were
stopped with their VM, containers, and volumes preserved. The next owned gates
are specified in the [scenario design](../../docs/readiness-scenarios.md): a
qualified candidate execution boundary, frozen baseline and Procedure candidate,
then a budgeted pilot and separate held-out comparison.
