# ADR 0005: Fresh PostgreSQL installation on Kubani

Status: accepted

## Decision and scope

The owner explicitly chose a fresh production deployment on 2026-09-05. SQLite
and local Temporal histories are development/test artifacts. There is no import
or compatibility obligation from those records into production. The core now
supports a separate PostgreSQL schema, versioned independently from SQLite.
The core owns migrations and all product tables. Kubani continues to own the
PostgreSQL and Temporal servers and environment activation.

Use one replica of a pod containing the Rust core and Python Temporal worker.
This is a private initial deployment, with the core still bound to loopback.
Kubernetes-authorized port-forward access opens the journal and native client's
existing operator session. There is no public ingress, Service, Kubernetes API
credential in the pod, or new authentication proxy. The containers have separate
images, resource budgets and secret mounts. Only core receives the application
DB credential; only the explicitly run migration job receives the owner one.
A PostgreSQL advisory lock refuses competing authoritative core processes.
Recreate deployment semantics intentionally trade availability for correctness.

Use a dedicated database and login roles, and one named Temporal namespace and
queue per installation. Temporal namespaces separate histories, not authority:
Kubani's current gRPC service has no verified per-namespace authorizer. Web OIDC
does not authenticate workers. PostgreSQL currently uses private non-TLS
connections. Restrict network paths and keep all external effects disabled.
These trust limitations must be reviewed before adding sensitive workloads,
public access, untrusted workers or stronger operational authority.

The production bundle enables the read-only review and evaluation runtime.
It disables the legacy fixture API, provider inference and microsandbox repairs.
The bundled review workspace is the shipped application source, with an explicit
synthetic sample target; neither is a cluster or GitHub observer. The native UI remains a separate local application.

## Alternatives

A PVC-backed SQLite core would avoid a driver change, but would carry the local
storage choice into production against the owner's direction. Separate core and
worker pods would require a remote operator authentication boundary now; retain
that option when independent scaling or a real remote client requires it. A new
Control/Evidence split, additional database, or new workflow service is not
needed for this deployment.

SQLx supplies the PostgreSQL driver and TLS support. A small core-private scalar
row/transaction adapter preserves the existing state machine and development
SQLite tests. Application queries use explicit numbered bindings, explicit
insert columns and native JSON expressions for each engine; there is no SQL
rewriter. The synchronous owner remains serialized and bounded by DB statement
and lock timeouts. This is not an HA or throughput claim.

## Rollout and recovery

Render an initially stopped bundle with immutable image digests. Create the
installation-owned database/roles and Temporal namespace; run the migration job
once, apply runtime grants, and enable one pod through Kubani GitOps. Migrations
are transactional and checksum-checked; normal startup never creates PostgreSQL
tables. No destructive downgrade exists. Keep prior images and source, drain
open histories before replacement, and restore into an empty dedicated database
when recovery requires a backup. Reconcile Temporal and retained state before
accepting work. A software rollback does not rewind histories or erase evidence.

The [deployment playbook](../deployment.md) covers preparation, credentials,
activation, stop, backup, restore, rollback and separate permanent purge.
Local PostgreSQL/Temporal rehearsal is evidence for those components only;
cluster admission, images, platform backups and operator access require target
qualification before activation. Review this decision before a second core,
public ingress, provider spending, repository credentials, or sandbox execution.
