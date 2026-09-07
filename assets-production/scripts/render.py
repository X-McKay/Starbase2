"""Render editable, rigged .blend sources through one fixed PNG export contract.

Run with Blender 4.5.3. Rendering does not rebuild or overwrite the source models.
Add a source to catalog.json; no per-character renderer branch is needed.
"""

import hashlib
import json
from pathlib import Path

import bpy
from mathutils import Matrix

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / ".local/character-frames"
assert bpy.app.version[:3] == (4, 5, 3), bpy.app.version_string
entries = json.loads((ROOT / "assets-production/characters/catalog.json").read_text())
for entry in entries:
    kind = entry["id"]
    source = ROOT / entry["source"]
    bpy.ops.wm.open_mainfile(filepath=str(source))
    scene = bpy.context.scene
    rig = bpy.data.objects[entry["rig_object"]]
    assert rig.type == "ARMATURE"
    assert rig.animation_data.action.name == entry["clip"]
    assert scene.render.resolution_x == 256 and scene.render.resolution_y == 320
    assert scene.render.film_transparent
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    # Source action contains idle at frame 0 and the eight reviewed gait samples.
    for direction, angle in [
        ("front", 0),
        ("back", 3.141592653589793),
        ("left", -1.5707963267948966),
        ("right", 1.5707963267948966),
    ]:
        for index in range(9):
            scene.frame_set(index)
            rotation = Matrix.Rotation(angle, 4, "Z")
            for obj in scene.objects:
                if obj.type == "MESH":
                    obj.matrix_world = rotation
            rig.rotation_euler.z = angle
            bpy.context.view_layer.update()
            path = OUT / kind / f"{direction}-{index}.png"
            path.parent.mkdir(parents=True, exist_ok=True)
            scene.render.filepath = str(path)
            bpy.ops.render.render(write_still=True)
    metadata = dict(
        entry,
        tool="Blender 4.5.3",
        canvas=[256, 320],
        pivot=[128, 280],
        license="Original Starbase2 artwork",
        style_status="Rejected visual direction; technical validation only",
        source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
    )
    (OUT / kind / "source.json").write_text(json.dumps(metadata, indent=2) + "\n")
