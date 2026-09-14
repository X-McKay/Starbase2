"""Offline Blender5.2.1 Habitat/Commons dressing; coordinates authored in Godot metres."""

import hashlib
import json
import math
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / "apps/world/assets/kits/aster-domestic"
SOURCE = ROOT / "assets-production/kits/aster-domestic/blender"


def main():
    assert bpy.app.background and bpy.app.version[:3] == (5, 2, 1)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    mats = {}
    for name, color, metallic, rough in [
        ("Honey timber", (0.38, 0.19, 0.075), 0, 0.65),
        ("Warm linen", (0.59, 0.46, 0.29), 0, 0.94),
        ("Terracotta", (0.49, 0.17, 0.075), 0, 0.82),
        ("Ceramic ivory", (0.72, 0.66, 0.52), 0.05, 0.4),
        ("Deep teal", (0.025, 0.13, 0.125), 0.12, 0.55),
        ("Brass", (0.45, 0.27, 0.10), 0.72, 0.3),
        ("Leaf", (0.08, 0.22, 0.065), 0, 0.85),
        ("Graphite", (0.025, 0.037, 0.04), 0.5, 0.4),
        ("Amber glow", (1, 0.53, 0.17), 0.05, 0.3),
    ]:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        sh = m.node_tree.nodes.get("Principled BSDF")
        sh.inputs["Base Color"].default_value = (*color, 1)
        sh.inputs["Metallic"].default_value = metallic
        sh.inputs["Roughness"].default_value = rough
        if name == "Amber glow":
            sh.inputs["Emission Color"].default_value = (*color, 1)
            sh.inputs["Emission Strength"].default_value = 2
        mats[name] = m

    def box(name, pos, size, mat, bevel=0.025):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(pos[0], -pos[2], pos[1]))
        o = bpy.context.object
        o.name = name
        o.scale = (size[0], size[2], size[1])
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        o.data.materials.append(mats[mat])
        if bevel:
            mod = o.modifiers.new("Soft manufactured edge", "BEVEL")
            mod.width = bevel
            mod.segments = 2
            o.modifiers.new("Weighted highlights", "WEIGHTED_NORMAL")
        return o

    def cylinder(name, pos, radius, depth, mat):
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=20, radius=radius, depth=depth, location=(pos[0], -pos[2], pos[1])
        )
        o = bpy.context.object
        o.name = name
        o.data.materials.append(mats[mat])
        mod = o.modifiers.new("Rounded lip", "BEVEL")
        mod.width = 0.015
        mod.segments = 2
        o.modifiers.new("Weighted highlights", "WEIGHTED_NORMAL")
        return o

    def plant(name, x, y, z, scale=1):
        cylinder(
            name + " vessel", (x, y + 0.19 * scale, z), 0.22 * scale, 0.38 * scale, "Terracotta"
        )
        for i in range(9):
            a = i * 2.399
            o = box(
                name + " leaf",
                (
                    x + math.cos(a) * 0.17 * scale,
                    y + (0.48 + i * 0.035) * scale,
                    z + math.sin(a) * 0.17 * scale,
                ),
                (0.12 * scale, 0.58 * scale, 0.035 * scale),
                "Leaf",
                0.025 * scale,
            )
            o.rotation_euler = (math.sin(a) * 0.45, math.cos(a) * 0.45, a)

    def mug(name, x, y, z):
        cylinder(name, (x, y + 0.065, z), 0.065, 0.13, "Ceramic ivory")
        cylinder(name + " coffee", (x, y + 0.133, z), 0.054, 0.005, "Graphite")
        box(name + " handle", (x + 0.073, y + 0.075, z), (0.055, 0.065, 0.022), "Brass", 0.012)

    def export(name):
        bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / (name + ".blend")))
        path = OUT / (name + ".glb")
        bpy.ops.export_scene.gltf(
            filepath=str(path), export_format="GLB", export_yup=True, export_apply=True
        )
        return {
            "path": str(path.relative_to(ROOT)),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "bytes": path.stat().st_size,
            "objects": len(bpy.context.scene.objects),
        }

    def bench(name, x, z):
        # 0.48m seat,0.4m depth; contact0.55m behind floor-root at z+0.55.
        box(name + " upholstered seat", (x, 0.43, z), (0.95, 0.10, 0.4), "Terracotta", 0.05)
        for dx in [-0.36, 0.36]:
            box(name + " brass leg", (x + dx, 0.21, z), (0.055, 0.42, 0.28), "Brass", 0.015)
        box(name + " backrest", (x, 0.78, z - 0.18), (0.98, 0.5, 0.09), "Deep teal", 0.035)

    # Layers remain below walking feet; no new obstacles in existing navigation lanes.
    for i in range(32):
        box(
            "Lounge timber plank",
            (-7.75 + i * 0.5, 0.178, -3.55),
            (0.485, 0.022, 7.1),
            "Honey timber",
            0.005,
        )
    box("Woven lounge carpet", (2.6, 0.205, -4.1), (8.1, 0.024, 5.8), "Warm linen", 0.05)
    for x in [-1.35, 6.55]:
        box("Carpet teal border", (x, 0.222, -4.1), (0.09, 0.01, 5.65), "Deep teal", 0.01)
    for z in [-6.86, -1.34]:
        box("Carpet teal border", (2.6, 0.222, z), (7.95, 0.01, 0.09), "Deep teal", 0.01)
    # Dressing occupies existing coffee table / galley / sofa collision footprints.
    box("Table timber top", (-3.8, 0.87, -2.65), (3.15, 0.09, 1.48), "Honey timber", 0.06)
    box("Table brass runner", (-3.8, 0.922, -2.65), (0.7, 0.014, 1.25), "Brass", 0.01)
    plant("Table herb", -3.85, 0.94, -2.65, 0.45)
    mug("Used mug", -4.7, 0.93, -2.7)
    mug("Second mug", -2.8, 0.93, -2.5)
    for i in range(3):
        o = box(
            "Paper field journal",
            (-3.15, 0.96 + i * 0.045, -3.08),
            (0.45, 0.045, 0.29),
            "Deep teal" if i % 2 else "Terracotta",
            0.015,
        )
        o.rotation_euler.z = i * 0.12
    for x in [2.5, 4.3]:
        box("Lounge textile cushion", (x, 0.97, -5.4), (0.65, 0.28, 0.65), "Terracotta", 0.1)
    for x in [-5.22, 0, 5.22]:
        box("Personal brass cabin plate", (x, 1.75, -10.92), (0.9, 0.2, 0.025), "Brass", 0.025)
        box("Cabin plate inset", (x, 1.75, -10.89), (0.64, 0.045, 0.01), "Deep teal", 0.01)
    plant("Galley rosemary", -7.75, 1.2, -5.15, 0.7)
    mug("Galley cup", -7.75, 1.22, -3.7)
    # Pendant clusters read as warm domestic objects, rather than flat room floodlight.
    for x, z in [(-3.8, -2.65), (3.4, -4.0)]:
        cylinder("Pendant stem", (x, 2.9, z), 0.025, 0.7, "Brass")
        cylinder("Pendant shade", (x, 2.55, z), 0.42, 0.17, "Deep teal")
        cylinder("Pendant diffuser", (x, 2.455, z), 0.34, 0.025, "Amber glow")
    # Thin threshold guide stays outside the opening and creates a legible destination.
    for x in [-1.45, 1.45]:
        box("Airlock warm guide", (x, 0.035, 1.0), (0.06, 0.025, 0.9), "Amber glow", 0.01)
    bench("Reading chair", 1.6, -2.75)
    report = [export("habitat-lounge")]
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    # Commons tabletop and planted focal point use its existing central blocked island.
    box("Garden table", (0, 0.88, 0), (1.2, 0.1, 1.7), "Honey timber", 0.06)
    mug("Commons mug", -0.36, 0.94, -0.35)
    mug("Commons second mug", 0.34, 0.94, 0.42)
    plant("Commons table plant", 0, 0.94, 0, 0.55)
    # Warm path inlays, flush to ground, no collision additions.
    for z in [-2.5, -1.8, -1.1, -0.4, 0.3, 1, 1.7, 2.4]:
        for x in [-3.05, 3.05]:
            box("Promenade light", (x, 0.05, z), (0.085, 0.03, 0.28), "Amber glow", 0.015)
    # Rear bench existing collision extent; detail backrest inlay.
    for i in range(8):
        box(
            "Bench timber accent",
            (-2 + i * 0.56, 1.01, 3.02),
            (0.5, 0.13, 0.07),
            "Honey timber",
            0.025,
        )
    bench("West garden bench", -3, -2.3)
    bench("East garden bench", 2.5, -1.3)
    report.append(export("commons-details"))
    (SOURCE.parent / "provenance.json").write_text(
        json.dumps(
            {
                "blender": bpy.app.version_string,
                "new_meshy_credits": 0,
                "method": "offline authored dressing reusing current Meshy hero props",
                "outputs": report,
            },
            indent=2,
        )
        + "\n"
    )


if __name__ == "__main__":
    main()
