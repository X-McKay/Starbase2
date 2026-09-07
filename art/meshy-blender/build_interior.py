"""Author the ivory/cyan engineering cutaway in Blender 5.2.1.

Run in a new background Blender process. All dimensions are metres.
"""

import math
from pathlib import Path

import bpy

assert bpy.app.version[:3] == (5, 2, 1)
root = Path(__file__).resolve().parents[2]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, color, metal=0.0, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metal
    shader.inputs["Roughness"].default_value = 0.48
    if emission:
        shader.inputs["Emission Color"].default_value = (*color, 1)
        shader.inputs["Emission Strength"].default_value = emission
    return mat


ivory = material("Ceramic / warm ivory", (0.72, 0.77, 0.78), 0.15)
graphite = material("Structure / graphite", (0.045, 0.071, 0.083), 0.65)
steel = material("Service rails / titanium", (0.24, 0.32, 0.35), 0.7)
floor = material("Deck / satin ceramic", (0.40, 0.48, 0.51), 0.25)
cyan = material("Decorative cyan lenses", (0.11, 0.8, 0.88), 0.1, 1.4)
amber = material("Safety markings", (0.95, 0.54, 0.08), 0.0)
screen = material("Decorative screen glass", (0.025, 0.12, 0.17), 0.35)


def box(name, location, dimensions, mat, bevel=0.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel:
        modifier = obj.modifiers.new("Manufactured edge radius", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        modifier = obj.modifiers.new("Weighted face normals", "WEIGHTED_NORMAL")
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return obj


# Blender +Y is the back of the room; GLB converts it to Godot -Z.
box("Foundation", (0, 0, -0.13), (10, 10, 0.22), graphite)
for x in range(-5, 5):
    for y in range(-5, 5):
        box("Deck panel", (x + 0.5, y + 0.5, -0.018), (0.97, 0.97, 0.05), floor, 0.009)
for x in (-4.65, 4.65):
    box("Floor service channel", (x, 0, 0.022), (0.17, 9.8, 0.028), graphite, 0.005)
    box("Floor guide light", (x, 0, 0.04), (0.035, 9.4, 0.012), cyan, 0.002)
for x in range(-5, 5):
    center = x + 0.5
    box("Rear wall panel", (center, 4.91, 1.65), (0.97, 0.18, 3.3), ivory)
    box("Rear kick plate", (center, 4.78, 0.24), (0.92, 0.12, 0.4), graphite)
    box("Upper service recess", (center, 4.79, 2.9), (0.78, 0.06, 0.26), graphite)
    for vent in range(5):
        box(
            "Vent louver",
            (center - 0.28 + vent * 0.14, 4.74, 2.9),
            (0.05, 0.05, 0.18),
            steel,
            0.004,
        )
    box("Wall light", (center, 4.77, 3.17), (0.82, 0.05, 0.055), cyan, 0.006)
for side in (-1, 1):
    for y in (2.5, 3.5, 4.5):
        box("Side panel", (side * 4.91, y, 1.65), (0.18, 0.97, 3.3), ivory)
        box("Side inset", (side * 4.79, y, 1.72), (0.06, 0.72, 1.55), graphite)
        box("Side window", (side * 4.75, y, 1.85), (0.03, 0.60, 1.16), screen)
        box("Window sill", (side * 4.72, y, 1.20), (0.12, 0.77, 0.06), cyan)
    box("Cutaway edge", (side * 4.91, -1.2, 0.14), (0.18, 6.1, 0.28), steel)
    box("Door pillar", (side * 1.05, -4.87, 0.30), (0.15, 0.18, 0.60), ivory)
    box("Entrance marker", (side * 1.05, -4.76, 0.31), (0.055, 0.02, 0.44), cyan)

# Back service consoles and side cabinets match their independent collider boxes.
for x in (-3, 3):
    box("Console pedestal", (x, 3.5, 0.5), (1.5, 0.7, 1.0), ivory)
    box("Console fascia", (x, 3.09, 0.74), (1.38, 0.12, 0.35), graphite)
    monitor = box("Monitor housing", (x, 3.38, 1.30), (1.48, 0.16, 0.68), graphite)
    monitor.rotation_euler.x = math.radians(-16)
    box("Monitor display", (x, 3.26, 1.30), (1.31, 0.035, 0.52), screen)
    for row in range(4):
        box(
            "Decorative screen row",
            (x - 0.12, 3.235, 1.12 + row * 0.10),
            (0.93 - row * 0.13, 0.008, 0.023),
            cyan,
            0,
        )
    for knob in range(6):
        box("Console key", (x - 0.5 + knob * 0.20, 3.04, 0.99), (0.075, 0.11, 0.025), cyan, 0.004)
for x in (-3.7, 3.7):
    for y in (-1.4, 1):
        box("Storage locker", (x, y, 0.87), (0.8, 0.8, 1.74), ivory)
        box("Locker inset", (x, y - 0.42, 0.85), (0.65, 0.04, 1.45), graphite)
        for z in (0.35, 0.8, 1.25):
            box("Locker drawer", (x, y - 0.455, z), (0.58, 0.055, 0.35), steel)
            box("Drawer handle", (x, y - 0.49, z + 0.07), (0.25, 0.035, 0.035), ivory)

box("Central apparatus base", (0, 0, 0.10), (2.4, 1.2, 0.2), graphite)
for x in range(10):
    box("Apparatus hazard mark", (-1.07 + x * 0.24, -0.61, 0.13), (0.13, 0.025, 0.10), amber, 0)
for x in (-2.05, 2.05):
    box("Gantry post", (x, 4.5, 1.65), (0.16, 0.20, 3.3), graphite)
    box("Gantry spine", (x, 4.5, 1.65), (0.05, 0.25, 3.0), steel)
box("Gantry beam", (0, 4.5, 3.25), (4.3, 0.27, 0.23), graphite)
box("Gantry task lens", (0, 4.5, 3.11), (3.8, 0.09, 0.025), cyan)
for x in (-1.75, 1.75):
    box("Rear vertical pipe", (x, 4.57, 1.45), (0.12, 0.14, 2.7), steel)
    for z in (0.3, 1.1, 2.0, 2.7):
        box("Pipe clamp", (x, 4.54, z), (0.22, 0.22, 0.08), graphite)

# Preserve all individually editable pieces in the source, then batch shipping
# geometry by material. There are no per-panel runtime scripts or colliders.
bpy.ops.wm.save_as_mainfile(filepath=str(root / "art/meshy-blender/engineering-interior.blend"))
for mat in (ivory, graphite, steel, floor, cyan, amber, screen):
    objects = [
        obj
        for obj in bpy.context.scene.objects
        if obj.type == "MESH" and obj.active_material == mat
    ]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    bpy.context.object.name = mat.name.split(" /")[0]
bpy.ops.export_scene.gltf(
    filepath=str(root / "apps/world/art/meshy/engineering-interior.glb"),
    export_format="GLB",
    export_animations=False,
)
print("INTERIOR_EXPORTED", len(bpy.context.scene.objects), "material batches")
