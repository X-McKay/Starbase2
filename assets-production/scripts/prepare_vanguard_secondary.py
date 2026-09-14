"""Add one conservative loose-strand joint to a separate Vanguard variant.

Blender 5.2.1 background only; original rig, source and runtime remain untouched.
Selection is bound to the inspected source hash and excludes helmet/face.
"""

import hashlib
import json
from pathlib import Path

import bpy
from mathutils import Quaternion, Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets-production/characters/cybercat-vanguard/blender/vanguard.blend"
OUT = ROOT / "assets-production/characters/cybercat-vanguard-secondary"
RUNTIME = ROOT / "apps/world/assets/characters/cybercat-vanguard-secondary/vanguard-secondary.glb"


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    if not bpy.app.background or bpy.app.version[:3] != (5, 2, 1):
        raise RuntimeError("Requires separate background Blender 5.2.1")
    source_runtime = ROOT / "apps/world/assets/characters/cybercat-vanguard/vanguard.glb"
    if digest(SOURCE) != "b06c80c324804878fd6ef18239166263f18aed5fede945d0755b707b9b1f2605":
        raise RuntimeError("Editable source changed: inspect the hair region again")
    if digest(source_runtime) != "1be1433ffd420a8dbbd72ee03a99fbb06132fad0bb2bdd2b475b06a1c8a0e998":
        raise RuntimeError("Selected source changed: inspect the hair region again")
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    bpy.context.preferences.filepaths.save_version = 0
    rig = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    mesh = next(
        obj
        for obj in bpy.context.scene.objects
        if obj.type == "MESH" and obj.vertex_groups.get("Head")
    )
    original_hash = digest(SOURCE)
    rig.data.pose_position = "REST"
    bpy.context.view_layer.update()
    head = mesh.vertex_groups["Head"]
    weights = {}
    for vertex in mesh.data.vertices:
        point = mesh.matrix_world @ vertex.co
        old = next((entry.weight for entry in vertex.groups if entry.group == head.index), 0)
        weight = max(0, min(1, (-point.x - 0.215) / 0.12)) * max(0, min(1, (point.z - 1.43) / 0.10))
        weight = weight * weight * (3 - 2 * weight)
        if old > 0.999 and weight > 0:
            weights[vertex.index] = weight
    if not 1500 < len(weights) < 3500:
        raise RuntimeError(f"Hair mask no longer matches reviewed region: {len(weights)} vertices")
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    parent = rig.data.edit_bones["Head"]
    hair = rig.data.edit_bones.new("HairSwing")
    hair.head = rig.matrix_world.inverted() @ Vector((-0.18, 0, 1.62))
    hair.tail = hair.head + (parent.tail - parent.head).normalized() * 8
    hair.parent = parent
    hair.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    group = mesh.vertex_groups.new(name="HairSwing")
    for index, weight in weights.items():
        head.add([index], 1 - weight, "REPLACE")
        group.add([index], weight, "REPLACE")
    rig.data.pose_position = "POSE"
    protected = [v.index for v in mesh.data.vertices if v.index not in weights]
    max_protected = 0.0
    max_hair = 0.0
    sampled = []
    tracks = list(rig.animation_data.nla_tracks)
    old_mutes = [track.mute for track in tracks]
    for track in tracks:
        for other in tracks:
            other.mute = other != track
        for frame in (0, 6, 12, 18, 24):
            bpy.context.scene.frame_set(frame)
            pose = rig.pose.bones["HairSwing"]
            pose.rotation_mode = "QUATERNION"
            pose.rotation_quaternion = Quaternion()
            bpy.context.view_layer.update()
            base = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
            baseline = [mesh.matrix_world @ v.co for v in base.data.vertices]
            pose.rotation_quaternion = Quaternion(Vector((1, 0, 0)), 0.10)
            bpy.context.view_layer.update()
            moved = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
            result = [mesh.matrix_world @ v.co for v in moved.data.vertices]
            max_protected = max(
                max_protected, max((result[i] - baseline[i]).length for i in protected)
            )
            max_hair = max(max_hair, max((result[i] - baseline[i]).length for i in weights))
            sampled.append({"clip": track.name, "frame": frame})
    if max_protected > 0.000001 or max_hair < 0.001 or max_hair > 0.08:
        raise RuntimeError(
            f"Secondary deformation audit failed: protected={max_protected}, hair={max_hair}"
        )
    for track, muted in zip(tracks, old_mutes, strict=True):
        track.mute = muted
    rig.pose.bones["HairSwing"].rotation_quaternion = Quaternion()
    bpy.context.scene.frame_set(0)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    mesh.select_set(True)
    OUT.joinpath("blender").mkdir(parents=True, exist_ok=True)
    RUNTIME.parent.mkdir(parents=True, exist_ok=True)
    blend = OUT / "blender/vanguard-secondary.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
    bpy.ops.export_scene.gltf(
        filepath=str(RUNTIME),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_anim_slide_to_zero=True,
    )
    report = {
        "source": str(SOURCE.relative_to(ROOT)),
        "source_sha256": original_hash,
        "original_runtime_sha256": digest(source_runtime),
        "selected_vertices": len(weights),
        "selection": (
            "Original full Head influence; x < -.215m and z > 1.43m; smooth x/z fade. "
            "Verified upper loose strands only."
        ),
        "protected_vertex_count": len(protected),
        "max_protected_deformation_m": max_protected,
        "max_hair_deformation_m_at_0_1rad": max_hair,
        "sampled_poses": sampled,
        "joint": "HairSwing",
        "parent": "Head",
        "blender_version": bpy.app.version_string,
        "files": {
            str(path.relative_to(ROOT)): digest(path) for path in (blend, RUNTIME, Path(__file__))
        },
        "limitations": (
            "Only reviewed upper loose strands move; lower hair remains in original rig. "
            "Native motion review required. No new generation or changes to original files."
        ),
    }
    OUT.joinpath("provenance.json").write_text(json.dumps(report, indent=2) + "\n")
    (ROOT / "evidence/world/inhabited-polish/secondary-region-audit.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    print("VANGUARD_SECONDARY_PREPARED", len(weights), max_protected, max_hair)


if __name__ == "__main__":
    main()
