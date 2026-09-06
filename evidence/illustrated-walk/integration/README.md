# Illustrated captain integration

Status: implemented for screen-right travel in the normal colony.

The captain now uses the eight illustrated walking frames when moving right.
The original illustrated idle poses remain, including when stopping or using
reduced motion. Front/back/left walking falls back to the matching approved still;
EVA and other appearances retain stills. No 3D replacement or automatic mirroring.

## Evidence

- [Colony and Command interior movie](colony.mp4): actual shared actor and route
  logic, fixture-only data, optional foley; 270 frames / 9 seconds / 30 FPS.
- [Character review movie](review.mp4): right-facing cycle, missing-direction
  fallbacks, reduced motion and background review; 450 frames / 15 seconds.
- `final-review-180.png` / `final-review-445.png`: transparent walk frames on dark
  and light ground. `colony-90.png` / `colony-210.png`: colony and interior.
- `character-final.log`: actual eight-frame playback, RGBA, matte preservation,
  provenance, fallback/stop layouts, reduced motion and real wall-contact checks.
- `world-check.log`: complete affected Godot scene suite.
- `commands-check.log`: native command reconciliation; six POSTs, GET recovery,
  no worker credentials and no duplicate effects.
- `repository-check.log`: lint/types, 34 Rust tests, 45 Python tests and contracts
  passed; its final documentation check caught an invalid lifecycle label.
  `docs-final.log` records the corrected documentation check passing.
- `encoding-final.log`: successful video encoding and full decode of both movies.

`import.log` retains the initial typed-loop-variable parser failure; `import-v2.log`
and `import-final.log` record successful generation. Earlier review/movie files
remain evidence of the first cadence pass; final movies use a 3.2-world-unit
stride rather than the inherited 1.28-unit rigged value.

## Source and implementation

The raw source and original generation prompts are in the parent directory.
`art/characters/illustrated-captain.json` specifies matte criteria, source grid,
anchors, uniform scale, frame order/durations and stride. The importer writes
`apps/world/art/characters/captain-illustrated.png` (true RGBA) and an editable
SpriteFrames resource. The JSON beside the atlas records all input/output hashes.

Matte cleanup flood-fills only light neutral pixels connected to cell boundaries.
A synthetic regression verifies enclosed white highlights and black outlines are
preserved. No global deletion of pale colors, per-frame automatic resizing, shader
keying or replacement of the raw source is used. Native inspection verifies the
result against both backgrounds and the existing environment.

Per-clip layouts and missing-clip fallback live in the shared CharacterDefinition
and actor. Adding another finished directional sheet requires art/configuration,
not a new character-specific actor. The source-specific cleanup is not guaranteed
for arbitrary artwork; new sources require visual inspection.

## Limits and next work

This is one illustrated directional clip, not a finished animated roster.
Captain front/back/left, EVA, other crew cycles and gesture/work poses remain to
be authored and reviewed. The source's high knee lift and cape motion are retained;
further artistic refinement is possible. No production backend or deployment
changes. The capture timings are not a 50-character performance benchmark.
