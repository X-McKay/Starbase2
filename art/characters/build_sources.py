"""Original segmented humanoid pilot; run with Blender 4.5.3, not runtime Python.

All geometry, rigid weights, cameras and gait keys are authored here. No downloaded
meshes, motion clips, AI images, or image postprocessing. The .blend remains editable.
"""

import math
from pathlib import Path

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / ".local/character-frames"
assert bpy.app.version[:3] == (4, 5, 3), bpy.app.version_string
PALETTE = {
    "ink": "142336",
    "navy": "23344f",
    "blue": "405776",
    "ivory": "deddd0",
    "white": "f5efe0",
    "gold": "dfa343",
    "cyan": "41d7df",
    "teal": "12687a",
    "red": "b94a36",
    "skin": "bc7750",
    "hair": "bccbdd",
    "visor": "704623",
}


def material(name):
    mat = bpy.data.materials.new(name)
    rgb = tuple(int(PALETTE[name][i : i + 2], 16) / 255 for i in (0, 2, 4))
    rgb = tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = 0.38 if name in ("visor", "gold") else 0.7
    bsdf.inputs["Metallic"].default_value = 0.6 if name in ("visor", "gold") else 0.15
    return mat


def shape(name, pos, size, color, bone="torso", form="box"):
    if form == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, location=pos)
    else:
        bpy.ops.mesh.primitive_cube_add(size=2, location=pos)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if form == "box":
        bevel = obj.modifiers.new("Rounded armor edges", "BEVEL")
        bevel.width = 0.035
        bevel.segments = 2
        obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
    obj.data.materials.append(MATS[color])
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1, "REPLACE")
    deform = obj.modifiers.new("Shared humanoid rigid skin", "ARMATURE")
    deform.object = RIG
    return obj


def rig():
    arm = bpy.data.armatures.new("Aster humanoid v1")
    obj = bpy.data.objects.new("Aster humanoid v1", arm)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    joints = {
        "torso": ((0, 0, 1.13), (0, 0, 1.85), None),
        "head": ((0, 0, 1.85), (0, 0, 2.45), "torso"),
    }
    for side, x in [("L", -0.21), ("R", 0.21)]:
        joints[f"thigh.{side}"] = ((x, 0, 1.13), (x, -0.035, 0.65), None)
        joints[f"shin.{side}"] = ((x, -0.035, 0.65), (x, 0, 0.17), f"thigh.{side}")
        joints[f"foot.{side}"] = ((x, 0, 0.17), (x, -0.25, 0.17), f"shin.{side}")
        sx = -0.48 if side == "L" else 0.48
        joints[f"arm.{side}"] = ((sx, 0, 1.79), (sx, 0, 1.38), "torso")
        joints[f"hand.{side}"] = ((sx, 0, 1.38), (sx, -0.045, 1.03), f"arm.{side}")
    for name, (head, tail, parent) in joints.items():
        bone = arm.edit_bones.new(name)
        bone.head, bone.tail = head, tail
        if parent:
            bone.parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)
    obj.show_in_front = True
    return obj


def costume(kind):
    eva = kind == "eva"
    suit = "ivory" if eva else "navy"
    shape(
        "Pressure torso" if eva else "Flight armor",
        (0, 0, 1.56),
        (0.37, 0.235, 0.39),
        suit,
        form="sphere",
    )
    shape("Waist undersuit", (0, 0, 1.14), (0.3, 0.19, 0.16), "ink")
    shape("Utility belt", (0, -0.015, 1.22), (0.32, 0.225, 0.06), "gold" if not eva else "ink")
    shape("Buckle", (0, -0.25, 1.22), (0.075, 0.028, 0.05), "gold")
    for x in [-0.27, 0.27]:
        shape("Belt pouch", (x, -0.23, 1.16), (0.06, 0.075, 0.13), "ivory" if eva else "gold")
    for side, x in [("L", -0.21), ("R", 0.21)]:
        thigh, shin, foot = f"thigh.{side}", f"shin.{side}", f"foot.{side}"
        shape("Thigh", (x, 0, 0.91), (0.17, 0.17, 0.26), suit, thigh, "sphere")
        shape("Knee gasket", (x, -0.015, 0.65), (0.16, 0.16, 0.10), "ink", shin, "sphere")
        shape("Knee plate", (x, -0.17, 0.67), (0.12, 0.065, 0.12), "ivory", shin)
        shape("Shin", (x, 0, 0.43), (0.145, 0.15, 0.23), suit, shin, "sphere")
        shape("Boot", (x, -0.09, 0.16), (0.165, 0.255, 0.125), "ink", foot)
        shape("Toe plate", (x, -0.26, 0.20), (0.145, 0.105, 0.08), "ivory", foot)
        shape(
            "Boot trim", (x, -0.27, 0.12), (0.15, 0.055, 0.023), "gold" if not eva else "blue", foot
        )
        sx = -0.48 if side == "L" else 0.48
        arm, hand = f"arm.{side}", f"hand.{side}"
        shape("Upper sleeve", (sx, 0, 1.58), (0.155, 0.16, 0.235), suit, arm, "sphere")
        shape(
            "Shoulder shell",
            (sx, 0, 1.79),
            (0.18, 0.19, 0.15) if eva else (0.15, 0.17, 0.115),
            "ivory" if eva else "blue",
            arm,
            "sphere",
        )
        shape(
            "Mission stripe",
            (sx, -0.005, 1.63),
            (0.16, 0.165, 0.048),
            "red" if eva else "gold",
            arm,
        )
        shape("Elbow joint", (sx, 0, 1.37), (0.13, 0.13, 0.09), "ink", hand, "sphere")
        shape("Gauntlet", (sx, -0.02, 1.21), (0.14, 0.14, 0.18), "ivory", hand)
        shape("Glove", (sx, -0.045, 1.02), (0.125, 0.12, 0.11), "ink", hand, "sphere")
        shape("Wrist display", (sx, -0.166, 1.22), (0.075, 0.018, 0.06), "cyan", hand)
        if eva:
            for z in [0.84, 0.95]:
                shape("Pressure fold", (x, 0, z), (0.175, 0.175, 0.032), "white", thigh, "sphere")
            for z in [0.38, 0.49]:
                shape("Pressure fold", (x, 0, z), (0.15, 0.157, 0.028), "white", shin, "sphere")
    if eva:
        shape("Life support pack", (0, 0.33, 1.59), (0.36, 0.19, 0.42), "ivory")
        shape("Pack inset", (0, 0.53, 1.6), (0.22, 0.025, 0.25), "blue")
        for x in [-0.28, 0.28]:
            shape("Oxygen cylinder", (x, 0.42, 1.54), (0.12, 0.14, 0.33), "white", form="sphere")
        shape("Neck seal", (0, 0, 1.92), (0.28, 0.24, 0.09), "ink", "head", "sphere")
        shape("Helmet", (0, 0, 2.19), (0.365, 0.31, 0.36), "white", "head", "sphere")
        shape("Visor seal", (0, -0.25, 2.20), (0.30, 0.115, 0.265), "ink", "head", "sphere")
        shape("Amber visor", (0, -0.305, 2.20), (0.258, 0.075, 0.225), "visor", "head", "sphere")
        shape(
            "Visor warm reflection",
            (-0.12, -0.373, 2.3),
            (0.08, 0.008, 0.035),
            "gold",
            "head",
            "sphere",
        )
        shape("Visor glint", (-0.15, -0.371, 2.35), (0.04, 0.008, 0.05), "white", "head", "sphere")
        for x in [-0.35, 0.35]:
            shape("Comms housing", (x, 0.015, 2.18), (0.075, 0.15, 0.16), "blue", "head")
        shape("Chest control unit", (0, -0.27, 1.6), (0.25, 0.075, 0.20), "white")
        shape("Telemetry display", (-0.07, -0.35, 1.66), (0.105, 0.014, 0.062), "ink")
        shape("Display glass", (-0.07, -0.367, 1.67), (0.075, 0.008, 0.035), "cyan")
        for i, color in enumerate(["red", "gold", "blue"]):
            shape(
                "Control",
                (-0.12 + i * 0.12, -0.351, 1.49),
                (0.025, 0.02, 0.025),
                color,
                form="sphere",
            )
    else:
        shape("Chest cuirass", (0, -0.20, 1.62), (0.28, 0.12, 0.25), "blue", form="sphere")
        shape("Chest seam", (0, -0.308, 1.59), (0.014, 0.012, 0.20), "gold")
        shape("Expedition insignia", (0.14, -0.303, 1.75), (0.045, 0.025, 0.055), "gold")
        shape("Scarf collar", (0, -0.015, 1.91), (0.30, 0.26, 0.105), "teal", "head", "sphere")
        shape("Face", (0, -0.02, 2.2), (0.23, 0.205, 0.29), "skin", "head", "sphere")
        shape("Hair crown", (0, 0.035, 2.38), (0.255, 0.21, 0.20), "hair", "head", "sphere")
        for x in [-0.21, 0.21]:
            shape("Side hair", (x, 0.025, 2.19), (0.06, 0.14, 0.24), "hair", "head", "sphere")
        # Side-swept fringe, leaving the eyes readable from the front.
        for i in range(4):
            shape(
                "Silver fringe",
                (-0.17 + i * 0.09, -0.19, 2.4 + i * 0.024),
                (0.07, 0.065, 0.11),
                "hair",
                "head",
                "sphere",
            )
        for x in [-0.083, 0.083]:
            shape("Eye outline", (x, -0.202, 2.23), (0.049, 0.025, 0.059), "ink", "head", "sphere")
            shape("Eye", (x, -0.226, 2.235), (0.025, 0.007, 0.035), "cyan", "head", "sphere")
            shape(
                "Eye light",
                (x - 0.007, -0.234, 2.25),
                (0.009, 0.005, 0.012),
                "white",
                "head",
                "sphere",
            )
        shape("Nose", (0, -0.23, 2.16), (0.035, 0.04, 0.05), "skin", "head", "sphere")
        shape("Mouth", (0, -0.209, 2.065), (0.045, 0.013, 0.01), "ink", "head")
        # Separate tapered cape mesh with weighted root; gait animates its shared bone.
        verts = [
            (-0.29, 0.24, 1.87),
            (0.29, 0.24, 1.87),
            (-0.43, 0.35, 0.72),
            (0.43, 0.35, 0.72),
            (0, 0.42, 0.64),
            (0, 0.28, 1.85),
        ]
        mesh = bpy.data.meshes.new("Cape panels")
        mesh.from_pydata(verts, [], [(0, 2, 4, 5), (5, 4, 3, 1)])
        cape = bpy.data.objects.new("Expedition cape", mesh)
        bpy.context.collection.objects.link(cape)
        mesh.materials.append(MATS["teal"])
        solid = cape.modifiers.new("Cloth thickness", "SOLIDIFY")
        solid.thickness = 0.022
        group = cape.vertex_groups.new(name="torso")
        group.add(list(range(6)), 1, "REPLACE")
        mod = cape.modifiers.new("Shared humanoid rigid skin", "ARMATURE")
        mod.object = RIG
        for x in [-0.19, 0.19]:
            shape("Rear hair locks", (x, 0.18, 1.99), (0.09, 0.10, 0.28), "hair", "head", "sphere")


def bone_matrix(name, head, tail):
    head, tail = Vector(head), Vector(tail)
    RIG.pose.bones[name].matrix = Matrix.LocRotScale(
        head, (tail - head).to_track_quat("Y", "Z"), Vector((1, 1, 1))
    )


def pose(index):
    for bone in RIG.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    if index < 0:
        return
    phase = index / 8
    bob = -0.025 * math.sin(phase * math.tau * 2)
    bone_matrix("torso", (0, 0, 1.13 + bob), (0, 0, 1.85 + bob))
    bpy.context.view_layer.update()
    for side, x, offset in [("L", -0.21, 0), ("R", 0.21, 0.5)]:
        p = (phase + offset) % 1
        # Stance: constant ground speed. Swing: lifted return, same stride length.
        y = -0.32 + 1.28 * p if p < 0.5 else 0.32 - 1.28 * (p - 0.5)
        z = 0.17 if p < 0.5 else 0.17 + 0.22 * math.sin((p - 0.5) * math.tau)
        hip, ankle = Vector((x, 0, 1.13 + bob)), Vector((x, y, z))
        mid = (hip + ankle) / 2
        length = 0.49
        depth = math.sqrt(max(0.001, length * length - (hip - ankle).length_squared / 4))
        axis = (ankle - hip).normalized()
        forward = Vector((0, -1, 0))
        forward = (forward - axis * forward.dot(axis)).normalized()
        knee = mid + forward * depth
        bone_matrix(f"thigh.{side}", hip, knee)
        bpy.context.view_layer.update()
        bone_matrix(f"shin.{side}", knee, ankle)
        bpy.context.view_layer.update()
        bone_matrix(f"foot.{side}", ankle, ankle + Vector((0, -0.25, 0)))
        sx = -0.48 if side == "L" else 0.48
        swing = -0.22 * math.cos(p * math.tau)
        shoulder = Vector((sx, 0, 1.79 + bob))
        elbow = shoulder + Vector((0, swing, -0.39))
        wrist = elbow + Vector((0, swing * 0.55 - 0.04, -0.33))
        bone_matrix(f"arm.{side}", shoulder, elbow)
        bpy.context.view_layer.update()
        bone_matrix(f"hand.{side}", elbow, wrist)
    bpy.context.view_layer.update()


def setup():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.cycles.seed = 17
    bpy.context.preferences.filepaths.save_version = 0
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 256, 320
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.world.color = (0.25, 0.25, 0.25)
    bpy.ops.object.camera_add(location=(0, -4.6, 4.7))
    cam = bpy.context.object
    cam.rotation_euler = (Vector((0, 0, 1.1)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 3.5
    scene.camera = cam
    bpy.context.view_layer.update()
    # Ground pivot is identical for every frame, direction and character.
    for _ in range(2):
        projected = world_to_camera_view(scene, cam, Vector((0, 0, 0)))
        up = cam.rotation_euler.to_matrix() @ Vector((0, 1, 0))
        cam.location += up * (projected.y - (40 / 320)) * cam.data.ortho_scale
        bpy.context.view_layer.update()
    for name, pos, energy, size in [("Key", (-3, -4, 7), 450, 4), ("Rim", (3, 3, 5), 550, 3)]:
        bpy.ops.object.light_add(type="AREA", location=pos)
        lamp = bpy.context.object
        lamp.name = name
        lamp.data.energy = energy
        lamp.data.shape = "DISK"
        lamp.data.size = size
        lamp.rotation_euler = (
            (Vector((0, 0, 1.3)) - lamp.location).to_track_quat("-Z", "Y").to_euler()
        )
    return scene


def build_sources():
    global MATS, RIG
    for kind in ["captain", "eva"]:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.context.scene.world = bpy.data.worlds.new("Studio world")
        MATS = {name: material(name) for name in PALETTE}
        RIG = rig()
        costume(kind)
        scene = setup()
        scene.frame_start, scene.frame_end = 1, 8
        samples = []
        # Capture all poses before creating the Action. Otherwise dependency-graph
        # evaluation can restore frame 1 while the remaining samples are authored.
        for i in range(-1, 8):
            pose(i)
            bpy.context.view_layer.update()
            samples.append({bone.name: bone.matrix_basis.copy() for bone in RIG.pose.bones})
        for frame, sample in enumerate(samples):
            for name, basis in sample.items():
                bone = RIG.pose.bones[name]
                bone.matrix_basis = basis
                bone.keyframe_insert("location", frame=frame)
                bone.keyframe_insert("rotation_quaternion", frame=frame)
                bone.keyframe_insert("scale", frame=frame)
        RIG.animation_data.action.name = "walk-eight-poses-v1"
        scene.frame_set(0)
        bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / f"art/characters/{kind}.blend"))


if __name__ == "__main__":
    build_sources()
