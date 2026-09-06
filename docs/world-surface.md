# Aster surface: red mineral basin

Status: accepted

Date: 2026-09-05. Scope: native environment art, terrain materials and landmark collision.

The subsequent [cliff-shelf pass](world-cliff.md) replaces the enclosing rock
barriers and infinite ground plane while retaining these surface materials.

## Art direction and implemented behavior

The owner's new references favor red planetary terrain, readable angular cliffs,
dry cracked ground, and cool accents against warm soil. The previous muted
brown/green noise and pebble-like perimeter did not establish that identity.
This pass implements original materials and meshes directly in Godot:

- Iron-red clay with irregular dry seams, fine mineral grain, and wind-rippled
  sand patches. Compacted trails share the ground material with a different wear
  parameter, instead of appearing as flat strips laid on top of the world.
- Fractured, flat-topped rock ledges with horizontal strata, darker purple distant
  formations and warmer exposed caps. Distance-aware smoothing reduces aliasing
  of rock seams in the colony overview.
- Grouped golden fronds and low eroded debris, replacing scattered green pebbles.
  Groundcover stays short and still, and respects blocked landmark footprints.
- A turquoise mineral pool with a pale shore and two weathered standing stones.
  These are original decorative landmarks, with conservative shared physical and
  navigation footprints. Walking through water or stones is blocked; routes to
  all existing districts and around both new landmarks remain available.
- Subtle text shadows improve HUD legibility over the richer, brighter surface.

The supplied images were used as references, not copied into runtime assets.
No watermarked tile sheet was extracted, no asset purchase was made, and no
new image generation was needed. The shaders and meshes are editable project
source. Existing crew artwork and its provenance remain unchanged.

For Destiny context, Bungie's [Prophecy development account](https://www.bungie.net/7/en/News/article/49301)
describes art-driven experimentation, bold visual ideas, and iteration toward
cohesive spaces. Our interpretation here is strong warm/cool contrast and a
weathered landmark that makes the new settlement feel younger than its landscape.
This is a visual reference, not a claim to implement Destiny's environments,
combat, light/shadow mechanics or narrative systems.

## Validation and retained evidence

The [previous gameplay capture](../evidence/world-surface/before.png) records the
unmet art requirement. Actual native captures show the implemented result:

- [Full red-planet basin](../evidence/world-surface/overview-final.png).
- [Normal gameplay](../evidence/world-surface/gameplay-final.png).
- [Physical walk to the mineral-pool district](../evidence/world-surface/survey-walk.png).
- [Compact stale fixture with larger text and reduced motion](../evidence/world-surface/stale-compact.png).

`just check-world` checks authoritative states, all existing crew/district routes,
new landmark avoidance, physical pool and stone collision, reduced-motion room
changes, UI interaction and native command failure/reconciliation. The native
surface walk uses the existing route follower and physics loop; its capture
reports whether the target was reached. The visual fixture remains explicitly
labeled and cannot dispatch work.

A GDScript inferred-type error was corrected before final renders. The first
render exposed excessive fine striping on cliff caps and aliasing on distant
seams; the shader now reserves bedding seams for side faces and filters their
width. Both `just check-world` and `just check` passed: 27 Rust tests, 16 Python
tests, lint/contracts and 32 Markdown documents. The final native survey walk
reached its target, with 16.67 ms median and p95 engine frame intervals at the
60 FPS cap over 870 post-warmup frames. Failed checks and intermediate renders remain in `evidence/world-surface`.

[Validation details](../evidence/world-surface/validation.json) retain exact checks,
frame samples and platform. Samples are short native 60-FPS-capped observations
on macOS Apple M5 / Godot 4.7.2 Compatibility, not proof of faster rendering or
other-platform qualification. No operational agent work or model inference was
dispatched; live captures display existing local core records.

## Boundaries and remaining work

The traversable basin is still finite and flat. Cracks and dunes are surface
shading; distant cliffs have visual elevation. Pool shading and vegetation are
static, so reduced motion does not require an animation bypass. There is no
swimming, climbing, dynamic weather, mining, resource economy, construction,
portal behavior or new permissions. No backend schema, service or deployment
changed. Recovery is reverting presentation files; no data rollback is required.

Owner: Starbase2 development. Further environment refinement should reduce the
regularity of the overall basin silhouette, add authored points of interest,
and qualify terrain traversal before introducing slopes or cliffs within the
walkable area. Preserve route/physical agreement and non-spatial access. Existing
animation, audio, interiors and platform gates remain in
[the playable-world record](world-playable.md).
