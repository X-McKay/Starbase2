# Godot Web delivery handoff

Status: proposed

The local export/transport slice is implemented and tested; production readiness
remains open.

Revalidated 2026-09-13 against the current independent-cast checkout. Godot remains
the product interface. The historical browser journal is not a fallback or delivery
gate. Native Godot remains supported and its macOS export preset is unchanged.

The owner has deferred container packaging and Kubernetes deployment to a separate
workstream, after the UI result is satisfactory. The intended later destination is
`https://Starbase2.almckay.io`. This handoff does not authorize a push, image publish,
cluster change or deployment.

## Implemented and verified

- **Pinned export:** Godot `4.7.2.stable.official.ed1daf0bf`, matching checksum-pinned
  no-thread Web templates, bounded installation/import/export commands, isolated
  stages, and manifests containing artifact sizes and SHA-256 hashes. The official
  template archive is 1,281,349,702 bytes; only the required Web templates are
  extracted into the checkout-local cache.
- **Minimal probe:** two clean nine-file exports are byte-identical at 39,852,657
  bytes, including a 39,514,754-byte WASM runtime and 3,276-byte PCK. One warm in-app
  Chromium observation reached first post-draw in 572 ms. This is a shell probe,
  not full-world or cold-network performance.
- **Current world:** the Web preset selects 177 resource roots, including the
  current world, seven character definitions, dynamic catalog inputs and browser
  transport. Two clean exports match byte-for-byte. Both pass the offline package
  check from empty directories: catalogs, character playback, reduced motion,
  five physical room/console/exit journeys and seven direct entry points, with
  development scripts excluded and no staged-source fallback.
- **Same-origin fixture:** `/game/` serves the exported shell beside the real
  in-memory Core routes. HTTP checks pass cookie bootstrap, authenticated
  create/cancel, missing-cookie and cross-site denial, traversal denial and WASM
  MIME handling. The fixture has no worker, providers or persistent production
  state. It grants no permissive CORS.
- **Browser transport:** a thin Fetch adapter preserves browser-managed HttpOnly
  cookies with `credentials: "same-origin"`, rejects redirects, aborts bounded
  requests, limits response size and fences obsolete callbacks. The existing
  command state machine reconciles uncertain writes by exact-record GET before
  another dispatch. Native consumers continue using `HTTPRequest`, loopback HTTP
  origins, and their existing cookie/Origin handling.
- **Transport checks:** in-app Chromium probes pass managed credentials, snapshot
  refresh, redirects, timeout, response bounds, cancellation and obsolete callbacks.
  The actual exported Godot command probe passes in both in-app Chromium and
  Chrome 151: session bootstrap, controlled command, pending duplicate fence,
  uncertain-write reconciliation and stop dispatch, without console warnings or
  errors.
- **Full browser journey:** the exact current-world PCK passes startup, refresh,
  controlled review submission, retained `cancel_requested`, synthetic evidence
  and full-record inspection, Rivet's actual dossier portrait, Sho Junko/Cybercat
  selection, keyboard Trial Hall entry, disconnected last-known state and
  reconnect. A resumed fixture produced a fresh Core receipt in about 0.2 seconds.
  Synthetic evidence and unavailable worker status remained explicit. No new
  console warnings or errors were collected. This full journey was performed in
  in-app Chromium; Chrome additionally received the command probe and exterior
  visual/performance review.
- **Native and repository regressions:** `just check-world` passed, including
  social animation, room journeys and both native HTTP fixture suites. Repository
  checks passed 43 Rust and 161 Python tests, lint, types, generated contracts and
  documentation. Seven focused Web tooling tests also passed and are included in
  `just test`.

## Artifact and measured comparison

The qualified artifact is `.local/world-web-closure-03/export-1`; its manifest is
`.local/world-web-closure-03/manifest.json`. Both clean exports contain nine files,
totaling **760,154,489 bytes**. Their **720,305,104-byte PCK** has SHA-256:

```text
2141fa334dd952027c2e2bb3fd40a18d3aa1d28b4cfefa22f0df91c452c0139d
```

This equals the PCK used for the completed full browser journey. Artifact sizes
are raw file sizes, not measured compressed internet transfer sizes.

Final samples used an Apple M5 with 24 GiB RAM, a verified 1280×800 view and no
competing task jobs; ordinary desktop activity remained present.

| Observation | Native Godot | Chrome 151 Web |
|---|---|---|
| Startup marker | 9,345 ms to first process tick | 42,609.9 ms from navigation to first post-draw |
| Interval sample | 150 monotonic process intervals | 600 browser rAF wall-clock intervals after warmup |
| Median / p95 interval | 16.693 / 23.941 ms | 16.7 / 17.6 ms |
| Local snapshot HTTP | Not separately sampled | 25 samples; median 2.6 ms, p95 4.0 ms |
| Reported texture allocation | Not sampled | 2,139,426,713 bytes |
| Errors in final capture/sample | None | No collected console warnings/errors |

The startup markers and interval types differ; this is not a controlled native/Web
speed ratio. Browser rAF cadence is not render CPU time or end-to-end UI latency.
The Web static-memory monitor returned zero and is treated as unavailable. Reported
texture allocation is not whole-tab memory or independently verified GPU residency.
The browser observation is one warm repeat navigation over local HTTP, not a cold
internet or target-device qualification.

The native capture and matched browser screenshot retain the same Trial Hall
exterior composition, HUD, player and truthful worker/report state. Web fine
texture and edge detail appears softer. This is a limited visual comparison, not
pixel identity, complete accessibility qualification or owner art approval. The
first browser Trial Hall entry also stalled for about five seconds and briefly
showed `STALE` before recovering.

The final machine-readable handoff is
`.local/web-resume-20260913/validation.json`; the matched browser sample is
`chrome-isolated-02.json` in that directory. Native capture, metrics and log are
`.local/web-native-comparison-02.png`, its `.png.json` companion and
`.local/web-native-comparison-02.log`. Full regression logs are
`.local/web-check-world-02.log` and `.local/web-repository-check-04.log`.

## Reproducibility mechanism and retained failures

Godot's clean GLB imports generated differing PackedScene node IDs. The qualified
command keeps authored text resources unconverted during export and applies an
exact-revision node-ID normalizer only to isolated imported caches. It rejects
unknown layouts, instances and collisions, reloads saved scenes, and verifies
persisted non-identity semantics. All 53 imported scenes passed. The normalizer's
SHA-256 is recorded in the manifest:

```text
9f237a55dccfa895df3e0d68b99172d2b6cf8665f538a90eed0ba2cbbce7612e
```

This is an engine-specific build workaround using private serialization, not
runtime architecture. Revalidate it on engine upgrades and retire it when a
supported import path satisfies the same exact reproducibility requirement.
The explicit resource list also needs maintenance when dynamic catalog paths
change. Clean pairs belong in qualification; ordinary edits need focused checks.

Earlier failures remain retained: contended import timeouts, a 38-root export
missing GDScript preload dependencies, nondeterministic imports, and a package
check that incorrectly saw development files in its staging directory. The final
package gate uses an empty directory. Old competing Godot test jobs were stopped;
the current test source and a delayed restore wrapper's backup were preserved.
Earlier contended timings and the first mismatched Chrome viewport sample are not
used as the final comparison. A repository run blocked by sandbox socket access
was followed by the authorized local-socket run recorded above.

## Reproduce the local review

Use a fresh output directory and freeze world sources for qualification:

```sh
mise exec -- just world-web-templates
mise exec -- just check-world-web --text-resources --stable-node-ids --output .local/world-web-review-next
mise exec -- just web-fixture .local/world-web-review-next/export-1 55625
```

Open `http://127.0.0.1:55625/game/` for the normal product or
`http://127.0.0.1:55625/__fixture/review` for the opt-in timing wrapper.
The fixture disables caching, reads each asset as one allocation, and lacks
streaming/range support. It is a correctness fixture, not the production server.

## Remaining UI work and separate deployment workstream

The current payload, startup time and reported texture allocation prevent a
production-readiness claim. Preserve this baseline. The next proposed UI experiment
is a staged 4K-to-2K cap on selected non-character structure material maps, keeping
native assets and compression unchanged. Measure payload, startup phases, texture
allocation, first-entry stalls and visual quality before adopting the profile.
Evaluate GPU compression separately; introduce deferred asset packs only if a
Web-sized single package still misses agreed delivery budgets. Do not assume the
42.6-second startup is entirely texture decode: download, WASM initialization,
resource decode/upload and first usable UI have not been separated.

The World implementation owner retains these completion gates: agreed target
browser/device and payload/startup budgets; background-tab suspension/resume;
structured keyboard/accessibility review; worker-backed completion and terminal
cancellation acknowledgment; and correction of Rivet's existing idle copy that
still directs users to the historical journal.

After owner acceptance of the UI result, the separate container/Kubernetes
workstream can package this artifact for `Starbase2.almckay.io`, using an established
static server and same-origin API routing. It must review ingress, certificates,
authenticated operator access, cookies, caching, startup budgets and recovery under
Kubani's GitOps authority. Same-origin routing and Secure cookies alone do not
provide user authentication. The accepted private access arrangement in ADR 0005
describes the current deployment boundary, not authorization to expose a new host.
No container packaging or external deployment was performed for this UI slice.
