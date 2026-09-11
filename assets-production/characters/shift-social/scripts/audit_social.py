"""Check head-space skin preservation through every baked social clip frame."""

import json
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[4]
records = []


def audit(identity):
    bpy.ops.wm.open_mainfile(
        filepath=str(
            ROOT / "assets-production/characters/shift-social/blender" / f"{identity}-social.blend"
        )
    )
    rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    meshes = [
        o for o in bpy.context.scene.objects if o.type == "MESH" and o.vertex_groups.get("Head")
    ]

    def sample():
        bpy.context.view_layer.update()
        deps = bpy.context.evaluated_depsgraph_get()
        head = (rig.matrix_world @ rig.pose.bones["Head"].matrix).inverted()
        values = []
        for obj in meshes:
            group = obj.vertex_groups["Head"].index
            indices = [
                v.index
                for v in obj.data.vertices
                if any(g.group == group and g.weight > 0.999 for g in v.groups)
            ]
            evaluated = obj.evaluated_get(deps)
            mesh = evaluated.to_mesh()
            values.extend(head @ obj.matrix_world @ mesh.vertices[i].co for i in indices)
            evaluated.to_mesh_clear()
        return values

    rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.matrix_basis.identity()
    original = sample()
    assert len(original) > 100
    for name in ["sit_down", "seated", "stand_up"]:
        action = bpy.data.actions[name]
        rig.animation_data.action = action
        rig.animation_data.action_slot = action.slots[0]
        maximum = 0.0
        count = int(action.frame_range.y)
        for frame in range(count + 1):
            bpy.context.scene.frame_set(frame)
            current = sample()
            assert len(current) == len(original)
            maximum = max(
                maximum, max((a - b).length * 0.01 for a, b in zip(original, current, strict=True))
            )
        assert maximum < 0.0001, (identity, name, maximum)
        records.append(
            {
                "identity": identity,
                "clip": name,
                "frames": count + 1,
                "protected_vertices": len(original),
                "maximum_head_local_change_m": maximum,
            }
        )


for identity in ["sentinel", "engineer", "vanguard"]:
    audit(identity)

(ROOT / "evidence/shift-change/animation/head-preservation.json").write_text(
    json.dumps(records, indent=2)
)
print("SOCIAL_HEAD_PRESERVATION_PASSED")
