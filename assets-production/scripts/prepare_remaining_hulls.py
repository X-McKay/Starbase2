"""Fit inspected Meshy hulls around exact playable rooms, Blender 5.2.1.

No generation. Keep the hull, authored architecture and physical opening separate.
Generated doors are decorative; cut a real clearance through the visual hull.
"""

import argparse
import hashlib
import json
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
FAMILIES = {"command": "review", "training": "gym", "habitat": "habitat", "botanical": "greenhouse"}
assert bpy.app.background and bpy.app.version[:3] == (5, 2, 1)
bpy.context.preferences.filepaths.save_version = 0
parser = argparse.ArgumentParser()
parser.add_argument("--asset", choices=FAMILIES, required=True)
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])
asset = args.asset
ledger = json.loads((ROOT / "meshy_output/remaining-structures-ledger.json").read_text())["stages"]
item = ledger[asset + "-hull/mesh"]
assert item["status"] == "complete"
source = Path(item["files"][0])
assert source.is_file() and source.resolve().is_relative_to(ROOT / "meshy_output")
data = json.loads((ROOT / "assets-production/structures" / asset / "layout.json").read_text())
left, back, width, depth = data["footprint"]
cx, cz = left + width / 2, back + depth / 2
front = back + depth
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.import_scene.gltf(filepath=str(source))
bpy.context.view_layer.update()
meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
assert meshes and not any(obj.type == "ARMATURE" for obj in bpy.context.scene.objects)
for obj in meshes:
    obj.data.transform(obj.matrix_world)
    obj.parent = None
    obj.matrix_world = Matrix.Identity(4)
points = [v.co for obj in meshes for v in obj.data.vertices]
lo = Vector([min(p[i] for p in points) for i in range(3)])
hi = Vector([max(p[i] for p in points) for i in range(3)])
size = hi - lo
assert min(size) > 0
# Engineering's proven fitted-hull approach; keep units and stretching explicit.
heights = {"command": 7.6, "training": 5.1, "habitat": 4.7, "botanical": 5.4}
target = Vector((width + 0.24, depth + 0.24, heights[asset]))
factor = Vector([target[i] / size[i] for i in range(3)])
center = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
offset = Vector((cx, -cz, 0.13))
removed = 0
for index, obj in enumerate(meshes):
    for v in obj.data.vertices:
        q = v.co - center
        v.co = Vector([q[i] * factor[i] for i in range(3)]) + offset
    obj.name = f"Roof_{asset}_Hull_{index}"
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    faces = [
        f
        for f in bm.faces
        if any(
            abs(v.co.x - cx) < 1.34 and v.co.y < -(front - 1.2) and v.co.z < 3.12 for v in f.verts
        )
    ]
    removed += len(faces)
    bmesh.ops.delete(bm, geom=faces, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
for obj in list(bpy.context.scene.objects):
    if obj not in meshes:
        bpy.data.objects.remove(obj, do_unlink=True)
for image in bpy.data.images:
    if image.source == "FILE" and image.has_data:
        image.pack()
production = ROOT / "assets-production/structures" / asset
runtime = ROOT / "apps/world/assets/structures" / asset / "hull.glb"
blend = production / "blender" / f"{asset}-hull.blend"
bpy.ops.wm.save_as_mainfile(compress=True, filepath=str(blend))
bpy.ops.export_scene.gltf(filepath=str(runtime), export_format="GLB", export_animations=False)
report = {
    "asset_id": asset,
    "task_id": item["task_id"],
    "consumed_credits": item["consumed_credits"],
    "source": str(source.relative_to(ROOT)),
    "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
    "raw_bounds_blender_xyz": {"min": list(lo), "max": list(hi)},
    "nonuniform_fit_scale": list(factor),
    "fit_size_width_depth_height_m": list(target),
    "removed_door_faces": removed,
    "clearance": {"width_m": 2.68, "height_m": 3.12, "front_depth_m": 1.2},
    "blender_version": bpy.app.version_string,
    "files": {
        str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in [blend, runtime]
    },
    "limitations": "Generated hull has an explicit visual opening; authored collision and floor remain authoritative. Native exterior/interior review required.",
}
(production / "hull-provenance.json").write_text(json.dumps(report, indent=2) + "\n")
print("HULL_PREPARED", asset, "removed_faces", removed)
