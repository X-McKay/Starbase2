"""Normalize reviewed static Meshy assets and retain full PBR detail in GLBs."""

import json
import math
from pathlib import Path

import bmesh
import bpy

# Background production saves selected sources without accumulating recovery copies.
bpy.context.preferences.filepaths.save_version = 0
from mathutils import Matrix, Vector

assert bpy.app.version[:3] == (5, 2, 1)
ROOT = Path(__file__).resolve().parents[2]

ledger = json.loads((ROOT / "meshy_output/engineering-polish-ledger.json").read_text())["stages"]
report = []
for asset in ["containment-reactor", "cooling-service-module"]:
    family = "props/containment-reactor" if asset == "containment-reactor" else "structures/engineering"
    OUT = ROOT / "apps/world/assets" / family
    OUT.mkdir(parents=True, exist_ok=True)
    source_dir = ROOT / "assets-production" / family / "blender"
    source_dir.mkdir(parents=True, exist_ok=True)
    item = ledger[asset + "/texture"]
    assert item["status"] == "complete"
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(Path(item["directory"]) / "texture.glb"))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for obj in meshes:
        transform = obj.matrix_world.copy()
        for v in obj.data.vertices:
            v.co = transform @ v.co
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)

    def bounds(meshes=meshes):
        points = [v.co for obj in meshes for v in obj.data.vertices]
        return Vector([min(v[i] for v in points) for i in range(3)]), Vector(
            [max(v[i] for v in points) for i in range(3)]
        )

    lo, hi = bounds()
    if asset == "containment-reactor":
        # The chosen reference has a horizontal cylinder. Stand its longest axis up.
        size = hi - lo
        axis = max(range(3), key=lambda i: size[i])
        rotation = Matrix.Identity(4)
        if axis == 0:
            rotation = Matrix.Rotation(-math.pi / 2, 4, "Y")
        if axis == 1:
            rotation = Matrix.Rotation(math.pi / 2, 4, "X")
        for obj in meshes:
            for v in obj.data.vertices:
                v.co = rotation @ v.co
        lo, hi = bounds()
        size = hi - lo
        scale = min(3.4 / size.z, 2.6 / max(size.x, size.y))
        factor = Vector((scale, scale, scale))
        center = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
        offset = Vector((0, 0, 0.24))
    else:
        size = hi - lo
        factor = Vector((10.7 / size.x, 8.3 / size.y, 5.2 / size.z))
        center = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
        offset = Vector((-1.95, 2.6, 0.13))
    for obj in meshes:
        for v in obj.data.vertices:
            q = v.co - center
            v.co = Vector((q.x * factor.x, q.y * factor.y, q.z * factor.z)) + offset
        obj.data.update()
        obj.name = "Roof_MeshyHull" if asset == "cooling-service-module" else "ReactorBody"
    removed = 0
    if asset == "cooling-service-module":
        # The generated door is cosmetic. Clear the precise playable airlock volume.
        for obj in meshes:
            bm = bmesh.new()
            bm.from_mesh(obj.data)
            faces = [
                f
                for f in bm.faces
                if any(
                    abs(v.co.x + 1.95) < 1.28 and v.co.y < -0.72 and v.co.z < 3.05 for v in f.verts
                )
            ]
            removed += len(faces)
            bmesh.ops.delete(bm, geom=faces, context="FACES")
            bm.to_mesh(obj.data)
            bm.free()
    bpy.ops.wm.save_as_mainfile(compress=True, filepath=str(source_dir / f"{asset}.blend"))
    filename = "reactor.glb" if asset == "containment-reactor" else "exterior.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(OUT / filename), export_format="GLB", export_animations=False
    )
    lo, hi = bounds()
    report.append(
        {
            "asset": asset,
            "output": str(OUT / filename),
            "min": list(lo),
            "max": list(hi),
            "removed_door_faces": removed,
        }
    )
(ROOT / "evidence/engineering-polish/model-preparation.json").write_text(
    json.dumps(report, indent=2) + "\n"
)
