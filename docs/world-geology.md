# Aster geology and colony paths

Status: accepted

Date: 2026-09-05. Scope: local environment art and walking-corridor presentation.

## Implemented

Cliffs now combine a continuous shelf face with irregular cap blocks, staggered
buttresses and recessed lower formations. The rear escarpment has a broken profile
and overlapping masses instead of a smooth striped wall. The original shelf
outline still owns the top, physical boundary and navigation clearance. Added
foreground rock masses remain below the walkable rim; rear masses remain beyond
the northern boundary. No new climb, fall or elevation traversal is implied.

An original generated [sandstone texture](../apps/world/art/geology/sandstone-v1.png)
supplies chipped edges, fractures and mineral grain. World-scale triplanar
sampling avoids stretching paint across vertical faces. Mipmaps and anisotropic
filtering support map-scale views; mirrored coordinates hide source-edge mismatch
without claiming that the generated image is a seamless production tile. Full
[prompt and provenance](../apps/world/art/geology/provenance.json) are retained.
The built-in image-generation tool produced the asset; reference images were not
copied into the project. This is color artwork, not an authored normal map.

Ground shading now separates quiet sand from localized erosion, smaller dry
fractures and exposed rock patches. Ripple contrast and regular striping are
reduced. A feathered caprock band joins soil to the cliff; lower canyon colors
suggest a distant channel and static mist. Neither mist nor material variation
represents live weather or operational conditions.

`colony_paths.gd` owns ten authored curved corridors connecting the plaza,
landing pad, utility/solar district, survey area, habitat, botanical module,
reserved sites and overlook. Compacted centers, subtle wear tracks, feathered
shoulders/endpoints and flush edge markers replace the disconnected straight
strips. Paths meet the landing pad at its edges instead of crossing its deck.
Groundcover and low debris avoid the corridors. Path edges are decorative,
traversable surfaces; click navigation still chooses collision-safe routes and
does not require staying on a trail. No path controls agent work or permissions.

## Surface scatter

Twelve small outcrop clusters and nine shallow impact scars now break up the
open ground. Outcrops combine differently sized rocks and loose chips using the
existing sandstone material. Craters have irregular low rims, softened soil
shading and scattered ejecta; they remain walkable surface details rather than
holes cut into the shelf. Their appearance has no operational meaning.

`surface_layout.gd` owns the authored positions and rock footprints. Physics and
click navigation share those footprints, while a fixed local seed keeps the
smaller fragments stable. Clearance checks protect paths, entrances, landmarks,
reserved sites and the cliff edge. The scatter test also exercises actual
operator contact, route recovery and walking across a crater.

See the [scatter overview](../evidence/world-scatter/overview.png),
[walking view](../evidence/world-scatter/walking.png) and
[validation record](../evidence/world-scatter/validation.json). The first placement
check caught a crater overlapping a route; it was moved outward. Native visual
review corrected crater face winding and softened overly dark basin shading.
This is a reusable authored scatter layer, not procedural planet generation.

## Cliff relief and mineral water

The next material pass varies the cliff joint spacing, block widths, shear and
stepped ledges. Rock shading now combines triplanar paint with subtle derived
surface relief, dust on upward faces, darker weathering and roughness variation.
The relief is inferred from artwork; it is not an authored or measured height map.
This uses Godot's [spatial shader material and normal outputs](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html).

The spring now has an irregular mesh shoreline inside its existing blocked
footprint. Mineral banks, shallow-water caustics, fine ripples and softer surface
highlights replace the smooth disk. Water movement is decorative: reduced motion
freezes its clock, and entering an interior pauses the hidden exterior animation.
The canyon water now has layered animated swells, broken ripple highlights,
fine surface grain and gentle foam around the four sea stacks. Shared stack
positions keep the decorative waterline rings aligned with the scenery. Its
clock also freezes in reduced-motion mode and pauses inside buildings. Static
patches of mist remain over the surface. No depth-buffer refraction, simulated fluid, weather or water interaction is
implemented; this remains compatible with the current Compatibility renderer.

[Overview](../evidence/world-materials/overview.png),
[player-scale spring view](../evidence/world-materials/spring.png) and
[validation](../evidence/world-materials/validation.json) retain the native review.
The environment test covers motion freeze/resume for spring and canyon water,
hidden-room behavior and shore bounds. The canyon pass retains its own
[overview](../evidence/world-canyon-water/overview.png),
[cliff-edge walk](../evidence/world-canyon-water/overlook.png) and
[validation](../evidence/world-canyon-water/validation.json). Existing edge, route, interaction and truthful-state checks remain required.

The remaining professional-art gate is a small authored cliff kit with distinct
corners, overhangs and rubble aprons, then a lighting/composition pass on the spring
and overlook at player scale. Owner: Al with implementation assistance. Completion
requires reviewed close and overview captures, preserved navigation and measured
frame cost before rolling the kit across the colony. Repeated module silhouettes,
flat terrain transitions and inconsistent building detail remain visible limitations;
additional shader complexity alone will not solve them.

## Connected coastal setting

The rear wall now joins a continuous mainland coast and rolling inland plateau.
`coastal_backdrop.gd` owns the authored headland outline and builds terrain beyond
the colony camera envelope. The high ground uses the colony soil material, and
lower coastal benches meet the water. The old finite wall and separate northern
mesa row are removed. Wider cliff bases and low talus formations give the colony
promontory a continuous foundation instead of an isolated slab silhouette.

The connected-coast pass preserved the then-current `Geography.OUTLINE`,
physical perimeter and navigation grid; the natural-outline pass below reshapes
that boundary while preserving the same ownership and confinement rules. Surrounding mainland, slopes, talus and
water are scenery without collision or routes. Steep grade changes mark the edge;
no new gate, mission area, climbing or off-shelf travel is implied. This visual
boundary grants no operational authority and changes no backend controls.

[Coast overview](../evidence/world-coast/overview.png),
[walking view](../evidence/world-coast/walking.png) and
[validation](../evidence/world-coast/validation.json) retain the review. The new
coast check rejects decorative mainland destinations, verifies no extra static
bodies or above-ground mesh vertices inside the playable shelf, and tests physical
contact and return routing at the north and both rear-side boundaries.

This establishes a connected setting, not a seamless explorable planet. The first
render was too dominated by a tall rear wall; lowering the escarpment and adding
rolling soil above it improved the composition. Cliff motifs and the flat colony
floor remain stylized. The authored cliff-kit and lighting gate above still owns
further polish. The subsequent outline change below includes navigation
coverage and physical contact/return checks for the reshaped boundary. No deployment or operational scope changes are involved.

## Natural plateau outline

The later silhouette pass replaces the long straight north/west/east edges with
an authored rounded western shoulder, eastern neck, southern headland and shallow
coves. A single corner-softening pass is baked into `Geography.OUTLINE`; it is
stable geometry, not runtime random generation. Buildings, existing paths, plots
and scattered landmarks keep their positions. The playable boundary now follows
this new shape, with some headlands extending beyond the old rectangle.

The cap, cliff faces, perimeter colliders and route clearance all consume that
outline. Navigation derives its grid extent from the polygon instead of the old
hard-coded rectangle. The mainland reads the same northern arc, avoiding a
straight wall or a gap behind the curved shelf. No operational authority changes.

[Before](../evidence/world-organic-shelf/before.png),
[overview](../evidence/world-organic-shelf/overview.png),
[walking view](../evidence/world-organic-shelf/walking.png) and
[validation](../evidence/world-organic-shelf/validation.json) retain the change.
The initial shape test reproduced the long straight edges, uneroded square corner
and missing route coverage for new headlands. Shape and existing route/scatter
checks pass after the change. Seven physical boundary contacts, including the new
curved edges, verify movement stops and safe return routes. The previously
hard-coded eastern boundary probe now starts inside the new contour and checks
polygon clearance rather than the old x coordinate.

The colony floor remains flat; elevation traversal and free mainland exploration
are still outside this implementation. Further cliff-kit and lighting polish
remain under the existing art gate.

## Continuous upland transition

The inland surface now starts at the exact northern plateau vertices and the same
-0.035 elevation. The old offset seam, rear caprock overlay and duplicate cliff
strip are removed from this connection. The short vertical western segment stays
an exposed coast edge, preventing the inland mesh from folding back into the
colony. The actual playable outline and its collision boundary do not change.

The mainland uses denser, smoothly shaded terrain with defined ridges and gullies.
Its soil starts with the same world-space material as the colony; exposed rock and
erosion shading blend in as elevation and slope increase. Seven buried outcrop
groups, small loose stones and sparse golden fronds add scale and distinct forms.
Surrounding terrain remains decorative and cannot be entered through navigation.

[Overview](../evidence/world-uplands/overview.png),
[survey-district view](../evidence/world-uplands/survey.png) and
[validation](../evidence/world-uplands/validation.json) retain this pass. The new
seam test first failed on the offset geometry and now verifies every northern
join vertex. Existing confinement checks caught a folded western strip invading
the shelf; the retained failure preceded its correction. Native review also
caught reversed terrain faces; correcting their winding restored the lighting.

This remains a stylized height-field backdrop, not erosion simulation or expanded
traversal. Detailed authored rock variants, less repetitive prop arrangements and
a broader lighting/atmosphere pass remain the next art-quality gate. Owner: Al
with implementation assistance; acceptance continues to require player-scale
and overview review with navigation and frame-cost evidence.

## Evidence and checks

- [Before, overview](../evidence/world-geology/before.png).
- [After, overview](../evidence/world-geology/overview-final.png).
- [Normal walking view](../evidence/world-geology/walking-final.png).
- [Actual walk to the overlook](../evidence/world-geology/overlook.png).
- [Compact stale fixture](../evidence/world-geology/stale-compact.png).
- [Validation and measurements](../evidence/world-geology/validation.json).

The new path check samples every baked curve, rejecting any centerline outside
the shelf or inside an inflated obstacle footprint and requiring a reachable
endpoint. Existing physical cliff contact, colony routes, room journeys, stale
state and native command checks run through `just check-world`. Native capture
confirms that the operator physically reached the overlook. The first import
exposed an untyped path vertex; its failure is retained in `import-first.log`.

Visual review reduced overly bright rock faces and repeated column silhouettes,
softened high-contrast ground fractures, corrected a trail crossing the landing
pad and cleared vegetation from the paths. The final surface remains a stylized
procedural composition with generated painted detail, not fully hand-authored
reference-level terrain. Large forms and lighting still deserve further review.
Frame samples are short, capped process intervals on Apple M5 / Godot 4.7.2
Compatibility; they establish neither an uncapped performance improvement nor
support for another platform. No backend, dependency, deployment or persistence
change is needed. Owner: Al with implementation assistance; next art gate is
in-game review of the revised terrain at intended zoom before expanding biomes.
