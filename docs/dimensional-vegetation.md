# Dimensional vegetation

Status: proposed

Implemented locally and technically reviewed; owner art acceptance and final
export integration remain separate.

The exterior grass, Commons planting and authored Botanical leaves now use closed,
curved geometry with twisted midribs, cupped edges and real undersides. These are
decorative assets; no crew capability, work status, collision or authority changes.
Existing walking routes, planter footprints, scatter positions and RNG consumption
are retained. Grass roots extend 1 cm below the actual soil plane at Y=-0.035.

Production sources use pinned Blender 5.2.1 LTS and the shared
`assets-production/scripts/dimensional_foliage.py`. Editable Blender files and
source/export hashes are retained in each asset's provenance. No paid generation
calls were made, and original generated equipment inputs and ledgers are unchanged.

| Surface | Geometry and runtime budget |
|---|---|
| Exterior | Four variants: 672, 840, 756, 588 triangles; ceiling 1,000 each; 110 placements in four opaque MultiMesh batches |
| Commons | 135,628 whole-assembly triangles, ceiling 150,000; unchanged 25 mesh/material batches; previous version 35,564 triangles |
| Botanical | 88,924 selected authored triangles; same architecture and generated equipment composition |

Commons retains its existing PBR foliage shader and reduced-motion behavior. The
exterior shared-mesh adapter explicitly enables imported vertex-color albedo;
otherwise extraction from the GLB can render the groundcover white. The focused
regression catches that issue and verifies manifold geometry, opaque materials,
orientation, bounded meshes, deterministic scatter and nonblocking groundcover.
Native execution also reads back every MultiMesh root transform. Headless Godot's
dummy renderer returns identity transforms, so only that hardware readback assertion
runs natively; all other checks run in both modes.

## Native evidence and measurements

[Retained evidence](../evidence/world/dimensional-foliage-20260928/) includes source
hashes, final normal/close/reverse images, all earlier failed captures and logs, and
original recipes/exports. `after-final` contains corrected production geometry.
`baseline-final` uses the preserved legacy exterior grass script with the exact
same cameras, current lighting and current interior assets. Earlier `baseline-clean`
retains the prior Commons geometry; it is a historical image, not a matched
performance baseline. The initial Botanical images showed only the exterior and
are retained as failed evidence; final captures explicitly enable its interior
presentation and suppress the generated hull for inspection.

The capture hides characters and Commons overhead slats in both variants so leaf
shape is inspectable. These are native asset-inspection views, not proof of a
physical player journey or exported-artifact qualification. Final Botanical close
shows the authored leaves in front of the existing generated hydroponic rack.

Measured on Godot 4.7.2 Compatibility / Apple M5 at 1280×800, capped at 60 FPS:

| Exterior view | Draw calls old → new | Rendered primitives old → new | Capture-loop median ms old → new |
|---|---|---|---|
| Normal | 142 → 118 | 25,841 → 29,249 | 16.725 → 16.688 |
| Close | 110 → 92 | 30,620 → 36,202 | 16.738 → 16.808 |
| Reverse | 114 → 97 | 31,282 → 36,869 | 16.721 → 16.684 |

The raw per-view p95/sample counts and comparison are retained in JSON. These
short static capped capture intervals are **not an FPS improvement benchmark**.
Batching reduces visible draws while adding geometry and widening culling groups.
No performance improvement is claimed.

Passed focused checks: `test_dimensional_foliage.gd` both native and headless,
`test_living_foliage.gd`, `test_living_colony.gd`; scoped Ruff lint/format and ty on
all four generator files. The geometry test is wired into `scripts/check_world.py`.
The parent integration owns full world/repository and fresh export checks.

Remaining art limitations: generated hydroponic-rack foliage is still its existing
textured source, and Botanical exterior glazing remains opaque textured greenery.
Those were not silently replaced. Final shadow-contact tuning is tracked separately
by the shadow pass. Owner aesthetic approval remains separate from technical checks.
