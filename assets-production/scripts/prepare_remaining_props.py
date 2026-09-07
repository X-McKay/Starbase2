"""Prepare reviewed remaining-structure props in a separate Blender process.

Blender 5.2.1 --background --python prepare_remaining_props.py -- [--asset ID]
No API calls. Missing or incomplete inputs fail before resetting the scene.
The glTF importer establishes Z-up Blender geometry; this script never guesses
orientation from the longest dimension. Native visual review remains required.
"""

import argparse
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
TARGETS = {
    "mission-table": (3.4, 2.4, 1.2),
    "analysis-console": (3.6, 1.1, 2.3),
    "communications-array": (3.0, 2.4, 2.8),
    "simulation-station": (2.2, 2.2, 2.6),
    "frontier-galley": (2.6, 0.8, 2.1),
    "hydroponic-rack": (2.2, 1.25, 2.2),
    "sleep-capsule": (3.0, 2.0, 2.5),
    "resistance-bench": (2.4, 1.2, 2.6),
    "botany-lab-bench": (2.7, 1.0, 1.8),
}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def bounds(objects):
    low = Vector((math.inf,) * 3)
    high = Vector((-math.inf,) * 3)
    for obj in objects:
        for vertex in obj.data.vertices:
            point = obj.matrix_world @ vertex.co
            for axis in range(3):
                require(math.isfinite(point[axis]), "Non-finite source geometry")
                low[axis] = min(low[axis], point[axis])
                high[axis] = max(high[axis], point[axis])
    size = high - low
    require(all(math.isfinite(v) and v > 1e-7 for v in size), "Empty or degenerate mesh bounds")
    return {"min": list(low), "max": list(high), "size": list(size)}


def materials_report(objects):
    materials = {mat.name: mat for obj in objects for mat in obj.data.materials if mat}
    report = []
    for name, material in sorted(materials.items()):
        entry = {"name": name, "use_nodes": material.use_nodes, "principled": [], "textures": []}
        if material.use_nodes:
            for node in material.node_tree.nodes:
                if node.type == "BSDF_PRINCIPLED":
                    channels = {}
                    for channel in (
                        "Base Color",
                        "Metallic",
                        "Roughness",
                        "Normal",
                        "Emission Color",
                        "Emission Strength",
                        "Alpha",
                    ):
                        socket = node.inputs.get(channel)
                        if socket is None:
                            continue
                        value = socket.default_value
                        channels[channel] = {
                            "linked": socket.is_linked,
                            "value": float(value)
                            if isinstance(value, (int, float))
                            else list(value),
                        }
                    entry["principled"].append(channels)
                elif node.type == "TEX_IMAGE" and node.image:
                    entry["textures"].append(
                        {
                            "name": node.image.name,
                            "size": list(node.image.size),
                            "colorspace": node.image.colorspace_settings.name,
                            "channels": node.image.channels,
                        }
                    )
        report.append(entry)
    return report


def prepare(asset, item, source):
    asset_id = asset["id"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.import_scene.gltf(filepath=str(source))
    bpy.context.view_layer.update()
    require(
        not any(obj.type == "ARMATURE" for obj in bpy.context.scene.objects),
        "Static prop input unexpectedly contains a rig",
    )
    imported = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    require(imported, "Input has no mesh objects")
    transforms = {obj.name: [list(row) for row in obj.matrix_world] for obj in imported}
    depsgraph = bpy.context.evaluated_depsgraph_get()
    prepared = []
    for index, obj in enumerate(imported):
        evaluated = obj.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(
            evaluated, preserve_all_data_layers=True, depsgraph=depsgraph
        )
        mesh.transform(evaluated.matrix_world)
        mesh.update()
        prefix = (
            "Roof_Communications"
            if asset_id == "communications-array"
            else asset_id.replace("-", "_")
        )
        clean = bpy.data.objects.new(f"{prefix}_{index:03d}", mesh)
        bpy.context.scene.collection.objects.link(clean)
        prepared.append(clean)
    for obj in list(bpy.context.scene.objects):
        if obj not in prepared:
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.context.view_layer.update()
    raw = bounds(prepared)
    width, depth, height = TARGETS[asset_id]
    scale = min(
        target / dimension for target, dimension in zip((width, depth, height), raw["size"])
    )
    center_floor = Vector(
        ((raw["min"][0] + raw["max"][0]) / 2, (raw["min"][1] + raw["max"][1]) / 2, raw["min"][2])
    )
    transform = Matrix.Scale(scale, 4) @ Matrix.Translation(-center_floor)
    for obj in prepared:
        obj.data.transform(transform)
        obj.data.update()
    bpy.context.view_layer.update()
    final = bounds(prepared)
    require(
        all(size <= target + 1e-5 for size, target in zip(final["size"], TARGETS[asset_id])),
        "Normalized bounds exceed intended fit",
    )
    material_info = materials_report(prepared)
    require(material_info, "Input has no materials to retain")
    for image in bpy.data.images:
        if image.source == "FILE" and image.has_data:
            image.pack()
    production = ROOT / "assets-production/props" / asset_id
    runtime = ROOT / "apps/world/assets/props" / asset_id
    blend = production / "blender" / f"{asset_id}.blend"
    exported = runtime / f"{asset_id}.glb"
    blend.parent.mkdir(parents=True, exist_ok=True)
    runtime.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in prepared:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = prepared[0]
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    bpy.ops.export_scene.gltf(
        filepath=str(exported),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=False,
        export_materials="EXPORT",
    )
    with exported.open("rb") as stream:
        require(stream.read(4) == b"glTF", "Export is not GLB")
        stream.read(8)
        length, chunk_type = struct.unpack("<II", stream.read(8))
        require(chunk_type == 0x4E4F534A, "Export lacks JSON header")
        gltf = json.loads(stream.read(length))
    counts = {"objects": len(prepared), "vertices": 0, "polygons": 0, "triangles": 0}
    for obj in prepared:
        obj.data.calc_loop_triangles()
        counts["vertices"] += len(obj.data.vertices)
        counts["polygons"] += len(obj.data.polygons)
        counts["triangles"] += len(obj.data.loop_triangles)
    provenance = {
        "asset_id": asset_id,
        "blender_version": bpy.app.version_string,
        "source": str(source.relative_to(ROOT)),
        "source_sha256": digest(source),
        "task_id": item["task_id"],
        "consumed_credits": item["consumed_credits"],
        "orientation": "Preserved imported Blender Z-up; GLB exports Y-up; no axis guessing",
        "source_object_world_matrices": transforms,
        "raw_bounds_blender_xyz": raw,
        "fit_target_width_depth_height_m": list(TARGETS[asset_id]),
        "applied_uniform_scale": scale,
        "source_center_floor": list(center_floor),
        "applied_normalization_matrix": [list(row) for row in transform],
        "final_bounds_blender_xyz": final,
        "final_size_godot_xyz": [final["size"][0], final["size"][2], final["size"][1]],
        "geometry": counts,
        "materials": material_info,
        "exported_materials": gltf.get("materials", []),
        "exported_image_count": len(gltf.get("images", [])),
        "blend": str(blend.relative_to(ROOT)),
        "blend_sha256": digest(blend),
        "runtime": str(exported.relative_to(ROOT)),
        "runtime_sha256": digest(exported),
        "runtime_bytes": exported.stat().st_size,
        "review_status": "Prepared; requires native orientation, PBR and placement review",
    }
    (production / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(
        json.dumps(
            {"asset": asset_id, "runtime": str(exported), "scale": scale, "geometry": counts}
        )
    )


def main():
    require(bpy.app.background, "Run only in a separate background Blender process")
    require(bpy.app.version[:3] == (5, 2, 1), "Requires pinned Blender 5.2.1")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset", choices=TARGETS)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])
    plan_path = ROOT / "assets-production/batches/remaining-structures/plan.json"
    ledger_path = ROOT / "meshy_output/remaining-structures-ledger.json"
    require(
        plan_path.is_file() and ledger_path.is_file(), "Missing remaining-structures plan or ledger"
    )
    plan = json.loads(plan_path.read_text())
    ledger = json.loads(ledger_path.read_text())
    selected = [args.asset] if args.asset else list(TARGETS)
    jobs = []
    for asset_id in selected:
        matches = [asset for asset in plan["assets"] if asset["id"] == asset_id]
        require(len(matches) == 1, f"Missing or duplicate asset in plan: {asset_id}")
        item = ledger["stages"].get(asset_id + "/mesh", {})
        require(
            item.get("status") == "complete" and "consumed_credits" in item,
            f"Mesh stage is not complete with actual charges: {asset_id}",
        )
        files = [Path(path) for path in item.get("files", []) if Path(path).suffix == ".glb"]
        require(len(files) == 1 and files[0].is_file(), f"Expected one downloaded GLB: {asset_id}")
        source = files[0].resolve()
        require(source.is_relative_to(ROOT / "meshy_output"), "Source must be in meshy_output")
        jobs.append((matches[0], item, source))
    for job in jobs:
        prepare(*job)


if __name__ == "__main__":
    main()
