# Aster frontier art

The [geology texture](geology/sandstone-v1.png) now supplies cliffs, rocks and
exposed ground detail; [provenance and the full generation prompt](geology/provenance.json)
are retained. See [geology rollout evidence](../../../docs/world-geology.md).
It is sampled as opaque RGB with mipmaps and mirrored world coordinates; physical
terrain still comes from geometry, not image detail.

The separate [Aster material kit](kits/aster-v1/manifest.json) supplies the native
`just world-kit` showroom. It uses generated PNG surface art on reusable geometry;
it also supplies the [playable colony rollout](../../../docs/world-rollout.md). See the
[production workflow and acceptance gates](../../../docs/art-production.md).
Source alpha is ignored by its opaque RGB shader; do not reuse this sheet as
transparent sprites. Prompt/provenance are retained alongside the atlas.

The current crew uses generated raster atlases, with prompts and provenance in
[crew-provenance.json](crew-provenance.json). The built-in image-generation tool
was used. `crew_art.gd` selects four facings per character; it handles actual image dimensions and clips empty side margins in memory.
`just check-world` validates atlas alpha, bounds and opaque-pixel clipping.
Walking candidates failed alpha or identity/direction review and are retained only
in evidence. Runtime travel uses procedural motion, not authored foot-stride frames.

The earlier editable SVGs were authored for Starbase2. No artwork was extracted from the
user's reference images or the predecessor games. The references informed visual
principles: readable silhouettes, layered environments, consistent texture scale,
and restrained background contrast.

- Legacy SVG character sheets (no longer used by the runtime) are 128×96: four 32×48 facings (front, back, left, right), with
  idle and step rows. The palette identifies operator, Mender, Surveyor and Trainer.
- Deck, ceramic wall and solar textures are 64×64; the garden tile is 32×32.
- Plants and trees are billboard silhouettes. Godot renders them with nearest
  texture filtering and real directional shadows.
- `art.gd`, `station.gd`, `landscape.gd`, `terrain.gdshader`, and `space.gdshader` contain original
  reusable geometry and background rendering. Text uses Godot's bundled font.

SVGs are source assets, not opaque generated raster exports. Keep hard pixel
boundaries, coherent palettes and matching character proportions when editing.

The planetary colony uses original mesh trails, faceted rocks and a terrain shader;
vegetation is now low mesh groundcover. The older tree/plant SVGs remain legacy
assets. Shuttle, habitat and reserved sites are decorative, not resource telemetry.

The current [red mineral basin](../../../docs/world-surface.md) uses original
`terrain.gdshader`, `strata.gdshader`, and `mineral_pool.gdshader` materials.
Terrain cracks and dunes are shading on a flat walkable surface; cliff ledges
are geometry, and water/stone footprints are shared with navigation. Reference
images informed color and composition; no purchased or watermarked assets ship.

The [cliff shelf](../../../docs/world-cliff.md) uses `geography.gd` for the
shared rim and `cliff_landform.gd` for the cap, exposed face and rear wall.
`canyon.gdshader` is static lower-canyon scenery; no falling or climbing is implied.

## Current 3D production · September 7, 2026

The earlier crew description above records the raster phase. The player now uses
`cybercat-vanguard`, Mender uses `engineering-polish`, and the remaining crew use
`meshy`. Illustrations still support portraits and fallbacks. `colony-3d` supplies
the authored colony; `engineering-polish` supplies the selected Engineering art.
Use the [source index](../../../art/README.md) and
[content convention](../../../docs/content-organization.md) to navigate or retire
assets. Keep Godot import sidecars with selected runtime files.
