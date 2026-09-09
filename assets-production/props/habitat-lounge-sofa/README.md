# Habitat lounge sofa

One user-approved Meshy prop derived from the built-in ImageGen Habitat design
reference. The retained batch concept and exact prompt are in
`assets-production/batches/inhabited-polish/concepts`. Image task
`01a0834d-61b8-7786-94de-655043fcd54e` consumed 9 credits; selected mesh task
`01a08353-cb46-74a4-89e5-ce118982b894` consumed 30. Total 39 belongs to the new
1,000-credit allowance, excluding historical 507-credit production spending.

The original downloaded GLB is retained under
`meshy_output/20260908_191443_habitat-lounge-sofa_01a0834d/mesh.glb`.
`provenance.json` records original/source/runtime hashes, 13,406 triangles,
uniform normalization, evaluated bounds, materials and four 2048px textures.
The final object measures approximately 3.265 m wide, 1.35 m deep and 0.960 m
high. Upright orientation is preserved, without guessing an axis from bounds.

Editable packed source: `blender/habitat-lounge-sofa.blend`. Runtime:
`apps/world/assets/props/habitat-lounge-sofa/habitat-lounge-sofa.glb`.
Reprepare in a separate Blender 5.2.1 background process:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python assets-production/scripts/prepare_inhabited_props.py
```

Run from the repository root with retained inputs present. The preparation
does not generate, spend credits, or import Godot resources. The complete
offline integration recipe is `mise exec -- just world-inhabited-build`.

Blender emitted a shared-texture-sampler warning. Exported base-color, normal,
metallic/roughness and emission bindings remain present in the GLB inspection;
sampling equivalence is not established. Final native room review found the
green upholstered sofa facing inward toward its coffee table, with the rear
profile partly occluded by the east wall and no evident furniture intersection.
Standalone `20260908-final-01` qualified against all 553 frozen world files;
the exported Habitat image confirms the intended sofa orientation and materials.
Durable package evidence is under
`evidence/world/inhabited-polish/final/package-01/`. Owner art acceptance remains
open; the sidewall occlusion is retained as an explicit visual limitation.
The generation prompt requested this object, not a verified measured source;
the recorded prepared bounds are authoritative for placement.
