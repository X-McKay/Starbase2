extends SceneTree
## Every world key binding is listed in Settings > Controls, and every key the
## Controls page lists is actually bound. Reproduces the quick fix from the
## frontend ideas pass: R opened Work but the help did not list it.
## Optional: --hud-script=res://other_hud.gd --world-source=<file> check another revision.
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()

const SPECIAL := {"TAB":"Tab", "ESCAPE":"Esc", "ENTER":"Enter", "EQUAL":"+", "PLUS":"+", "KP_ADD":"+",
	"MINUS":"−", "KP_SUBTRACT":"−", "1":"1–5", "2":"1–5", "3":"1–5", "4":"1–5", "5":"1–5"}

## Keys matched in world.gd's _unhandled_key_input, as help tokens.
static func bound_keys(source: String) -> Array:
	var start := source.find("func _unhandled_key_input")
	var end := source.find("\nfunc ", start + 10)
	var body := source.substr(start, end - start)
	var arm := RegEx.create_from_string("(?m)^\\t\\t((?:KEY_[A-Z0-9_]+(?:, )?)+):")
	var name := RegEx.create_from_string("KEY_([A-Z0-9_]+)")
	var keys: Array = []
	for match in arm.search_all(body):
		for key in name.search_all(match.get_string(1)):
			var token: String = SPECIAL.get(key.get_string(1), key.get_string(1))
			if not keys.has(token): keys.append(token)
	return keys

## Key column of every "<keys>  ·  <action>" line on the Controls page.
static func listed_keys(help: String) -> Array:
	var keys: Array = []
	for line in help.split("\n"):
		if not line.contains("  ·  "): continue
		var column := line.get_slice("  ·  ", 0)
		for part in column.split(" / "):
			for token in part.split(" or "):
				var clean := token.strip_edges()
				if not clean.is_empty() and not keys.has(clean): keys.append(clean)
	return keys

func run() -> void:
	var hud_script := "res://hud.gd"
	var world_source := "res://world.gd"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hud-script="): hud_script = arg.trim_prefix("--hud-script=")
		if arg.begins_with("--world-source="): world_source = arg.trim_prefix("--world-source=")
	var hud = load(hud_script).new()
	root.add_child(hud)
	await process_frame
	var controls: Node = hud.settings_tabs.get_node("Controls")
	var help := "\n".join(controls.find_children("*", "Label", true, false).map(func(label): return label.text))
	var listed := listed_keys(help)
	var bound := bound_keys(FileAccess.get_file_as_string(world_source))
	check(bound.has("R") and bound.has("J"), "Parser finds the R and J bindings: " + str(bound))
	for key in bound:
		check(listed.has(key), "Bound key %s is listed in Controls (listed: %s)" % [key, listed])
	# Reverse direction for single letters: help must not promise an unbound key.
	# F1 lives in hud.gd; W, T and the crew board keys are routed by the HUD.
	for key in listed:
		if key.length() == 1 and key.unicode_at(0) >= 65 and key.unicode_at(0) <= 90 and not key in ["W", "A", "S", "D"]:
			check(bound.has(key), "Listed key %s is bound in world.gd" % key)
	check(help.contains("J / R  ·  Work & history"), "R is listed as Work beside J")
	check(help.contains("Tab  ·  Crew board") and help.contains("P  ·  Crew & places"), "Tab opens the crew board; P keeps Crew & places")
	hud.queue_free()
	await process_frame
	# The binding itself: R still opens Work from the world.
	var world = load("res://main.tscn").instantiate()
	world.fixture_path = "res://../../fixtures/world/stale.json"
	world.board_fixture = "__empty_visual_fixture__"
	world.player_preferences_path = ""
	root.add_child(world)
	await process_frame
	var press := InputEventKey.new()
	press.physical_keycode = KEY_R; press.keycode = KEY_R; press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await process_frame
	check(world.hud.operations.visible, "R opens Work & history")
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("KEY_HELP_PASSED: every world key binding is listed and every listed key is bound")
	quit(0 if failures.is_empty() else 1)
