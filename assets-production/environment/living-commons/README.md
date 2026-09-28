# Sheltered garden commons

Version 3 is a garden destination at world origin `(-7, 0, 23)`, replacing the
vacant expansion-plot placeholder south of the road spur. Its exact footprint is
`Rect2(-12, 19.6, 10, 7.1)`. Two deep arched canopy bays shelter long raised beds
with 52 layered plants, irrigation and small water troughs. A central island
adds 16 specimens between broad walking aisles; a cushioned timber bench sits
at the rear. Lighting is decorative and static. No generation credits
were spent, and no operational status is represented.

`build_living_commons.py` runs in a separate background Blender 5.2.1 process.
The editable source retains individual parts; the 25-mesh runtime export has
135,628 triangles (150,000 ceiling). Closed, cupped and twisted leaves replace
open triangle fans; radial tiers avoid a flat stacked silhouette. The shared
`assets-production/scripts/dimensional_foliage.py` helper is bound in provenance.
The prior version 2 had 35,564 triangles. `provenance.json` records version and exact source/export/script hashes.
`review.png` is the inspected Blender studio render, not native qualification.

`living_commons.gd` instances the assembly and creates four physical boxes from
the same public `BLOCKS` rectangles used for navigation integration. The terrace
is visual and nearly flush, with no raised floor collider. Six canopy posts
sit within the planter collision footprints. Both north/south routes at world
X=-10 and X=-4 avoid the blocks with 0.4 m actor clearance; final physics qualification is
owned by world integration.

Pure geometry checks confirmed the entire footprint and all four furniture
rectangles avoid every authored road rectangle and Engineering's landing radius.
No existing building, road, navigation file or landing asset was changed by this
production script. The parent task integrates navigation blocks and performs
Godot import/native review.

The initial sandboxed Blender process exited 139 before script execution;
the separate unsandboxed background process completed. The first preview-only
render lacked a world datablock, so its setup was corrected and rendering then
completed. These were environment/preview failures, not successful asset builds.

The dimensional vegetation pass retains all 25 material batches, planter bounds,
collisions and existing reduced-motion foliage behavior. Native evidence and
limitations are recorded in [the vegetation review](../../../docs/dimensional-vegetation.md).
