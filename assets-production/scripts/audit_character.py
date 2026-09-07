"""Sample exported-source poses and measure rigid helmet deformation in head space."""

import argparse
import json
import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--vanguard", action="store_true")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])
source = (
    "assets-production/characters/cybercat-vanguard/blender/vanguard.blend"
    if args.vanguard
    else "assets-production/characters/engineering-specialist/blender/engineer.blend"
)
evidence = "evidence/cybercat-vanguard" if args.vanguard else "evidence/engineering-polish"
bpy.ops.wm.open_mainfile(filepath=str(ROOT / source))
rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
mesh = next(
    o for o in bpy.context.scene.objects if o.type == "MESH" and o.vertex_groups.get("Head")
)
for track in rig.animation_data.nla_tracks:
    track.mute = True
group = mesh.vertex_groups["Head"]
indices = [
    v.index
    for v in mesh.data.vertices
    if any(g.group == group.index and g.weight > 0.999999 for g in v.groups)
    and all(g.group == group.index or g.weight < 0.0000001 for g in v.groups)
]
assert indices
reference = None
results = []
for name in ["idle", "walk", "run", "console"]:
    action = bpy.data.actions[name]
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    worst = 0.0
    for step in range(25):
        frame = action.frame_range[0] + (action.frame_range[1] - action.frame_range[0]) * step / 24
        bpy.context.scene.frame_set(int(frame), subframe=frame % 1)
        bpy.context.view_layer.update()
        graph = bpy.context.evaluated_depsgraph_get()
        evaluated = mesh.evaluated_get(graph)
        geometry = evaluated.to_mesh()
        head_space = (rig.matrix_world @ rig.pose.bones["Head"].matrix).inverted()
        points = [head_space @ evaluated.matrix_world @ geometry.vertices[i].co for i in indices]
        if reference is None:
            reference = points
        # Head-space units are centimetres on Meshy's imported 0.01-scale rig.
        worst = max(
            worst, max((a - b).length * 0.01 for a, b in zip(points, reference, strict=True))
        )
        evaluated.to_mesh_clear()
    results.append({"clip": name, "samples": 25, "max_rigid_helmet_deformation_m": worst})
assert max(r["max_rigid_helmet_deformation_m"] for r in results) < 0.0001, results
report = {
    "rigid_helmet_vertices": len(indices),
    "clips": results,
    "scope": "Measures repaired rigid region; visual review also required for collar and limbs.",
}
(ROOT / evidence / "helmet-audit.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report))
