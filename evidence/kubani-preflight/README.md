# Kubani deployment preflight · 2026-09-06

Scope: read-only cluster/GitHub checks, local manifest fixes and preparation.
No images published, GitHub changes submitted, secrets installed, database
provisioning performed, or cluster desired state changed.

Kubani main and Flux source revision inspected:
`1d816581416368c0aec92c78ebbf4d81e7c631d3`.
The existing Kubani checkout was preserved; current main was read into a separate
ignored local checkout. Context `default` was explicitly checked against the
configured Kubani API and four expected nodes running K3s v1.34.7.

| Check | Observed result |
|---|---|
| Nodes | asio, rig0, sparky and strix Ready |
| arm64 placement | sparky only; GPU NoSchedule taint requires an explicit exception |
| amd64 placement | asio, rig0 and strix are general nodes, without taints; native images still need qualification |
| PostgreSQL | Actual server 18.3, ready; new Starbase2 database and roles absent |
| Temporal | All service deployments ready; gRPC SERVING; starbase2-prod namespace absent |
| GitHub | Repository read/push/admin permissions available; no push performed |
| Operator RBAC | Can create namespace, deployment, Secret and port-forward in intended scope |
| SOPS | Version 3.13.3 can decrypt the existing PostgreSQL secret; plaintext discarded without display or files |
| Registry | Podman not logged in; no Docker/Podman credential config found |
| Backup | Last success 2026-09-06 02:00:11 UTC; encrypted files current; retained isolated-restore log confirms catalog checks |
| Flux | apps, databases, infrastructure, root and old Starbase dojo Ready; old Starbase foundation has an immutable ConfigMap failure |
| Dependency network | New PostgreSQL and Temporal policies accepted by server-side dry-run |

The old Starbase failure is reported, not repaired under this task. The proposed
Starbase2 Flux Kustomization is independent, depending on databases and apps
(which owns Temporal), with its own installation labels. It starts at replicas=0
and accept_work=false. The migration Job is not automatically reconciled.

## Findings fixed locally

Temporal permits only the older Starbase execution namespace through its worker
ingress rule. Starbase2's renderer lacked a matching new allowance. Added a rule
limited to this installation's namespace/pod labels, the Temporal frontend
selector, and TCP 7233. Added standard application labels. Permanent cleanup now
verifies both external policy ownership markers before deleting either rule.
The failing regression test is retained in `missing-temporal-rule-test.log`.

## Outstanding choices and prerequisites

1. Registry login through the approved credential source, then publish and
   verify exact registry digests and node pulls. Do not paste credentials in chat.
2. Native amd64 qualification for a general node, or an explicit arm64 scheduling
   exception on sparky. The stopped local preview still uses unpublished arm64
   manifest digests and must be regenerated after this choice.
3. The current Kubani recovery runbook explicitly describes development recovery,
   no point-in-time recovery/HA, and a backup key coupled to the PostgreSQL admin
   password. It requires an independently recoverable key before production.
   Include that separately scoped platform upgrade and isolated verification,
   or retain Starbase2 as stopped/staging until it is resolved.

After these gates: publish, finalize/render and validate the exact Kubani diff,
bootstrap the stopped installation, provision dedicated data and encrypted
credentials, migrate/grant, start with submissions closed, then verify bounded
work/recovery and admit duties. No local preflight result certifies those future
cluster actions. See the [deployment playbook](../../docs/deployment.md).

## Registry and native-builder continuation

Podman now has the `human` login, and authenticated manifest checks reach the
registry successfully. Neither qualified release tag exists yet. Automatic
approval review rejected the Core publication attempt before execution because
it requires explicit authorization for the payload and destination; no image
was pushed. The [publication plan](publication-plan.json) identifies both exact
qualified images and their destination tags.

Read-only SSH verification confirms `rig0` is x86_64 with Docker 29.3.0 available,
32 logical CPUs, and approximately 899 GiB free on its root filesystem. The
proposed isolated build directory is unused. The [native build plan](native-build-plan.json)
records the 83-file, 696,320-byte committed source archive prepared locally for
an amd64 build. No source, credentials, or new workloads were transferred to the
node. Native amd64 qualification and the platform backup decision remain open.

## Single Kubani deployment PR

The subsequent PR preparation is tracked in
[Kubani draft PR #127](https://github.com/X-McKay/kubani/pull/127), branch
`codex/starbase2-deployment`, initial commit `ef1ad1b`. It is based on Kubani
`efb5e245e8db40eecaabf886501c55a4c7bae55d`. All further Kubani deployment changes
belong in this same PR. The original Kubani checkout remains unchanged.

The draft contains only the five namespace/service-account/network-boundary
resources, an unreferenced suspended Flux owner with pruning disabled and
orphan-on-deletion behavior, an installation/recovery gate checklist, and
local/CI tests. The four active Kustomize roots render byte-for-byte identically
to the base revision. No workloads, image references, secrets, migration jobs,
or provisioning are activated by this preparation.

`just pre-push-check` passed: 149 existing tests and 3 new boundary/inactivity
tests, manifest builds, whole-tree secret checks, installed hooks and no offline
drift. Commit and push hooks also passed, including gitleaks and whole-tree
secret scanning. No merge or cluster mutation was performed. Publication,
native amd64 qualification/placement, credentials and production recovery gates
remain open as documented in the draft; this is not a deployment-ready release.

## Authorized publication attempt and PR feedback review

The user subsequently authorized image publication. PR #127 had no issue
comments, reviews or inline review comments when checked; all three CI checks
passed. Both qualified local image identities/platforms were reverified.

Core publication reached the registry but failed with HTTP 500 during layer
upload initialization. Logs identify root-owned mode-0755 registry storage
ancestors that UID/GID 65532 cannot write. The release tag was still absent on
reconciliation; the worker upload was not attempted against this same fault.
No new registry manifest was published. The earlier approval-review block is
resolved; the current blocker is shared storage permissions.

The same Kubani PR now contains a proposed ownership repair with a retained ACL
snapshot and rollback procedure. Read-only checks identified the exact PVC,
PV, host path and node (`strix`), and available recovery tooling. Repair was
not executed and requires approval because it changes shared production storage.
