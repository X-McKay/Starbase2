# Four-direction captain and packaged world

Status: accepted

This pass completes the captain’s illustrated walk directions and qualifies a
local unsigned macOS client. It does **not** establish Kubani deployment readiness.

## Implemented

- Original illustrated idle/portrait artwork retained. Eight existing right-facing
  frames plus four new contact/passing poses each for front, back and left.
- Shared actor, collision, distance-based phase and contact-driven foley. Turns
  preserve phase; walls stop animation; reduced motion uses the original stills.
- Independent SpriteFrames libraries compose through character metadata. One
  catalog command imports every registered sheet, including uneven source cells.
- New source sheets have actual alpha. Original source PNGs and prompts are kept;
  no direction is automatically mirrored. Name labels clear the taller artwork.
- Explicit offline verification runs inside the **exported release executable**
  outside the checkout. It exercises every captain walk frame, reduced motion,
  colony construction and three interiors through five room entry points.
- Export presets explicitly include JSON catalogs and omit development tests,
  capture scripts, galleries and import/validation tools. Normal startup is unchanged.
- Each local qualification writes a new directory, retains failure logs, requires
  explicit completion and native captures, rejects source changes during the run,
  and binds the archive/PCK/executable, source files, runner and evidence by SHA-256.

## Actual checks

| Check | Evidence |
|---|---|
| Every illustrated manifest rebuilt; frame alpha, provenance, motion, wall, stop, teleport, reduced motion and showroom checks | `catalog-check.log` |
| Full affected Godot suite and native HTTP command integration | `world-check.log` |
| Rust/Python tests, Ruff, ty, Cargo formatting/Clippy, contracts and docs | `repository-final.log` and `repository-release-final.log` |
| Exported release playback, catalogs and all room entry points | `export-smoke.log` and `export-manifest.json` |
| Refuses package verification without an offline fixture, with no extra errors/leaks | Final package `fixture-refusal.log` |
| Actual exported colony walking reaches destination; compact reduced-motion interior | Exported `colony.png`, `interior.png` and their measurement JSON |
| Native four-direction review, dark/light, wall and reduced motion | `directions.mp4`, `final-*.png`, `movie-final.log` |
| Movie encoded and completely decoded without errors | `encoding.log` |

Captures use an explicit synthetic fixture labeled in the UI. No live backend,
inference or cluster is needed. Capture timings are one local workload on Apple M5
with a 60 fps cap; they are not a general capacity or comparative speed claim.

## Failures retained and resolved

- `front-rejected.png` repeated the leading foot across an eight-frame draft.
  It is not shipped. The four-pose source uses explicit opposite contact poses.
- `eva-rejected.png` tested a compact 16-pose full-direction sheet. Its side rows
  repeated extended contact silhouettes without clear passing poses. It is not
  imported or enabled; this shortcut does not satisfy the remaining roster gate.
- Initial back/left imports rejected bounds. Source alpha contained nearly
  invisible margin pixels; source-bounds validation now matches the existing
  alpha > 0.1 visible-margin test. Uniform source scales were adjusted. Tests
  ensure visible artwork still cannot clip the canvas.
- The first export probe supplied the editor-only `--script` option to a release
  executable. It did not execute the probe. Missing completion correctly failed
  qualification (`export-check.log`). The explicit packaged offline check fixes it.
- Running the package check against editor resources deliberately fails the two
  development-script exclusion checks (`package-probe-editor.log`). This provides
  a negative control for the packaging gate.
- The missing-fixture refusal originally leaked a Camera3D and HTTPRequest created
  before `_ready`. Both are now freed on that early exit. The exported qualification
  requires exactly the intended refusal error and no leak warnings; unit tests
  cover zero-exit errors, process failures, timeout evidence and secondary errors.

## Readiness boundary and remaining owner work

The local macOS client is suitable for private review/use with the existing local
or port-forwarded Core. It is unsigned and not qualified for public distribution,
Web, Windows or Linux desktop. No images were published and no Kubani state changed.

EVA, Mender and Trainer retain approved still artwork. Their directional cycles
and optional gestures remain owned by the implementation assistant, with Al’s
visual review and the same import/native checks as completion gates. This pass
does not claim a fully animated roster or 50-texture performance qualification.

The broader Kubani release still needs a reviewed, committed source revision,
qualified immutable Linux Core/worker images, published registry digests and the
explicit target configuration before GitOps activation. The release builder’s
clean-source gate is preserved. Production repairs remain disabled; Linux sandbox
qualification is not implied by the passing macOS animation/export checks.
