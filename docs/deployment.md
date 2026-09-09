# Kubani setup, recovery and teardown

Status: accepted


## Current staged scope · 2026-09-08

The accepted sequence is stopped resource preparation, dependency connectivity,
and reviewed provisioning/migrations; then an explicitly disposable read-only
pilot; then durable admission after its backup/recovery gates pass. Keep
`replicas: 0` and `accept_work: false` during preparation. The independent backup
key and verified restore/RPO/RTO remain gates for durable work, not a reason to
block stopped namespace, identity, policy or connectivity preparation. A pilot
must have bounded scope, duration and cleanup, and its disposable records must
not become production data.

The [current read-only audit](../evidence/kubani-namespaces/current-readiness.md)
found that Kubani main `d72107f` has no Starbase2 directory or Flux owner, and
`starbase2-prod` does not exist. Commit `cd565b6` deliberately removed the inactive
PR127 draft. References to that preparation below are historical; they do not
establish a current installation or authorize restoring the old draft. Prepare
a fresh reviewed GitOps change against current main.

Fresh committed and qualified amd64 images are required to carry the current
installation/capability/source-time contract into the pilot. Published revision
`71ca83d` is retained release evidence, not qualification of these later changes.
Infrastructure preparation can be designed in parallel, but final manifests
must bind the chosen qualified images by digest. The current renderer disables
field observations, inference, memory and repairs and permits only dependency
egress. A real GitHub pilot needs a separately reviewed field-only target,
credential and network configuration; enabling admission alone is insufficient.

This is the executable preparation package for a **fresh** Starbase2 production
installation. Nothing in this work activates Kubani or imports local SQLite or
Temporal data. [ADR 0005](adr/0005-fresh-kubani-installation.md) records the
storage and private access decisions. The existing SQLite launcher remains for
development/testing.

## What will be deployed

| Resource | Owner and boundary |
|---|---|
| `starbase2-prod` Kubernetes namespace | Dedicated application scope, restricted pod policy |
| One `starbase2` Deployment, two containers | Core and runtime share only pod loopback and worker credential; Recreate, 0 or 1 replicas |
| PostgreSQL `starbase2_prod` | Fresh database on Kubani PostgreSQL; core-owned schema |
| `starbase2_prod_owner` / `starbase2_prod_app` | Separate migration owner and restricted application login; no superuser or role/database creation |
| Temporal namespace `starbase2-prod` | Dedicated histories and 30-day closed-history retention; queue `starbase2-prod-v1` |
| Migration Job | Explicit one-shot, no automatic retries or TTL deletion of failure evidence |
| Network policies | No incoming pod traffic; DNS, PostgreSQL and Temporal only; specific database-side allowance |
| Private secrets | Worker token, application URL, temporary migration URL; no secrets in rendered bundle |

The journal and native Godot client use a local port-forward. No public ingress,
TLS certificate, FalkorDB, dedicated Temporal server, persistent volume, or
Kubernetes workload credential is needed by this application. Images contain
the read-only application source and the explicit sample repository. Selecting
**workspace** reads that shipped release source; **sample** reads the fixture.
This deployment does not observe Kubani or GitHub yet.
Legacy fixture endpoints, hosted inference and synthetic microVM repairs are
explicitly disabled. Enabling those requires an intentional capability release,
not changing an appearance/progression setting.

The network policy does not authenticate Temporal clients or encrypt traffic.
Kubani's checked-in Temporal Web OIDC configuration protects the Web UI, not
worker gRPC. The private PostgreSQL configuration has no verified TLS setup.
Treat cluster/platform administrators and other authorized service clients as
trusted for this first private installation. Public ingress, sensitive source
and operational permissions remain gated on a stronger identity design.

## Starbase2 naming and namespace ownership

All new Kubani application resources belong to `starbase2`, with production
installation identity `starbase2-prod`. Use the GitOps directory
`infrastructure/gitops/apps/starbase2/`; do not adopt or rename the predecessor's
`starbase/` resources. Preserve historical references as history.

| Kubernetes scope | Starbase2 additions |
|---|---|
| `starbase2-prod` | Deployment `starbase2`, ServiceAccount `starbase2`, migration Jobs `starbase2-migrate-*`, Secrets `starbase2-worker`, `starbase2-database`, `starbase2-migrator`, and NetworkPolicy `starbase2-boundary` |
| Existing PostgreSQL namespace (`database` by default) | Only NetworkPolicy `starbase2-prod-postgres`, allowing the selected Starbase2 pods to the existing database |
| Existing Temporal namespace (`temporal` by default) | Only NetworkPolicy `starbase2-prod-temporal`, allowing the selected Starbase2 pods to the existing frontend |
| Cluster scope | Namespace `starbase2-prod`; no generated ClusterRoles or ClusterRoleBindings |

The two infrastructure-side policies must live beside the destination pods.
Their source selector combines the exact Starbase2 namespace and installation
pod labels. Shared PostgreSQL and Temporal retain their existing names and
ownership. New Starbase2 workloads, secrets or future application stores belong
in the installation namespace; any future cluster-scoped permissions require
an explicit reviewed boundary change.

The renderer rejects legacy application identities, default/system/legacy
infrastructure namespaces, and application/infrastructure namespace overlap.
Kubernetes and Temporal namespace identities must match the installation;
the queue must start with that installation plus `-`. Database names begin
`starbase2_`. Application image repositories end in `/starbase2/core` and
`/starbase2/runtime`; the build registry path ends in `/starbase2`.
All generated resources and installed Secrets carry the `starbase2.io/installation`
label and `app.kubernetes.io/name: starbase2`.

Existing `STARBASE_*` settings, `starbase-core` executable and `starbase_runtime`
Python module are versioned runtime interfaces inside the qualified images.
They are not Kubernetes resource names. Preserve these interfaces until a
coordinated code/image compatibility migration; independently changing the
manifest's commands or environment names would break the current release.

## Commands and safety behavior

For the native client, run `mise exec -- just check-world-export` on macOS before
handoff. It exports and runs the actual application with an offline fixture,
checks packaged walking/interiors, and records native captures plus SHA-256
provenance. The output is an unsigned private client, not a signed public macOS
distribution. The Godot client is not a container in the Kubani deployment;
its local export qualification does not qualify the Linux Core/worker images.
See [character and export evidence](../evidence/illustrated-walk/release/README.md).

Use pinned project tooling: `mise exec -- just bootstrap`, then `mise exec -- just check`.
The entry point is `mise exec -- just deploy ACTION ...`. `render`, `credentials`
and `connections` only write local files. `preflight`, `status` and
`temporal-check` are read-only remote checks. Other actions default to a plan;
execution requires `--execute --confirm starbase2-prod`. Every Kubernetes call
uses the config's explicit context. Destructive operations additionally require
a retained backup and/or `--gitops-detached` as shown below.

The scripts do not suspend shared Flux reconciliation, push Git, publish images,
extract Kubani credentials, or choose a cluster context. Kubani owns those
steps. Do not apply this package alongside a competing GitOps owner. Examples
below describe operator actions for a future authorized deployment.

## 1. Build and freeze the release

1. Review and commit the source in the normal workflow. The release builder
   rejects dirty/untracked application inputs. Preserve the exact committed
   revision for each release candidate.
2. Copy [build inputs](../deploy/build-inputs.example.json) to a private working
   directory. Resolve the exact Linux platform and four base image digests from
   the intended registry; tags and unresolved placeholders are rejected. Kubani
   nodes must support the selected architecture. Do not assume macOS builds can
   be executed on Linux.
3. Run `mise exec -- just deployment-build .local/deploy/build-inputs.json` to
   inspect commands, then add `--execute` to build. The Dockerfiles use locked
   Cargo/uv dependencies and a non-root runtime. The runtime includes pinned
   Ruff and source files needed to compute immutable agent build identities.
4. Qualify both Linux images, retain their build inputs, test logs and source
   revision, and publish through an explicitly authorized registry workflow.
   Record **registry digests**, not local image IDs or movable tags. Publishing
   is deliberately not automated by the preparation command.
5. Copy [production config](../deploy/production.example.json) to
   `.local/deploy/production.json`. Set the verified Kubernetes context, source
   revision, qualified Linux `platform`, published image digests and actual
   dependency service addresses.
   Keep `replicas: 0` and `accept_work: false` initially.

```sh
mise exec -- just deploy render --config .local/deploy/production.json
kubectl kustomize .local/deploy/bundle
mise exec -- just deploy preflight --config .local/deploy/production.json
```

The deterministic bundle includes a checksum inventory in `release.json`.
`application.json` is valid Kubernetes YAML in JSON form. `migration.json` is
outside `kustomization.yaml`, so Flux does not unexpectedly rerun migrations.
Keep a copy of each full release directory outside the checkout.

First preflight against a namespace that does not yet exist may report missing
namespace during server dry-run. Activate only the reviewed stopped bundle
first, then repeat preflight. Any existing namespace must have the exact
installation ownership label; never relabel another application's namespace to
make this check pass.

## 2. Prepare dependency access and credentials

Verify the **actual** Kubani service names and network policy selectors before
using them. Checked-in references were `postgresql.database.svc.cluster.local`
and `temporal-frontend.temporal.svc.cluster.local:7233`. Starbase2's generated
PostgreSQL ingress policy is narrowly scoped to its namespace and pod label;
it does not modify Kubani's existing allow rules.

In separate terminals, use your explicit verified context:

```sh
kubectl --context YOUR_KUBANI_CONTEXT -n database port-forward svc/postgresql 54329:5432
kubectl --context YOUR_KUBANI_CONTEXT -n temporal port-forward svc/temporal-frontend 17239:7233
```

Use PostgreSQL **18-compatible** `psql`, `pg_dump`, `pg_restore` clients for the
currently checked-in Kubani PostgreSQL 18.3 image. Never use an older `pg_dump`
against a newer major server. Configure an operator-owned libpq service
`starbase2-admin` using the already authorized platform administrator identity,
loopback port 54329, database `postgres`, and a private passfile. Do not put its
password in argv, shell history, a manifest, this repo or an agent container.
The scripts do not obtain that identity for you.

```sh
mise exec -- just deploy credentials --config .local/deploy/production.json
mise exec -- just deploy connections --config .local/deploy/production.json
```

Generated credentials are exclusive-create, mode 0600 and stable across retries.
Archive them in the approved encrypted secret store. `connections` produces
private libpq files for `starbase2-prod-owner` and `starbase2-prod-app` on the
loopback PostgreSQL forward. Select that service file for owner/application
operations:

```sh
export PGSERVICEFILE="$PWD/.local/deploy/libpq/pg_service.conf"
```

The administrator service must be in a separate selected service file (or added
securely to this one); set `PGSERVICEFILE` accordingly for each command. Production
pod URLs refer to the cluster service, whereas operator libpq services refer to
the loopback forward. Never confuse them.

## 3. Provision and migrate, with the application stopped

Prepare a reviewed Kubani change adding the generated application directory
under `infrastructure/gitops/apps/starbase2/` and its reference in the apps
aggregate. The currently checked-in `starbase/` directory belongs to the older
project and must not be reused. Kubani's apps Kustomization uses SOPS and depends
on databases. Follow its current promotion instructions, activate the stopped
bundle, and wait for namespace, service account and policies to exist.

```sh
# Select the administrator libpq service file before this command.
mise exec -- just deploy provision-db --config .local/deploy/production.json --execute --confirm starbase2-prod
mise exec -- just deploy temporal-ensure --config .local/deploy/production.json --temporal-address 127.0.0.1:17239 --execute --confirm starbase2-prod
mise exec -- just deploy secrets --config .local/deploy/production.json --execute --confirm starbase2-prod
mise exec -- just deploy migrate --config .local/deploy/production.json --execute --confirm starbase2-prod
# Select the generated owner libpq service file for grants.
mise exec -- just deploy grants --config .local/deploy/production.json --service starbase2-prod-owner --execute --confirm starbase2-prod
```

`provision-db` marks database and roles with the installation ID, refuses adoption
of existing unmarked objects, and does not rotate existing passwords. A failure
between database creation and the ownership comment requires inspection of that
specific newly created database; there is no automatic adoption or forced drop.
If credential verification fails on retry, recover the original credentials
rather than generating replacements and silently overwriting roles.

The migration owner runs core's `--migrate`. The fresh schema creates missions,
evidence, immutable builds, tasks, events, duties, runtime heartbeat, repairs,
crew, credits and qualifications plus identity sequences and immutability
triggers. Schema v1 is PostgreSQL-specific; SQLite's v3 is unrelated. A transaction
commits both DDL and the migration checksum. Startup checks it and rejects an
absent, changed or newer schema. The application cannot create tables, mutate
schema version, delete evidence, or administer roles. Runtime grants are a
separate idempotent owner operation.

The `secrets` command creates private Kubernetes Secrets through stdin without
printing values, and refuses differing/unowned existing secrets. Use it as a
controlled bootstrap, or manage equivalent Secrets with Kubani SOPS before
activation. Do not manage the same Secret both ways without a reviewed handoff.
Retain the encrypted source of truth. After successful migration/grants, remove
the migration Job and `starbase2-migrator` Secret; the live pod never mounts it.
Recreate that narrowly scoped credential only for an explicitly authorized
migration. A failed Job is retained and not automatically rerun: inspect its
logs, fix the issue, remove that exact owned Job, then rerun.

Temporal provisioning checks ownership metadata and exact retention. A short,
bounded read-only retry handles namespace-cache propagation after creation.
There is no mutation of `default`, Temporal's PostgreSQL tables, global settings,
or existing namespace retention. For an intentional retention change, use the
official Temporal administrative workflow, record the old/new values and the
effect on closed histories, then update this config. Retention is not a backup.

## 4. Start, verify, and admit work

Change the config to `replicas: 1`, initially keeping `accept_work: false`, render
again, and promote that reviewed bundle through Kubani. Check:

```sh
mise exec -- just deploy status --config .local/deploy/production.json
kubectl --context YOUR_KUBANI_CONTEXT -n starbase2-prod rollout status deployment/starbase2 --timeout=180s
kubectl --context YOUR_KUBANI_CONTEXT -n starbase2-prod port-forward deployment/starbase2 8787:8787
mise exec -- just deploy temporal-check --config .local/deploy/production.json --temporal-address 127.0.0.1:17239
```

Open `http://127.0.0.1:8787` and optionally `mise exec -- just world`. Keep the
forward bound to localhost; do not add `--address 0.0.0.0`. Kubernetes RBAC for
pods/port-forward grants operational journal access, not a view-only role. Never
give it to an untrusted viewer. The port must be 8787 to match native-client and
operator-origin checks. Neither core nor worker gets a Kubernetes API token.

Core readiness performs a real store-backed request. Worker readiness checks a
heartbeat written only after successful reconciliation. A live process with a
broken dependency is not ready. Inspect container logs, dependency DNS, policies,
DB grants and namespace registration on failure; do not disable the checks.

Once both containers and retained state are verified, promote `accept_work: true`.
Run a sample review and paired evaluation without inference, inspect timestamps,
frozen builds and results, restart the worker/pod during a bounded run, and prove
completion/recovery on the **target images and cluster**. Verify denied repair,
legacy API and inference requests. Test one recurring duty, pause it, and observe
that no later review is admitted. These are activation gates, not results claimed
by the local rehearsal. No model calls happen merely by starting this bundle.

## 5. Quiesce, stop and back up

Stop operator submissions and close other journal clients. With the port-forward
and worker still running, pause duties and drain bounded work:

```sh
mise exec -- just deploy drain --config .local/deploy/production.json --execute --confirm starbase2-prod
```

This waits at most three minutes. A timeout leaves active records intact: inspect
or explicitly cancel them in the journal and wait for acknowledgement. It never
labels uncertain work completed. Drain requires an operational core/worker and
is not the emergency stop path. Prevent competing operator submissions during
this maintenance window. Promote `accept_work: false`; repeat the active-work
check, and confirm Temporal reports **zero open workflows**, including cancelled
recurring timers, before a release replacement or consistent backup. If open
work remains, preserve its exact worker images and resolve it first.

Promote `replicas: 0` through Kubani and wait for pod termination. Then:

```sh
mise exec -- just deploy backup --config .local/deploy/production.json --service starbase2-prod-owner --backup .local/deploy/backups/BEFORE_CHANGE --execute --confirm starbase2-prod
mise exec -- just deploy export-temporal --config .local/deploy/production.json --temporal-address 127.0.0.1:17239 --backup .local/deploy/backups/BEFORE_CHANGE --execute --confirm starbase2-prod
```

Backups require no active pods, a matching database service and a new private
directory. A failed dump has no valid manifest; partial artifacts remain for
inspection. The manifest binds the dump checksum and release inputs. Store the
backup and credentials encrypted off-host and test recovery regularly; the
application does not configure platform-wide backup schedules or invent an RPO.

History JSON exports are audit/replay evidence, **not** an importable Temporal
server backup. They contain sensitive workflow payloads and are mode 0600.
Export refuses open executions and is bounded to 10,000 retained histories.
Closed histories already expired under retention cannot be recovered by export.
For Temporal disaster recovery, retain Kubani's PostgreSQL persistence **and
visibility** backups with compatible server configuration. Do not restore shared
Temporal databases just to roll back this application. Require a platform-owned
restore rehearsal and measured RPO/RTO before production acceptance.

## 6. Software rollback and database recovery

Keep previous published image digests, source, configuration, schema checksum,
worker build manifests and backups. Drain first; never replace an open history's
worker with an incompatible build. This release has no versioned-worker routing
or database downgrade path.

```sh
mise exec -- just deploy rollback --config .local/deploy/production.json --previous /secure/releases/PREVIOUS --execute --confirm starbase2-prod
```

This prepares `.local/deploy/bundle/rollback` at zero replicas. It does not mutate
Kubernetes. It verifies identical installation/database/namespace/queue and the
supported schema checksum. Promote the old image pair through Kubani, verify
with work disabled, then explicitly re-enable. Do not use `kubectl rollout undo`
under an actively reconciling Flux definition. If schema or history compatibility
is unknown, remain stopped and investigate; never force an old binary onto new
records. A pre-migration backup is not needed for an image-only rollback when
schema is compatible, and no data should be discarded for that rollback.

For database loss or corruption, take/retain the damaged database separately,
stop all workload connections, and have the platform operator supply an empty,
installation-owned recovery database with the intended owner. **Do not drop
healthy production data merely to make restore pass.** The restore command
refuses any existing public tables and verifies target identity and dump checksum:

```sh
mise exec -- just deploy restore --config .local/deploy/production.json --service starbase2-prod-owner --backup /secure/backups/KNOWN_GOOD --execute --confirm starbase2-prod
mise exec -- just deploy grants --config .local/deploy/production.json --service starbase2-prod-owner --execute --confirm starbase2-prod
```

`pg_restore` is transactional and fails on error. Restored schema/version must
match the selected core. Start with work disabled. Compare retained run IDs,
terminal results and action/credit ledgers with Temporal. A database restore can
make Temporal histories newer than application records. Do not rerun uncertain
external effects or claim missing evidence successful; in this initial release
all external effects are disabled. Escalate inconsistent histories for explicit
reconciliation. Never fabricate a successful receipt or overwrite immutable
results to make health indicators green.

## 7. Emergency stop and retained teardown

If the journal/worker cannot drain, suspend/remove the **application's** Kubani
Flux reference through its recovery workflow first. An imperative scale command
alone is not a persistent stop: Flux may restore replicas. Do not suspend a
shared apps Kustomization casually or assume this script did it for you.

```sh
mise exec -- just deploy emergency-stop --config .local/deploy/production.json --gitops-detached --execute --confirm starbase2-prod
```

Wait for pods to disappear. An already started activity may finish or time out;
Temporal histories and records remain for reconciliation. This path uses only
kubectl and works without core/worker availability. PostgreSQL statement timeout
is ten seconds; a lost DB connection makes health fail rather than transparently
replaying writes. The core may restart after repeated failed liveness probes.

For ordinary uninstall, retain data and credentials by default:

```sh
mise exec -- just deploy teardown --config .local/deploy/production.json --gitops-detached --execute --confirm starbase2-prod
```

It removes stopped workloads and owned migration jobs, retaining namespace,
network policies, secrets, database, roles and Temporal namespace. Reinstall the
same owned release/config and credentials to resume. Do not declare workflows
cancelled simply because pods are gone.

## 8. Permanent cleanup

Only after an explicit data-destruction decision, verified backup, history export,
zero open workflows, stopped pods and detached GitOps:

```sh
mise exec -- just deploy purge-temporal --config .local/deploy/production.json --temporal-address 127.0.0.1:17239 --backup /secure/backups/FINAL --gitops-detached --execute --confirm starbase2-prod
# Use the administrator libpq service file.
mise exec -- just deploy purge-db --config .local/deploy/production.json --backup /secure/backups/FINAL --gitops-detached --execute --confirm starbase2-prod
mise exec -- just deploy purge-kubernetes --config .local/deploy/production.json --backup /secure/backups/FINAL --gitops-detached --execute --confirm starbase2-prod
```

PostgreSQL purge verifies ownership and refuses active connections; it never
uses FORCE, terminates other sessions, or drops shared databases. Temporal purge
checks exact ownership, retention, zero running histories and a checksum-verified
history export before requesting permanent namespace deletion. Its service may
finish deletion asynchronously. Kubernetes purge inventories discoverable
namespaced objects and refuses unowned resources, removes only the owned
cross-namespace PostgreSQL and Temporal policies, then requests namespace deletion. Run it **last**;
the earlier purge commands need the namespace ownership marker. API errors and
stuck finalizers require inspection, not force deletion. Remove the detached
Kubani reference and any encrypted credentials through its reviewed GitOps
workflow. Keep backup retention subject to the agreed data-retention policy.

## Rotation and release acceptance

For worker-token rotation, quiesce/stop both containers, retain old encrypted
credentials for rollback, generate a fresh private token, update the one owned
Secret through its chosen manager and restart the matched pair. It must never
be copied into Godot/browser settings. For DB login rotation, stop the app,
rotate the **dedicated** login through the owner/admin, update its encrypted URL
and libpq passfile together, verify connection/grants, then restart. `secrets`
intentionally refuses silently replacing differing credentials. Temporal TLS
certificate/key/CA configuration is supported by the Python client via
`STARBASE_TEMPORAL_*_FILE` settings; introducing it requires corresponding reviewed
Secret mounts and platform endpoint configuration, not speculative manifests.

Before activation, Al/platform owner must verify image builds/digests and Linux
execution, cluster context/admission/CNI policies and dependency names, private
operator RBAC, registry pulls, encrypted secret custody, real cluster restart
behavior, and platform PostgreSQL/Temporal backup restore/RPO/RTO. Public ingress,
HA, arbitrary repositories, model spending, Linux microsandbox qualification and
operational cluster agents remain separate owned capability gates. Preparation
and local rehearsal do not certify those capabilities.

## Validation references

`just check-deployment` exercises offline renderer and destructive-action guards.
`just deployment-test-db` starts a specifically named disposable, loopback-only
PostgreSQL container, `just test-postgres` runs the core state-machine tests
against fresh databases, and `just deployment-rehearse` proves provisioning,
migration, real Temporal review, role restrictions, restart, dump/restore and
cleanup. `just deployment-test-db-stop` removes only that container. These
commands never use kubeconfig. The [local rehearsal result](../evidence/deployment-rehearsal.json)
is scoped separately from cluster acceptance; earlier failed runs are retained
in [the history directory](../evidence/deployment-rehearsal-history).

Primary references: [Temporal namespace administration](https://docs.temporal.io/cli/operator#namespace),
[PostgreSQL dump](https://www.postgresql.org/docs/18/app-pgdump.html),
[PostgreSQL restore](https://www.postgresql.org/docs/18/app-pgrestore.html),
and [Kubernetes network policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/).

The [validation summary](../evidence/deployment-validation.json) records the exact
checks run and what was not performed. The PostgreSQL 18.3 rehearsal passed;
the disposable container and its data were removed afterward.

## Field-agent schema and memory extension

The core now requires PostgreSQL schema versions 1 and 2. V1's checksum is
unchanged; the existing migration job applies the additive field-agent V2 schema.
Run the updated runtime grants afterward: builds/review events are insert-only,
while runs, duties and memory approval state are mutable. The rendered inventory
includes the field-schema digest. Older images refuse the newer schema; rolling
back requires a compatible image or the existing restore-into-empty-database
procedure, never deleting migration records.

The production bundle explicitly sets `STARBASE_FIELD_ENABLED=false` and
`STARBASE_MEMORY_ENABLED=false`, and sets installation identity for future graph
scope. Enabling them requires a reviewed Kubani overlay for the selected targets,
read-only provider identities and FalkorDB egress/credentials. This is not supplied
by changing the local developer environment. See [field setup and gates](field-agents.md).
The existing pod deliberately has no Kubernetes token; do not turn on an
unrestricted default service-account token to make observation work. Mount only
an explicitly scoped short-lived observer identity into the worker.

SQL backups now include field runs, immutable source/report bodies, memory
proposals/reviews and duties. Revoking memory prevents future recall without
rewriting old evidence. Graphs can be rebuilt from approved SQL records; cleanup
must select this installation's graph names, not flush a shared service. Keep
field work and memory disabled during restore reconciliation, as with other work.

### Exact Linux image rehearsal

`just deployment-qualify-images INPUTS NEW_OUTPUT_DIRECTORY` runs the existing
fresh PostgreSQL/Temporal provisioning and recovery rehearsal against local
Core and worker images in a new disposable Podman pod. It never uses kubeconfig,
publishes images, or adopts an existing container. Ports 18887 and 17239 must be
free; only loopback is published. Temporary database authentication is deliberately
trust-based inside this isolated pod; this does not qualify production database
or Temporal authentication. Synthetic worker credentials are separate Podman
secrets, and the worker receives no database secret.

Inputs are JSON with `platform` (`linux/arm64` or `linux/amd64`), `revision` (the
committed 40-character source revision), `core` and `runtime` (each an exact local
`sha256:` image ID), and `temporal` (an immutable registry digest). PostgreSQL
18.3 uses the platform-specific pinned digest in the test database helper.
Dependency images must already be available locally. The command checks image
architecture and source labels before creating resources. The Core and worker
run as UID 10001 with read-only roots and all capabilities dropped. The output
retains private logs, synthetic evaluation reports and Temporal histories; inspect
and sanitize these before promoting evidence into Git. Unique resources created
by the command are removed after success or failure; no shared service is stopped.

The production configuration now requires `platform`. Both the application and
migration pod select that Linux architecture explicitly. Qualifying one
architecture does not qualify another, and local image IDs are not published
registry digests. The first amd64 attempt on the local arm64 VM failed when QEMU
crashed running `rustc -vV`; retain that failure and use a native amd64 builder
before claiming amd64 readiness. The native amd64 build and qualification were
completed on 2026-09-07 (below). The native arm64 build also exposed uv's valid
platform suffix in `--version`; the release check accepts that suffix while
still requiring exactly version 0.12.7.

The [2026-09-06 arm64 qualification](../evidence/linux-release/README.md) passed
16 lifecycle checks against committed images, including graceful PID 1 shutdown
and PostgreSQL restore. It retains failures, exact image IDs and closed Temporal
histories. These are local candidates, not published artifacts or cluster approval.
Production images exclude development-only dependencies and include contract
schemas; image construction now verifies worker import. Core handles SIGTERM
and SIGINT with graceful HTTP shutdown. The test-only loopback relay models
port-forward access; it is not part of the production deployment.

### Native amd64 qualification · 2026-09-07

Kubani node `rig0` (x86_64, Docker and podman) built both images natively with
podman from committed revision `71ca83dd7e5a9d763760a81f900e72aaaae2ea15` and
passed the 16-check disposable-pod rehearsal; see
[the amd64 release record](../evidence/linux-release-amd64/README.md). Two
harness defects surfaced and were fixed with retained failures: the readiness
wait accepted the PostgreSQL image's temporary socket-only initdb server (it now
requires TCP readiness), and the recorded Temporal digest was the arm64 manifest
of `temporalio/temporal:1.8.2`, so amd64 inputs pin its amd64 manifest. On Linux,
podman must use **crun**: runc 1.3 cannot create secret mountpoints on the
read-only rootfs the pod requires (`~/.config/containers/containers.conf`,
`[engine] runtime = "crun"`). On 2026-09-08 both images were published and
verified by immutable digest, and node `rig0` pulled them through its own
containerd configuration; the [publication record](../evidence/linux-release-amd64/publication-plan.json)
holds the exact references for `.local/deploy/production.json`. amd64 images on
general nodes resolve the placement gate without an arm64 taint exception. The
platform backup-key item is deferred in the roadmap backlog; activation remains
a separate reviewed Kubani change.

## Live Kubani preflight · 2026-09-06

The [preflight record](../evidence/kubani-preflight/README.md) verifies the live
cluster and current Kubani main branch without activation. PostgreSQL and Temporal
are healthy, the new database/roles/namespace are absent, SOPS access works, and
the required Kubernetes operator permissions are available.

The generated bundle now includes **both** database-side and Temporal-side
installation-scoped ingress allowances. Temporal's default-deny policy otherwise
blocks the new worker even when its own egress is allowed. Both rules passed
server-side dry-run. Permanent purge prechecks ownership of both rules before
removing either. Ordinary teardown continues to retain them.

Placement remains an explicit gate: the only current arm64 node is tainted
`nvidia.com/gpu=true:NoSchedule`. The arm64 selector alone does not qualify
scheduling. Choose qualified amd64 images on general nodes or explicitly approve
an arm64 scheduling exception; do not silently tolerate reserved-node taints.
Registry authentication and the authorized storage ownership repair are now
verified. Both qualified Linux arm64 images were published and pulled by their
immutable registry digests; configuration identities match the qualified images.
The [publication record](../evidence/kubani-preflight/publication-plan.json) retains
those exact references. [Kubani PR #127](https://github.com/X-McKay/kubani/pull/127)
was merged as inactive preparation. Platform backup readiness and qualified node
placement remain unresolved; publication does not activate Starbase2.
