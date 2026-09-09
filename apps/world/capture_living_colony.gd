extends SceneTree
## Runs the same live presentation journey used by standalone qualification.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var output:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if output.is_empty():
		push_error("Living colony capture requires --output=<existing-directory>")
		quit(1)
		return
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json"
	world.board_fixture="__empty_visual_fixture__"
	root.add_child(world)
	await process_frame
	await load("res://package_capture.gd").new().run(self,world,output)
