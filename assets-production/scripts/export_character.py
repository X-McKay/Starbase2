"""Export the inspected Meshy source with Blender 5.2.1, outside the live session.

Open cybercat-repaired.blend in background Blender and pass this file with --python.
"""

from pathlib import Path

import bpy

# Background production saves selected sources without accumulating recovery copies.
bpy.context.preferences.filepaths.save_version = 0
from mathutils import Quaternion, Vector

assert bpy.app.version[:3] == (5, 2, 1), bpy.app.version_string
root = Path(__file__).resolve().parents[2]
rig = bpy.data.objects["Meshy_cybercat-sentinel-rigged_Armature"]
mesh = bpy.data.objects["char1"]
for obj in (rig, mesh):
    if obj.name not in bpy.context.scene.objects:
        bpy.context.scene.collection.objects.link(obj)
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
mesh.select_set(True)
bpy.context.view_layer.objects.active = rig
# A neutral stance comes from the mean of a complete symmetric gait, rather
# than freezing with one foot raised. The imported walk itself is preserved.
walk = rig.animation_data.action
walk.name = "walk"
samples = {bone.name: [] for bone in rig.pose.bones}
for index in range(16):
    frame = 0.8 + 24.8 * index / 16
    bpy.context.scene.frame_set(int(frame), subframe=frame % 1)
    for bone in rig.pose.bones:
        samples[bone.name].append(
            (bone.rotation_quaternion.copy(), bone.location.copy(), bone.scale.copy())
        )
idle = bpy.data.actions.new("idle")
rig.animation_data.action = idle
for bone in rig.pose.bones:
    values = samples[bone.name]
    reference = values[0][0]
    aligned = [q if q.dot(reference) >= 0 else -q for q, _, _ in values]
    bone.rotation_mode = "QUATERNION"
    bone.rotation_quaternion = Quaternion(
        [sum(q[i] for q in aligned) / len(aligned) for i in range(4)]
    ).normalized()
    bone.location = sum((v[1] for v in values), Vector()) / len(values)
    bone.scale = sum((v[2] for v in values), Vector()) / len(values)
    for frame in (0, 24):
        bone.keyframe_insert("rotation_quaternion", frame=frame)
        bone.keyframe_insert("location", frame=frame)
        bone.keyframe_insert("scale", frame=frame)
walk.use_fake_user = True
rig.animation_data.action = walk
output = root / "apps/world/assets/characters/cybercat-sentinel/cybercat.glb"
output.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(compress=True, filepath=str(root / "assets-production/characters/cybercat-sentinel/blender/cybercat.blend"))
bpy.ops.export_scene.gltf(
    filepath=str(output),
    export_format="GLB",
    use_selection=True,
    export_animations=True,
    export_anim_slide_to_zero=True,
)
print(f"EXPORTED {output}")
