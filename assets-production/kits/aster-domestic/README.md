# Shift Change environment

Art direction uses `../../batches/shift-change/concepts/art-target-v1.png`. The concept is a target, not a
capture of the implemented scene. Habitat retains its existing generated Meshy
sofa, galley and sleep capsules; the sofa moves into the central lounge with its
physical/navigation bounds. Existing furnishings, walls and structure positions
remain. This stage makes no paid generation calls.

Rebuild new dressing in a separate Blender5.2.1 background process:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --python assets-production/kits/aster-domestic/scripts/build_lounge.py
```

`blender/` retains editable source files; `provenance.json` records version,
output sizes and hashes. Runtime assets are `habitat-lounge.glb` and
`commons-details.glb` under `apps/world/assets/kits/aster-domestic/`.
They contain warm timber/rug layers, textile cushions, domestic pendant shades,
herbs, mugs/journals, cabin trim, pathway inlays and three functional seats.
The existing Meshy sofa remains an art focal point; it is not falsely treated as
a qualified animation seat.

`apps/world/shift_change_anchors.gd` collects named scene markers into global
floor positions, facing targets, pose and zone. Habitat supplies four anchors;
Commons supplies three. Three seats match the animation author's contract:
seat top0.48m, contact0.55m behind a floor-root facing+Z, seat depth0.4m. Their
front edges remain0.35m behind the root, preserving character collision.
Seat colliders and navigation definitions are changed together. Actor motion,
reservation and animation are owned by the world integration, not this art.

All dressing is decorative. Mugs, journals and plants assert no operational
activity or resource telemetry. Existing authoritative labels and HUD remain
independent. Occupied-seat appearance, blended transitions and integrated native
journeys require the animation/motion integration checks, in addition to the
asset import and focused physical-room checks.

A startup crash under the restrictive Blender sandbox is retained in
`.local/shift-change-art-build.log`; the isolated background process succeeds
outside that restriction. Initial floor dressing was beneath the existing deck;
inspection of the native capture prompted a geometry-height correction. Review
actual native composition rather than accepting successful GLB export as visual
approval. Al's art acceptance remains separate from technical checks.

Commons seat and floor-root positions use the navigation grid's quarter-cell
offset after full directed-route checks reproduced an inflated-cell conflict.
Seat contact and physical clearance remain unchanged; navigation was not weakened.
