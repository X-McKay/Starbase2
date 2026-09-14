extends SceneTree

var output: String=""

func _initialize() -> void:
	run.call_deferred()

func picture(name:String) -> void:
	for frame in 4: await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(output.path_join(name+".png"))

func key(code:Key) -> void:
	var event:=InputEventKey.new()
	event.pressed=true; event.physical_keycode=code
	root.push_input(event)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): output=arg.trim_prefix("--capture-dir=")
	if output.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(output)
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json"
	world.board_fixture="__empty_visual_fixture__"
	root.add_child(world)
	for frame in 10: await process_frame
	print("NATIVE_INITIAL window=%s root=%s viewport=%s" % [root.size,root.size,root.get_viewport().get_visible_rect().size])
	world.enter_room("habitat")
	for frame in 4: await process_frame
	print("NATIVE_HABITAT room=%s building=%s" % [world.room_kind,str(world.active_building.name)])
	world.hud.open_connection()
	await process_frame
	var connection_open:bool=world.hud.connection_panel.visible
	var focus=world.hud.connection_panel.endpoint
	focus.grab_focus(); await process_frame
	key(KEY_ESCAPE); await process_frame
	print("NATIVE_ESCAPE focused_line_edit open_before=%s open_after=%s" % [connection_open,world.hud.is_open()])
	world.hud.open_connection(); await process_frame
	var collapsed:bool=world.hud.exploration_hud_collapsed
	key(KEY_F1); await process_frame
	print("NATIVE_F1 focused_line_edit collapsed_before=%s collapsed_after=%s" % [collapsed,world.hud.exploration_hud_collapsed])
	root.size=Vector2i(800,640)
	for frame in 8: await process_frame
	world.hud.open_operations(); await process_frame
	print("NATIVE_COMPACT window=%s root=%s viewport=%s" % [root.size,root.size,root.get_viewport().get_visible_rect().size])
	await picture("800x640-reflow")
	world.queue_free(); await process_frame; quit()
