"""Assemble Meshy rig, walking/running/idle and a baked Blender console gesture."""

import argparse
import json
import math
import sys
from pathlib import Path

import bpy

# Background production saves selected sources without accumulating recovery copies.
bpy.context.preferences.filepaths.save_version = 0
from mathutils import Matrix, Vector

assert bpy.app.version[:3] == (5, 2, 1)
ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--asset", default="engineering-specialist")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])
vanguard = args.asset == "cybercat-vanguard"
art_dir = ROOT / ("assets-production/characters/cybercat-vanguard/blender" if vanguard else "assets-production/characters/engineering-specialist/blender")
world_dir = ROOT / (
    "apps/world/assets/characters/cybercat-vanguard" if vanguard else "apps/world/assets/characters/engineering-specialist"
)
evidence_dir = ROOT / ("evidence/cybercat-vanguard" if vanguard else "evidence/engineering-polish")
for directory in [art_dir, world_dir, evidence_dir]:
    directory.mkdir(parents=True, exist_ok=True)
asset_name = "vanguard" if vanguard else "engineer"
ledger = json.loads((ROOT / "meshy_output/engineering-polish-ledger.json").read_text())["stages"]
folder = Path(ledger[args.asset + "/rig"]["directory"])
assert ledger[args.asset + "/animation"]["status"] == "complete"
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(folder / "rigged-character.glb"))
rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
meshes = [
    o
    for o in bpy.context.scene.objects
    if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)
]
bpy.context.view_layer.update()
rig.animation_data_create()
for track in list(rig.animation_data.nla_tracks):
    rig.animation_data.nla_tracks.remove(track)
rig.animation_data.action = None
# Preserve the untouched rig export, then work in its actual metre scale.
bpy.ops.wm.save_as_mainfile(compress=True, filepath=str(art_dir / (asset_name + "-imported.blend")))
points = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
lo = Vector([min(v[i] for v in points) for i in range(3)])
hi = Vector([max(v[i] for v in points) for i in range(3)])
assert 1.5 < hi.z - lo.z < 2.2, f"Inspect unexpected rig scale: {hi - lo}"
# The importer creates display tails 100x longer than joint spacing on this rig.
# Correct lengths along the same axis so IK reaches the wrist joint, preserving
# bind matrices and animation rotations.
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
for b in rig.data.edit_bones:
    if b.children:
        distance = (b.children[0].head - b.head).length
        if distance > 0:
            b.length = distance
bpy.ops.object.mode_set(mode="OBJECT")
clips = {}
for name, file in [("walk", "walking.glb"), ("run", "running.glb"), ("idle", "idle.glb")]:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(folder / file))
    imported = [o for o in bpy.data.objects if o not in before]
    source = next(o for o in imported if o.type == "ARMATURE")
    action = source.animation_data.action
    if action is None:
        action = source.animation_data.nla_tracks[0].strips[0].action
    action = action.copy()
    action.name = name
    action.use_fake_user = True
    clips[name] = action
    for obj in imported:
        bpy.data.objects.remove(obj, do_unlink=True)


def activate(action):
    rig.animation_data.action = action
    if len(action.slots):
        rig.animation_data.action_slot = action.slots[0]


def bone(suffix):
    return next(b for b in rig.pose.bones if b.name.lower().split(":")[-1] == suffix.lower())


activate(clips["idle"])
start = clips["idle"].frame_range[0]
bpy.context.scene.frame_set(int(start))
bpy.context.view_layer.update()
# Firm helmet weights only where the original rig already identifies the head.
head = bone("Head")
rigid = 0
neck_height = (rig.matrix_world @ bone("neck").bone.head_local).z
for obj in meshes:
    group = obj.vertex_groups.get(head.name)
    if group is None:
        continue
    for vertex in obj.data.vertices:
        weight = next((g.weight for g in vertex.groups if g.group == group.index), 0)
        height = (obj.matrix_world @ vertex.co).z
        blend = 0.0
        if vanguard:
            blend = max(0.0, min(1.0, (height - (neck_height - 0.02)) / 0.075))
            blend = blend * blend * (3 - 2 * blend)
        elif height > lo.z + (hi.z - lo.z) * 0.83 and weight > 0.2:
            blend = 1.0
        if blend > 0:
            original = {g.group: g.weight for g in vertex.groups}
            for other in obj.vertex_groups:
                other.remove([vertex.index])
            for index, value in original.items():
                if value * (1 - blend) > 0.000001:
                    obj.vertex_groups[index].add([vertex.index], value * (1 - blend), "REPLACE")
            group.add([vertex.index], weight * (1 - blend) + blend, "REPLACE")
            if blend == 1:
                rigid += 1
# Match the four-influence game export in the editable source and audit.
for obj in meshes:
    for vertex in obj.data.vertices:
        if len(vertex.groups) <= 4:
            continue
        selected = sorted(
            ((g.group, g.weight) for g in vertex.groups), key=lambda pair: pair[1], reverse=True
        )[:4]
        total = sum(weight for _, weight in selected)
        for group in obj.vertex_groups:
            group.remove([vertex.index])
        for index, weight in selected:
            obj.vertex_groups[index].add([vertex.index], weight / total, "REPLACE")
rig.animation_data.action = None
for pb in rig.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()
neutral = {b.name: b.matrix.copy() for b in rig.pose.bones}
console = bpy.data.actions.new("console")
console.use_fake_user = True
activate(console)
for pb in rig.pose.bones:
    pb.rotation_mode = "QUATERNION"
    pb.matrix = neutral[pb.name]
targets = []
constraints = []
center = (lo + hi) / 2
for side, sign in [("Left", 1), ("Right", -1)]:
    target = bpy.data.objects.new(side + "ConsoleTarget", None)
    bpy.context.scene.collection.objects.link(target)
    target.location = Vector((center.x + sign * 0.25, center.y - 0.46, lo.z + 0.99))
    forearm = bone(side + "ForeArm")
    constraint = forearm.constraints.new("IK")
    constraint.target = target
    constraint.chain_count = 2
    constraint.use_tail = True
    targets.append((target, sign))
    constraints.append((forearm, constraint))
poses = []
for frame in range(49):
    bpy.context.scene.frame_set(frame)
    for target, sign in targets:
        target.location.z = lo.z + 0.99 + math.sin(frame / 48 * math.tau + sign) * 0.012
        target.location.x = center.x + sign * 0.25 + math.sin(frame / 24 * math.tau + sign) * 0.012
    bpy.context.view_layer.update()
    evaluated = rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
    poses.append({b.name: b.matrix.copy() for b in evaluated.pose.bones})
for pb, constraint in constraints:
    pb.constraints.remove(constraint)
for target, _ in targets:
    bpy.data.objects.remove(target, do_unlink=True)
ordered = sorted(rig.pose.bones, key=lambda b: len(b.parent_recursive))
for frame, pose in enumerate(poses):
    bpy.context.scene.frame_set(frame)
    for pb in ordered:
        pb.rotation_mode = "QUATERNION"
        pb.matrix_basis = pb.bone.convert_local_to_pose(
            pose[pb.name],
            pb.bone.matrix_local,
            parent_matrix=pose[pb.parent.name] if pb.parent else Matrix.Identity(4),
            parent_matrix_local=pb.parent.bone.matrix_local if pb.parent else Matrix.Identity(4),
            invert=True,
        )
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)
        pb.keyframe_insert("scale", frame=frame)
clips["console"] = console
# Keep the high-resolution original; ship a bounded game texture set.
if vanguard:
    for image in bpy.data.images:
        if image.size[0] > 2048 or image.size[1] > 2048:
            image.scale(2048, 2048)
# Track-based export gives one explicit named clip per runtime animation.
rig.animation_data.action = None
for name, action in clips.items():
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 0, action)
    if len(action.slots):
        strip.action_slot = action.slots[0]
    strip.extrapolation = "NOTHING"
# Make every mesh bone transform explicit without touching the source downloads.
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
for obj in meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.wm.save_as_mainfile(compress=True, filepath=str(art_dir / (asset_name + ".blend")))
bpy.ops.export_scene.gltf(
    filepath=str(world_dir / (asset_name + ".glb")),
    export_format="GLB",
    use_selection=True,
    export_animations=True,
    export_animation_mode="NLA_TRACKS",
    export_anim_slide_to_zero=True,
)
(evidence_dir / "character-preparation.json").write_text(
    json.dumps(
        {
            "rig": rig.name,
            "bones": [b.name for b in rig.pose.bones],
            "clips": list(clips),
            "height": hi.z - lo.z,
            "rigid_helmet_vertices": rigid,
        },
        indent=2,
    )
    + "\n"
)
print("ENGINEER_EXPORTED", list(clips))
