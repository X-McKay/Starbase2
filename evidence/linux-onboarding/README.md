# Linux onboarding evidence · 2026-09-07

Scope: the existing local stack (Rust core, Python worker, Temporal development
server, browser journal and native Godot client) started for the first time on a
clean x86_64 Linux host. No product behavior changed. This is a local functional
record, not a performance benchmark, agent-quality claim or deployment approval.
The host is also Kubani node `rig0`; every listener stayed on loopback and no
cluster resource was read for or changed by these checks.

- `onboarding.json`: host, pinned tool versions, every command with exit code,
  attempts and wall-clock seconds, and what was deliberately not performed.
- `failed-toolchain-dns.log`: `mise install` needed seven attempts because the
  local systemd-resolved stub intermittently failed lookups while upstream
  resolvers answered. rustup resumed partial downloads; nothing was skipped.
- `bootstrap.log`, `doctor.log`: checksum-pinned Temporal CLI, locked uv/Cargo
  builds, and the read-only diagnosis including the new Git LFS checks.
- `repository-check.log`: `just check` — 34 Rust and 61 Python tests, Rustfmt,
  Clippy, Ruff, ty, generated-contract drift and documentation validation.
- `acceptance-loop.json`: one Surveyor review of the shipped sample repository
  and one paired comparison (v1 versus the regression control) submitted through
  the operator session. Both reached `completed · Evidence retained` in about one
  second; the review retained 2 findings, the comparison 12 trials with
  baseline 5/6 versus candidate 4/6 (`regressed`). An exact duplicate returned the
  same id; a changed input under that id was rejected with 409.
- `failed-character-pipeline-lfs-pointer.log`: the first `just check-world` run
  stopped at `test_character_pipeline.gd`. The `.blend` provenance sources were
  132-byte Git LFS pointers because `git-lfs` was not installed; a failed
  headless assertion never reaches `quit()`, so the run idled until the 60 s
  guard. `git lfs pull` fetched 20 objects (539 MB) in 635 s; the same script then
  passed in 1 s. `mise.toml` now pins `git-lfs` and `just doctor` reports
  unresolved pointers.
- `world-check.log`: the passing rerun — 30 headless Godot runs with zero errors
  in 64 s, plus the loopback HTTP command fixtures.
- `integration.log`, `operations.log`: the v1 and v2 recovery harnesses on fresh
  loopback core/Temporal processes (worker SIGKILL in both modes, 53-event replay,
  actual Temporal CANCELED, unloaded build rejected, core restart, paired grading,
  real analyzer snapshot, durable timer through worker plus Temporal restart, pause).
- `world-live-outdoor.png`, `world-live-inspect.png` and their `.json` samples:
  the native client against the live core. The header reads `LIVE CORE` with the
  core's observation time, the footer shows `Surveyor: Findings` from the retained
  review, and the inspector lists the completed run with its outcome and input
  kind. Frame samples are 210-frame smoke measurements under a 60 fps cap.

## Optional subsystems on the same host

- `memory-check.log`, `field-integration.log`, `repositories-integration.log`:
  FalkorDB persistence/tamper/scope checks and the field-agent and repository-watch
  integrations on real loopback Temporal/Core/FalkorDB with synthetic providers.
- `field-loop.json`, `world-live-command-board.png/.json`: live Watchkeeper and PR
  Reviewer observations through the memory-enabled core, three memory proposals,
  one operator approval (revision 0→1, stale repeat rejected with 409), and the
  native command board listing both completed observations.
- `deployment-guards.log`, `failed-postgres-tests-before-ready.log`,
  `postgres-tests.log`, `deployment-rehearsal.log`: renderer/destructive-action
  guards; the PostgreSQL tests first raced a fresh container (retained), then
  passed 34/34; the podman rehearsal passed its fifteen provisioning, migration,
  role, Temporal, recovery, backup/restore and cleanup checks.
- `inference-pilot.log`, `field-pilot.log`, `repair-pilot.log`: the explicitly
  authorized model calls (12 + 1 + 3). Trials for the inference pilot are in
  `../inference-pilot-1788821473450419838`. Outcomes match the earlier Mac pilot;
  they are smoke gates, not quality claims.
- `microsandbox-0.6.14-checksums.sha256`, `sandbox-doctor.log`: the upstream
  checksum file used to verify the Linux archive, and the host report (KVM
  read/write, SVM).
- `failed-sandbox-probes-arm64-image.log`, `failed-repairs-arm64-image.log`: the
  first Linux attempt. The guest `python3` failed with `Exec format error`
  because the pinned digest was the arm64 manifest of `python:3.12.13-alpine`.
  The adapter now pins one manifest digest per architecture.
- `sandbox-probes.log`, `repairs-integration.log`: the passing rerun — five
  isolation/limit probes, both crash probes, and the repair harness (interrupted
  mission recovered as improved, regression, no change, cancellation without
  credit, ledger retained). Probe records are in `../sandbox-qualification/linux`.
- `build-inputs-amd64.json`: linux/amd64 manifest digests resolved from the
  pinned base-image tags for the native image build.
- `failed-repository-check-float-parse.log`: `just check` failed once in
  `field::tests::capture_retry_and_active_history_remain_visible` because a
  stored `f64` timestamp (`1788822474.4166563`) parsed back one ULP higher;
  `serde_json` without `float_roundtrip` is not correctly rounded. A repeat of
  the same test under a correct invocation failed 1 of 15 runs before the fix.
  The core now enables `float_roundtrip`; `timestamp_tests` in `lib.rs` sweeps
  200,000 current-epoch values and the field test was soaked afterwards.

Not performed here: web export, cold-cache timing, and any Kubani change.
