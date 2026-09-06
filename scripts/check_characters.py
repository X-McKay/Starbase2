"""Validate the character package, optionally re-rendering editable Blender sources."""

import argparse
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(args: list[str], timeout: int = 60) -> None:
    result = subprocess.run(
        args, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout
    )
    print(result.stdout)
    if result.returncode or any(
        marker in result.stdout for marker in ("ERROR:", "Assertion failed", "Traceback (")
    ):
        raise SystemExit("Character check failed; inspect this output before retrying.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--render", action="store_true", help="Render sources, pack and validate")
    parser.add_argument("--blender", help="Path to Blender 4.5.3 executable")
    parser.add_argument("--illustrated-manifest", help="Import an illustrated PNG manifest first")
    parser.add_argument(
        "--illustrated", action="store_true", help="Rebuild the illustrated catalog"
    )
    args = parser.parse_args()
    manifests = [args.illustrated_manifest] if args.illustrated_manifest else []
    if args.illustrated:
        catalog = ROOT / "art/characters/illustrated.json"
        manifests += [str(catalog.parent / name) for name in json.loads(catalog.read_text())]
    for manifest in manifests:
        run(
            [
                "godot",
                "--headless",
                "--path",
                "apps/world",
                "--script",
                "characters/illustrated_import.gd",
                "--quit-after",
                "2",
                "--",
                "--manifest=" + manifest,
            ]
        )
    if args.render:
        local = ROOT / ".local/tools/character-renderer/Blender.app/Contents/MacOS/Blender"
        blender = args.blender or shutil.which("blender") or str(local)
        run(
            [blender, "--background", "--factory-startup", "--python", "art/characters/render.py"],
            300,
        )
        run(["godot", "--headless", "--path", "apps/world", "--script", "characters/pack.gd"])
    run(["godot", "--headless", "--path", "apps/world", "--editor", "--import"])
    for script in [
        "test_character_pipeline.gd",
        "test_illustrated_character.gd",
        "test_character_motion.gd",
        "test_character_lab.gd",
    ]:
        run(
            [
                "godot",
                "--headless",
                "--path",
                "apps/world",
                "--max-fps",
                "60",
                "--quit-after",
                "600",
                "--script",
                script,
            ]
        )


if __name__ == "__main__":
    main()
