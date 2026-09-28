extends SceneTree
var directory:=""
var world:Node3D
var landscape_override:=""
var measurements:Array[Dictionary]=[]
func _initialize() -> void:run.call_deferred()
func shot(name:String,point:Vector3,distance:float,angle:Vector3) -> void:
	world.set_process(false);world.set_physics_process(false)
	for actor in world.find_children("*","CharacterBody3D",true,false):actor.hide()
	for mesh in world.get_node("LivingCommons").find_children("CanopySlats*","MeshInstance3D",true,false):mesh.hide()
	world.camera.position=point+angle;world.camera.look_at(point);world.camera.size=distance
	for frame in 5:await process_frame
	var intervals:Array[float]=[];var previous:=Time.get_ticks_usec()
	for frame in 20:
		await process_frame
		var now:=Time.get_ticks_usec();intervals.append(float(now-previous)/1000.0);previous=now
	intervals.sort()
	RenderingServer.force_draw(false)
	measurements.append({"view":name,"camera_size":distance,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"capture_loop_median_ms":intervals[10],"capture_loop_p95_ms":intervals[18]})
	assert(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK)
func run() -> void:
	create_timer(50).timeout.connect(func():push_error("Vegetation capture exceeded bounded wait");quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):directory=arg.trim_prefix("--output=")
		if arg.begins_with("--landscape-path="):landscape_override=arg.trim_prefix("--landscape-path=")
	assert(not directory.is_empty());DirAccess.make_dir_recursive_absolute(directory)
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	world=load("res://main.tscn").instantiate();world.fixture_path="res://../../fixtures/world/stale.json";world.board_fixture="__empty_visual_fixture__";world.player_preferences_path=""
	if not landscape_override.is_empty():world.get_node("Terrace").set_script(load(landscape_override))
	root.add_child(world);await process_frame;await physics_frame
	world.isolate_capture_input();world.hud.reduced=true;world.apply_settings();world.set_process(false)
	world.hud.root.hide();world.get_node("LivingCommons").update_presentation(Vector3(-7,0,23),1,true)
	var grass_point:=Vector3(-30,0,24);var nearest:=INF
	var terrain=world.get_node("Terrace")
	var points:Array=[]
	if terrain.get_node_or_null("DryFoliage")!=null:
		for record in terrain.get_node("DryFoliage").placements:points.append(record.position)
	else:
		for child in terrain.get_children():
			if child is MeshInstance3D and child.mesh is ArrayMesh and child.mesh.get_surface_count()==1 and child.mesh.surface_get_array_len(0)==15:points.append(child.position)
	for point in points:
		if point.distance_to(Vector3(-30,0,24))<nearest:nearest=point.distance_to(Vector3(-30,0,24));grass_point=point
	print("FOLIAGE_GRASS_FOCUS ",grass_point," tufts=",points.size())
	await shot("exterior-normal",grass_point+Vector3(0,.25,0),9,Vector3(10,11,14))
	await shot("exterior-close",grass_point+Vector3(0,.3,0),1.8,Vector3(5,3,6))
	await shot("exterior-reverse",grass_point+Vector3(0,.3,0),1.8,Vector3(-5,2,-6))
	await shot("commons-normal",Vector3(-7,1,23),11.25,Vector3(10,11,14))
	await shot("commons-close",Vector3(-11.35,1.05,22.0),3.3,Vector3(5,3,6))
	await shot("commons-reverse",Vector3(-11.35,1.05,22.0),3.3,Vector3(-5,2,-6))
	world.enter_room("greenhouse");world.set_process(false)
	var station=world.get_node("Structures/Greenhouse")
	# Asset inspection cutaway: suppress exterior hull, preserve authored interior.
	for hull in station.find_children("GeneratedHull", "Node3D", true, false):hull.hide()
	var focus:Vector3=station.global_position+Vector3(-3.3,1,-5.0)
	station.update_presentation(focus,1,true)
	await shot("botanical-normal",station.global_position+Vector3(0,1,-4.45),15,Vector3(10,11,14))
	await shot("botanical-close",focus,4.5,Vector3(5,4,6))
	var file:=FileAccess.open(directory.path_join("measurements.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"viewport":"1280x800","renderer":"Godot Compatibility","static_fixture":true,"samples_per_view":20,"scope":"Capture-loop intervals; not an FPS improvement benchmark", "views":measurements},"  "))
	world.queue_free();await process_frame;print("DIMENSIONAL_FOLIAGE_CAPTURED");quit()
