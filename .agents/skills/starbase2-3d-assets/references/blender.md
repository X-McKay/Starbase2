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

Read glTF defaults when a field is absent: omitted `metallicFactor` means 1, not
0. Inspect emission texture bindings and factors separately from albedo. In the
Shift Change characters, omitted metallic values and full-strength albedo-like
emission produced misleading material response. A renderer override can correct
those parameters while leaving baked texture contrast intact; inspect the texture
and native lighting before declaring the appearance fixed.

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
When assigning a complete pose in a batch, derive each desired local transform
from the desired parent transform, then express it relative to the bone's local
rest transform in `matrix_basis`. Do not compute a child from a stale evaluated
parent matrix while updating the same hierarchy: the Shift Change bake accumulated
incorrect child transforms this way. Update/evaluate the completed pose before
sampling its deformation, and inspect the exported result rather than only the
editable rig. This is a fix for that reproduced batch-assignment failure, not a
reason to rewrite every animation pipeline.
Match the engine/export skin-influence limit in the editable source before
measuring it; inspect exporter warnings rather than accepting silent pruning.

[Preparation script](../../../../assets-production/scripts/prepare_character.py)
and [helmet audit](../../../../assets-production/scripts/audit_character.py) are
concrete examples. The audit measures fully rigid vertices in head space over
multiple poses; deliberately blended neck vertices need separate evaluation.
Its threshold and sampled region must remain explicit. A passing rigid-region
audit does not establish good feet, hands, collar motion or all-frame quality.

For seats, inspect the actual deformed thigh/hip skin and soles against the seat
and floor from front and side views. Bone centers can clear the bench while the
weighted skin penetrates it, as the Sentinel seating check demonstrated. Keep
model scale, floor offset, seat geometry and contact measurements in the evidence;
do not reuse one rig's pelvis height as a universal seating constant. A proposed
bone-position correction remains unqualified until native skin-contact views pass.

Inspect idle, walk, run, turning, stopping and any task gesture at close range in
native Godot. Watch root drift, floor contact, clipping, foot sliding and loop
seams. Use displacement-driven locomotion and different walk/run stride lengths
where appropriate, not a faster walk playback for every travel speed.
