"""Connect selected remaining structures; no generation or Engineering writes.

Run with --asset command for the representative slice, or omit for all four.
All selected layouts and prepared resources are checked before any output write.
"""

import argparse
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "apps/world"
FAMILIES = {
    "command": "review",
    "training": "gym",
    "habitat": "habitat",
    "botanical": "greenhouse",
}

# Authored gameplay views and static architectural lighting, never work status.
ROOM_PRESENTATION = {
    "review": ([7, 12, 18], 18.0, [0.42, 0.76, 1.0]),
    "gym": ([-6, 15, 19], 18.5, [0.67, 0.56, 1.0]),
    "habitat": ([8, 13, 17], 19.5, [1.0, 0.70, 0.38]),
    "greenhouse": ([8, 15, 18], 19.0, [0.75, 1.0, 0.75]),
}


def vec(values):
    return "Vector3(" + ",".join(f"{value:.4f}" for value in values) + ")"


def rect(values):
    return "Rect2(" + ",".join(f"{value:.4f}" for value in values) + ")"


def prop_path(asset):
    if asset.endswith("-hull"):
        return f"assets/structures/{asset.removesuffix('-hull')}/hull.glb"
    return f"assets/props/{asset}/{asset}.glb"


def placements(asset, data):
    left, back, width, depth = data["footprint"]
    cx, cz = left + width / 2, back + depth / 2
    if asset == "command":
        return (
            [("CommunicationsArray", "communications-array", [cx - 4.2, 4.05, back + 2.8], 0)],
            [("MissionTable", "mission-table", [cx, 0.25, cz], 0)]
            + [
                (f"Analysis{index}", "analysis-console", [cx + x, 0.15, back + 1.4], 0)
                for index, x in enumerate((-3.2, 3.2))
            ]
            + [
                (f"SideAnalysis{i}", "analysis-console", [cx + x, 0.15, cz], rotation)
                for i, (x, rotation) in enumerate([(-6.7, math.pi / 2), (6.7, -math.pi / 2)])
            ],
        )
    if asset == "training":
        return [], [
            (f"ResistanceBench{i}", "resistance-bench", [cx + x, 0.15, back + 1.5], 0)
            for i, x in enumerate([-3.4, 3.4])
        ] + [
            (f"Simulator{index}", "simulation-station", [cx + offset, 0.28, cz - 0.2], 0)
            for index, offset in enumerate((-3.4, 3.4))
        ]
    if asset == "habitat":
        return [], [
            ("Galley", "frontier-galley", [left + 1.25, 0.15, cz + 0.6], math.pi / 2),
            (
                "LoungeSofa",
                "habitat-lounge-sofa",
                [left + width - 1.2, 0.15, cz + 1.2],
                -math.pi / 2,
            ),
        ] + [
            (f"SleepPod{i}", "sleep-capsule", [cx + i * width * 0.29, 0.15, back + 1.6], 0)
            for i in [-1, 0, 1]
        ]
    return [], [("ResearchBench", "botany-lab-bench", [cx, 0.15, back + 1.0], 0)] + [
        (f"HydroponicRack{ix}{iz}", "hydroponic-rack", [cx + dx, 0.50, cz - 0.85 + dz], math.pi / 2)
        for ix, dx in enumerate((-3.3, 3.3))
        for iz, dz in enumerate((-1.3, 1.3))
    ]


def scene_text(base_path, instances, data=None):
    resources = [base_path]
    for _, asset, _, _ in instances:
        path = prop_path(asset)
        if path not in resources:
            resources.append(path)
    blocks = data["blocks"] if data is not None else []
    text = f"[gd_scene load_steps={len(resources) + len(blocks) + 1} format=3]\n"
    for index, path in enumerate(resources, 1):
        text += f'[ext_resource type="PackedScene" path="res://{path}" id="{index}"]\n'
    for index, block in enumerate(blocks):
        text += f'[sub_resource type="BoxShape3D" id="Shape{index}"]\n'
        text += f"size = {vec([block['rect'][2], block['height'], block['rect'][3]])}\n"
    root_name = "Interior" if data is not None else "Shell"
    text += f'[node name="{root_name}" type="Node3D"]\n'
    base_name = "Furniture" if data is not None else "Architecture"
    text += f'[node name="{base_name}" parent="." instance=ExtResource("1")]\n'
    for name, asset, position, rotation in instances:
        index = resources.index(prop_path(asset)) + 1
        text += f'[node name="{name}" parent="." instance=ExtResource("{index}")]\n'
        text += f"position = {vec(position)}\n"
        if rotation:
            text += f"rotation = {vec([0, rotation, 0])}\n"
    for index, block in enumerate(blocks):
        x, z, width, depth = block["rect"]
        text += f'[node name="Prop{index}" type="StaticBody3D" parent="."]\n'
        text += f"position = {vec([x + width / 2, block['height'] / 2, z + depth / 2])}\n"
        text += f'[node name="Collision" type="CollisionShape3D" parent="Prop{index}"]\n'
        text += f'shape = SubResource("Shape{index}")\n'
    if data is not None:
        left, back, width, depth = data["footprint"]
        identity = next(
            key for key in ROOM_PRESENTATION if base_path.endswith(key + "-interior.glb")
        )
        offset, camera_size, color = ROOM_PRESENTATION[identity]
        focus = [left + width / 2, 1.0, back + depth / 2]
        text += '[node name="CameraFocus" type="Marker3D" parent="."]\n'
        text += f"position = {vec(focus)}\nmetadata/view_size = {camera_size}\n"
        text += '[node name="CameraPosition" type="Marker3D" parent="."]\n'
        text += f"position = {vec([a + b for a, b in zip(focus, offset, strict=True)])}\n"
        for index, x in enumerate((left + width * 0.27, left + width * 0.73)):
            text += f'[node name="TaskLight{index}" type="OmniLight3D" parent="."]\n'
            text += f"position = {vec([x, 2.8, back + 2.5])}\n"
            text += f"light_color = Color({color[0]},{color[1]},{color[2]},1)\n"
            text += "light_energy = 1.35\nomni_range = 7.0\nshadow_enabled = true\n"
        text += '[node name="EntranceLight" type="OmniLight3D" parent="."]\n'
        text += f"position = {vec([left + width / 2, 2.2, back + depth - 1.3])}\n"
        text += "light_color = Color(1,0.68,0.34,1)\nlight_energy = 0.85\nomni_range = 4.5\n"
        if identity == "habitat":
            for index, (position, energy) in enumerate(
                [([-3.8, 2.55, -2.65], 0.65), ([6.5, 2.4, -3.75], 0.55)]
            ):
                text += f'[node name="DomesticLight{index}" type="OmniLight3D" parent="."]\n'
                text += f"position = {vec(position)}\n"
                text += "light_color = Color(1,0.79,0.55,1)\n"
                text += f"light_energy = {energy}\nomni_range = 4.2\n"
        for name, position in data["markers"].items():
            text += f'[node name="{name}" type="Marker3D" parent="."]\n'
            text += f"position = {vec(position)}\n"
    return text, resources


def validate_layout(data):
    for field in ("footprint", "bounds"):
        values = data[field]
        if len(values) != 4 or not all(math.isfinite(v) for v in values) or min(values[2:]) <= 0:
            raise ValueError("Invalid structure " + field)
    for item in data["blocks"]:
        values = item["rect"]
        if len(values) != 4 or not all(math.isfinite(v) for v in values) or min(values[2:]) <= 0:
            raise ValueError("Invalid furniture bounds")
        if not math.isfinite(item["height"]) or item["height"] <= 0:
            raise ValueError("Invalid furniture height")
    for name in ("Spawn", "Console", "Crew", "Activity", "WalkTarget"):
        values = data["markers"][name]
        if len(values) != 3 or not all(math.isfinite(v) for v in values):
            raise ValueError("Invalid marker " + name)


def connect(asset):
    kind = FAMILIES[asset]
    layout = ROOT / "assets-production/structures" / asset / "layout.json"
    data = json.loads(layout.read_text())
    validate_layout(data)
    exterior_props, interior_props = placements(asset, data)
    exterior_props.insert(0, ("GeneratedHull", asset + "-hull", [0, 0, 0], 0))
    output = {}
    for suffix, instances, room in (
        ("shell", exterior_props, None),
        ("interior", interior_props, data),
    ):
        base = f"assets/structures/{asset}/{kind}-{suffix}.glb"
        text, resources = scene_text(base, instances, room)
        for resource in resources:
            if not (WORLD / resource).is_file():
                raise FileNotFoundError(
                    f"Prepare required resource before connecting {asset}: {resource}"
                )
        folder = "exteriors" if suffix == "shell" else "interiors"
        output[WORLD / f"structures/{folder}/{kind}-continuous.tscn"] = text
    definition = WORLD / f"structures/definitions/{kind}.tres"
    text = definition.read_text()
    # Bounds, thresholds, identity and direct-visit metadata stay untouched.
    for field, value in {
        "exterior_scene": f'"res://structures/exteriors/{kind}-continuous.tscn"',
        "interior_scene": f'"res://structures/interiors/{kind}-continuous.tscn"',
        "room_blocks": "Array[Rect2](["
        + ",".join(rect(block["rect"]) for block in data["blocks"])
        + "])",
    }.items():
        text, count = re.subn(rf"^{field} = .*$", f"{field} = {value}", text, flags=re.M)
        if count != 1:
            raise ValueError(f"Expected exactly one {field} in {definition}")
    output[definition] = text
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset", choices=FAMILIES)
    args = parser.parse_args()
    assets = [args.asset] if args.asset else list(FAMILIES)
    outputs = {}
    for asset in assets:
        outputs.update(connect(asset))
    for path, text in outputs.items():
        path.write_text(text)
    print("STRUCTURES_CONNECTED", ", ".join(assets))


if __name__ == "__main__":
    main()
