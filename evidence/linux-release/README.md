# Linux arm64 release qualification · 2026-09-06

Status: **local Linux arm64 qualification passed**. Nothing was pushed,
published, or deployed to Kubani. These images are a private read-only review
and evaluation candidate; production activation still requires the target checks
in the [deployment playbook](../../docs/deployment.md).

## Exact artifacts

Source and qualification harness: `e7a51acf4c4d465287b913379876d7beda7f0d3c`.
[Inputs](qualification-inputs.json), [base digests](build-inputs-arm64.json),
[build log](build.log), [image metadata](image-metadata.json), and the
[qualification report](qualification-report.json) bind this result to:

| Component | Local image ID (not a published registry digest) |
|---|---|
| Core | `sha256:665baa0154e416573c07f3d3e12c956494fdec19543a46c6c5ac8b7417ab02e6` |
| Worker | `sha256:65833c328b634e384336e834f969e15a36f989d967ef58f313c8b1027c9d241b` |

## Verified behavior

The [rehearsal log](qualification.log) and report record 16 passing checks:
fresh PostgreSQL 18.3 provisioning, repeatable migrations, runtime-role write
restrictions, dedicated Temporal namespace/retention, refusal of a competing
Core, review evidence retention, actual container probes, non-root/read-only
execution, no worker database credential, paired verdicts, in-image history
replay, cancellation/stale state, duplicate queued work after worker restart,
disabled legacy/repair APIs, restart persistence, backup/transactional restore,
closed history checksums, and owned-resource teardown.

Both [improvement](improved.json) and [regression](regressed.json) have 12 retained
trials. These are deterministic controls over the explicit synthetic `sample`
target, not evidence of general agent quality or live repository/cluster work.
No model inference or external effects were enabled. The [history manifest](histories/manifest.json)
and closed histories retain the actual Temporal execution evidence. The report
also records harness file hashes and the database dump hash used for restoration.

Core and worker termination exited 0; observed stops took 0.123–0.284 seconds.
This is a bounded local observation, not a load benchmark or shutdown SLA.
The pod and synthetic secrets were removed. Shared local services were untouched.
[Repository checks](repository-check.log) passed: 34 Rust and 56 Python tests,
Clippy, Ruff, ty, generated contracts, and documentation validation.

## Failures retained and fixed

- [amd64 attempt](failed-amd64-emulator.log): local QEMU crashed executing
  `rustc -vV` with signal 11. **amd64 is not qualified**; use a native builder.
- [uv check](failed-uv-version.log): official uv includes a valid platform
  suffix. Accept that suffix while enforcing exact version 0.12.7.
- [development dependencies](failed-dev-dependencies.log): FalkorDB Lite tried
  to compile in the minimal image. Exclude development dependencies; Ruff is now
  an explicit runtime dependency because the review agent uses it.
- [worker import](failed-worker-import.log): the contract schema was missing
  from the image. Copy contracts and verify worker import during the build.
- [shutdown before](shutdown-before.json) / [after](shutdown-after.json):
  Core ignored SIGTERM as PID 1 (exit 137). Tokio signal handling now drains
  Axum and exits normally (0); the integrated rehearsal rejects forced stops.

## Remaining deployment gates

Publish these exact artifacts through an authorized registry workflow and record
registry digests. Select a verified arm64 Kubani target (the application and
migration Job now require the configured architecture). Verify admission,
network policy, resource limits under target workloads, operator access, actual
PostgreSQL/Temporal identities and platform-owned backup recovery. This local
pod uses trust-based disposable PostgreSQL and a Temporal development server;
it does not establish production authentication, availability, or disaster recovery.

The already-qualified unsigned macOS UI is separate; see its
[export evidence](../illustrated-walk/release/README.md). Linux sandbox execution,
field integrations and richer memory remain disabled in the initial production
bundle and retain their separate qualification requirements.
