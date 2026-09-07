"""Connect the reviewed architecture and Meshy assets to the existing station."""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "apps/world"
d = json.loads((ROOT / "assets-production/structures/engineering/layout.json").read_text())


def vec(values):
    return "Vector3(" + ",".join(f"{v:.4f}" for v in values) + ")"


def rect(values):
    return "Rect2(" + ",".join(f"{v:.4f}" for v in values) + ")"


shell = """[gd_scene load_steps=3 format=3]
[ext_resource type="PackedScene" path="res://assets/structures/engineering/engineering-shell.glb" id="1"]
[ext_resource type="PackedScene" path="res://assets/structures/engineering/exterior.glb" id="2"]
[node name="Engineering" type="Node3D"]
[node name="Architecture" parent="." instance=ExtResource("1")]
[node name="GeneratedHull" parent="." instance=ExtResource("2")]
"""
(WORLD / "structures/exteriors/engineering-polished.tscn").write_text(shell)
text = f"[gd_scene load_steps={len(d['blocks']) + 4} format=3]\n"
for i, path, kind in [
    (1, "assets/structures/engineering/engineering-interior.glb", "PackedScene"),
    (2, "assets/props/containment-reactor/reactor.glb", "PackedScene"),
    (3, "structures/engineering_effects.gd", "Script"),
]:
    text += f'[ext_resource type="{kind}" path="res://{path}" id="{i}"]\n'
for i, b in enumerate(d["blocks"]):
    text += f'[sub_resource type="BoxShape3D" id="Shape{i}"]\n'
    text += f"size = {vec([b['rect'][2], b['height'], b['rect'][3]])}\n"
text += '[node name="EngineeringInterior" type="Node3D"]\nscript = ExtResource("3")\n'
text += '[node name="Furniture" parent="." instance=ExtResource("1")]\n'
text += (
    '[node name="Reactor" parent="." instance=ExtResource("2")]\nposition = Vector3(-1.95,0,-2.6)\n'
)
for i, b in enumerate(d["blocks"]):
    x, z, w, h = b["rect"]
    text += f'[node name="Prop{i}" type="StaticBody3D" parent="."]\n'
    text += f"position = {vec([x + w / 2, b['height'] / 2, z + h / 2])}\n"
    text += f'[node name="Collision" type="CollisionShape3D" parent="Prop{i}"]\n'
    text += f'shape = SubResource("Shape{i}")\n'
for name, v in d["markers"].items():
    text += f'[node name="{name}" type="Marker3D" parent="."]\nposition = {vec(v)}\n'
(WORLD / "structures/interiors/engineering-polished.tscn").write_text(text)
p = WORLD / "structures/definitions/repair.tres"
s = p.read_text()
s = re.sub(
    r"^exterior_scene = .*$",
    'exterior_scene = "res://structures/exteriors/engineering-polished.tscn"',
    s,
    flags=re.M,
)
s = re.sub(
    r"^interior_scene = .*$",
    'interior_scene = "res://structures/interiors/engineering-polished.tscn"',
    s,
    flags=re.M,
)
s = re.sub(
    r"^room_blocks = .*$",
    "room_blocks = Array[Rect2]([" + ",".join(rect(b["rect"]) for b in d["blocks"]) + "])",
    s,
    flags=re.M,
)
p.write_text(s)
