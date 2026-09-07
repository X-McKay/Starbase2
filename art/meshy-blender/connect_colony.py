"""Generate Godot scene resources from Blender's authoritative colony layout."""

import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[2]
world = root / "apps/world"
layout = json.loads((root / "art/meshy-blender/colony-layout.json").read_text())


def vec(values):
    return "Vector3(" + ",".join(f"{x:.4f}" for x in values) + ")"


def rect(values):
    return "Rect2(" + ",".join(f"{x:.4f}" for x in values) + ")"


for kind, data in layout.items():
    exterior = f"res://art/colony-3d/{kind}-shell.glb"
    furniture = f"res://art/colony-3d/{kind}-interior.glb"
    (world / f"buildings/exteriors/{kind}-continuous.tscn").write_text(
        "[gd_scene load_steps=2 format=3]\n"
        f'[ext_resource type="PackedScene" path="{exterior}" id="1"]\n'
        '[node name="Shell" instance=ExtResource("1")]\n'
    )
    blocks = data["blocks"]
    text = f"[gd_scene load_steps={len(blocks) + 2 + (kind == 'repair')} format=3]\n"
    text += f'[ext_resource type="PackedScene" path="{furniture}" id="1"]\n'
    if kind == "repair":
        reactor = "res://art/meshy/reactor-apparatus.glb"
        text += f'[ext_resource type="PackedScene" path="{reactor}" id="2"]\n'
    for index, block in enumerate(blocks):
        size = vec([block["rect"][2], block["height"], block["rect"][3]])
        text += f'[sub_resource type="BoxShape3D" id="Shape{index}"]\nsize = {size}\n'
    text += '[node name="Interior" type="Node3D"]\n'
    text += '[node name="Furniture" parent="." instance=ExtResource("1")]\n'
    if kind == "repair":
        x, z, width, depth = blocks[0]["rect"]
        text += '[node name="Reactor" parent="." instance=ExtResource("2")]\n'
        text += f"position = {vec([x + width / 2, 0, z + depth / 2])}\n"
    for index, block in enumerate(blocks):
        x, z, width, depth = block["rect"]
        text += f'[node name="Prop{index}" type="StaticBody3D" parent="."]\n'
        text += f"position = {vec([x + width / 2, block['height'] / 2, z + depth / 2])}\n"
        text += f'[node name="Collision" type="CollisionShape3D" parent="Prop{index}"]\n'
        text += f'shape = SubResource("Shape{index}")\n'
    for name, position in data["markers"].items():
        text += f'[node name="{name}" type="Marker3D" parent="."]\n'
        text += f"position = {vec(position)}\n"
    (world / f"buildings/interiors/{kind}-continuous.tscn").write_text(text)
    definition = world / f"buildings/definitions/{kind}.tres"
    generated_fields = (
        "exterior_image|exterior_scene|interior_scene|threshold|approach|return_point|"
        "seamless|room_blocks|interior_bounds"
    )
    text = re.sub(rf"^({generated_fields}) = .*\n", "", definition.read_text(), flags=re.M)
    threshold = data["threshold"]
    text += "seamless = true\n"
    text += f'exterior_scene = "res://buildings/exteriors/{kind}-continuous.tscn"\n'
    text += f'interior_scene = "res://buildings/interiors/{kind}-continuous.tscn"\n'
    text += f"interior_bounds = {rect(data['bounds'])}\nthreshold = {vec(threshold)}\n"
    text += f"approach = {vec([threshold[0], 0, threshold[2] + 0.85])}\n"
    text += f"return_point = {vec([threshold[0], 0, threshold[2] + 1.55])}\n"
    text += "room_blocks = Array[Rect2](["
    text += ",".join(rect(block["rect"]) for block in blocks) + "])\n"
    definition.write_text(text)
