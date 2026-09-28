extends SceneTree
## Same-process native A/B: only the roof sightline clip changes between images.
var output := ""
func _initialize() -> void: run.call_deferred()
func shot(name: String) -> void:
	for frame in range(5): await process_frame
	RenderingServer.force_draw(false)
	assert(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK)
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	assert(not output.is_empty() and DisplayServer.get_name()!="headless")
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(90).timeout.connect(func():push_error("INTERIOR_SIGHTLINES_CAPTURE_TIMEOUT");quit(1))
	root.size=Vector2i(1280,800); root.content_scale_size=root.size
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json"
	world.board_fixture="__empty_visual_fixture__"; world.player_preferences_path=""
	root.add_child(world); world.isolate_capture_input()
	await process_frame; await physics_frame
	world.hud.reduced=true; world.apply_settings(); world.hud.root.hide()
	world.set_process(false); world.set_physics_process(false)
	var report := {"fixture":true,"same_process":true,"only_variant":"roof sightline shader clip", "captures":[]}
	for id in ["review","gym"]:
		var station:Node3D
		for placed in world.get_node("Structures").get_children():
			if str(placed.definition.id)==id: station=placed
		assert(station!=null)
		world.enter_room(str(station.name))
		station.update_presentation(world.get_node("Operator").position,1,true)
		await physics_frame; await physics_frame
		world.process_mode=Node.PROCESS_MODE_DISABLED
		var content:Node3D=station.room.content
		world.camera.position=content.get_node("CameraPosition").global_position
		world.camera.look_at(content.get_node("CameraFocus").global_position)
		world.camera.size=float(content.get_node("CameraFocus").get_meta("view_size"))
		var roof_materials:Array[ShaderMaterial]=[]
		for material in station.reveal_materials:
			if material.get_shader_parameter("sightline_clip")==true: roof_materials.append(material)
		assert(not roof_materials.is_empty())
		for clipped in [false,true]:
			for material in roof_materials: material.set_shader_parameter("sightline_clip",clipped)
			var name:String=id+("-after" if clipped else "-before")
			await shot(name)
			report.captures.append({"name":name,"camera":str(world.camera.global_transform),"size":world.camera.size,"clipped":clipped})
		world.process_mode=Node.PROCESS_MODE_INHERIT
		world.exit_room()
		station.update_presentation(station.return_position()+Vector3(0,0,8),1,true)
		world.process_mode=Node.PROCESS_MODE_DISABLED
		await shot(id+"-exterior")
	assert(world.commands.payload.is_empty())
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("INTERIOR_SIGHTLINES_CAPTURE_PASSED: native same-camera before/after, no commands")
	quit()
