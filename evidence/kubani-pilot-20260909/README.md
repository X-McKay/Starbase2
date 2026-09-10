# Kubani disposable pilot · 2026-09-09

Status: **deployed; backend and native cluster acceptance passed; admission
closed**. This is a bounded read-only pilot in
`starbase2-prod`, not durable production admission. Its records are disposable.

## Exact release and deployed boundaries

Committed source `ef60c6acc7afdc238c44af4f01fefb75cff03aaf` was built on rig0
with pinned amd64 inputs. [Image qualification](qualification-report.json)
passed all 16 checks; all six container stops exited successfully and owned
Podman resources were removed. [Publication](publication.json) records the
explicitly authorized registry pushes and pullback identity verification:

| Component | Immutable registry reference |
|---|---|
| Core | `registry.almckay.io/starbase2/core@sha256:be60700aee18d583d6adde0547332456d5187e4365c32086504a4b6937ffa514` |
| Runtime | `registry.almckay.io/starbase2/runtime@sha256:270548d9715f87f1c75545941594efc5061be592f713a6620bed590dbb4e01a3` |

The [live boundary audit](live-boundary-audit.json) confirms these same image
references, no service-account token, no migration-owner secret, and no runtime
database credential. Core mounts application database and worker credentials;
runtime mounts only the worker credential. Both containers use read-only roots,
drop all capabilities and disallow privilege escalation. The dependency init
completed successfully. [Startup log review](live-startup-log-audit.json) found
no logged errors; the empty runtime log alone is not evidence of worker health.

## GitOps history

Kubani changes used normal hooks, CI and reviewed merge revisions:
[stopped preparation PR140](https://github.com/X-McKay/kubani/pull/140),
[user registry policy fix PR141](https://github.com/X-McKay/kubani/pull/141),
[startup PR142](https://github.com/X-McKay/kubani/pull/142), and
[bounded test admission PR143](https://github.com/X-McKay/kubani/pull/143).
The dependency readiness correction is Starbase2 commit `1e719f6`; 53 focused
checks passed. It changes deployment preparation, not the qualified application
images. The [native artifact identity](native-artifact.json) binds the actual
live client to the previously qualified unsigned executable and pack.

## Actual cluster behavior

[Startup proof](startup-proof.json) records a healthy worker with admission
initially disabled, zero runs and refusal of new work. An unauthenticated write
was [rejected with HTTP 403](operator-auth-proof.json). Migration completed with
[PostgreSQL schema verification](migration-03-pod.log); the application role was denied
schema CREATE, evidence DELETE and schema-version UPDATE privileges in the
[role check](runtime-role-check.log). The three `f` columns report those object
privileges, not role-level superuser or role/database creation flags.

[Acceptance events](acceptance-events.json) establish:

- Sample review completed with one reviewed file and one advisory finding.
- Deterministic comparison retained 12 trials: baseline 5/6, candidate 6/6,
  zero provider cost and no hard-gate failures. This public fixture result does
  not establish generalization, promotion or operational authority.
- Recurring sample review ran, then pausing it prevented new runs during a
  36-second observation window longer than its 30-second interval.
- Cancellation reached the authoritative cancelled state.
- Field, inference and repair requests were denied. Memory was disabled in
  metadata with empty records; its review endpoint lacks a configuration denial
  guard, so no endpoint-level memory policy denial is claimed.

An [actual pod replacement](pod-replacement.json) changed the pod UID. The
previous report remained unchanged and the recurring duty produced a later
scheduled run after replacement, with shared Temporal left running. The duty
was paused again and another 36-second window showed no new runs. This proves
pod replacement recovery, not interruption during an activity, a Temporal
restart or production disaster recovery.

## Native Godot verification

The [native review record](native-live-review.json) and
[actual app screenshot](native-live-review.png) show Godot connected to live
`starbase2-prod`. Starting a workspace review from Operations created a backend
run that completed with retained evidence: 38 files reviewed, outcome
`incomplete`, zero model calls. Workspace means source shipped in the qualified
release image, not a remote provider checkout. This was advisory static analysis
with incomplete coverage, not a clean repository certification.

The displayed report was refreshed by selecting another history row and returning.
Clicking the same selected row did not refresh it. This interaction limitation
remains open; the screenshot instruction to select again is misleading for that
case. Owner: Starbase2 world implementation. Completion requires an explicit
refresh action or same-row activation that refetches retained detail, accurate
help text, and a native check showing a selected running run refresh to its
completed report without switching rows. The root and evidence reviewer visually
inspected the captured live app.

## Failures diagnosed without broadening application access

The registry mirror was correct but a new default-deny policy blocked node
pulls. [Diagnosis](registry-pull-diagnosis.md) identified the host flannel source;
Kubani subsequently added narrow node-source TCP 5000 ingress. The
[node pull verification](registry-pull-after-policy.json) then resolved both
published digests to the qualified image IDs.

New pods initially reached DNS but received dependency TCP refusals until
kube-router installed their source membership. The
[bounded probe](dependency-policy-convergence.log) failed initially and passed
both service and direct-pod paths five seconds later. Deployment preparation
now waits for dependency TCP readiness before dispatching the one-shot migration;
migration execution itself is not automatically retried.

## Remaining scope

[Final status](final-status.json) confirms admission closure through
[Kubani PR144](https://github.com/X-McKay/kubani/pull/144), merge
`5def3cad4808724ea998209a610a53219006b254`. Flux applied that revision; the
[final pod](close-admission-live-pod.json) has two ready containers with admission
false. The [final API observation](final-observation.json) shows a healthy worker,
zero active runs and the test duty paused. The running native client reconnected
and [disabled Start review](native-admission-paused.png). Native Godot cluster
verification is complete. No
external repository/provider observation, inference, memory execution or repair
was enabled. Workloads used shipped sample fixtures and shipped workspace source. No production
backup/restore, RPO/RTO or independently recoverable backup-key qualification is
claimed; these remain prerequisites for durable admission. Keep the pilot data
separate from any future production history.

The [manifest](manifest.json) checksums an explicit allowlist of sanitized
records and logs. Credential files, operator sessions, private deployment
configuration and arbitrary raw run state were not copied.
