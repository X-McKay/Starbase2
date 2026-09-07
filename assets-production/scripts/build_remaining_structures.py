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
        data["markers"]["Crew"] = [2.4, 0, cz - 0.2]
        data["markers"]["WalkTarget"] = [-3, 0, cz + 0.1]
    if asset == "training":
        data["markers"]["Crew"] = [1.25, 0, cz - 0.2]
        data["markers"]["WalkTarget"] = [0, 0, cz - 1.6]
    if asset == "botanical":
        data["markers"]["Crew"] = [0, 0, cz]
        data["markers"]["WalkTarget"] = [0, 0, cz]
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
    # Shared real inspection terminal preserves near-side access and identity.
    console(cx + 2.6, front - 2.05)
    block("InspectionTerminal", cx + 2.6, front - 2.05, 1.5, 0.9, 1.65)
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
        label("InteriorRevealBack", "OBSERVATION / ANALYSIS", (cx, 2.75, back + 0.36), 0.27)
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
        label("InteriorRevealBack", "SIMULATION / PRACTICE", (cx, 3.03, back + 0.36), 0.25)
    elif asset == "habitat":
        for x in [cx - w * 0.31, cx, cx + w * 0.31]:
            roof_vault(x, cz, w * 0.30, d - 0.6, 1.0)
            box("Roof", (x, 4.40, cz), (w * 0.22, 0.12, 2.3), "Glass")
        for i in [-1, 0, 1]:
            x = cx + i * w * 0.29
            block("SleepPod", x, back + 1.6, 3.1, 2.1, 2.7)
        block("Galley", left + 1.25, cz + 0.6, 1.7, 2.8, 2.3)
        block("CommonsTable", cx - 1.7, cz + 1.3, 2.0, 1.0, 1.0)
        box("Furniture", (cx - 1.7, 0.92, cz + 1.3), (2.0, 0.14, 1.0), "Ivory", 0.09)
        for x in [cx - 2.4, cx - 1.0]:
            chair(x, cz + 2.05)
            block("DiningChair", x, cz + 2.05, 0.72, 0.72, 1.5)
        # A comfortable east-side sofa and service shelf complete the commons.
        sx = right - 1.2
        box("Furniture", (sx, 0.56, cz + 0.55), (1.30, 0.5, 2.75), "Steel", 0.11)
        box("Furniture", (sx, 0.89, cz + 0.55), (1.20, 0.22, 2.6), "Fabric", 0.11)
        box("Furniture", (sx + 0.52, 1.20, cz + 0.55), (0.20, 0.72, 2.8), "Fabric", 0.10)
        block("Sofa", sx, cz + 0.55, 1.45, 2.9, 1.6)
        label("InteriorRevealBack", "REST / SHARED LIVING", (cx, 3.05, back + 0.36), 0.26)
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
            "Furniture", (right - 1.05, 2.65, back + 1.1), (cx + 1.1, 2.65, back + 1.1), 0.07, "Copper"
        )
        pipe("Furniture", (cx + 1.1, 2.65, back + 1.1), (cx + 1.1, 1.4, back + 1.1), 0.07, "Copper")
        label("InteriorRevealBack", "CULTIVATION / WATER", (cx, 3.10, back + 0.36), 0.27)
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
