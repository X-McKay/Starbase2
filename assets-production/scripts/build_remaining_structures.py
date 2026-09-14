"""Build selected frontier structures with Blender 5.2.1; never calls paid APIs.

Godot coordinates in metres. Geometry, door leaves, cutaway and furniture remain
separate. --asset command is the representative slice; default builds all four.
"""

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
assert bpy.app.background, "Use a separate background Blender process"
assert bpy.app.version[:3] == (5, 2, 1)
bpy.context.preferences.filepaths.save_version = 0
parser = argparse.ArgumentParser()
parser.add_argument("--asset", choices=["command", "training", "habitat", "botanical"])
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])
FAMILIES = {"command": "review", "training": "gym", "habitat": "habitat", "botanical": "greenhouse"}
PALETTES = {
    "command": (0.08, 0.57, 0.78),
    "training": (0.58, 0.33, 0.78),
    "habitat": (0.85, 0.40, 0.12),
    "botanical": (0.20, 0.64, 0.36),
}
GROUPS = {}
MATS = {}


def coord(p):
    return Vector((p[0], -p[2], p[1]))


def finish(obj, group, mat):
    obj.name = group + "_" + mat
    obj.data.materials.append(MATS[mat])
    GROUPS.setdefault((group, mat), []).append(obj)
    return obj


def box(group, at, size, mat="Ivory", bevel=0.035):
    bpy.ops.mesh.primitive_cube_add(size=1, location=coord(at))
    obj = bpy.context.object
    obj.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new("Manufactured edges", "BEVEL")
        mod.width = min(bevel, min(size) * 0.35)
        mod.segments = 3
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(obj, group, mat)


def pipe(group, a, b, r=0.045, mat="Steel", vertices=16):
    a, b = coord(a), coord(b)
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=r, depth=(b - a).length, location=(a + b) / 2
    )
    obj = bpy.context.object
    obj.rotation_euler = (b - a).to_track_quat("Z", "Y").to_euler()
    return finish(obj, group, mat)


def cylinder(group, at, r, h, mat="Steel"):
    return pipe(group, (at[0], at[1] - h / 2, at[2]), (at[0], at[1] + h / 2, at[2]), r, mat, 32)


def label(group, text, at, size=0.26, mat="Edge"):
    bpy.ops.object.text_add(location=coord(at))
    obj = bpy.context.object
    obj.data.body = text
    obj.data.align_x = "CENTER"
    obj.data.size = size
    obj.data.extrude = 0.002
    obj.rotation_euler = (math.pi / 2, 0, 0)
    bpy.ops.object.convert(target="MESH")
    return finish(bpy.context.object, group, mat)


def block(name, x, z, w, d, h=1.4):
    blocks.append({"name": name, "rect": [x - w / 2, z - d / 2, w, d], "height": h})


def console(x, z, w=1.5):
    box("Furniture", (x, 0.6, z), (w, 1.05, 0.75), "Graphite", 0.1)
    box("Furniture", (x, 1.30, z - 0.20), (w, 0.65, 0.20), "Ivory", 0.07)
    box("Furniture", (x, 1.30, z - 0.08), (w - 0.13, 0.48, 0.035), "Glass", 0.025)
    for i in range(4):
        box(
            "Furniture",
            (x - 0.1, 1.17 + i * 0.09, z - 0.055),
            (w * 0.58 - i * 0.13, 0.015, 0.015),
            "Accent",
            0,
        )
    box("Furniture", (x, 1.01, z + 0.25), (w - 0.12, 0.07, 0.32), "Steel")
    for i in range(6):
        box(
            "Furniture",
            (x - w * 0.36 + i * w * 0.14, 1.053, z + 0.25),
            (0.075, 0.014, 0.12),
            "Edge",
            0,
        )


def locker(x, z):
    box("Furniture", (x, 1.16, z), (0.8, 2.1, 0.68), "Ivory", 0.07)
    box("Furniture", (x, 1.18, z + 0.36), (0.69, 1.9, 0.04), "Steel")
    box("Furniture", (x + 0.22, 1.12, z + 0.39), (0.05, 0.34, 0.05), "Edge")
    for i in range(4):
        box("Furniture", (x, 1.82 + i * 0.06, z + 0.39), (0.43, 0.018, 0.012), "Graphite", 0)


def chair(x, z):
    cylinder("Furniture", (x, 0.38, z), 0.10, 0.55)
    cylinder("Furniture", (x, 0.15, z), 0.38, 0.10, "Graphite")
    box("Furniture", (x, 0.73, z), (0.68, 0.18, 0.68), "Fabric", 0.09)
    box("Furniture", (x, 1.10, z - 0.27), (0.68, 0.75, 0.16), "Fabric", 0.09)


def roof_vault(x, z, w, d, h=1.0, mat="Ivory"):
    # Deliberate tapered manufactured canopy, front/back independent of room.
    for side in [-1, 1]:
        obj = box("Roof", (x + side * w * 0.24, 3.91 + h * 0.22, z), (w * 0.53, 0.15, d), mat, 0.06)
        obj.rotation_euler.y = side * 0.32
    box("Roof", (x, 4.03 + h * 0.4, z), (0.24, 0.17, d), "Steel")


def reveal_arch(group, x, z, radius, spring, rise, mat="Ivory"):
    """An open section above head clearance; it retains the roof silhouette."""
    points = [
        (x + radius * math.cos(i * math.pi / 16), spring + rise * math.sin(i * math.pi / 16), z)
        for i in range(17)
    ]
    for a, b in zip(points, points[1:], strict=False):
        pipe(group, a, b, 0.105, mat, 12)


def pointed_leaf(group, at, length, width, heading, mat="Moss"):
    """A small folded pointed blade, deliberately authored without box edges."""
    x, y, z = at
    outline = [
        (-0.5, 0, 0),
        (-0.12, -0.5, 0.025),
        (0.5, 0, 0.10),
        (-0.12, 0.5, 0.025),
        (-0.05, 0, 0.12),
    ]
    vertices = []
    for along, across, lift in outline:
        dx, dz = along * length, across * width
        vertices.append(
            coord(
                (
                    x + dx * math.cos(heading) - dz * math.sin(heading),
                    y + lift,
                    z + dx * math.sin(heading) + dz * math.cos(heading),
                )
            )
        )
    mesh = bpy.data.meshes.new("Folded leaf")
    mesh.from_pydata(vertices, [], [(4, 1, 0), (4, 2, 1), (4, 3, 2), (4, 0, 3)])
    mesh.update()
    obj = bpy.data.objects.new("Leaf blade", mesh)
    bpy.context.collection.objects.link(obj)
    return finish(obj, group, mat)


layout_path = ROOT / "assets-production/structures/colony-layout.json"
layout = json.loads(layout_path.read_text())
for asset, kind in FAMILIES.items():
    if args.asset and args.asset != asset:
        continue
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    GROUPS.clear()
    MATS.clear()
    for name, color, metal, rough, glow in [
        ("Ivory", (0.55, 0.51, 0.43), 0.4, 0.40, 0),
        ("Edge", (0.76, 0.72, 0.62), 0.45, 0.32, 0),
        ("Graphite", (0.042, 0.056, 0.060), 0.6, 0.40, 0),
        ("Steel", (0.19, 0.25, 0.27), 0.65, 0.35, 0),
        ("Floor", (0.13, 0.17, 0.17), 0.25, 0.65, 0),
        ("Glass", (0.025, 0.10, 0.13), 0.45, 0.22, 0),
        ("Accent", PALETTES[asset], 0.2, 0.35, 1.1),
        ("Warm", (0.95, 0.64, 0.29), 0.15, 0.4, 0.7),
        ("Copper", (0.35, 0.17, 0.075), 0.75, 0.38, 0),
        ("Fabric", (0.19, 0.27, 0.27), 0, 0.94, 0),
        ("Leaf", (0.13, 0.31, 0.10), 0, 0.85, 0),
        ("Soil", (0.095, 0.058, 0.026), 0, 1, 0),
        ("Wood", (0.32, 0.16, 0.065), 0.05, 0.72, 0),
        ("Linen", (0.49, 0.32, 0.19), 0, 0.97, 0),
        ("Moss", (0.23, 0.40, 0.12), 0, 0.88, 0),
    ]:
        mat = bpy.data.materials.new(asset + "_" + name)
        mat.use_nodes = True
        p = mat.node_tree.nodes.get("Principled BSDF")
        p.inputs["Base Color"].default_value = (*color, 1)
        p.inputs["Metallic"].default_value = metal
        p.inputs["Roughness"].default_value = rough
        p.inputs["Emission Color"].default_value = (*color, 1)
        p.inputs["Emission Strength"].default_value = glow
        MATS[name] = mat
    data = layout[kind]
    w, d = {
        "command": (16.0, 12.0),
        "training": (16.0, 12.0),
        "habitat": (18.0, 13.0),
        "botanical": (17.0, 12.0),
    }[asset]
    data["footprint"] = [-w / 2, 1.55 - d, w, d]
    data["bounds"] = [-w / 2 + 0.24, 1.55 - d + 0.24, w - 0.48, d - 0.48]
    data["threshold"] = [0, 0, 1.55]
    cz = 1.55 - d / 2
    data["markers"] = {
        "Spawn": [0, 0, 0.70],
        "Console": [2.6, 0, 0.50],
        "Crew": [1.75, 0, cz - 0.2],
        "Activity": [0, 2.6, 2.05 - d],
        "WalkTarget": [-2, 0, cz + 0.1],
    }
    if asset == "command":
        data["markers"]["Console"] = [0, 0, cz + 2.0]
        data["markers"]["Crew"] = [2.4, 0, cz - 0.2]
        data["markers"]["WalkTarget"] = [-3, 0, cz + 0.1]
    if asset == "training":
        data["markers"]["Console"] = [-3.4, 0, cz + 1.9]
        data["markers"]["Crew"] = [1.25, 0, cz - 0.2]
        data["markers"]["WalkTarget"] = [0, 0, cz - 1.6]
    if asset == "botanical":
        data["markers"]["Console"] = [0, 0, 1.55 - d + 2.4]
        data["markers"]["Crew"] = [0, 0, cz]
        data["markers"]["WalkTarget"] = [0, 0, cz]
    if asset == "habitat":
        data["markers"]["Console"] = [-0.7, 0, cz + 2.3]
    left, back, w, d = data["footprint"]
    right, front = left + w, back + d
    cx, cz = left + w / 2, back + d / 2
    blocks = []
    box("Floor", (cx, 0.08, cz), (w, 0.13, d), "Graphite")
    for ix in range(math.ceil(w)):
        for iz in range(math.ceil(d)):
            x = left + (ix + 0.5) * w / math.ceil(w)
            z = back + (iz + 0.5) * d / math.ceil(d)
            box(
                "Floor",
                (x, 0.155, z),
                (w / math.ceil(w) - 0.035, 0.025, d / math.ceil(d) - 0.035),
                "Floor",
                0.006,
            )
    # A quiet central approach strip; ornamental paint has no navigation authority.
    for x in [cx - 1.04, cx + 1.04]:
        box("Floor", (x, 0.174, front - 1.45), (0.035, 0.008, 2.6), "Accent", 0)
    box("InteriorRevealBack", (cx, 1.88, back + 0.10), (w, 3.76, 0.20), "Graphite")
    for x in [left + 0.10, right - 0.10]:
        box("Cutaway", (x, 1.88, cz), (0.20, 3.76, d), "Graphite")
    for i in range(math.floor(w / 1.35)):
        x = left + 0.75 + i * 1.35
        box("InteriorRevealBack", (x, 1.88, back + 0.23), (1.20, 3.35, 0.15), "Steel", 0.06)
        box("InteriorRevealBack", (x, 0.50, back + 0.32), (1.13, 0.63, 0.15), "Steel")
        box("InteriorRevealBack", (x, 3.43, back + 0.34), (1.03, 0.07, 0.08), "Warm")
        for j in range(5):
            box(
                "InteriorRevealBack",
                (x - 0.32 + j * 0.16, 2.99, back + 0.32),
                (0.05, 0.23, 0.02),
                "Graphite",
                0,
            )
    for side in [left, right]:
        inward = 1 if side == left else -1
        for i in range(math.floor(d / 1.5)):
            z = back + 0.82 + i * 1.5
            box("Cutaway", (side + inward * 0.18, 1.95, z), (0.14, 3.42, 1.32), "Ivory", 0.055)
            box("Cutaway", (side + inward * 0.27, 2.15, z), (0.05, 1.1, 1.12), "Glass")
            box("Cutaway", (side + inward * 0.30, 0.55, z), (0.11, 0.72, 1.2), "Steel")
    for a, b in [(left, cx - 1.25), (cx + 1.25, right)]:
        x = (a + b) / 2
        box("Cutaway", (x, 1.88, front - 0.10), (b - a, 3.76, 0.2), "Graphite")
        box("Cutaway", (x, 1.93, front + 0.015), (b - a - 0.14, 3.40, 0.18), "Ivory", 0.08)
        box("Cutaway", (x, 2.15, front + 0.12), (b - a - 0.42, 1.00, 0.04), "Glass")
        box("Cutaway", (x, 0.44, front + 0.10), (b - a - 0.08, 0.65, 0.22), "Steel")
        for j in range(max(1, math.floor((b - a) / 1.25))):
            px = a + 0.55 + j * 1.25
            box("Cutaway", (px, 1.91, front + 0.16), (0.075, 3.22, 0.13), "Edge")
    for x in [cx - 1.42, cx + 1.42]:
        box("CutawayEntrance", (x, 1.52, front), (0.32, 3.04, 0.48), "Graphite", 0.07)
        box("CutawayEntrance", (x, 1.50, front + 0.26), (0.07, 2.75, 0.04), "Accent")
    box("CutawayEntrance", (cx, 3.15, front), (3.2, 0.38, 0.50), "Graphite", 0.07)
    box("CutawayEntrance", (cx, 3.16, front - 0.38), (3.1, 0.45, 1.2), "Graphite", 0.06)
    label("CutawayEntrance", asset.upper(), (cx, 3.07, front + 0.265), 0.25)
    for group, x in [("DoorLeft", cx - 0.62), ("DoorRight", cx + 0.62)]:
        box(group, (x, 1.42, front - 0.10), (1.22, 2.84, 0.16), "Steel", 0.06)
        box(group, (x, 1.42, front + 0.01), (1.06, 2.56, 0.10), "Ivory", 0.05)
        box(group, (x, 1.77, front + 0.07), (0.84, 0.33, 0.024), "Glass")
        box(group, (x, 0.70, front + 0.07), (0.77, 0.035, 0.02), "Accent", 0)
    box("Roof", (cx, 3.83, cz), (w + 0.08, 0.20, d + 0.08), "Graphite", 0.06)
    # Fascia, corner shoes, external services stay within the established pad.
    for z in [back + 0.1, front - 0.1]:
        box("Roof", (cx, 3.83, z), (w, 0.28, 0.3), "Edge")
        box("Roof", (cx, 3.98, z), (w - 0.4, 0.035, 0.045), "Accent", 0)
    for x in [left + 0.27, right - 0.27]:
        for z in [back + 0.35, front - 0.35]:
            box("Cutaway", (x, 1.89, z), (0.40, 3.78, 0.48), "Steel", 0.065)
    # Inspection now occurs at each room's meaningful equipment/commons marker;
    # the generic entrance kiosk is deliberately absent from all four rooms.
    if asset == "command":
        roof_vault(cx - 1.2, cz, 8.8, d - 0.65, 1.3)
        box("Roof", (cx - 1.2, 4.35, cz + 0.6), (7.9, 0.5, 2.4), "Steel", 0.15)
        box("Roof", (cx - 1.2, 4.37, cz + 1.82), (7.4, 0.33, 0.025), "Glass")
        for z in [cz - 1.0, cz, cz + 1.0]:
            box("Roof", (left + 0.8, 4.03, z), (1.0, 0.20, 0.70), "Steel")
            for i in range(5):
                box("Roof", (left + 0.48 + i * 0.16, 4.15, z), (0.05, 0.08, 0.58), "Graphite")
        # Recessed mission table, two analysis desks, communications rack.
        block("MissionTable", cx, cz, 3.5, 2.5, 1.6)
        box("Furniture", (cx, 0.22, cz), (3.4, 0.3, 2.4), "Graphite", 0.12)
        for x in [cx - 3.2, cx + 3.2]:
            block("AnalysisDesk", x, back + 1.4, 3.7, 1.2, 2.6)
            chair(x, back + 2.85)
            block("AnalysisChair", x, back + 2.85, 0.7, 0.72, 1.5)
        for x in [left + 0.85, right - 0.85]:
            locker(x, back + 1.1)
            block("CommsRack", x, back + 1.1, 0.8, 0.78, 2.3)
        for x in [cx - 6.7, cx + 6.7]:
            block("SideAnalysis", x, cz, 1.2, 3.7, 2.6)
        box("Furniture", (cx - 4.6, 0.55, front - 2.1), (2.9, 0.72, 0.9), "Steel", 0.10)
        box("Furniture", (cx - 4.6, 0.96, front - 2.1), (2.8, 0.15, 0.85), "Fabric", 0.09)
        block("BriefingBench", cx - 4.6, front - 2.1, 3.0, 1.0, 1.2)
        for x in [-2.15, 2.15]:
            box("Floor", (x, 0.18, cz), (0.035, 0.008, 3.1), "Accent", 0)
        for z in [cz - 1.55, cz + 1.55]:
            box("Floor", (cx, 0.18, z), (4.3, 0.008, 0.035), "Accent", 0)
        # Preserve the bridge silhouette during cutaway. High ribs stay above
        # navigation; perimeter uprights stay in the existing wall envelope.
        for z in [back + 0.50, cz - 1.75]:
            points = [
                (left + 0.16, 3.10, z),
                (left + 1.65, 4.10, z),
                (cx - 3.25, 4.48, z),
                (cx + 3.25, 4.48, z),
                (right - 1.65, 4.10, z),
                (right - 0.16, 3.10, z),
            ]
            for a, b in zip(points, points[1:], strict=False):
                pipe("InteriorRevealBridge", a, b, 0.15, "Ivory", 12)
                pipe(
                    "InteriorRevealBridge",
                    (a[0], a[1] - 0.19, a[2]),
                    (b[0], b[1] - 0.19, b[2]),
                    0.045,
                    "Warm",
                    12,
                )
            for x in [left + 0.16, right - 0.16]:
                box("InteriorRevealBridge", (x, 2.05, z), (0.17, 2.1, 0.32), "Steel")
        # Deep observation glazing, with mullions and a continuous sill, gives
        # Command a distinct back wall without inventing another physical room.
        for x in [cx - 4.75, cx, cx + 4.75]:
            box(
                "InteriorRevealObservation",
                (x, 2.47, back + 0.42),
                (4.48, 1.84, 0.13),
                "Graphite",
                0.08,
            )
            box(
                "InteriorRevealObservation",
                (x, 2.49, back + 0.50),
                (4.23, 1.59, 0.04),
                "Glass",
                0.04,
            )
            for dx in [-1.42, 0, 1.42]:
                box(
                    "InteriorRevealObservation",
                    (x + dx, 2.49, back + 0.54),
                    (0.055, 1.62, 0.07),
                    "Steel",
                )
            box("InteriorRevealObservation", (x, 1.51, back + 0.46), (4.5, 0.18, 0.27), "Ivory")
            box("InteriorRevealObservation", (x, 3.45, back + 0.48), (4.48, 0.06, 0.08), "Accent")
        # The raised plinth remains wholly within MissionTable collision.
        for y, size, mat in [
            (0.20, (3.48, 0.12, 2.48), "Steel"),
            (0.29, (3.40, 0.09, 2.40), "Graphite"),
        ]:
            box("Furniture", (cx, y, cz), size, mat, 0.10)
        for x in [-1.62, 1.62]:
            box("Furniture", (cx + x, 0.36, cz), (0.045, 0.045, 2.16), "Accent", 0)
        # Flush floor inlays define bridge work zones without physical risers.
        for x in [cx - 3.2, cx + 3.2]:
            box("Floor", (x, 0.178, back + 2.15), (4.15, 0.012, 3.3), "Graphite", 0.06)
            box("Floor", (x, 0.187, back + 3.76), (3.8, 0.008, 0.05), "Copper", 0)
        # Equipment niches and cable trays complete the bridge without occupying aisles.
        for x in [left + 0.28, right - 0.28]:
            box("InteriorRevealBridge", (x, 2.65, cz + 0.4), (0.32, 0.80, 2.8), "Graphite", 0.06)
            for k in range(5):
                box(
                    "InteriorRevealBridge",
                    (x, 2.65, cz - 0.7 + k * 0.5),
                    (0.39, 0.61, 0.35),
                    "Ivory",
                    0.035,
                )
                box(
                    "InteriorRevealBridge",
                    (x, 2.95, cz - 0.7 + k * 0.5),
                    (0.40, 0.035, 0.28),
                    "Copper",
                )
            pipe(
                "InteriorRevealBridge", (x, 3.35, back + 1.0), (x, 3.35, front - 2.0), 0.11, "Steel"
            )
        for k in range(3):
            box(
                "Furniture",
                (cx - 5.4 + k * 0.72, 0.52, front - 2.1),
                (0.57, 0.58, 0.65),
                "Graphite",
                0.06,
            )
            box(
                "Furniture", (cx - 5.4 + k * 0.72, 0.65, front - 1.76), (0.30, 0.06, 0.03), "Copper"
            )
        label("InteriorRevealBack", "OBSERVATION / ANALYSIS", (cx, 3.66, back + 0.40), 0.22)
    elif asset == "training":
        for x in [cx - 3.7, cx + 3.7]:
            roof_vault(x, cz, 5.65, d - 0.65, 1.2, "Steel")
            for z in [cz - 2.5, cz, cz + 2.5]:
                box("Roof", (x, 4.55, z), (4.8, 0.1, 0.11), "Accent")
        for x in [cx - 3.4, cx + 3.4]:
            block("Simulator", x, cz - 0.2, 2.35, 2.35, 2.8)
            cylinder("Furniture", (x, 0.20, cz - 0.2), 1.12, 0.16, "Graphite")
        # Distinct rear exercise bar and near-side equipment storage.
        for x in [cx - 1.0, cx + 1.0]:
            pipe("Furniture", (x, 0.2, back + 0.7), (x, 2.65, back + 0.7), 0.075)
        pipe("Furniture", (cx - 1, 2.65, back + 0.7), (cx + 1, 2.65, back + 0.7), 0.06)
        block("ExerciseFrame", cx, back + 0.7, 2.2, 0.6, 2.8)
        for x in [cx - 3.4, cx + 3.4]:
            block("ResistanceBench", x, back + 1.5, 2.5, 1.3, 2.8)
        for x in [left + 0.85, left + 1.8]:
            locker(x, front - 1)
            block("TrainingLocker", x, front - 1, 0.8, 0.75, 2.3)
        # Wall-mounted resistance equipment, kept outside the main aisle.
        for x in [cx - 5.6, cx + 5.6]:
            box("Furniture", (x, 1.30, back + 0.55), (0.72, 2.3, 0.25), "Graphite")
            pipe("Furniture", (x, 2.3, back + 0.8), (x, 1.1, back + 0.8), 0.035, "Copper")
            pipe(
                "Furniture", (x - 0.22, 1.1, back + 0.8), (x + 0.22, 1.1, back + 0.8), 0.06, "Steel"
            )
            block("ResistanceStation", x, back + 0.60, 0.9, 0.7, 2.5)
        # A recovery bench, folded towels and bottle shelf opposite the lockers.
        block("RecoveryBench", cx + 4.7, front - 1.15, 3.1, 0.94, 1.2)
        box("Furniture", (cx + 4.7, 0.57, front - 1.15), (3.0, 0.76, 0.84), "Graphite", 0.10)
        box("Furniture", (cx + 4.7, 0.99, front - 1.15), (3.05, 0.14, 0.90), "Fabric", 0.10)
        for k in range(3):
            box(
                "Furniture",
                (cx + 3.9, 1.10 + k * 0.055, front - 1.15),
                (0.65, 0.05, 0.52),
                "Linen",
                0.04,
            )
        for dx in [0, 0.33, 0.66]:
            cylinder("Furniture", (cx + 5.0 + dx, 1.22, front - 1.15), 0.09, 0.31, "Copper")
        # Flush lane endings and rack outlines read as practice space, not status.
        for x in [cx - 3.4, cx + 3.4]:
            for dx in [-1.35, 1.35]:
                box("Floor", (x + dx, 0.188, cz - 0.2), (0.08, 0.008, 2.75), "Linen", 0)
        label("InteriorRevealBack", "SIMULATION / PRACTICE", (cx, 3.03, back + 0.36), 0.25)
        for x in [cx - 3.4, cx + 3.4]:
            # Paired barrel sections survive the exterior fade; colored mats
            # define practice zones while the middle stays a clear circulation aisle.
            for z in [back + 0.46, cz - 0.2]:
                reveal_arch("InteriorRevealVault", x, z, 3.12, 3.0, 1.4, "Steel")
            pipe("InteriorRevealVault", (x, 4.4, back + 0.46), (x, 4.4, cz - 0.2), 0.08, "Accent")
            # Longitudinal beams tie the retained middle section back into the
            # rear structure; all beam surfaces stay above 3.2 m clearance.
            for dx in [-2.55, 2.55]:
                y = 3.0 + 1.4 * math.sqrt(1.0 - (dx / 3.12) ** 2)
                pipe(
                    "InteriorRevealVault",
                    (x + dx, y, back + 0.46),
                    (x + dx, y, cz - 0.2),
                    0.10,
                    "Steel",
                    12,
                )
                box("InteriorRevealVault", (x + dx, 3.34, back + 0.31), (0.25, 0.98, 0.18), "Ivory")
            box("Floor", (x, 0.181, cz - 0.3), (4.7, 0.012, 4.25), "Graphite", 0.09)
            for dx in [-2.3, 2.3]:
                box("Floor", (x + dx, 0.190, cz - 0.3), (0.065, 0.008, 4.1), "Accent", 0)
            box("Floor", (x, 0.181, back + 1.5), (3.0, 0.012, 2.0), "Fabric", 0.08)
            box("InteriorRevealPractice", (x, 2.42, back + 0.42), (3.2, 1.05, 0.10), "Graphite")
            for dx in [-1.35, 1.35]:
                box(
                    "InteriorRevealPractice",
                    (x + dx, 2.42, back + 0.50),
                    (0.08, 0.85, 0.03),
                    "Accent",
                )
        label("InteriorRevealPractice", "A / BASELINE", (cx - 3.4, 2.68, back + 0.49), 0.24)
        label("InteriorRevealPractice", "B / CANDIDATE", (cx + 3.4, 2.68, back + 0.49), 0.24)
    elif asset == "habitat":
        for x in [cx - w * 0.31, cx, cx + w * 0.31]:
            roof_vault(x, cz, w * 0.30, d - 0.6, 1.0)
            box("Roof", (x, 4.40, cz), (w * 0.22, 0.12, 2.3), "Glass")
        for i in [-1, 0, 1]:
            x = cx + i * w * 0.29
            block("SleepPod", x, back + 1.6, 3.1, 2.1, 2.7)
        block("Galley", left + 1.25, cz + 0.6, 1.7, 2.8, 2.3)
        # Dining sits west of the central aisle; low seats expose the tabletop.
        tx, tz = cx - 3.8, cz + 2.3
        block("CommonsTable", tx, tz, 3.4, 1.7, 1.05)
        box("Furniture", (tx, 1.0, tz), (3.4, 0.16, 1.7), "Wood", 0.20)
        box("Furniture", (tx, 0.56, tz), (1.6, 0.72, 0.65), "Graphite", 0.12)
        for dx in [-1.0, 1.0]:
            for side in [-1, 1]:
                x, z = tx + dx, tz + side * 1.45
                block("DiningChair", x, z, 0.78, 0.72, 0.94)
                for foot in [-0.25, 0.25]:
                    pipe("Furniture", (x + foot, 0.17, z), (x + foot, 0.56, z), 0.05, "Wood")
                box("Furniture", (x, 0.59, z), (0.76, 0.17, 0.66), "Fabric", 0.12)
                box("Furniture", (x, 0.80, z + side * 0.28), (0.74, 0.36, 0.12), "Fabric", 0.10)
                box(
                    "Furniture",
                    (tx + dx, 1.095, tz + side * 0.35),
                    (0.56, 0.016, 0.44),
                    "Linen",
                    0.03,
                )
                cylinder(
                    "Furniture", (tx + dx + 0.22, 1.18, tz + side * 0.32), 0.085, 0.16, "Ivory"
                )
        cylinder("Furniture", (tx, 1.17, tz), 0.22, 0.20, "Copper")
        for k in range(7):
            pointed_leaf("Furniture", (tx, 1.31 + k * 0.025, tz), 0.5, 0.23, k * 2.4, "Leaf")
        # Generous east lounge, with a low table and an unobstructed central aisle.
        sx, sz = right - 1.2, cz + 1.2
        # Selected Meshy upholstered sofa is instanced by the connector.
        block("Sofa", sx, sz, 1.5, 3.65, 1.45)
        box("Furniture", (cx + 5.25, 0.65, sz), (1.7, 0.16, 2.1), "Wood", 0.18)
        box("Furniture", (cx + 5.25, 0.35, sz), (1.25, 0.45, 1.6), "Graphite", 0.10)
        block("LoungeTable", cx + 5.25, sz, 1.7, 2.1, 0.75)
        for k in range(3):
            box(
                "Furniture",
                (cx + 5.0, 0.755 + k * 0.045, sz - 0.45),
                (0.52, 0.04, 0.40),
                "Linen" if k % 2 else "Fabric",
                0.015,
            )
        cylinder("Furniture", (cx + 5.4, 0.85, sz + 0.45), 0.10, 0.23, "Ivory")
        box("Floor", (cx + 6.05, 0.19, sz), (4.9, 0.012, 4.8), "Linen", 0.08)
        label("InteriorRevealBack", "REST / SHARED LIVING", (cx, 3.05, back + 0.36), 0.26)
        # Capsule privacy wings stay inside the existing sleeping-unit blockers.
        for i in [-1, 0, 1]:
            x = cx + i * w * 0.29
            for dx in [-1.48, 1.48]:
                box(
                    "InteriorRevealAlcove",
                    (x + dx, 1.17, back + 1.6),
                    (0.12, 2.1, 1.95),
                    "Wood",
                    0.05,
                )
                box("InteriorRevealAlcove", (x + dx, 2.23, back + 1.6), (0.15, 0.065, 1.94), "Warm")
            reveal_arch("InteriorRevealAlcove", x, back + 0.55, 1.53, 2.3, 0.6)
            box("Floor", (x, 0.18, back + 2.35), (3.06, 0.016, 3.1), "Linen", 0.08)
        # Broad wood deck and woven rug visually pull kitchen, dining and lounge
        # together. These are flush surfaces, never physical risers.
        for i in range(18):
            box(
                "Floor",
                (cx - 1.0, 0.182, cz + 0.05 + i * 0.25),
                (w - 3.4, 0.012, 0.23),
                "Wood",
                0.005,
            )
        box("Floor", (tx, 0.195, tz), (4.8, 0.012, 4.0), "Linen", 0.09)
        # Bedside storage and warm sconces give each capsule an individual alcove.
        for i in [-1, 0, 1]:
            x, z = cx + i * w * 0.29 + 1.92, back + 1.70
            block("Bedside", x, z, 0.64, 0.78, 0.98)
            box("Furniture", (x, 0.57, z), (0.64, 0.78, 0.78), "Wood", 0.065)
            for y in [0.39, 0.68]:
                box("Furniture", (x, y, z + 0.40), (0.48, 0.23, 0.025), "Ivory", 0.02)
                box("Furniture", (x, y, z + 0.43), (0.20, 0.035, 0.03), "Copper")
            cylinder("Furniture", (x, 1.10, z), 0.15, 0.18, "Graphite")
            cylinder("Furniture", (x, 1.33, z), 0.22, 0.30, "Warm")
        # Retained wall niches and ceiling service rails, safely above circulation.
        for x in [left + 0.30, right - 0.30]:
            for y in [1.5, 2.25]:
                box("InteriorRevealDomestic", (x, y, cz + 0.85), (0.48, 0.12, 3.5), "Wood", 0.035)
            for k in range(6):
                box(
                    "InteriorRevealDomestic",
                    (x, 1.74, cz - 0.4 + k * 0.38),
                    (0.24, 0.38, 0.16),
                    "Linen" if k % 2 else "Fabric",
                    0.015,
                )
            pipe(
                "InteriorRevealDomestic",
                (x, 3.15, back + 0.5),
                (x, 3.15, front - 1.2),
                0.10,
                "Graphite",
            )
        # The galley task light and overhead cupboards share its collision envelope.
        box(
            "InteriorRevealDomestic",
            (left + 0.4, 2.58, cz + 0.6),
            (0.58, 0.65, 2.75),
            "Ivory",
            0.07,
        )
        box("InteriorRevealDomestic", (left + 0.71, 2.22, cz + 0.6), (0.08, 0.05, 2.55), "Warm")
        for x in [left + 0.16, right - 0.16]:
            box("InteriorRevealDomestic", (x, 1.64, cz + 1.8), (0.12, 1.25, 4.0), "Wood", 0.03)
            box("InteriorRevealDomestic", (x, 2.3, cz + 1.8), (0.17, 0.07, 4.1), "Warm")
    else:
        # Glazed clerestory, bright ribs and a separate water-service spine.
        roof_vault(cx - 1.2, cz, w - 3.2, d - 0.65, 1.4, "Glass")
        for i in range(9):
            x = left + 0.6 + i * (w - 3) / 8
            pipe("Roof", (x, 3.92, back + 0.35), (x, 4.75, cz), 0.065, "Edge")
            pipe("Roof", (x, 4.75, cz), (x, 3.92, front - 0.35), 0.065, "Edge")
        for x in [cx - 3.3, cx + 3.3]:
            block("Cultivation", x, cz - 0.85, 2.0, 5.2, 2.8)
            box("Furniture", (x, 0.3, cz - 0.85), (2.0, 0.4, 5.2), "Steel", 0.09)
        block("ResearchBench", cx, back + 1.0, 2.8, 1.1, 2.0)
        block("WaterSystem", right - 1.05, back + 1.1, 1.35, 1.55, 2.9)
        cylinder("Furniture", (right - 1.05, 1.37, back + 1.1), 0.56, 2.45, "Ivory")
        for y in [0.4, 1.2, 2.3]:
            cylinder("Furniture", (right - 1.05, y, back + 1.1), 0.59, 0.08, "Copper")
        pipe(
            "Furniture",
            (right - 1.05, 2.65, back + 1.1),
            (cx + 1.1, 2.65, back + 1.1),
            0.07,
            "Copper",
        )
        pipe("Furniture", (cx + 1.1, 2.65, back + 1.1), (cx + 1.1, 1.4, back + 1.1), 0.07, "Copper")
        # A dedicated potting station with seedling trays, pots and low storage.
        px, pz = left + 1.15, cz + 2.0
        block("PottingBench", px, pz, 1.3, 2.5, 1.5)
        box("Furniture", (px, 0.6, pz), (1.1, 0.9, 2.3), "Graphite", 0.05)
        box("Furniture", (px, 1.1, pz), (1.3, 0.13, 2.5), "Wood", 0.07)
        for j in range(4):
            z = pz - 0.8 + j * 0.5
            cylinder("Furniture", (px, 1.26, z), 0.16, 0.23, "Copper")
            for k in range(5):
                pointed_leaf(
                    "Furniture", (px, 1.40 + k * 0.028, z), 0.42, 0.16, j + k * 2.4, "Moss"
                )
        for x in [cx - 3.3, cx + 3.3]:
            for j in range(7):
                for side in [-1, 1]:
                    z = cz - 3.0 + j * 0.72
                    for k in range(4):
                        pointed_leaf(
                            "Furniture",
                            (x + side * 0.77, 0.72 + k * 0.06, z),
                            0.45,
                            0.22,
                            j * 1.6 + k * 2.1,
                            "Leaf" if j % 2 else "Moss",
                        )
        label("InteriorRevealBack", "CULTIVATION / WATER", (cx, 3.10, back + 0.36), 0.27)
        for z in [back + 0.45, cz - 1.9]:
            reveal_arch("InteriorRevealConservatory", cx, z, w / 2 - 0.18, 3.0, 2.0)
            for x in [left + 0.16, right - 0.16]:
                box("InteriorRevealConservatory", (x, 2.02, z), (0.16, 2.0, 0.23), "Steel")
        # Retained glazing sections and irrigation describe a conservatory,
        # while keeping the front half open to the isometric camera.
        for x in [-5.6, -2.8, 0, 2.8, 5.6]:
            box("InteriorRevealGlazing", (x, 2.26, back + 0.43), (2.55, 1.9, 0.06), "Glass", 0.035)
            box("InteriorRevealGlazing", (x - 1.32, 2.26, back + 0.49), (0.06, 2.03, 0.09), "Ivory")
        for x in [cx - 3.3, cx + 3.3]:
            pipe(
                "InteriorRevealIrrigation",
                (x, 3.2, back + 0.5),
                (x, 3.2, cz + 1.75),
                0.065,
                "Copper",
            )
            for z in [cz - 2.3, cz - 0.85, cz + 0.65]:
                box("InteriorRevealIrrigation", (x, 3.10, z), (1.65, 0.13, 0.18), "Ivory")
                box("InteriorRevealIrrigation", (x, 3.01, z), (1.46, 0.035, 0.11), "Warm")
            box("Floor", (x, 0.18, cz - 0.85), (3.0, 0.012, 6.0), "Graphite", 0.06)
            # Additional soil and foliage occupy the existing cultivation box.
            box("Furniture", (x, 0.56, cz - 0.85), (1.85, 0.08, 4.95), "Soil", 0.035)
            for j in range(9):
                z = cz - 3.1 + j * 0.55
                for dx in [-0.78, 0.78]:
                    for k in range(3):
                        pointed_leaf(
                            "Furniture",
                            (x + dx, 0.69 + k * 0.015, z),
                            0.33,
                            0.15,
                            j * 0.7 + k * 2.1,
                            "Moss" if k % 2 else "Leaf",
                        )
    # Low cutaway walls retain the feeling of a room without concealing the player.
    for x in [left + 0.15, right - 0.15]:
        box("InteriorRevealRail", (x, 0.51, cz), (0.25, 0.75, d), "Steel", 0.05)
        box("InteriorRevealRail", (x, 0.91, cz), (0.30, 0.09, d), "Edge", 0.025)
    for a, b in [(left, cx - 1.65), (cx + 1.65, right)]:
        box(
            "InteriorRevealRail",
            ((a + b) / 2, 0.43, front - 0.12),
            (b - a, 0.65, 0.25),
            "Steel",
            0.05,
        )
    # Copper services and warm floor-level orientation lights enrich the cutaway.
    for height in [0.45, 3.2]:
        pipe(
            "InteriorRevealBack",
            (left + 0.5, height, back + 0.38),
            (right - 0.5, height, back + 0.38),
            0.045,
            "Copper",
        )
    for x in [left + 0.52, right - 0.52]:
        box("Floor", (x, 0.18, cz), (0.05, 0.01, d - 1), "Warm", 0)
    # Omit the superseded preview roof/walls; the fitted generated hull owns exterior art.
    for key in list(GROUPS):
        if key[0] in {"Roof", "Cutaway"}:
            for obj in GROUPS.pop(key):
                bpy.data.objects.remove(obj, do_unlink=True)
    # Selected generation assets are prepared separately and instanced by connector.
    data["blocks"] = blocks
    source = ROOT / "assets-production/structures" / asset / "blender" / f"{asset}-polished.blend"
    source.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(compress=True, filepath=str(source))
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
    out = ROOT / "apps/world/assets/structures" / asset
    out.mkdir(parents=True, exist_ok=True)
    for suffix, interior in [("shell", False), ("interior", True)]:
        bpy.ops.object.select_all(action="DESELECT")
        for group, obj in batches:
            obj.select_set((group == "Furniture") == interior and group not in {"Roof", "Cutaway"})
        bpy.ops.export_scene.gltf(
            filepath=str(out / f"{kind}-{suffix}.glb"),
            export_format="GLB",
            use_selection=True,
            export_animations=False,
        )
    (source.parents[1] / "layout.json").write_text(json.dumps(data, indent=2) + "\n")
    files = [source, out / f"{kind}-shell.glb", out / f"{kind}-interior.glb", Path(__file__)]
    provenance = {
        "asset_id": asset,
        "room_id": kind,
        "blender_version": bpy.app.version_string,
        "units": "metres; Godot Y-up exported from Blender Z-up",
        "footprint": data["footprint"],
        "palette": list(PALETTES[asset]),
        "source_kind": "authored architecture; generated equipment remains separate props",
        "files": {
            str(p.relative_to(ROOT)): {
                "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
                "bytes": p.stat().st_size,
            }
            for p in files
        },
        "semantic_groups": sorted({group for group, obj in batches}),
        "mesh_objects": len(batches),
        "triangles": sum(
            sum(len(face.vertices) - 2 for face in obj.data.polygons) for group, obj in batches
        ),
        "review_status": "Requires native and package qualification; owner art judgment separate",
    }
    (source.parents[1] / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print("STRUCTURE_AUTHORED", asset)
layout_path.write_text(json.dumps(layout, indent=2) + "\n")
