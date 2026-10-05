extends SceneTree
## Comfort settings (reduced motion, larger text, ambient sound, crew summary)
## survive a restart through user:// preferences, keep the character choice,
## ignore malformed values, and are never read by fixture runs.
const Preferences = preload("res://player_preferences.gd")
var failures: Array[String] = []
var config_path := ""
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()

func make_world(path: String) -> Node:
	var world = load("res://main.tscn").instantiate()
	world.fixture_path = "res://../../fixtures/world/stale.json"
	world.board_fixture = "__empty_visual_fixture__"
	world.player_preferences_path = path
	root.add_child(world)
	return world

## Find a Display/Audio toggle by its label, so the test reads the real UI.
func toggle(world: Node, prefix: String) -> CheckButton:
	for item in world.hud.help.find_children("*", "CheckButton", true, false):
		if item.text.begins_with(prefix): return item
	return null

func run() -> void:
	root.size = Vector2i(1280, 800); root.content_scale_size = root.size
	config_path = OS.get_user_data_dir().path_join("starbase2-comfort-test-%d.cfg" % OS.get_process_id())
	DirAccess.remove_absolute(config_path)
	Preferences.write_character("cybercat", config_path)
	var world := make_world(config_path)
	for _frame in 3: await process_frame
	check(not world.hud.reduced and not world.hud.large_text and not world.hud.sound_enabled, "Defaults are off with no saved comfort settings")
	for prefix in ["Reduced motion", "Larger interface text", "Ambient sounds", "Crew summary"]:
		var item := toggle(world, prefix)
		check(item != null, "Toggle exists: " + prefix)
		if item != null: item.button_pressed = true
	await process_frame
	world.queue_free()
	await process_frame
	# Restart: a new world reads the same user:// file.
	world = make_world(config_path)
	for _frame in 3: await process_frame
	check(world.hud.reduced and world.hud.large_text and world.hud.sound_enabled and world.hud.crew_summary, "Comfort settings restored after restart")
	for prefix in ["Reduced motion", "Larger interface text", "Ambient sounds", "Crew summary"]:
		var item := toggle(world, prefix)
		check(item != null and item.button_pressed and item.text.ends_with("· On"), "Restored toggle shows On: " + prefix)
	check(world.foley.enabled and world.get_node("Operator").reduced_motion, "Restored settings are applied, not only displayed")
	check(world.hud.prompt.get_theme_font_size("font_size") > 14, "Larger text is applied to labels")
	check(world.player_character_id == "cybercat", "The character choice is kept beside comfort settings")
	var item := toggle(world, "Reduced motion")
	if item != null: item.button_pressed = false
	await process_frame
	world.queue_free()
	await process_frame
	check(Preferences.read_comfort(config_path).get("reduced_motion", true) == false and Preferences.read_comfort(config_path).get("large_text", false), "Turning one setting off saves only that change")
	# Malformed values are ignored; the rest still load.
	var config := ConfigFile.new()
	config.load(config_path)
	config.set_value("comfort", "large_text", "yes")
	config.save(config_path)
	check(not Preferences.read_comfort(config_path).has("large_text") and Preferences.read_comfort(config_path).get("sound", false), "A malformed value is ignored")
	check(Preferences.read_comfort("").is_empty() and Preferences.read_comfort(config_path + ".missing").is_empty(), "No file means no saved settings")
	# A fixture run with the default path neither reads nor writes preferences.
	var fixture_world = load("res://main.tscn").instantiate()
	fixture_world.fixture_path = "res://../../fixtures/world/stale.json"
	fixture_world.board_fixture = "__empty_visual_fixture__"
	root.add_child(fixture_world)
	await process_frame
	check(fixture_world.player_preferences_path.is_empty(), "Fixture runs do not use personal preferences")
	fixture_world.queue_free()
	await process_frame
	DirAccess.remove_absolute(config_path)
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("COMFORT_SETTINGS_PASSED: reduced motion, larger text, sound and crew summary persist across restarts")
	quit(0 if failures.is_empty() else 1)
