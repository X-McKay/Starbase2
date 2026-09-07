"""Repair the inspected Cybercat skin weights without changing the source file.

Run using Blender 5.2.1 with cybercat-source.blend as the input file.
The authored region is in the original model's world-space metres.
"""

import json
from pathlib import Path

import bpy

assert bpy.app.version[:3] == (5, 2, 1), bpy.app.version_string
root = Path(__file__).resolve().parents[2]
mesh = bpy.data.objects["char1"]
rig = bpy.data.objects["Meshy_cybercat-sentinel-rigged_Armature"]
for obj in (rig, mesh):
    if obj.name not in bpy.context.scene.objects:
        bpy.context.scene.collection.objects.link(obj)
bpy.context.view_layer.update()
points = [mesh.matrix_world @ vertex.co for vertex in mesh.data.vertices]
# Face and helmet above the collar must behave as a rigid head shell. A smooth
# transition below it avoids an abrupt change at the neck/upper chest seam.
blend_bottom = 1.40
rigid_bottom = 1.47
rigid = {i for i, point in enumerate(points) if point.z >= rigid_bottom}
edges = [
    (edge.vertices[0], edge.vertices[1])
    for edge in mesh.data.edges
    if all(i in rigid for i in edge.vertices)
    and (points[edge.vertices[0]] - points[edge.vertices[1]]).length > 0.0001
]
frames = [0.8, 4.9, 9.1, 13.2, 17.3, 21.5, 25.6]


def strain():
    samples = []
    for frame in frames:
        bpy.context.scene.frame_set(int(frame), subframe=frame % 1)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        evaluated = mesh.evaluated_get(depsgraph)
        posed = evaluated.to_mesh()
        positions = [evaluated.matrix_world @ vertex.co for vertex in posed.vertices]
        stretch = [
            abs((positions[a] - positions[b]).length / (points[a] - points[b]).length - 1)
            for a, b in edges
        ]
        samples.append({"frame": frame, "max_relative_edge_strain": max(stretch)})
        evaluated.to_mesh_clear()
    return samples


baseline = strain()
assert max(sample["max_relative_edge_strain"] for sample in baseline) > 0.01
original = [tuple((g.group, g.weight) for g in vertex.groups) for vertex in mesh.data.vertices]
head = mesh.vertex_groups["Head"]
changed = 0
for index, point in enumerate(points):
    if point.z <= blend_bottom:
        continue
    blend = min(1.0, (point.z - blend_bottom) / (rigid_bottom - blend_bottom))
    blend = blend * blend * (3 - 2 * blend)
    weights = dict(original[index])
    for group in mesh.vertex_groups:
        group.remove([index])
    for group_index, weight in weights.items():
        value = weight * (1 - blend)
        if value > 0.000001:
            mesh.vertex_groups[group_index].add([index], value, "REPLACE")
    head.add([index], weights.get(head.index, 0.0) * (1 - blend) + blend, "REPLACE")
    changed += 1
bpy.context.view_layer.update()
repaired = strain()
assert max(sample["max_relative_edge_strain"] for sample in repaired) < 0.002
for index, point in enumerate(points):
    if point.z <= blend_bottom:
        assert original[index] == tuple(
            (g.group, g.weight) for g in mesh.data.vertices[index].groups
        )
report = {
    "source": "assets-production/characters/cybercat-sentinel/blender/cybercat-source.blend",
    "blender": bpy.app.version_string,
    "rigid_region_z_m": rigid_bottom,
    "blend_bottom_z_m": blend_bottom,
    "changed_vertices": changed,
    "rigid_vertices": len(rigid),
    "measured_edges": len(edges),
    "baseline": baseline,
    "repaired": repaired,
    "unchanged_below_blend": True,
}
evidence = root / "evidence/meshy-blender"
evidence.mkdir(parents=True, exist_ok=True)
(evidence / "head-weight-repair.json").write_text(json.dumps(report, indent=2) + "\n")
bpy.data.libraries.write(
    str(root / "assets-production/characters/cybercat-sentinel/blender/cybercat-repaired.blend"),
    {rig, mesh},
    path_remap="ABSOLUTE",
    fake_user=True,
    compress=True,
)
print(json.dumps(report, indent=2))
