# Character production

Status: accepted for the shared runtime and four-direction captain cycle; the remaining roster artwork is open.

## Visual decision · 2026-09-06

Keep the original illustrated 2.5D crew. The user reviewed the rigged captain and
EVA experiment and preferred the older characters' detail and polish. The new
segmented 3D designs are **not approved replacements**. Their technical success
does not establish visual improvement. Do not roll them out by default or use
them as the style reference for new characters.

The illustrated captain now has authored walks in all four directions.
Continue authoring other crew’s illustrated 2D walk frames against
`apps/world/art/crew-adventure.png`, preserving costume, silhouette, proportions,
palette and texture. A layered source or a carefully drawn sprite sheet can use
the same import contract. Blender is an optional producer, not a required art
style or a runtime dependency. The earlier recommendation to standardize on
Rigify/rendered models is superseded by this experiment and the user's review.

## Implemented runtime

All crew use one `AnimatedSprite3D` actor. The JSON character catalog maps each
identity to a CharacterDefinition resource; approved still poses use legacy atlas
regions. The actor no longer contains per-character atlas rows or rendering
branches. Portraits continue to use approved illustrations. Both illustrated and
animated definitions retain the same collision and operational state boundaries.

A shared gait advances from horizontal displacement after `move_and_slide()`.
It preserves phase through turns and stops, resets after teleports, and supplies
foot-contact events to optional foley. Sub-millimeter movement per physics tick
is ignored to suppress measured collision recovery jitter. Extremely slow motion
below that threshold is not animation-qualified. Authored frames get no extra
procedural bob; still poses now remain still rather than bouncing at walls.
Reduced motion displays idle poses while traveling. Sound remains independently
optional and muted by default. No movement or animation starts operational work.

The rejected rigged captain and EVA resources remain confined to explicit
technical previews. Normal colony startup now uses the cleaned illustrated
eight-frame captain cycle when traveling screen-right and four-pose contact/passing
cycles for front, back and left. The original four illustrated stills remain its
idle poses. EVA and the other crew still use their approved stills. No direction
is silently mirrored, and no 3D character is enabled by default.

## Shared asset contract

| Property | Implemented pilot contract |
|---|---|
| Frames | 256×320 RGBA; identical canvas in every frame |
| Foot anchor | Per clip: illustrated captain (128,296); rigged prototypes (128,280) |
| Directions | front, back, left, right; asymmetric details need authored views |
| Required clips | idle in all four directions; optional walk clips fall back to the corresponding idle |
| Packaging | illustrated right 4×2, other directions 2×2; rigged prototypes 9×4; two-pixel gutters |
| Asset size | captain walks: one 1040×648 and three 520×648 atlases; about 6.43 MiB decoded RGBA, excluding original stills and engine overhead |
| Motion | illustrated captain stride 3.2 world units; rigged prototype 1.28; contacts at phases 0 and 0.5 |
| Definition | atlas, canvas, pivot, pixel size, stride, provenance and legacy/animated mode |
| Collision | owned separately by the shared actor, never inferred from silhouette |
| Review | technical validation plus native inspection; visual approval is separate |

These values are configurable art metadata. The illustrated stride was increased
after native review found the inherited rigged stride too fast at normal movement
speed. Additional optional work/gesture clips have no runtime dispatch
implemented yet; they must not substitute for authoritative state labels.

Add a character's editable source entry to `art/characters/catalog.json`. Supply
36 PNGs under a frame directory, named `front-0.png` through `right-8.png`; zero
is idle, 1–8 are walk samples. A `source.json` names the project-relative editable
`source`, `tool`, `canvas`, `pivot`, and `stride_m`. Pack into one atlas and generated
CharacterDefinition, then register its resource in `apps/world/characters/catalog.json`.
No actor-code change is needed. A recolor may share compatible frames; a new
silhouette requires its own art and review. The current tool does not automatically
turn a complete still image into layered animation art.

Run from the repository:

```sh
mise exec -- just check-characters
mise exec -- just characters-pack .local/character-frames
```

The packer reads exporter-neutral PNGs and records source, atlas, individual-frame
and packer hashes. Validation rejects missing transparency (including fully opaque
RGBA), empty images, clipped canvas margins, duplicate stride poses, out-of-bounds
frames, invalid pivots/scales, oversized atlases, missing clips and stale source
hashes. It cannot certify anatomy, readability or absence of painted checkerboards.

## Retained technical experiment

`art/characters/captain.blend` and `eva.blend` are original editable models with a
shared native Blender armature, rigid segment weights and a named eight-pose walk
Action. Idle is frame 0, walk is frames 1–8. This is **not a Rigify implementation**;
soft skinning, expressive cloth, detailed illustrated shading and production art
quality were not established.

`build_sources.py` recreates these initial models and overwrites those two source
files; it is deliberately excluded from the normal rendering command.
`render.py` reads the editable sources without rewriting them. Its pinned Blender
4.5.3 studio produces real RGBA frames. Packing is a separate Godot step that
accepts frames from other editors too.

```sh
# Only needed to reproduce the rejected 3D visual experiment.
mise exec -- just characters-render --blender /path/to/Blender
mise exec -- just world-rig-study
```

The local macOS renderer lives under `.local/tools/character-renderer`, outside
shipping assets. Official macOS arm64 Blender 4.5.3 DMG SHA-256:
`73ea841053b55404bb3a71a9a22366f1f8821787fe5c899f8b55a7fff929d01b`.
The exporter checks the version. Other rendering platforms are unverified.

The isolated Character Lab has buttons and matching keys for idle/walk, four
directions, two speeds, colony/interior camera angles, dark/light backdrop,
reduced motion, wall collision, optional sound and reset. It has no backend
requests. Approved stills are shown beside the experiment for comparison.

## Evidence and remaining work

[Character evidence](../evidence/character-pilot/README.md) records the checks,
failures and captures. The tests exercised real CharacterBody3D wall collisions,
turning, stops, teleports, reduced motion and shared contact phase. No production
migration, deployment or operational behavior was changed.

Next art owner: implementation assistant, with visual acceptance by Al. Remaining
work is all four EVA walk directions, followed by other
crew and gesture/work clips. Each must retain the approved look, pass the common
validator, and survive native loop/turn/contact review before enabling it.
Do not interpret the retained 3D prototype as satisfying this gate. Measure many
distinct textures on representative hardware before claiming 50-character memory
or performance qualification; two atlases and a capture are not that benchmark.

## Illustrated integration · 2026-09-06

The [integrated illustrated cycle](../evidence/illustrated-walk/integration/README.md)
documents the first screen-right cycle; the [four-direction release pass](../evidence/illustrated-walk/release/README.md) completes captain travel, including crew sharing that
appearance. Its generated raw source is retained unchanged. A deterministic
Godot import pass removes only light neutral background pixels connected to each
cell's boundary. Enclosed white armor and hair highlights remain intact. It then
applies one uniform scale and authored foot anchors, packs true RGBA frames,
and emits an editable SpriteFrames resource plus provenance hashes.

This is a controlled matte-removal recipe for this source, not general-purpose
segmentation. Different background colors or open pale silhouettes need adjusted
metadata and visual review. No light-colored pixels are globally deleted.

`art/characters/illustrated-captain.json` owns source cells, anchors, uniform scale,
clip order/duration and matte parameters. The CharacterDefinition binds the
SpriteFrames resource and per-clip layout/stride. This permits adding artwork or
clips without new actor branches. Runtime timing honors per-frame durations;
collision, movement, foley and all operational UI remain shared.

```sh
mise exec -- just characters-import
mise exec -- just check-characters
mise exec -- just world-characters  # isolated illustrated review room
mise exec -- just world             # illustrated cycle enabled in normal colony
```

The import/check command fails on logged Godot errors even when its process exits
zero. Checks cover source/manifest/importer/atlas/resource hashes, true alpha,
preserved enclosed whites, eight distinct frames, live playback, missing-direction
fallback, stop/reset layout, reduced motion, and actual wall collision without
continued animation or footsteps. Native captures include both colony and Command
interior, with light/dark background review. The current release pass implements all four captain directions. EVA, Mender and
Trainer retain their approved stills; this is not a fully animated roster or a
performance qualification.

## Directional rollout and packaging · 2026-09-06

A character can compose its base SpriteFrames with `additional_frames` libraries.
Each direction’s PNG, source crop, scale, foot anchor and timing remain metadata;
the actor contains no direction-specific or character-specific rendering branches.
`art/characters/illustrated.json` lists every illustrated import manifest, so
`just characters-import` rebuilds all registered sheets and validates the result.
Optional explicit `cells` handle source sheets whose row boundaries are uneven.

The new front/back/left sources have genuine alpha; no matte pixels were removed.
The importer uses the same alpha > 0.1 threshold for source bounds and frame margins;
sub-visible alpha noise cannot inflate the bounds. The actor discards alpha below
0.5. A failed eight-pose front draft remains in evidence: it repeated the leading
foot and was replaced with four explicitly alternating contact/passing keyframes.

`just check-world-export` creates a fresh local macOS release archive, runs that
executable outside the checkout with an explicit offline fixture, exercises all
four directions and reduced motion, loads the colony and all three authored
interiors through five entry points, then captures native colony walking and a
compact interior. It rejects logged errors, missing completion/captures, source
changes during the run and nonempty output directories. SHA-256 provenance binds
the archive, executable, PCK, inputs and captured evidence. This is an unsigned
private macOS candidate; Linux/backend deployment has separate gates.
