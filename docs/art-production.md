# Modular art production

Status: proposed

Date: 2026-09-05. The native Aster kit pilot is implemented and approved for rollout.
The [playable rollout](world-rollout.md) now uses it across three buildings and
interiors. The production art standard below remains proposed.

## Fixed-camera building catalog · 2026-09-06

The [implemented building catalog](building-catalog.md) now accepts whole-building
transparent PNGs at the fixed gameplay camera, alongside native scene exteriors.
All five colony buildings use distinct original images; independent collision and doorway anchors
supply interaction. This supersedes the pilot recommendation below that confined
whole-building billboards to distant scenery. It does not establish arbitrary-angle
rendering, volumetric shadows or seamless interiors. Shared authored interior
scenes and image props avoid per-building rendering code.

## Original pilot recommendation

Use PNG artwork substantially more, with reusable Godot scenes as the unit of
composition. PNG is an image format, not a rendering technique. A sprite can
depict a whole building, a tile can cover a floor, and a texture can put painted
detail on a simple mesh. The references demonstrate consistent authored forms,
material detail, lighting and prop placement; changing file formats alone will
not deliver their quality.

| Approach | Benefit | Constraint for Starbase2 |
|---|---|---|
| Current mostly procedural geometry | Editable depth, collision and cameras | Repeated plain boxes make detailed environments expensive to author in code |
| 2D sprites and TileMapLayer | Strong pixel control and efficient tile painting | Would require reworking the existing 3D camera, terrain and navigation; promising if we later choose a fixed 2D view |
| Textured simple geometry plus sprites | Keeps current depth and movement; artwork supplies surface detail | Requires consistent UV density, restrained baked shading and camera-aware sprite placement |

The third approach is the reversible next step. Godot supports
[sprites in 3D](https://docs.godotengine.org/en/stable/classes/class_sprite3d.html)
and [2D tile atlases with collision/occlusion metadata](https://docs.godotengine.org/en/stable/tutorials/2d/using_tilesets.html).
Use sprites for crew, vegetation and selected fixed-view props; use real geometry
for buildings, cliff faces, door frames and roofs. A whole-building billboard can
work for distant scenery, but provides neither an explorable volume nor reliable
views from different directions. No renderer replacement, plugin or new service
is required for this pilot.

## Implemented pilot

Run `mise exec -- just world-kit`. This opens a separate native art showroom:

- `1` / `2`: workshop interior / field-lab exterior.
- `C`: alternate camera; `L`: daylight / cool work light; `R`: exterior roof cutaway.
- Every shortcut has a visible button. There is no ambient movement or audio.

The [manifest](../apps/world/art/kits/aster-v1/manifest.json) provides six named
UV regions in one original generated 1254×1254 PNG. One module scene supports
floor, wall, hull, console and roof configurations. Authored
[interior](../apps/world/scenes/kit/workshop_interior.tscn) and
[exterior](../apps/world/scenes/kit/workshop_exterior.tscn) scenes reuse those
modules, with a repeated floor assembled on a two-unit grid. Module changes
preview in the Godot editor. Materials are cached by surface ID; collision is
defined separately from artwork. A decorative module can disable collision.
This is ordinary scene composition, not a custom editor or universal asset system.

The atlas is sampled as opaque RGB, regardless of its source alpha. It is not a
transparent sprite sheet. Linear filtering and a two-source-pixel UV inset are
used without mipmaps. Mesh borders hide joins at the demonstrated distances;
there is no seamless-texture or arbitrary-zoom guarantee. The first nearest-filter
render showed distracting fine detail, motivating linear sampling. Production
exports need deliberate atlas gutters and appropriate mipmap testing.

This showroom makes no backend requests and starts no work. Characters are static
scale references, console graphics are decorative, the door is static and the
roof is manually toggled. The smaller exterior and larger interior are separate
composition studies, not spatially matching rooms. They are not connected to
colony traversal. The separate playable rollout reuses the kit with bounded
interior layouts and the existing authoritative state. No operational status is
encoded in the painted artwork.

## Production contract to establish with one finished room

Adopt one visual target before multiplying buildings: a frontier workshop with
an exterior, entrance, interior, crew interaction and surrounding terrain.

1. **Style sheet:** blue-gray steel, ivory hulls, restrained cyan electronics and
   amber utility accents against the red planet; clear silhouettes and quiet
   walkable space. Fix a shipping camera and test its alternate angles. The pilot
   uses orthographic projection at roughly 35 degrees downward and a two-unit
   grid; it does not establish a final pixel-art standard.
2. **Scale sheet:** keep floor-origin pivots, explicit footprints, door clearance
   and crew height together. Lock one texel density with crew visible before
   final export. The pilot stretches some square art onto rectangular surfaces;
   its prop density and baked shading are not production-consistent yet.
3. **Small kit:** plain/worn/hazard floors; straight/corner/end/door walls;
   roof edges/caps; windows; console, chair, storage, pipe and light families.
   Add a few distinctive large props instead of uniformly cluttering every tile.
   The pilot supplies five module kinds, not this complete catalog.
4. **Layer separation:** structure, detail, shadows, emissive masks, foreground
   occluders and interaction anchors have separate responsibilities. Keep static
   screen art decorative; display real work state through explicit overlays or
   controlled screen elements driven by the existing projection.

Godot supports normal and emission textures, but a height map does not provide
collision or replace silhouette geometry. Emissive appearance also does not by
itself illuminate neighboring geometry. See the
[material documentation](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html).
The pilot has no normal map or authored emissive mask; its console material adds
a small uniform emission term. Dedicated masks and local lighting are future art
work, not implemented features.

## Repeatable workflow

Create concepts and a style sheet, then finish the small kit in layered source
files. An artist can use a pixel editor, a painting tool or textured low-poly
models rendered to sprites; the export contract should not depend on one editor.
Retain editable source, palette, source dimensions, export settings, ownership
and license/provenance with each asset family. Image generation is useful for
concepts and material candidates, but does not reliably guarantee matching
views, tile seams or animation frames. This pilot is a candidate, not a substitute
for deliberate asset cleanup. A coherent licensed kit or commissioned kit is also
an option; no purchase or third-party asset ingestion was performed.

Export PNGs and a stable manifest; assemble scenes by instancing approved modules.
Use a named palette variant or prop arrangement for a second building before
adding another art family. Expand metadata only when needed: anchors, collision
footprints and foreground/roof groups belong in the scene; provenance and atlas
regions belong with the asset. Avoid a parallel catalog database or custom plugin.

Acceptance gates for the first production room:

- Inspect native 1280×800 and 960×600 captures with crew, all supported cameras,
  lighting states and the intended game zoom. Reject stretched motifs, noisy
  repetition, atlas bleed, illegible entrances and inconsistent pixel scale.
- Exercise walking in front of and behind props, physical door clearance,
  entering/exiting, camera transition and roof occlusion. A screenshot cannot
  verify these. Match the exterior footprint to the chosen interior treatment.
- Check atlas bounds/content and sprite alpha where alpha is actually required;
  check module edits do not duplicate nodes and art replacement preserves
  collision/interaction anchors. Retain the asset version and capture settings.
- Keep an explicitly decorative art gallery, plus a live integration scene that
  exercises unknown/stale/failed/pending state and non-spatial controls.
- Measure frame times at representative colony density and on a second target
  platform. One atlas does not automatically mean one draw call. Accept visual
  quality through review, not through a passing unit test.

Owner: Al with implementation assistance. The playable workshop, matching doorway
journey and authoritative console interaction now exist, together with command
and trial-room variants. This establishes reuse; review the three journeys in
game before expanding the kit. Reference-level polish and scalable production
throughput remain review goals, not consequences of passing the tests.

## Evidence

Actual native renders: [interior](../evidence/world-kit/interior.png),
[exterior](../evidence/world-kit/exterior.png), and
[alternate camera under cool light](../evidence/world-kit/interior-alternate.png).
[Validation record](../evidence/world-kit/validation.json) retains checks, short
frame samples and limitations. The atlas prompt and provenance are retained
[with the asset](../apps/world/art/kits/aster-v1/provenance.json).

The pilot establishes that shared PNG artwork and scene modules can render both
inside and outside in the current Godot architecture. It does not establish
reference-level art quality, production throughput, a performance improvement,
playable interiors, export behavior or a finished animation pipeline.

## Command journey review · 2026-09-06

The [Command District](command-district.md) adds a fixture-only native movie
recipe, shared footprint shadows/sills, reduced-motion-aware dust and optional
surface/door foley. Two proposed walk sheets were rejected before runtime import.
Transparent alpha, frame alignment and readable alternating strides are now
explicit acceptance gates for the next crew-art handoff. The current static atlas
remains the shipping reference; no successful walk-animation rollout is claimed.

## Consistent character production

The [character pipeline](character-production.md) now supplies shared resources,
PNG packing/validation, displacement-driven gait and a technical two-character
rigged experiment. The user rejected the new 3D-rendered visual direction in favor
of the existing illustrated crew. Those original assets remain the default.
Future production walk frames should preserve their illustrated 2.5D look and use
the exporter-neutral contract; Blender is optional, not the required art source.

The [first illustrated animation integration](character-production.md#illustrated-integration--2026-09-06)
now enables the captain's screen-right cycle. Source-specific matte cleanup,
registration and SpriteFrames imports preserve the illustrated style. Missing
directional clips use approved stills; no mirrored frames or 3D art are substituted.
