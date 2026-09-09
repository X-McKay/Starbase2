"""Godot can exit zero after script/import errors; treat logged errors as failures."""

import subprocess

for args in [
    ["--editor", "--import"],
    ["--script", "test_state.gd"],
    ["--script", "test_command_board.gd"],
    ["--script", "test_contextual_hud.gd"],
    ["--script", "test_living_foliage.gd"],
    ["--fixed-fps", "60", "--script", "test_inhabited_character.gd"],
    ["--fixed-fps", "60", "--script", "test_inhabited_journey.gd"],
    ["--script", "test_colony_vent.gd"],
    ["--fixed-fps", "60", "--script", "test_living_colony.gd"],
    ["--script", "test_visual_fixture.gd", "--", "--fixture=res://../../fixtures/world/stale.json"],
    ["--script", "test_navigation.gd"],
    ["--script", "test_exploration.gd"],
    ["--script", "test_shelf_shape.gd"],
    ["--script", "test_paths.gd"],
    ["--script", "test_paving.gd"],
    ["--script", "test_paving_lights.gd", "--", "--api=http://127.0.0.1:1"],
    ["--script", "test_surface_scatter.gd", "--", "--api=http://127.0.0.1:1"],
    ["--script", "test_environment.gd", "--", "--api=http://127.0.0.1:1"],
    ["--script", "test_coast.gd", "--", "--api=http://127.0.0.1:1"],
    ["--script", "test_uplands.gd", "--", "--api=http://127.0.0.1:1"],
    ["--script", "test_colony.gd"],
    ["--script", "test_crew.gd"],
    ["--script", "test_character_pipeline.gd"],
    ["--script", "test_illustrated_character.gd"],
    ["--script", "test_character_motion.gd"],
    ["--script", "test_meshy_character.gd"],
    ["--fixed-fps", "60", "--script", "test_run_cadence.gd"],
    ["--script", "test_engineering_polish.gd"],
    ["--fixed-fps", "60", "--script", "test_remaining_structures.gd"],
    ["--fixed-fps", "60", "--script", "test_seamless_colony.gd"],
    ["--script", "test_character_lab.gd"],
    ["--script", "test_field_crew.gd", "--", "--api=http://127.0.0.1:1"],
    ["--script", "test_kit.gd"],
    ["--script", "test_structures.gd"],
    ["--script", "test_rooms.gd", "--", "--api=http://127.0.0.1:1"],
    ["--script", "test_interaction.gd", "--", "--api=http://127.0.0.1:1"],
]:
    try:
        result = subprocess.run(
            ["godot", "--headless", "--path", "apps/world", *args],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
        )
    except subprocess.TimeoutExpired as error:
        output = error.stdout or ""
        print(output.decode(errors="replace") if isinstance(output, bytes) else output, flush=True)
        raise SystemExit(
            f"Godot validation timed out: {args}; retained partial output above."
        ) from error
    print(result.stdout)
    if result.returncode or "ERROR:" in result.stdout or "Parse Error" in result.stdout:
        raise SystemExit("Godot validation failed; inspect the retained command output.")
