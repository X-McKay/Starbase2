"""Build five dimensionally matched, editable Blender buildings and Godot rooms.

Blender 5.2.1, metres. Source scenes precede shipping material batching.
No Meshy API calls: reuse the approved reactor and the repaired character.
"""

import json
import math
from pathlib import Path

import bpy

# Background production saves selected sources without accumulating recovery copies.
bpy.context.preferences.filepaths.save_version = 0

ROOT = Path(__file__).resolve().parents[2]
FAMILIES = {"repair": "engineering", "review": "command", "gym": "training", "greenhouse": "botanical", "habitat": "habitat"}
OUT = ROOT / "apps/world/assets/structures"
OUT.mkdir(exist_ok=True)
assert bpy.app.version[:3] == (5, 2, 1)
BUILDINGS = {
    "repair": (-7.3, -6.75, 10.7, 8.3, (0.10, 0.78, 0.87)),
    "review": (-7.0, -7.0, 14.0, 8.55, (0.12, 0.62, 0.92)),
    "gym": (-7.5, -7.0, 15.0, 8.55, (0.62, 0.38, 0.93)),
    "habitat": (-8.0, -8.65, 17.35, 10.2, (0.97, 0.60, 0.20)),
    "greenhouse": (-6.5, -6.0, 15.8, 7.55, (0.25, 0.84, 0.51)),
}
MATERIALS = {}
GROUPS = {}


def material(name, rgb, metal=0.0, glow=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    p = mat.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Metallic"].default_value = metal
    p.inputs["Roughness"].default_value = 0.48
    p.inputs["Emission Color"].default_value = (*rgb, 1)
    p.inputs["Emission Strength"].default_value = glow
    return mat


def finish(obj, group, mat):
    obj.name = group + "_" + mat
    obj.data.materials.append(MATERIALS[mat])
    GROUPS.setdefault((group, mat), []).append(obj)
    return obj


def box(group, at, size, mat="Ivory", bevel=0.035):
    # Author coordinates use Godot X/Y/Z; Blender conversion happens here.
    bpy.ops.mesh.primitive_cube_add(size=1, location=(at[0], -at[2], at[1]))
    obj = bpy.context.object
    obj.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new("Edge radius", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(obj, group, mat)


def cylinder(group, at, radius, height, mat="Steel"):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=20, radius=radius, depth=height, location=(at[0], -at[2], at[1])
    )
    return finish(bpy.context.object, group, mat)


def prop(blocks, name, x, z, width, depth, height=1.2):
    blocks.append(
        {"name": name, "rect": [x - width / 2, z - depth / 2, width, depth], "height": height}
    )


def console(x, z, blocks, name, width=1.5):
    prop(blocks, name, x, z, width, 0.9, 1.65)
    box("Furniture", (x, 0.50, z), (width, 1, 0.8))
    box("Furniture", (x, 1.30, z - 0.15), (width, 0.65, 0.18), "Dark")
    box("Furniture", (x, 1.30, z - 0.04), (width - 0.12, 0.49, 0.025), "Glass")
    for row in range(4):
        box(
            "Furniture",
            (x - 0.12, 1.12 + row * 0.10, z - 0.018),
            (width * 0.6 - row * 0.12, 0.022, 0.008),
            "Accent",
            0,
        )
    box("Furniture", (x, 1.00, z + 0.22), (width - 0.15, 0.05, 0.30), "Dark")
    for key in range(5):
        box("Furniture", (x - 0.5 + key * 0.25, 1.035, z + 0.22), (0.08, 0.015, 0.1), "Accent", 0)


manifest = {}
for kind, (left, back, width, depth, accent) in BUILDINGS.items():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    GROUPS.clear()
    MATERIALS = {
        "Ivory": material(kind + "_Ivory", (0.62, 0.69, 0.72), 0.2),
        "Dark": material(kind + "_Dark", (0.035, 0.062, 0.080), 0.65),
        "Steel": material(kind + "_Steel", (0.20, 0.29, 0.34), 0.65),
        "Floor": material(kind + "_Floor", (0.32, 0.40, 0.45), 0.15),
        "Glass": material(kind + "_Glass", (0.06, 0.17, 0.23), 0.5),
        "Accent": material(kind + "_Accent", accent, 0.1, 1.2),
        "Leaf": material(kind + "_Leaf", (0.13, 0.38, 0.19)),
    }
    right, front = left + width, back + depth
    cx, cz = left + width / 2, back + depth / 2
    blocks = []
    box("Floor", (cx, 0.025, cz), (width, 0.16, depth), "Dark")
    nx, nz = math.ceil(width), math.ceil(depth)
    for ix in range(nx):
        for iz in range(nz):
            box(
                "Floor",
                (left + (ix + 0.5) * width / nx, 0.117, back + (iz + 0.5) * depth / nz),
                (width / nx - 0.025, 0.02, depth / nz - 0.025),
                "Floor",
                0.005,
            )
    # Walls stay physically solid when their upper visual surfaces fade.
    box("Back", (cx, 1.65, back + 0.1), (width, 3.3, 0.2))
    for x in (left + 0.1, right - 0.1):
        box("Cutaway", (x, 1.65, cz), (0.2, 3.3, depth))
    for x0, x1 in ((left, cx - 1.25), (cx + 1.25, right)):
        box("Cutaway", ((x0 + x1) / 2, 1.65, front - 0.1), (x1 - x0, 3.3, 0.2))
    box("Cutaway", (cx, 3.13, front - 0.1), (2.5, 0.34, 0.2))
    for x in (cx - 1.34, cx + 1.34):
        box("Cutaway", (x, 1.52, front + 0.035), (0.12, 3.05, 0.22), "Dark")
        box("Cutaway", (x, 1.52, front + 0.16), (0.035, 2.85, 0.025), "Accent")
    for group, x in (("DoorLeft", cx - 0.61), ("DoorRight", cx + 0.61)):
        box(group, (x, 1.40, front - 0.1), (1.20, 2.80, 0.12), "Steel")
        box(group, (x, 1.75, front - 0.025), (0.90, 0.48, 0.025), "Glass")
        box(group, (x, 0.65, front - 0.023), (0.90, 0.04, 0.025), "Accent")
    for ix in range(math.floor(width)):
        x = left + 0.5 + ix
        box("Back", (x, 3.00, back + 0.22), (0.82, 0.12, 0.05), "Accent")
        box("Back", (x, 0.22, back + 0.22), (0.92, 0.36, 0.05), "Dark")
        for vent in range(4):
            box("Back", (x - 0.24 + vent * 0.16, 2.70, back + 0.22), (0.05, 0.18, 0.04), "Steel")
    for side in (left, right):
        inward = 0.115 if side == left else -0.115
        for iz in range(1, math.floor(depth) - 1):
            box("Cutaway", (side + inward, 1.83, back + iz), (0.03, 1.12, 0.76), "Glass")
    box("Roof", (cx, 3.47, cz), (width + 0.12, 0.27, depth + 0.12), "Dark")
    box("Roof", (cx, 3.63, cz), (width - 0.45, 0.12, depth - 0.45))
    for z in (back + 0.24, front - 0.24):
        box("Roof", (cx, 3.71, z), (width - 0.5, 0.04, 0.055), "Accent")
    if kind == "repair":
        for x in (cx - 2.5, cx + 2.5):
            box("Roof", (x, 3.92, cz), (1.4, 0.45, 3.2), "Steel")
            for i in range(10):
                box("Roof", (x, 4.17, cz - 1.35 + i * 0.3), (1.2, 0.06, 0.10), "Dark")
        prop(blocks, "Reactor", cx, cz, 2.4, 1.2, 2.7)
        box("Furniture", (cx, 0.10, cz), (2.4, 0.20, 1.2), "Dark")
    elif kind == "review":
        box("Roof", (cx, 4.0, cz), (width * 0.55, 0.7, 2.2), "Steel", 0.20)
        box("Roof", (cx, 4.02, cz + 1.12), (width * 0.5, 0.4, 0.03), "Glass")
        cylinder("Roof", (cx + width * 0.32, 4.1, back + 1.6), 0.22, 1.1)
        dish = cylinder("Roof", (cx + width * 0.32, 4.7, back + 1.6), 0.95, 0.10, "Ivory")
        dish.rotation_euler.x = 0.65
        prop(blocks, "MapTable", cx, cz, 2.4, 1.2)
        box("Furniture", (cx, 0.58, cz), (2.4, 1.16, 1.2), "Dark")
        box("Furniture", (cx, 1.18, cz), (2.15, 0.04, 0.96), "Glass")
        for i in range(5):
            box("Furniture", (cx - 0.8 + i * 0.4, 1.21, cz), (0.025, 0.015, 0.80), "Accent", 0)
    elif kind == "gym":
        for x in (cx - 3, cx + 3):
            box("Roof", (x, 3.95, cz), (3.6, 0.55, depth - 1.3), "Steel", 0.20)
            box("Roof", (x, 4.25, cz), (3.1, 0.05, 0.10), "Accent")
            prop(blocks, "TrialPod" + str(x), x, cz - 0.6, 1.6, 1.3, 2.2)
            cylinder("Furniture", (x, 0.10, cz - 0.6), 0.70, 0.20, "Dark")
            for dx in (-0.62, 0.62):
                box("Furniture", (x + dx, 1.1, cz - 0.6), (0.10, 2.2, 0.85), "Steel")
                box("Furniture", (x + dx, 1.1, cz - 0.13), (0.04, 1.9, 0.035), "Accent")
    elif kind == "habitat":
        for i in (-1, 0, 1):
            x = cx + i * width * 0.30
            box("Roof", (x, 3.92, cz), (width * 0.28, 0.5, depth - 0.9), "Ivory", 0.23)
            prop(blocks, "Bunk" + str(i), x, back + 1.6, 2.3, 2.0, 1.0)
            box("Furniture", (x, 0.35, back + 1.6), (2.3, 0.70, 2.0), "Steel")
            box("Furniture", (x, 0.78, back + 1.6), (2.1, 0.17, 1.8), "Ivory", 0.10)
            box("Furniture", (x, 0.89, back + 1.9), (2.0, 0.10, 1.1), "Accent", 0.05)
    else:
        box("Roof", (cx, 3.79, cz), (width - 0.8, 0.15, depth - 0.8), "Glass")
        for ix in range(1, math.floor(width)):
            box("Roof", (left + ix, 3.94, cz), (0.09, 0.10, depth - 0.5), "Ivory")
        for x in (cx - 3.2, cx + 3.2):
            prop(blocks, "GrowBed" + str(x), x, cz, 2.0, depth - 3, 1.25)
            box("Furniture", (x, 0.36, cz), (2.0, 0.72, depth - 3), "Steel")
            for z in (cz - 1, cz, cz + 1):
                for dx in (-0.5, 0.5):
                    cylinder("Furniture", (x + dx, 0.88, z), 0.25, 0.34, "Leaf")
                    cylinder("Furniture", (x + dx, 1.12, z), 0.16, 0.20, "Leaf")
    for x in (cx - 2.5, cx + 2.5):
        if kind not in ("habitat", "greenhouse"):
            console(x, back + 0.90, blocks, "Console" + str(x))
    # A shared near-side interaction terminal gives every room an inspectable
    # destination without routing through a large central apparatus.
    console(cx + 2.6, front - 2.05, blocks, "InspectionTerminal")
    bounds = [left + 0.24, back + 0.24, width - 0.48, depth - 0.48]
    markers = {
        "Spawn": [cx, 0, front - 0.85],
        "Console": [cx + 2.6, 0, front - 1.05],
        "Crew": [cx + 1.75, 0, cz - 0.2],
        "Activity": [cx, 2.6, back + 0.5],
        "WalkTarget": [cx - 2, 0, cz + 0.1],
    }
    if kind == "gym":
        markers["WalkTarget"] = [cx, 0, cz - 1.6]
    if kind == "greenhouse":
        markers["Crew"] = [cx, 0, cz]
        markers["WalkTarget"] = [cx, 0, cz]
    if kind == "gym":
        markers["Crew"] = [cx + 1.25, 0, cz - 0.2]
    source = ROOT / "assets-production/structures" / FAMILIES[kind] / "blender" / f"{kind}-building.blend"
    source.parent.mkdir(parents=True, exist_ok=True)
    (OUT / FAMILIES[kind]).mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(compress=True, filepath=str(source))
    # Ordinary material batches, preserving semantic occluder/door groups.
    batches = []
    for (group, mat), objects in GROUPS.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        if len(objects) > 1:
            bpy.ops.object.join()
        obj = bpy.context.object
        obj.name = group + "_" + mat
        batches.append((group, obj))
    for suffix, interior in (("shell", False), ("interior", True)):
        bpy.ops.object.select_all(action="DESELECT")
        for group, obj in batches:
            obj.select_set((group == "Furniture") == interior)
        bpy.ops.export_scene.gltf(
            filepath=str(OUT / FAMILIES[kind] / f"{kind}-{suffix}.glb"),
            export_format="GLB",
            use_selection=True,
            export_animations=False,
        )
    manifest[kind] = {
        "footprint": [left, back, width, depth],
        "bounds": bounds,
        "blocks": blocks,
        "markers": markers,
        "threshold": [cx, 0, front],
        "accent": list(accent),
    }
(ROOT / "assets-production/structures/colony-layout.json").write_text(json.dumps(manifest, indent=2) + "\n")
print("COLONY_AUTHORED", list(manifest))
