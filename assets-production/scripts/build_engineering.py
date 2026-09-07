"""Author Engineering architecture around the reviewed Meshy centerpiece.

Blender 5.2.1. Coordinates are Godot metres, converted at creation. Walking
surfaces remain at colony level; railings and machinery never cross the route.
"""

import json
import math
from pathlib import Path

import bpy

# Background production saves selected sources without accumulating recovery copies.
bpy.context.preferences.filepaths.save_version = 0
from mathutils import Vector

assert bpy.app.version[:3] == (5, 2, 1)
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "apps/world/assets/structures/engineering"
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
MATS = {}
GROUPS = {}
for name, color, metal, rough, emission in [
    ("Ivory", (0.55, 0.51, 0.43), 0.5, 0.36, 0),
    ("Edge", (0.72, 0.68, 0.58), 0.4, 0.35, 0),
    ("Graphite", (0.045, 0.055, 0.058), 0.75, 0.4, 0),
    ("Floor", (0.10, 0.13, 0.14), 0.6, 0.45, 0),
    ("Copper", (0.34, 0.15, 0.065), 0.8, 0.3, 0),
    ("Rubber", (0.012, 0.02, 0.024), 0.05, 0.8, 0),
    ("Amber", (0.95, 0.44, 0.09), 0.2, 0.3, 2.0),
    ("Cyan", (0.045, 0.65, 0.85), 0.2, 0.3, 2.0),
    ("Glass", (0.035, 0.12, 0.15), 0.45, 0.22, 0),
]:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    p = mat.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Metallic"].default_value = metal
    p.inputs["Roughness"].default_value = rough
    p.inputs["Emission Color"].default_value = (*color, 1)
    p.inputs["Emission Strength"].default_value = emission
    MATS[name] = mat


def coord(p):
    return Vector((p[0], -p[2], p[1]))


def finish(obj, group, material):
    obj.name = group + "_" + material
    obj.data.materials.append(MATS[material])
    GROUPS.setdefault((group, material), []).append(obj)
    return obj


def box(group, at, size, mat="Ivory", bevel=0.035):
    bpy.ops.mesh.primitive_cube_add(size=1, location=coord(at))
    obj = bpy.context.object
    obj.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new("Manufactured edge", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(obj, group, mat)


def pipe(group, start, end, radius=0.055, mat="Copper", vertices=12):
    a, b = coord(start), coord(end)
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=(b - a).length, location=(a + b) / 2
    )
    obj = bpy.context.object
    obj.rotation_euler = (b - a).to_track_quat("Z", "Y").to_euler()
    return finish(obj, group, mat)


def cylinder(group, at, radius, height, mat="Graphite", vertices=48):
    return pipe(
        group,
        (at[0], at[1] - height / 2, at[2]),
        (at[0], at[1] + height / 2, at[2]),
        radius,
        mat,
        vertices,
    )


left, back, width, depth = -7.3, -6.75, 10.7, 8.3
right, front = left + width, back + depth
cx, cz = -1.95, -2.6
# Metallic deck with inset panels, service channels and deliberate travel markings.
box("Floor", (cx, 0.08, cz), (width, 0.12, depth), "Graphite")
for x in range(10):
    for z in range(8):
        px = left + (x + 0.5) * width / 10
        pz = back + (z + 0.5) * depth / 8
        box("Floor", (px, 0.15, pz), (width / 10 - 0.035, 0.025, depth / 8 - 0.035), "Floor", 0.008)
        for dx in [-0.4, 0.4]:
            box("Floor", (px + dx, 0.168, pz + 0.38), (0.04, 0.005, 0.04), "Edge", 0)
for x in [cx - 1.45, cx + 1.45]:
    box("Floor", (x, 0.175, -0.1), (0.055, 0.01, 3.0), "Amber", 0)
# Rear and side wall layers: ribbed graphite backing, inset insulation and panels.
box("InteriorRevealBack", (cx, 2.0, back + 0.10), (width, 4, 0.2), "Graphite")
for side in [left + 0.1, right - 0.1]:
    box("Cutaway", (side, 2.0, cz), (0.2, 4, depth), "Graphite")
for i in range(8):
    x = left + 0.68 + i * 1.33
    box("InteriorRevealBack", (x, 2.15, back + 0.23), (1.15, 2.95, 0.14), "Ivory", 0.06)
    box("InteriorRevealBack", (x, 0.45, back + 0.26), (1.12, 0.55, 0.20), "Graphite")
    box("InteriorRevealBack", (x, 3.62, back + 0.34), (1.1, 0.07, 0.12), "Amber", 0.01)
    for offset in [-0.45, 0.45]:
        box("InteriorRevealBack", (x + offset, 2.0, back + 0.36), (0.05, 2.5, 0.045), "Edge", 0.005)
    for row in range(6):
        box(
            "InteriorRevealBack",
            (x - 0.28 + row * 0.11, 3.10, back + 0.32),
            (0.045, 0.24, 0.035),
            "Graphite",
            0.004,
        )
for side in [left + 0.24, right - 0.24]:
    sign = 1 if side < cx else -1
    for i in range(6):
        z = back + 0.72 + i * 1.3
        box("Cutaway", (side, 2.15, z), (0.14, 2.95, 1.15), "Ivory", 0.06)
        box("Cutaway", (side + sign * 0.08, 0.45, z), (0.20, 0.55, 1.12), "Graphite")
        box("Cutaway", (side + sign * 0.12, 3.6, z), (0.12, 0.07, 1.1), "Amber", 0.01)
        box("Cutaway", (side + sign * 0.10, 2.1, z + 0.49), (0.08, 2.9, 0.09), "Edge", 0.01)
# Front shoulders and a deep, layered airlock frame. Opening stays 2.5m clear.
for a, b in [(left, cx - 1.25), (cx + 1.25, right)]:
    x = (a + b) / 2
    box("Cutaway", (x, 1.95, front - 0.1), (b - a, 3.9, 0.2), "Graphite")
    box("Cutaway", (x, 2.0, front - 0.03), (b - a - 0.16, 3.6, 0.23), "Ivory", 0.1)
    box("Cutaway", (x, 0.35, front + 0.05), (b - a - 0.1, 0.4, 0.22), "Graphite")
for x in [cx - 1.42, cx + 1.42]:
    box("Airlock", (x, 1.55, front - 0.02), (0.32, 3.1, 0.48), "Graphite", 0.09)
    box("Airlock", (x, 1.55, front + 0.24), (0.08, 2.75, 0.04), "Amber", 0.01)
box("Airlock", (cx, 3.05, front - 0.02), (3.15, 0.32, 0.5), "Ivory", 0.09)
box("Airlock", (cx, 3.03, front + 0.25), (2.4, 0.055, 0.045), "Amber", 0.01)
for name, x in [("DoorLeft", cx - 0.62), ("DoorRight", cx + 0.62)]:
    box(name, (x, 1.43, front - 0.10), (1.22, 2.85, 0.16), "Graphite", 0.06)
    box(name, (x, 1.43, front + 0.015), (1.08, 2.55, 0.12), "Ivory", 0.09)
    box(name, (x, 1.62, front + 0.08), (0.80, 0.20, 0.025), "Rubber", 0.02)
    box(name, (x, 1.05, front + 0.09), (0.075, 0.5, 0.04), "Amber", 0.01)
# Stepped roof massing: low perimeter and a taller central containment housing.
box("Roof", (cx, 4.03, cz), (width + 0.08, 0.22, depth + 0.08), "Graphite", 0.1)
for x in [left + 1.45, right - 1.45]:
    box("Roof", (x, 4.22, cz), (2.8, 0.36, depth - 0.1), "Ivory", 0.15)
    for i in range(6):
        z = back + 0.7 + i * 1.25
        box("Roof", (x, 4.42, z), (2.5, 0.025, 1.10), "Edge", 0.06)
        box("Roof", (x, 4.44, z), (0.9, 0.05, 0.67), "Graphite", 0.04)
        for j in range(5):
            box("Roof", (x - 0.34 + j * 0.17, 4.48, z), (0.055, 0.06, 0.60), "Ivory", 0.01)
box("Roof", (cx, 4.5, cz - 1.05), (4.1, 1.1, 4.4), "Graphite", 0.25)
box("Roof", (cx, 4.6, cz - 1.05), (3.88, 1.15, 4.15), "Ivory", 0.30)
cylinder("Roof", (cx, 5.22, cz - 1.05), 1.38, 0.20, "Graphite")
for angle in range(0, 360, 30):
    rad = math.radians(angle)
    x = cx + math.cos(rad) * 1.10
    z = cz - 1.05 + math.sin(rad) * 1.10
    box("Roof", (x, 5.34, z), (0.20, 0.08, 0.20), "Copper", 0.03)
# Dense copper circulation loops stay high against the interior walls.
for y in [2.85, 3.05]:
    pipe("InteriorRevealBack", (left + 0.5, y, back + 0.5), (right - 0.5, y, back + 0.5), 0.07)
    for x in [left + 0.5, right - 0.5]:
        pipe("Cutaway", (x, y, back + 0.5), (x, y, front - 0.55), 0.07)
for x in [cx - 1.9, cx + 1.9]:
    pipe("Furniture", (x, 0.3, cz), (x, 2.7, cz), 0.065)
    pipe("Furniture", (x, 2.7, cz), (x, 2.7, back + 0.65), 0.065)
    for y in [0.6, 1.1, 1.6, 2.1]:
        cylinder("Furniture", (x, y, cz), 0.085, 0.065, "Graphite", 16)
# Reactor pedestal and surrounding service deck are flush enough for level walking.
cylinder("Floor", (cx, 0.21, cz), 1.5, 0.10, "Graphite", 64)
for angle in range(0, 360, 15):
    rad = math.radians(angle)
    cylinder(
        "Floor",
        (cx + math.cos(rad) * 1.42, 0.27, cz + math.sin(rad) * 1.42),
        0.035,
        0.025,
        "Edge",
        8,
    )
# Wall consoles, lockers and cable channels fill recesses, leaving the middle free.
blocks = [{"name": "Reactor", "rect": [cx - 1.35, cz - 1.35, 2.7, 2.7], "height": 3.6}]
for x in [left + 1.25, right - 1.25]:
    z = back + 0.75
    blocks.append({"name": "WallConsole", "rect": [x - 0.65, z - 0.38, 1.3, 0.76], "height": 1.65})
    box("Furniture", (x, 0.62, z), (1.3, 1.05, 0.76), "Graphite", 0.08)
    box("Furniture", (x, 1.35, z - 0.16), (1.25, 0.70, 0.18), "Ivory", 0.07)
    box("Furniture", (x, 1.36, z - 0.055), (1.08, 0.46, 0.025), "Glass", 0.02)
    for row in range(4):
        box(
            "Furniture",
            (x - 0.12, 1.20 + row * 0.10, z - 0.034),
            (0.70 - row * 0.12, 0.025, 0.012),
            "Cyan",
            0,
        )
    box("Furniture", (x, 1.06, z + 0.12), (1.15, 0.08, 0.40), "Ivory", 0.03)
    for i in range(6):
        box("Furniture", (x - 0.44 + i * 0.17, 1.11, z + 0.12), (0.07, 0.01, 0.08), "Amber", 0)
# Operator console on the right of the entry lane.
x, z = cx + 2.6, -0.5
blocks.append({"name": "InspectionTerminal", "rect": [x - 0.65, z - 0.4, 1.3, 0.8], "height": 1.5})
box("Furniture", (x, 0.64, z), (0.9, 1.2, 0.65), "Graphite", 0.1)
box("Furniture", (x, 1.22, z), (1.3, 0.15, 0.8), "Ivory", 0.08)
box("Furniture", (x, 1.32, z - 0.12), (1.06, 0.035, 0.45), "Glass", 0.03)
for i in range(5):
    box("Furniture", (x - 0.38 + i * 0.19, 1.345, z - 0.12), (0.07, 0.012, 0.3), "Cyan", 0)
for x in [left + 0.5, right - 0.5]:
    for i in range(3):
        z = back + 2 + i * 0.7
        box("Furniture", (x, 0.64, z), (0.48, 1.1, 0.55), "Graphite", 0.06)
        box("Furniture", (x, 0.68, z + 0.3), (0.40, 0.9, 0.04), "Ivory", 0.04)
# Low perimeter edges keep the cutaway readable without hiding the crew.
for side in [left + 0.1, right - 0.1]:
    box("Floor", (side, 0.40, cz), (0.20, 0.55, depth), "Graphite")
    box("Floor", (side, 0.70, cz), (0.24, 0.05, depth), "Copper")
for x in [left + 0.5, right - 0.5]:
    blocks.append({"name": "Lockers", "rect": [x - 0.24, back + 1.70, 0.48, 2.0], "height": 1.2})
for x in [cx - 1.9, cx + 1.9]:
    blocks.append({"name": "Riser", "rect": [x - 0.10, cz - 0.10, 0.2, 0.2], "height": 2.8})
# Save editable objects before batching, with named groups preserved in exports.
bpy.ops.wm.save_as_mainfile(compress=True,
    filepath=str(ROOT / "assets-production/structures/engineering/blender/engineering-architecture.blend")
)
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
for suffix, interior in [("shell", False), ("interior", True)]:
    bpy.ops.object.select_all(action="DESELECT")
    for group, obj in batches:
        obj.select_set(
            group == "Furniture"
            if interior
            else group in ["Floor", "InteriorRevealBack", "Airlock", "DoorLeft", "DoorRight"]
        )
    bpy.ops.export_scene.gltf(
        filepath=str(OUT / f"engineering-{suffix}.glb"),
        export_format="GLB",
        use_selection=True,
        export_animations=False,
    )
layout = {
    "footprint": [left, back, width, depth],
    "bounds": [left + 0.24, back + 0.24, width - 0.48, depth - 0.48],
    "blocks": blocks,
    "threshold": [cx, 0, front],
    "markers": {
        "Spawn": [cx, 0, 0.7],
        "Console": [cx + 2.6, 0, 0.5],
        "Crew": [right - 1.25, 0, back + 1.55],
        "Activity": [cx, 3.6, back + 0.55],
        "WalkTarget": [cx - 2.5, 0, cz + 0.1],
    },
}
(ROOT / "assets-production/structures/engineering/layout.json").write_text(json.dumps(layout, indent=2) + "\n")
print("ENGINEERING_ARCHITECTURE_EXPORTED")
