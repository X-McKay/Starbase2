extends SceneTree
var output := "res://../../.local/captures/morning-atmosphere"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): output=arg.trim_prefix("--capture-dir=")
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output)!=OK:
		push_error("Cannot create capture output directory"); quit(1); return
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json"
	world.board_fixture="__empty_visual_fixture__"
	root.add_child(world)
	await process_frame
	var morning=world.get_node_or_null("MorningAtmosphere")
	if morning==null:
		morning=preload("res://morning_atmosphere.gd").new()
		world.add_child(morning); morning.install(world)
	world.enter_room("habitat")
	world.get_node("Operator").position=world.get_node("Structures/Habitat").to_global(Vector3(0,0,-3))
	world.route=[]
	for i in range(100):
		await process_frame
		morning.update_presentation([world.get_node("Operator").position],0.016,false)
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(output.path_join("habitat-native.png"))
	world.set_physics_process(false)
	world.set_process(false)
	var station=world.get_node("Structures/Habitat")
	var threshold:Vector3=station.to_global(station.definition.threshold)
	world.camera.position=threshold+Vector3(5,5,7)
	world.camera.look_at(threshold+Vector3(0,1.5,0))
	world.camera.size=8.0
	for i in range(10):
		await process_frame
		morning.update_presentation([threshold],0.016,false)
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(output.path_join("doorway-native.png"))
	print("Morning atmosphere native captures complete")
	quit()
