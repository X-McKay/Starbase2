extends SceneTree
## Native-only bounded fixture rehearsal; no production credentials or commands.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(180.0).timeout.connect(func(): push_error("Morning journey total watchdog expired"); quit(1))
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Morning journey requires a native renderer and --output=<directory>")
		quit(1); return
	var world = load("res://main.tscn").instantiate()
	world.fixture_path = "res://../../fixtures/world/stale.json"
	world.board_fixture = "__empty_visual_fixture__"
	root.add_child(world)
	world.isolate_capture_input()
	await process_frame; await physics_frame
	var rehearsal = load("res://morning_capture.gd").new()
	await rehearsal.run(self, world, output)
