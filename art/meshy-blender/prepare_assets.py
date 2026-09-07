"""Normalize the approved Meshy batch for existing Godot footprints.

Blender 5.2.1; source downloads remain untouched in meshy_output.
"""

import hashlib
import json
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

assert bpy.app.version[:3] == (5, 2, 1)
root = Path(__file__).resolve().parents[2]
batch = json.loads((root / "meshy_output/approved-batch.json").read_text())
provenance = []


def trim_box(name, center, size, color, glow=False):
    material = bpy.data.materials.get(name)
    if material is None:
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        shader = material.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value = (*color, 1)
        shader.inputs["Roughness"].default_value = 0.5
        shader.inputs["Metallic"].default_value = 0.4
        if glow:
            shader.inputs["Emission Color"].default_value = (*color, 1)
            shader.inputs["Emission Strength"].default_value = 1.2
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    bevel = obj.modifiers.new("Edge radius", "BEVEL")
    bevel.width = 0.025
    bevel.segments = 2
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


for item in batch["tasks"]:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    source = Path(item["directory"]) / "refined.glb"
    bpy.ops.import_scene.gltf(filepath=str(source))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    for obj in meshes:
        transform = obj.matrix_world.copy()
        for vertex in obj.data.vertices:
            vertex.co = transform @ vertex.co
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
    points = [vertex.co.copy() for obj in meshes for vertex in obj.data.vertices]
    lo = Vector([min(p[axis] for p in points) for axis in range(3)])
    hi = Vector([max(p[axis] for p in points) for axis in range(3)])
    removed = 0
    if item["asset"] == "engineering-exterior":
        # The generated ground platform is not part of the building: the colony
        # already owns paving. Remove its lowest thin band before fitting.
        cutoff = lo.z + (hi.z - lo.z) * 0.035
        for obj in meshes:
            bm = bmesh.new()
            bm.from_mesh(obj.data)
            remove = [vertex for vertex in bm.verts if vertex.co.z < cutoff]
            removed += len(remove)
            bmesh.ops.delete(bm, geom=remove, context="VERTS")
            bm.to_mesh(obj.data)
            bm.free()
        points = [vertex.co.copy() for obj in meshes for vertex in obj.data.vertices]
        lo = Vector([min(p[axis] for p in points) for axis in range(3)])
        hi = Vector([max(p[axis] for p in points) for axis in range(3)])
        size = hi - lo
        factor = min(10.7 / size.x, 8.3 / size.y)
        # Front is Blender -Y / Godot +Z. Match the existing physical rectangle.
        offset = Vector(
            (-1.95 - (lo.x + hi.x) * 0.5 * factor, -1.55 - lo.y * factor, -lo.z * factor + 0.04)
        )
    else:
        size = hi - lo
        factor = min(2.8 / size.z, 1.18 / max(size.x, size.y))
        offset = Vector(
            (-(lo.x + hi.x) * 0.5 * factor, -(lo.y + hi.y) * 0.5 * factor, -lo.z * factor + 0.20)
        )
    for obj in meshes:
        for vertex in obj.data.vertices:
            vertex.co = vertex.co * factor + offset
        obj.data.update()
    if item["asset"] == "engineering-exterior":
        dark = (0.035, 0.065, 0.08)
        ivory = (0.55, 0.64, 0.68)
        cyan = (0.08, 0.7, 0.85)
        # Authored entry trim gives the generated hull a precise gameplay door.
        for x in (-3.28, -0.62):
            trim_box("Airlock graphite", (x, -1.51, 1.28), (0.26, 0.35, 2.56), dark)
            trim_box("Airlock cyan", (x, -1.71, 1.28), (0.055, 0.035, 2.24), cyan, True)
        trim_box("Airlock graphite", (-1.95, -1.51, 2.58), (2.92, 0.35, 0.25), dark)
        trim_box("Airlock cyan", (-1.95, -1.71, 2.58), (2.5, 0.035, 0.055), cyan, True)
        roof_z = (hi.z - lo.z) * factor + 0.08
        for y in (0.2, 1.4, 2.6, 3.8):
            trim_box("Roof service rails", (-1.95, y, roof_z), (5.8, 0.12, 0.10), ivory)
        for x in (-4.1, 0.2):
            trim_box("Roof equipment base", (x, 2.2, roof_z + 0.12), (1.1, 2.5, 0.25), dark)
            for index in range(9):
                trim_box(
                    "Cooling fins",
                    (x, 1.2 + index * 0.25, roof_z + 0.31),
                    (0.94, 0.09, 0.24),
                    ivory,
                )
        trim_box("Roof equipment base", (-1.95, 3.9, roof_z + 0.22), (1.6, 0.9, 0.45), dark)
        for x in (-2.5, -1.95, -1.4):
            trim_box("Roof cyan", (x, 3.42, roof_z + 0.24), (0.32, 0.025, 0.12), cyan, True)
        # Batch added repeated parts by material after preserving their geometry.
        for mat in list(bpy.data.materials):
            pieces = [
                obj
                for obj in bpy.context.scene.objects
                if obj.type == "MESH" and obj.active_material == mat
            ]
            if len(pieces) < 2:
                continue
            bpy.ops.object.select_all(action="DESELECT")
            for obj in pieces:
                obj.select_set(True)
            bpy.context.view_layer.objects.active = pieces[0]
            bpy.ops.object.join()
        meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    output = root / f"apps/world/art/meshy/{item['asset']}.glb"
    bpy.ops.wm.save_as_mainfile(filepath=str(root / f"art/meshy-blender/{item['asset']}.blend"))
    bpy.ops.export_scene.gltf(filepath=str(output), export_format="GLB", export_animations=False)
    provenance.append(
        {
            "asset": item["asset"],
            "preview_task": item["preview"],
            "texture_task": item["refine"],
            "credits": item["preview_credits"] + item["refine_credits"],
            "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "output": str(output.relative_to(root)),
            "output_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
            "bytes": output.stat().st_size,
            "scale": factor,
            "removed_ground_vertices": removed,
            "triangles": sum(len(p.vertices) - 2 for obj in meshes for p in obj.data.polygons),
        }
    )
(root / "art/meshy-blender/provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
print(json.dumps(provenance, indent=2))
