extends SceneTree
## Native fixture-only exterior/inspection acceptance; no production connections.
var output := ""
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void: run.call_deferred()
func picture(name: String) -> void:
	await process_frame; await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Saved "+name)
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if output.is_empty() or DisplayServer.get_name()=="headless": push_error("Native station capture requires renderer and --output"); quit(1); return
	create_timer(60).timeout.connect(func(): push_error("Station capture watchdog"); quit(1))
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json"
	world.board_fixture="__empty_visual_fixture__"
	root.add_child(world); world.isolate_capture_input()
	await process_frame; await physics_frame
	check(not world.fixture_path.is_empty() and not world.hud.board.fixture.is_empty(),"Offline fixtures retained")
	DirAccess.make_dir_recursive_absolute(output)
	world.hud.close_panels(); world.stop_watching()
	var command=world.get_node(world.STATIONS.review)
	world.get_node("Operator").position=command.entrance()+Vector3(0,0,7)
	world.hud.follow=true
	var rehearsal=load("res://shift_change_capture.gd").new()
	rehearsal.scene=world; rehearsal.observation=Time.get_unix_time_from_system()+10
	rehearsal.project([rehearsal.record("station-active","running"),rehearsal.record("station-completed","completed")])
	for i in range(150): await physics_frame
	check(world.station_signals.visible_context=="review","Command signal visible from exterior")
	await picture("01-fresh-command")
	world.disconnected=true; world.show_mission()
	await picture("02-offline-command")
	check(world.station_signals.labels.review.text.contains("OFFLINE"),"Offline aggregate explicit")
	var click:=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true
	click.position=world.camera.unproject_position(world.station_signals.labels.review.global_position)
	world._unhandled_input(click)
	await process_frame
	check(world.hud.station_records.visible,"Physical badge click opens native station records")
	await picture("03-pointer-inspector")
	world.hud.close_panels()
	var key:=InputEventKey.new(); key.physical_keycode=KEY_I; key.pressed=true
	world._unhandled_key_input(key)
	await process_frame
	check(world.hud.station_records.visible,"I opens same native station records")
	await picture("04-keyboard-inspector")
	check(world.hud.station_records.model.reports.size()==2,"Station inspector retains both field-run identities")
	var inspect_buttons=world.hud.station_records.reports.find_children("*","Button",true,false)
	inspect_buttons[0].pressed.emit()
	await process_frame; await process_frame
	check(world.hud.board.visible and world.hud.board.selected=="station-active","Exact field-run inspector opens native Command for selected ID")
	await picture("04b-exact-field-record")
	world.hud.open_place("reviewer"); world.show_mission()
	await picture("04c-crew-dossier")
	world.hud.toggle_settings()
	await picture("04d-settings")
	world.hud.open_operations()
	await picture("04e-work")
	check(world.commands.phase.is_empty() and world.hud.board.commands.phase.is_empty(),"Read-only inspection issues no commands")
	world.hud.close_panels(); world.hud.large_text=true; world.apply_settings()
	for i in range(3): await process_frame
	await picture("05-large-text")
	root.size=Vector2i(800,640); root.content_scale_size=Vector2i(800,640)
	world.open_station_records("review")
	for i in range(5): await process_frame
	await picture("06-compact-large-inspector")
	check(root.get_visible_rect().encloses(world.hud.station_records.get_global_rect()),"Compact large-text station inspector fits")
	world.hud.close_panels()
	for i in range(3): await process_frame
	await picture("07-compact-exterior")
	var report={"failures":failures,"fixture":true,"native":true,"pointer_station_records":true,"keyboard_station_records":true,"scope":"Explicit staged exterior fixture; no production commands or travel acceptance"}
	FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("STATION_SIGNALS_NATIVE_PASSED")
	quit(0 if failures.is_empty() else 1)
