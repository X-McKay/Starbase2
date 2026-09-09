"""Build the open garden commons with pinned Blender 5.2.1, entirely offline.

Separate background process only. Local coordinates export Y-up to Godot; the
assembly is placed at (-7, 0, 23) by living_commons.gd. No building is changed.
"""

import hashlib
import json
import math
import random
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets-production/environment/living-commons"
RUNTIME = ROOT / "apps/world/assets/environment/living-commons"


def main():
    if not bpy.app.background or bpy.app.version[:3] != (5, 2, 1):
        raise RuntimeError("Use a separate background Blender 5.2.1 process")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    materials = {}
    groups = {}
    for name, color, metallic, roughness, emission in [
        ("Ceramic", (0.64, 0.60, 0.49), 0.18, 0.43, 0),
        ("Graphite", (0.045, 0.067, 0.062), 0.55, 0.43, 0),
        ("Copper", (0.34, 0.16, 0.065), 0.7, 0.34, 0),
        ("Timber", (0.29, 0.20, 0.105), 0.0, 0.66, 0),
        ("Sage", (0.21, 0.30, 0.20), 0.0, 0.9, 0),
        ("LeafDark", (0.028, 0.115, 0.035), 0.0, 0.65, 0),
        ("LeafLight", (0.11, 0.26, 0.045), 0.0, 0.66, 0),
        ("LeafSilver", (0.23, 0.36, 0.18), 0.0, 0.72, 0),
        ("Soil", (0.045, 0.031, 0.016), 0.0, 1, 0),
        ("Water", (0.025, 0.17, 0.16), 0.48, 0.13, 0),
        ("WarmLight", (0.95, 0.53, 0.17), 0.1, 0.4, 1.7),
    ]:
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        shader = material.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value = (*color, 1)
        shader.inputs["Metallic"].default_value = metallic
        shader.inputs["Roughness"].default_value = roughness
        shader.inputs["Emission Color"].default_value = (*color, 1)
        shader.inputs["Emission Strength"].default_value = emission
        materials[name] = material

    def coord(point):
        return Vector((point[0], -point[2], point[1]))

    def finish(obj, group, material):
        obj.name = group + "_" + material
        obj.data.materials.append(materials[material])
        groups.setdefault((group, material), []).append(obj)
        return obj

    def box(group, point, dimensions, material, bevel=0.025):
        bpy.ops.mesh.primitive_cube_add(size=1, location=coord(point))
        obj = bpy.context.object
        obj.dimensions = dimensions[0], dimensions[2], dimensions[1]
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        if bevel:
            mod = obj.modifiers.new("Rounded manufactured edges", "BEVEL")
            mod.width = min(bevel, min(dimensions) * 0.32)
            mod.segments = 3
            bpy.ops.object.modifier_apply(modifier=mod.name)
        return finish(obj, group, material)

    def rod(group, start, end, radius, material, vertices=12):
        a, b = coord(start), coord(end)
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=vertices, radius=radius, depth=(b - a).length, location=(a + b) / 2
        )
        obj = bpy.context.object
        obj.rotation_euler = (b - a).to_track_quat("Z", "Y").to_euler()
        return finish(obj, group, material)

    # Fine-grained flush terrace, with a broad uninterrupted through route.
    box("Terrace", (0, 0.026, 0.15), (9.9, 0.042, 7.0), "Graphite", 0.01)
    for index in range(32):
        x = -4.805 + index * 0.31
        box("Terrace", (x, 0.055, 0.15), (0.292, 0.022, 6.9), "Timber", 0.004)
        for z in (-3.16, 3.46):
            box("Terrace", (x, 0.069, z), (0.026, 0.005, 0.026), "Copper", 0)
    for z in (-3.34, 3.64):
        box("Terrace", (0, 0.055, z), (9.94, 0.052, 0.07), "Ceramic", 0.009)

    rng = random.Random(1702)

    def leaf(base, tip, width, material):
        a, b = Vector(base), Vector(tip)
        direction = (b - a).normalized()
        across = direction.cross(Vector((0, 1, 0))).normalized() * width
        # A folded, tapering lance leaf; raised midrib catches soft daylight.
        points = [
            a,
            a.lerp(b, 0.30) - across,
            a.lerp(b, 0.67) - across * 0.72,
            b,
            a.lerp(b, 0.67) + across * 0.72,
            a.lerp(b, 0.30) + across,
            a.lerp(b, 0.43) + Vector((0, width * 0.28, 0)),
        ]
        mesh = bpy.data.meshes.new("Lance leaf")
        mesh.from_pydata([coord(p) for p in points], [], [(i, (i + 1) % 6, 6) for i in range(6)])
        mesh.update()
        obj = bpy.data.objects.new("Foliage", mesh)
        bpy.context.scene.collection.objects.link(obj)
        for polygon in mesh.polygons:
            polygon.use_smooth = True
        finish(obj, "Planting", material)

    # Two substantial raised beds: all stems, supports and irrigation stay within
    # the matching 1.0 x 6.5m collision rectangles declared in the runtime module.
    for side in (-1, 1):
        x = side * 4.35
        box("Planter", (x, 0.33, 0.15), (1.0, 0.55, 6.5), "Graphite", 0.07)
        for sx in (-0.465, 0.465):
            box("Planter", (x + sx, 0.42, 0.15), (0.07, 0.43, 6.46), "Ceramic", 0.022)
            box("Planter", (x + sx, 0.64, 0.15), (0.085, 0.055, 6.46), "Copper", 0.012)
        for z in (-3.06, 3.36):
            box("Planter", (x, 0.42, z), (0.95, 0.43, 0.08), "Ceramic", 0.02)
        box("Planter", (x, 0.60, 0.15), (0.82, 0.05, 6.25), "Soil", 0.01)
        rod("Irrigation", (x, 0.68, -2.95), (x, 0.68, 3.15), 0.022, "Copper")
        for i in range(26):
            z = -2.88 + i * 0.239
            plant_x = x + rng.uniform(-0.13, 0.13)
            height = rng.uniform(0.60, 1.55)
            rod("Planting", (plant_x, 0.63, z), (plant_x, 0.64 + height, z), 0.010, "LeafDark", 6)
            for tier in range(6):
                y = 0.73 + height * tier / 7
                for azimuth in (0, math.pi):
                    angle = azimuth + rng.uniform(-0.45, 0.45) + (tier % 2) * 0.6
                    tip = (
                        plant_x + math.cos(angle) * 0.28,
                        y + rng.uniform(0.18, 0.35),
                        z + math.sin(angle) * 0.24,
                    )
                    leaf(
                        (plant_x, y, z),
                        tip,
                        0.105,
                        rng.choice(("LeafDark", "LeafLight", "LeafSilver")),
                    )
        # Slim arched support legs are incorporated in the beds, not the aisle.
        for z in (-2.85, 0.15, 3.15):
            box("Pergola", (x, 1.60, z), (0.14, 3.05, 0.14), "Graphite", 0.018)
            rod("Pergola", (x, 2.40, z), (x - side * 0.6, 2.94, z), 0.045, "Copper")
        box("WaterTrough", (x, 0.70, 3.0), (0.72, 0.14, 0.46), "Graphite", 0.025)
        box("WaterTrough", (x, 0.777, 3.0), (0.62, 0.012, 0.36), "Water", 0.012)

    # Raised ribs and individually spaced slats provide shelter without an
    # opaque roof: the garden remains visible from the colony camera.
    def canopy_height(x):
        return 2.95 + 0.65 * (1 - (x / 4.75) ** 2)

    for z in (-2.92, 0.15, 3.22):
        for index in range(24):
            a = -4.75 + index * (9.5 / 24)
            b = a + (9.5 / 24)
            rod("Pergola", (a, canopy_height(a), z), (b, canopy_height(b), z), 0.055, "Ceramic")
    for index in range(21):
        x = -4.65 + index * 0.465
        box("CanopySlats", (x, canopy_height(x) + 0.025, 0.15), (0.17, 0.10, 6.8), "Timber", 0.015)
        if index % 4 == 0:
            box(
                "CanopyLights",
                (x, canopy_height(x) - 0.055, 0.15),
                (0.035, 0.03, 4.5),
                "WarmLight",
                0.008,
            )
    # Back bench is a continuous warm seating niche, leaving the central aisle.
    box("Bench", (0, 0.25, 3.075), (4.8, 0.36, 0.85), "Graphite", 0.06)
    for index in range(16):
        x = -2.24 + index * 0.298
        box("Bench", (x, 0.48, 3.075), (0.278, 0.12, 0.80), "Timber", 0.025)
        box("Bench", (x, 0.85, 3.43), (0.278, 0.69, 0.105), "Timber", 0.025)
    for x in (-2.25, 2.25):
        box("Bench", (x, 0.73, 3.075), (0.065, 0.05, 0.80), "Copper", 0.015)
    for x in (-1.65, -0.55, 0.55, 1.65):
        box("BenchCushions", (x, 0.58, 3.0), (0.88, 0.11, 0.48), "Sage", 0.07)

    # Central layered specimen island divides two generous accessible aisles.
    box("Island", (0, 0.30, 0.05), (1.4, 0.50, 2.1), "Ceramic", 0.10)
    box("Island", (0, 0.57, 0.05), (1.23, 0.06, 1.94), "Soil", 0.025)
    for i in range(8):
        z = -0.76 + i * 0.23
        for x in (-0.30, 0.30):
            height = rng.uniform(0.45, 1.25)
            rod("Planting", (x, 0.6, z), (x, height + 0.6, z), 0.013, "LeafDark", 6)
            for tier in range(5):
                y = 0.66 + height * tier / 6
                for angle in (0, math.pi / 2, math.pi, 3 * math.pi / 2):
                    leaf(
                        (x, y, z),
                        (x + math.cos(angle) * 0.25, y + 0.25, z + math.sin(angle) * 0.22),
                        0.11,
                        rng.choice(("LeafDark", "LeafLight", "LeafSilver")),
                    )

    # Editable meshes remain separate in the source; material batches in export.
    SOURCE.joinpath("blender").mkdir(parents=True, exist_ok=True)
    RUNTIME.mkdir(parents=True, exist_ok=True)
    blend = SOURCE / "blender/living-commons.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
    for (group, material), objects in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        if len(objects) > 1:
            bpy.ops.object.join()
        bpy.context.object.name = group + "_" + material
    bpy.ops.object.select_all(action="SELECT")
    exported = RUNTIME / "living-commons.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(exported),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=False,
    )
    objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    triangles = 0
    for obj in objects:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
    files = {}
    for path in (blend, exported, Path(__file__)):
        with path.open("rb") as stream:
            files[str(path.relative_to(ROOT))] = {
                "sha256": hashlib.file_digest(stream, "sha256").hexdigest(),
                "bytes": path.stat().st_size,
            }
    (SOURCE / "provenance.json").write_text(
        json.dumps(
            {
                "asset_id": "living-commons",
                "blender_version": bpy.app.version_string,
                "source_kind": "Authored garden architecture and leaf meshes; no paid generation",
                "version": 2,
                "world_origin": [-7, 0, 23],
                "world_footprint": [-12, 19.6, 10, 7.1],
                "blocks": [
                    [-11.85, 19.9, 1.0, 6.5],
                    [-3.15, 19.9, 1.0, 6.5],
                    [-9.4, 25.65, 4.8, 0.85],
                    [-7.7, 22.0, 1.4, 2.1],
                ],
                "mesh_objects": len(objects),
                "triangles": triangles,
                "files": files,
                "review_status": "Requires native visual review and physics/navigation integration",
            },
            indent=2,
        )
        + "\n"
    )
    print("LIVING_COMMONS_PREPARED", len(objects), triangles)


if __name__ == "__main__":
    main()
