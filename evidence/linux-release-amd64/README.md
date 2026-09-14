# Linux amd64 release qualification · 2026-09-07

Status: **Linux amd64 images qualified, published and verified; not activated**.
These are private images built on
Kubani node `rig0` (x86_64) with rootless podman; production activation still
requires the target checks in the [deployment playbook](../../docs/deployment.md).

## Exact artifacts

Source revision `71ca83dd7e5a9d763760a81f900e72aaaae2ea15`. [Build inputs](build-inputs-amd64.json)
pin the linux/amd64 manifest digests of the same base-image tags used for arm64;
[the build log](build.log) and [image metadata](image-metadata.json) bind the
result to:

| Component | Local image ID (not a published registry digest) |
|---|---|
| Core | `sha256:582fdec376899d9f8f463872bf3253adddf96577fcc441ec1ffc00e1c314dbe8` |
| Worker | `sha256:a5aa0648dc5a267cfea97e1f57c0cbfb2df3b1a3d9e50e86501fa2390257f8b9` |

[Qualification inputs](qualification-inputs.json) use the amd64 manifest of
`temporalio/temporal:1.8.2` (`sha256:2aeb9718…`); the arm64 record had pinned
that tag's arm64 manifest.

## Verified behavior

[The qualification log](qualification.log) and [report](qualification-report.json)
record 16 passing checks: fresh PostgreSQL 18.3 provisioning, repeatable
migrations, runtime-role write restrictions, dedicated Temporal namespace and
retention, refusal of a competing Core, review evidence retention, container
probes, non-root/read-only execution with no worker database credential, paired
verdicts ([improved](improved.json) 6/6 versus 5/6, [regressed](regressed.json)
4/6 versus 5/6, 12 retained trials each), in-image history replay,
cancellation/stale state, duplicate queued work after worker restart, disabled
legacy/repair APIs, restart persistence, backup and transactional restore,
closed-history checksums, and owned-resource cleanup. All six container stops
exited 0 (0.04–1.06 s). [The history manifest](histories/manifest.json) lists
the exported closed histories by hash; the payload files remain in the ignored
local output directory.

## Failures retained and fixed

- [Database readiness race](failed-database-readiness-race.log): the harness
  accepted `pg_isready` from the PostgreSQL image's temporary socket-only initdb
  server, which then stopped before the first SQL. The driver now waits for TCP
  readiness; `test_image_driver_waits_for_tcp_database_readiness` covers it.
- [runc secret mount](failed-runc-secret-mount.log): runc 1.3.4 cannot create
  `/run/secrets/*` mountpoints on the read-only rootfs the pod requires. crun
  1.14.1 runs the unchanged harness flags; podman now defaults to crun through
  the user's `containers.conf`.
- The image build itself succeeded on the first attempt (67 s with warm caches).

## Publication · 2026-09-08

With explicit authorization, both images were pushed from this host and
verified; see [the publication record](publication-plan.json):

| Component | Immutable registry reference |
|---|---|
| Core | `registry.almckay.io/starbase2/core@sha256:955d9e4989340ea3a55607e8f2ece49ce6796c13985b0d4165a9d3aab9f51bd3` |
| Worker | `registry.almckay.io/starbase2/runtime@sha256:c9cedb3ff576138420e11bc952e21ec002d5ba766bfb8579028b9ad53d93f05d` |

Each digest was pulled back and its configuration identity, root filesystem
layers, labels and history matched the qualified local image exactly (the
first verification pass mis-compared a prefixed and a bare digest and was
corrected). Kubani node `rig0` also pulled both digests through its own
containerd registry configuration and resolved them to the qualified image IDs.
Tags `71ca83dd…-amd64` are movable conveniences; the digests above are the
release identity. No Kubernetes resource was created.

## Remaining deployment gates

Regenerate and review the exact stopped bundle with these digests and
`platform: linux/amd64` on general nodes; the platform backup-key item is in
the roadmap backlog by owner decision; then follow the activation steps in the
playbook. This disposable pod used trust-based PostgreSQL and a Temporal
development server; it establishes nothing about production authentication,
availability, or disaster recovery.
