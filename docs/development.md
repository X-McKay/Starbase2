# Developer experience

Status: accepted

## Implemented local repair extension · 2026-09-05

For the isolated repair workshop, install pinned microsandbox 0.6.14, run `just sandbox-prepare`, then `just sandbox-doctor`. The sandbox image is pinned per CPU architecture (arm64 and x86_64 manifest digests of `python:3.12.13-alpine`). `just test-sandbox` and `just test-repairs` require local virtualization and bind isolated integration ports 18789/17235; they use no model calls. `just repair-pilot` explicitly makes three development model calls. See [repair operations](repairs.md).

This document describes the implemented local operations edition. Production tooling and
unimplemented commands are explicitly deferred.

## Linux onboarding · 2026-09-07

The existing stack ran for the first time on a clean x86_64 Linux host: pinned
toolchain, bootstrap (114 s), `just check` (11 s), `just check-world` (64 s), the
v1/v2 recovery harnesses (44 s / 54 s), an operator review plus paired comparison
through the live core, and native captures showing the Godot client reading those
retained records. See [the retained record](../evidence/linux-onboarding/README.md).
The one onboarding defect was missing Git LFS content (below). The same host then
ran the optional subsystems: FalkorDB memory (`test-memory`, `test-field`,
`test-repositories`, a live field observation with an operator memory approval),
microsandbox 0.6.14 (`test-sandbox`, `test-repairs`), Docker/podman PostgreSQL
(`test-postgres`, `deployment-rehearse`) and the explicit inference, field and
repair pilots. The sandbox first failed because the pinned image digest was the
arm64 manifest; the adapter now pins one manifest digest per architecture. These
are local functional checks; they establish nothing about performance or deployment.

On Linux, install podman **with crun** for `deployment-test-db`,
`deployment-rehearse` and `deployment-qualify-images` (runc cannot mount secrets
into the read-only pod rootfs); the local database helper also accepts
`--engine docker`. Install microsandbox from the upstream release archive after
verifying `checksums.sha256`; `msb` and `libkrunfw` live under `~/.microsandbox`
with `~/.local/bin/msb` on `PATH`. The Ollama pilot expects `qwen2.5-coder:7b`.

## Start locally

Install [mise](https://mise.jdx.dev/getting-started.html), then from this checkout:

```sh
mise install
mise exec -- just bootstrap
mise exec -- just check
mise exec -- just dev
```

In another terminal:

```sh
mise exec -- just world
```

The journal is at [localhost:8787](http://127.0.0.1:8787). `just dev` runs the Rust
core, Python worker, and persistent Temporal development server. Ctrl-C stops
its own processes and preserves `.local/` databases and logs. No browser or world
window is required for execution. Launching Godot is optional.

`just demo` is idempotent for the default ID `first-survey`. After changing a build,
restart the worker and use `just demo another-survey`. Changed input under an
existing mission ID is rejected. The journal creates v2 runs with fresh IDs.
Use its Stop control to cancel a run;
stopping the local launcher merely takes workers offline and leaves work durable.

Run under `mise exec --` if tools are not on PATH. Bootstrap downloads a
checksum-pinned Temporal CLI into `.local/tools`, runs `uv sync --locked` and
`cargo build --locked`, and uses `.local/cache/uv`. It supports macOS/Linux ARM64
and x86-64. Rust/Cargo use the normal Cargo cache; `CARGO_HOME` may point to a
project cache when needed. Windows remains unverified.

Blender sources under `assets-production/**/*.blend` are Git LFS objects.
`mise.toml` pins `git-lfs`; after `mise install`, run `git lfs install --local`
once and `git lfs pull` (about 539 MB). `just doctor` reports unresolved pointer
files. Without the objects, `just check-world` stops at the character provenance
check: a failed headless assertion never reaches `quit()`, so the run idles until
its 60-second guard instead of failing fast.

No `.env` file or provider credentials are loaded. The local launcher gives child
processes only basic OS environment fields and project configuration. All listeners
are loopback. Sandboxed development hosts may require permission to bind local
ports and run native Godot; ordinary checks need neither network nor a cluster
once dependencies are present.

## Commands that exist

| Command | Behavior |
|---|---|
| `just bootstrap` | Locked dependencies, checksum-pinned Temporal CLI, Rust build |
| `just doctor` | Read-only tool/version/file diagnostics |
| `just build` | Build the Rust core from the locked workspace |
| `just dev` | Build then launch persistent local Temporal, core, worker; logs in `.local/` |
| `just demo ID` | Submit one synthetic baseline/regression campaign |
| `just world` | Playable native outpost; H opens controls and comfort settings |
| `just world-map` | Open the planetary colony overview |
| `just world-crew` | Native preview of the actual generated crew atlas regions |
| `just world-shot` | Capture the real native viewport to `.local/world-preview.png` |
| `just contracts` | Generate Rust-owned JSON Schema and Python models |
| `just fmt` / `just lint` | Rustfmt, Clippy, Ruff, ty for implemented sources |
| `just test` | Rust store/grader/migration tests; Python review, fake-model, and inference-adapter tests |
| `just check` | Lint, tests, Rust build, generated-contract drift, documentation |
| `just check-world` | Import, state, navigation, keyboard/mouse and local HTTP command fixtures; visual QA remains separate |
| `just characters-import` | Rebuild every registered illustrated sheet, then validate artwork, movement and the review room |
| `just check-world-export` | On macOS, build and exercise an unsigned release outside the checkout; retain hashes, logs and native captures in a fresh `.local/world-release/` directory |
| `just test-integration` | Fresh core/Temporal processes, worker SIGKILL, duplicates, cancellation, replay, core restart |
| `just test-operations` | v2 review/gym, operator boundary, durable recurring timer restart, replay, pause; no inference |
| `just inference-pilot` | Explicitly opt into twelve bounded hosted/Ollama synthetic prompt trials |
| `just eval-smoke` | Public fake-model and grader controls; no real quality estimate |

The v1 integration uses ports 18787 and 17233 and a new `.local/integration-<timestamp>`
directory. Failed runs and logs are retained. It kills only processes it launched.
Run a named evidence capture with:

```sh
PYTHONPATH=services/runtime .venv/bin/python scripts/integration.py --output .local/my-experiment
```

The v2 integration uses ports 18788 and 17234. Its optional `--inference` flag
authorizes one additional hosted-model call in that invocation. See
[operations](operations.md) for profiles, source handling, and recovery semantics.

Temporal CLI is pinned at 1.8.3 (embedded server 1.31.2); Python, uv, Rust, just,
and Godot are pinned in [mise.toml](../mise.toml). Python uses one `uv.lock` and
Rust one `Cargo.lock`. Generated model changes are checked; readers support
additive snapshot fields, but commands are strict. Generator warnings about
unsigned integer formats are bounded by Rust's authoritative command validation.

## Source map

`mise exec -- just world-kit` opens the isolated interior/exterior art showroom.
Use `1`/`2`, `C`, `L`, and `R` for scene, camera, lighting and roof review; matching
buttons are visible. It needs no services. See [art production](art-production.md)
for scene authoring, asset contracts, evidence and the remaining integration gate.

`mise exec -- just world-structure repair` previews a building definition without
services. Add `50` for the shared-art load fixture. The [building authoring guide](building-catalog.md)
explains how PNG/native exteriors and reusable interior scenes are added without
new building-specific GDScript. `Tab` includes searchable direct place visits.

The [playable rollout](world-rollout.md) runs with ordinary `just world`.
For local visual checks, `godot --path apps/world -- --room=repair` starts in the
workshop (`review` and `gym` select the other rooms). `--inspect` opens that
room's inspector; normal startup remains outdoors. These flags dispatch no work.

- `services/core`: Rust API, SQLite migration, fixture grader, store tests.
- `services/runtime`: Python review tools, inference adapter, legacy fake agent, workflows, coordinator, tests.
- `contracts`: generated v1/v2 JSON Schemas; endpoint semantics in the owning README.
- `apps/world`: original SVG art, reusable habitats, navigation, actors, HUD, native
  operator client and state projection. See [playable world evidence](world-playable.md).
- `apps/console`: dependency-free structured HTML journal embedded in the core.
- `scripts`: bootstrap, launcher, integration experiment, contracts, documentation.
- `evidence`: selected retained experiment records and actual rendered captures.

## Limits and next tooling work

General statistical comparison tooling, Postgres integration,
container images, deployment, signing/notarization, and production telemetry are
not implemented. Godot native export was exercised; web export needs matching
web templates and same-origin API hosting. The native archive was also launched and rendered locally; it is unsigned
and is not a distributed release.

No plugin packaging or hooks were added. Existing tailored development skills
were usable in this session; Codex exposed them, while actual Claude-host discovery
is still unverified. Add prek/hooks only after a recurring workflow demonstrates
value; CI runs the same checked-in commands without relying on local hooks.

Static journal files need no Node runtime or frontend build step. For optional
source formatting, this session used `npx --yes prettier@3.6.2 --write apps/console/*`
with Node 24.19.0 and npm's cache under `.local/cache/npm`. JavaScript syntax was
checked with `node --check apps/console/console.js`. These optional tools are not
required by bootstrap or the running product.

## Fresh Kubani deployment preparation

The [setup, rollback, recovery and teardown playbook](deployment.md) prepares a fresh
PostgreSQL-backed installation. Local SQLite and local Temporal histories are
development-only and are not imported. The private deployment bundle starts
stopped, with provider inference, legacy fixture API and unqualified sandbox
repairs disabled. Cluster/image qualification and platform backup restoration
remain required before activation; no Kubani deployment has been performed.
