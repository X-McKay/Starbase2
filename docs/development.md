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

The Core root at [localhost:8787](http://127.0.0.1:8787) is a non-interactive
service page. `just dev` runs the Rust core, Python worker, and persistent
Temporal development server. Launch Godot with `just world`; `J` opens native
operations, while Field Command and Connection expose structured controls.
Ctrl-C stops its own processes and preserves `.local/` databases and logs.

`just demo` is idempotent for the default ID `first-survey`. After changing a build,
restart the worker and use `just demo another-survey`. Changed input under an
existing mission ID is rejected. The Godot Work panel creates v2 runs with fresh
IDs; use its Stop control to cancel a run. Stopping the local launcher merely
takes workers offline and leaves work durable.

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
| `just world-web-templates` | Download and verify the pinned Godot 4.7.2 template archive, then install only the no-thread Web templates in the checkout-local cache |
| `just check-world-web-probe` | Export the isolated Web probe twice and retain a deterministic size/hash manifest |
| `just check-world-web --output DIRECTORY --text-resources --stable-node-ids` | Qualified current-world path: export two clean staged copies, normalize Godot 4.7.2 imported-scene node IDs, run both package journeys from empty directories and require byte-identical artifacts without editing the checkout |
| `just prepare-world-web-transport --output DIRECTORY` | Export a minimal fixture containing the actual Web request adapter and Godot command state machine |
| `just web-fixture EXPORT_DIRECTORY` | Serve a Godot export and an in-memory Core together on one isolated loopback origin |
| `just check-web-fixture --output DIRECTORY` | Exercise the fixture's real Core cookie/origin boundary, static routing and controlled create/cancel flow |
| `just world-map` | Open the planetary colony overview |
| `just world-crew` | Native preview of the actual generated crew atlas regions |
| `just world-shot` | Capture the real native viewport to `.local/world-preview.png` |
| `just contracts` | Generate Rust-owned JSON Schema and Python models |
| `just fmt` / `just lint` | Rustfmt, Clippy, Ruff, ty for implemented sources |
| `just test` | Rust store/grader/migration tests; Python review, fake-model, inference-adapter and Web export-tooling tests |
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
- `apps/console`: historical dependency-free journal source; it is not served by
  the current Godot-native product.
- `scripts`: bootstrap, launcher, integration experiment, contracts, documentation.
- `evidence`: selected retained experiment records and actual rendered captures.

## Limits and next tooling work

General statistical comparison tooling, signing/notarization, and production
telemetry remain open. The local Godot Web handoff is verified through its export,
transport, browser journey and native regression gates. Godot 4.7.2 templates are
checksum-pinned; the minimal probe and current 177-root world export are
byte-identical across clean pairs. The current artifact is 760,154,489 bytes, with
a 720,305,104-byte PCK at SHA-256
`2141fa334dd952027c2e2bb3fd40a18d3aa1d28b4cfefa22f0df91c452c0139d`.
Both copies pass the five-structure package journey from empty directories, so
the check cannot fall back to staged source files. The qualified command is:

```sh
just check-world-web --output FRESH_DIRECTORY --text-resources --stable-node-ids
```

This staged pipeline keeps authored text resources unconverted during export and
uses a Godot-revision-pinned normalizer for imported GLB node IDs. All 53 imported
scenes passed persisted semantic verification; the manifest records the
normalizer hash and the checkout's world resources remain unchanged.

The same-origin `/game/` plus in-memory Core fixture passes browser-managed
credentials, redirect, timeout, cancellation and uncertain-write reconciliation.
Chrome 151 passed the actual exported-Godot command probe with no console errors.
The exact deterministic PCK completed startup, snapshot refresh, controlled work,
stop to `cancel_requested`, synthetic evidence inspection, character selection,
keyboard interior entry, disconnected last-known state and reconnect. The full
native `just check-world` suite, repository check and seven Web-tooling tests also
pass. The historical journal remains source history, not a fallback product or
delivery gate.

The matched 1280×800 comparison is a limited local measurement on an Apple M5
with 24 GiB RAM. Native reached its first process frame in 9.345 seconds and
sampled 150 monotonic intervals at 16.693 ms median / 23.941 ms p95. Chrome reached
the first Web post-draw marker in 42.610 seconds, then sampled 600 child-frame
`requestAnimationFrame` intervals at 16.7 ms median / 17.6 ms p95; 25 snapshot
requests measured 2.6 ms median / 4.0 ms p95. The browser reported
2,139,426,713 bytes of texture memory. The startup markers differ, the browser
navigation was a warm local no-store run, and rAF cadence is not render CPU or
end-to-end projection latency, so these numbers support no native/Web performance
improvement claim. The same Trial Hall composition, HUD, player and authoritative
state were visible in both; Web fine textures and edges were softer.

This is not production-ready: the 760 MB artifact, 42.6-second warm local startup
and 2.14 GB reported texture allocation require UI/content optimization. Cold
transfer, background-tab suspend/resume, wider browser/device coverage, structured
keyboard/accessibility review and worker-backed cancellation through terminal
acknowledgment also remain open; Rivet still contains one historical journal
reference. Container packaging and Kubernetes deployment are a separate workstream
explicitly deferred until the owner is happy with the UI. No deployment is part
of this handoff; `Starbase2.almckay.io` remains the intended eventual hostname.

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

The [setup, rollback, recovery and teardown playbook](deployment.md) documents
the disposable PostgreSQL-backed Kubani pilot, its stopped-by-default posture,
and the remaining durable production admission gates.

## Native launch import

`just world` runs a bounded headless editor import before opening the game, including
on a fresh checkout. Import or script errors prevent launch even if Godot exits
zero. Use `just world -- --fixture=res://../../fixtures/world/stale.json` for an
offline world fixture. The import also refreshes assets changed since the last run.
