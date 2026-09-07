# World, interior and asset quality pass

Status: accepted

Date: 2026-09-07. Scope: the Godot client's lighting, exterior set dressing,
interior dressing and surface detail. No backend, contract, navigation-contract
or authority change. Every addition is decorative; operational state still comes
only from retained records.

## Why

The colony had a strong illustrated exterior but a flat, single-light look, and
its three interiors were bare blue boxes: one directional light, no ceiling
detail, no wall detail and two props each
([before](../evidence/world-quality/before-repair.png)). The overview read as a
diagram rather than a place.

## Implemented

**Lighting and atmosphere** (`world.gd`). A lower, warmer late-afternoon key
light with orthogonal soft shadows; sky-tinted ambient; ACES tonemapping with a
light contrast and saturation lift; and a very thin warm depth haze toward the
coast. Interiors switch to a cooler, dimmer ambient with the haze off so their
own lamps carry the room. Glow was probed and rejected: under the Compatibility
renderer it recoloured the interior backdrop, so "light" comes from emissive
surfaces and real omni lights instead.

**Interior dressing** ([`room_dressing.gd`](../apps/world/room_dressing.gd)).
Applied to every authored room under its content node before navigation blocks
are derived, so any physical prop it adds is also a routing block:

- Floor: a seeded set of worn tiles and hazard tiles from the existing kit atlas,
  and a painted guide line from the door to the console.
- Walls: a dark skirting, a contact-shade gradient where floor meets wall, twin
  service pipes with valve boxes, a large decorative status screen between the
  flanking consoles, a wall locker, a side-wall cabinet with an accent lamp and
  a hanging cable pair.
- Ceiling: a perimeter frame with two cross beams, four hanging light fixtures
  with warm omni lights, and one accent omni light in the room's colour (orange
  for engineering, cyan for command, violet for the trial hall).
- Props by room: crate stacks and drums in the hangar, a data pillar and locker
  in command, floor rings under the trial apparatus and a supply crate in the
  hall. Props carry `BoxShape3D` colliders, which the room host already requires.
- Slow drifting dust motes, stopped under reduced motion.

**Exterior dressing** (`landscape.gd`). A cargo yard beside the hangar with
containers, drums, pallets and a work light; a parked survey rover on the
landing apron; a utility conduit with junction boxes and a lit cabinet along the
solar field; strapped pallets at freight staging; and wind-laid dust drifting
across the basin, stopped under reduced motion. The yard and rover footprints
are declared in [`surface_layout.gd`](../apps/world/surface_layout.gd) and join
the shared navigation block list, so click routing and physics agree.

**Surfaces.** Roughly one pad tile in five uses the kit's worn floor variant
(`colony_paving.gd`, stable per-cell hash). The terrain shader gains fine pebble
speckle and wind streaks in the sandy expanses. The sky gains a second layer of
larger soft stars and a faint galactic band.

## State ownership

Nothing in this pass reads the snapshot. Lamps, screens, rings, dust and props
are constant scenery. Room activity labels, crew labels and every panel keep
their existing projections. Reduced motion stops both dust systems and is
plumbed through the room host and `apply_settings`.

## Verification

- `just check-world` passes in full. The paving test was updated for the new
  worn-tile mesh (five batched meshes, worn tiles a minority). Path, navigation,
  room, environment, interaction and building checks are unchanged and pass with
  the new physical props in the block list.
- Actual renders under a virtual display in
  [evidence/world-quality](../evidence/world-quality/README.md): before and after
  for the walking view, colony overview and all three interiors, plus the landing
  apron and a reduced-motion interior.
- Draw calls in the capture metadata: walking view 655 to 740, hangar interior
  337 to 446, colony overview 1364 to 1424. Each interior adds five omni lights.
  The software-rendered frame intervals in the same files rose in the walking
  view and are not a performance measurement; a measurement on the reference
  hardware named in [experience](experience.md) remains the performance gate.

Preserved failures from this pass: the first dust motes rendered at unit size
(mesh size, not particle scale, drives the quad under this renderer); the first
fog density washed out the overview and was cut by more than half; filmic
tonemapping flattened the cliffs and was replaced by ACES; and the first
interior dressing failed to parse on an untyped loop variable.

## Limits and next gate

All new geometry is procedural boxes, cylinders and kit panels: no new painted
assets, textures or character work were produced, and the interiors still share
one room shell. The next art gate is an in-game review at intended zoom, then
authored props (a real holo table, tool walls, a hangar door) and per-room floor
plans to replace the shared shell. Owner: Al reviewing art direction.
