"""Bake social contact clips from the exact selected rigs; no provider calls."""

import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[4]
assert bpy.app.background and bpy.app.version[:3] == (5, 2, 1)
bpy.context.preferences.filepaths.save_version = 0
sources = {
    "sentinel": "cybercat-sentinel/cybercat.glb",
    "engineer": "engineering-specialist/engineer.glb",
    "vanguard": "cybercat-vanguard-secondary/vanguard-secondary.glb",
}
records = []


def build(identity, relative):
    source = ROOT / "apps/world/assets/characters" / relative
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.import_scene.gltf(filepath=str(source))
    rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    meshes = [
        o
        for o in bpy.context.scene.objects
        if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)
    ]
    for track in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(track)
    rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for bone in rig.data.edit_bones:
        if bone.children:
            bone.length = (bone.children[0].head - bone.head).length
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()
    world = {b.name: rig.matrix_world @ b.matrix for b in rig.pose.bones}
    points = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    floor = min(p.z for p in points)
    runtime_scale = 1.2 if identity == "sentinel" else 1.0
    seat_pelvis = 0.76 if identity == "sentinel" else 0.63
    lap_height = 0.80 if identity == "sentinel" else 0.70

    def empty(name, position):
        o = bpy.data.objects.new(name, None)
        bpy.context.scene.collection.objects.link(o)
        o.location = position
        return o

    def assign(values):
        for pb in rig.pose.bones:
            local = (
                values[pb.parent.name].inverted() @ values[pb.name]
                if pb.parent
                else values[pb.name]
            )
            rest = (
                pb.parent.bone.matrix_local.inverted() @ pb.bone.matrix_local
                if pb.parent
                else pb.bone.matrix_local
            )
            pb.matrix_basis = rest.inverted() @ local

    def aim(name, head, child_name, child):
        original = world[child_name].translation - world[name].translation
        desired = child - head
        rotation = original.rotation_difference(desired) @ world[name].to_quaternion()
        return Matrix.LocRotScale(head, rotation, world[name].to_scale())

    def joint(start, end, l1, l2, pole):
        direction = end - start
        distance = direction.length
        assert distance < l1 + l2 + 0.001, (identity, distance, l1 + l2)
        axis = direction.normalized()
        projection = (l1 * l1 - l2 * l2 + distance * distance) / (2 * distance)
        perpendicular = (pole - axis * pole.dot(axis)).normalized()
        return (
            start
            + axis * projection
            + perpendicular * math.sqrt(max(0, l1 * l1 - projection * projection))
        )

    def pose(amount):
        hips = world["Hips"].copy()
        hips.translation = world["Hips"].translation.lerp(
            Vector(
                (
                    world["Hips"].translation.x,
                    0.55 / runtime_scale,
                    seat_pelvis / runtime_scale + floor,
                )
            ),
            amount,
        )
        shift = hips @ world["Hips"].inverted()
        desired = {name: shift @ matrix for name, matrix in world.items()}
        for side in ["Left", "Right"]:
            upper = side + "UpLeg"
            lower = side + "Leg"
            foot = side + "Foot"
            start = desired[upper].translation
            initial = world[foot].translation
            end = initial.lerp(Vector((initial.x, 0.15 / runtime_scale, initial.z)), amount)
            l1 = (world[lower].translation - world[upper].translation).length
            l2 = (world[foot].translation - world[lower].translation).length
            knee = joint(start, end, l1, l2, Vector((0, -1, 0)))
            desired[upper] = aim(upper, start, lower, knee)
            desired[lower] = aim(lower, knee, foot, end)
            desired[foot] = world[foot].copy()
            desired[foot].translation = end
            delta = desired[foot] @ world[foot].inverted()
            for bone in rig.data.bones:
                if any(parent.name == foot for parent in bone.parent_recursive):
                    desired[bone.name] = delta @ world[bone.name]
            arm = side + "Arm"
            fore = side + "ForeArm"
            hand = side + "Hand"
            start = desired[arm].translation
            end = world[hand].translation.lerp(
                Vector(
                    (
                        (0.18 if side == "Left" else -0.18) / runtime_scale,
                        0.42 / runtime_scale,
                        lap_height / runtime_scale + floor,
                    )
                ),
                amount,
            )
            l1 = (world[fore].translation - world[arm].translation).length
            l2 = (world[hand].translation - world[fore].translation).length
            if (end - start).length > l1 + l2 - 0.001:
                end = start + (end - start).normalized() * (l1 + l2 - 0.001)
            elbow = joint(start, end, l1, l2, Vector((1 if side == "Left" else -1, 0.3, 0)))
            desired[arm] = aim(arm, start, fore, elbow)
            desired[fore] = aim(fore, elbow, hand, end)
            desired[hand] = world[hand].copy()
            desired[hand].translation = end
            delta = desired[hand] @ world[hand].inverted()
            for bone in rig.data.bones:
                if any(parent.name == hand for parent in bone.parent_recursive):
                    desired[bone.name] = delta @ world[bone.name]
        assign({name: rig.matrix_world.inverted() @ matrix for name, matrix in desired.items()})
        bpy.context.view_layer.update()

    scene = bpy.context.scene
    scene.render.fps = 30
    clips = {}
    contacts = []
    for name, length in [("sit_down", 1.2), ("seated", 3.0), ("stand_up", 1.0)]:
        count = round(length * 30)
        samples = []
        for frame in range(count + 1):
            t = frame / count
            smooth = t * t * (3 - 2 * t)
            amount = smooth if name == "sit_down" else 1 - smooth if name == "stand_up" else 1
            pose(amount)
            evaluated = {b.name: b.matrix.copy() for b in rig.pose.bones}
            samples.append(evaluated)
            if frame in [0, count // 2, count]:
                contacts.append(
                    {
                        "clip": name,
                        "frame": frame,
                        "amount": amount,
                        "hips": list((rig.matrix_world @ evaluated["Hips"]).translation),
                        "feet": [
                            list((rig.matrix_world @ evaluated[s + "Foot"]).translation)
                            for s in ["Left", "Right"]
                        ],
                    }
                )
        clips[name] = (count, samples)
    # Bake evaluated matrices into unconstrained parent-relative bone transforms.
    for pb in rig.pose.bones:
        for con in list(pb.constraints):
            pb.constraints.remove(con)
    actions = []
    for name, (_count, samples) in clips.items():
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        rig.animation_data.action = action
        for frame, values in enumerate(samples):
            assign(values)
            for pb in rig.pose.bones:
                pb.rotation_mode = "QUATERNION"
                pb.keyframe_insert("location", frame=frame)
                pb.keyframe_insert("rotation_quaternion", frame=frame)
                pb.keyframe_insert("scale", frame=frame)
        actions.append(action)
    rig.animation_data.action = None
    for action in actions:
        track = rig.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, 0, action)
        strip.action_slot = action.slots[0]
        strip.action_frame_start = 0
        strip.action_frame_end = clips[action.name][0]
        track.mute = True
    scene.frame_start = 0
    scene.frame_end = 90
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    # Editable source retains complete character and constraint targets alongside baked clips.
    out = ROOT / "assets-production/characters/shift-social/blender" / f"{identity}-social.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(out), compress=True)
    # A tiny skin establishes the exact skeleton without duplicating textures.
    bpy.ops.object.select_all(action="DESELECT")
    dummydata = bpy.data.meshes.new("AnimationCarrier")
    dummydata.from_pydata([(0, 0, 0), (0.001, 0, 0), (0, 0.001, 0)], [], [(0, 1, 2)])
    dummy = bpy.data.objects.new("AnimationCarrier", dummydata)
    scene.collection.objects.link(dummy)
    group = dummy.vertex_groups.new(name="Hips")
    group.add([0, 1, 2], 1, "REPLACE")
    mod = dummy.modifiers.new("Skin", "ARMATURE")
    mod.object = rig
    dummy.parent = rig
    dummy.select_set(True)
    rig.select_set(True)
    for track in rig.animation_data.nla_tracks:
        track.mute = False
    target = ROOT / "apps/world/assets/characters/shift-social" / f"{identity}-social.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(target),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_frame_range=False,
        export_skins=True,
        export_all_influences=False,
    )
    records.append(
        {
            "identity": identity,
            "source": str(source.relative_to(ROOT)),
            "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "runtime": str(target.relative_to(ROOT)),
            "bytes": target.stat().st_size,
            "floor_z": floor,
            "clips": {"sit_down": 1.2, "seated": 3, "stand_up": 1},
            "contacts": contacts,
        }
    )


for identity, relative in sources.items():
    build(identity, relative)

(ROOT / "evidence/shift-change/animation/baked-contacts.json").write_text(
    json.dumps(records, indent=2)
)
print("SOCIAL_ANIMATIONS_BAKED")
