# Blender preparation by asset type

Verify the installed/pinned Blender version before running automation. Prefer
the MCP for supported scene inspection and a separate background Blender process
for reproducible builds. Do not overwrite the user's open `.blend` file.

## Geometry and materials

Inspect evaluated transforms and world-space bounds after updating the view
layer. Imported rig control shapes can appear as mesh objects: include the
intended skinned meshes rather than every object of type MESH in bounds/export.
Normalize scale, forward direction and floor anchor once; retain source scale
and the applied transform in provenance. Confirm orientation visually instead
of assuming the longest axis is always the intended upright axis.

Preserve UVs and PBR channels through preparation and Godot overrides. Inspect
albedo, normal, roughness/metallic packing and emission in the target renderer.
Keep high-resolution originals; select runtime texture resolution and topology
from the on-screen use and measured budget. Our 2K character / larger prop maps
are examples, not universal quality requirements. Check exported texture sizes
and GLB contents, not just the source image settings.

For architecture, separate the hull, traversable floor, collision shell, sliding
doors, cutaway surfaces and interior dressing. Validate any removed hull faces
around the entrance visually. Build real interior space and collision; a hollow
looking generated exterior does not establish a walkable room. Avoid baking
lighting into textures when it should respond to game lights.

## Rig and animation

Inspect joint heads, tails, bind transforms, active actions and action slots.
The earlier importer produced display tails far beyond joint spacing; fix
lengths only if that defect is reproduced. Preserve bind orientation and joint
locations. Do not apply a blanket scale correction to every rig.

For a stretching face/helmet, first locate the actual neck and weight influences.
Use a model-specific rigid region with a flexible collar transition, excluding
shoulder/body geometry. Do not copy Vanguard's height threshold onto another
character. Compare poses before and after; a newly generated rig is not proof
that the original deformation defect is gone.

Bake constraint-driven motion into parent-relative bone transforms. Export
explicitly named clips and verify them in Godot. A scene that looks right with
live IK can export incorrectly when baking loses the hierarchy or action slot.
Match the engine/export skin-influence limit in the editable source before
measuring it; inspect exporter warnings rather than accepting silent pruning.

[Preparation script](../../../../assets-production/scripts/prepare_character.py)
and [helmet audit](../../../../assets-production/scripts/audit_character.py) are
concrete examples. The audit measures fully rigid vertices in head space over
multiple poses; deliberately blended neck vertices need separate evaluation.
Its threshold and sampled region must remain explicit. A passing rigid-region
audit does not establish good feet, hands, collar motion or all-frame quality.

Inspect idle, walk, run, turning, stopping and any task gesture at close range in
native Godot. Watch root drift, floor contact, clipping, foot sliding and loop
seams. Use displacement-driven locomotion and different walk/run stride lengths
where appropriate, not a faster walk playback for every travel speed.
