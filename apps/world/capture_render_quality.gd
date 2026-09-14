extends SceneTree
## Same-camera native comparison; fixtures only, no requests or commands.
var output := "res://../../.local/captures/render-quality"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): output=arg.trim_prefix("--capture-dir=")
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output)!=OK:
		push_error("Cannot create capture output directory"); quit(1); return
	if DisplayServer.get_name()=="headless": quit(1); return
	create_timer(55).timeout.connect(func():push_error("Render comparison timed out");quit(1))
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json"
	world.board_fixture="__empty_visual_fixture__"
	root.add_child(world); world.isolate_capture_input()
	await process_frame; await physics_frame
	world.enter_room("Habitat")
	world.hud.close_panels(); world.start_observing()
	for frame in range(120): await process_frame
	world.stop_watching()
	world.set_process(false); world.set_physics_process(false)
	world.camera.size=9.5
	var station=world.get_node("Structures/Habitat")
	var focus:Vector3=station.to_global(Vector3(0,1,-3))
	world.camera.position=focus+Vector3(5,14,18); world.camera.look_at(focus)
	var measurements:Array=[]
	for mode in [Viewport.MSAA_DISABLED,Viewport.MSAA_4X]:
		root.msaa_3d=mode
		for frame in range(60): await process_frame
		var times:Array=[]; var prior:=Time.get_ticks_usec()
		for frame in range(180):
			await process_frame
			var now:=Time.get_ticks_usec(); times.append(float(now-prior)/1000.0); prior=now
		times.sort()
		measurements.append({"msaa":mode,"samples":times.size(),"median_ms":times[90],"p95_ms":times[171],"viewport":str(root.size),"renderer":RenderingServer.get_video_adapter_name()})
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(output.path_join("disabled.png" if mode==Viewport.MSAA_DISABLED else "4x.png"))
	var file:=FileAccess.open(output.path_join("measurements.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fixture":true,"measurements":measurements,"limitations":"Sequential capped native comparison, not an uncapped GPU benchmark"},"  "))
	print("RENDER_QUALITY_PASSED"); quit()
