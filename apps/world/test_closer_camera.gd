extends SceneTree
## Native before/after framing and focused camera/control regression journey.
var failures:Array[String]=[]
var records:Array[Dictionary]=[]
var output:=""
var baseline:=false
var exterior_two_step:=false
var world:Node3D
func check(value:bool,message:String) -> void:
	if not value:failures.append(message);push_error(message)
func _initialize() -> void:run.call_deferred()
func picture(name:String) -> void:
	for tick in range(6):await process_frame
	world._process(1.0)
	var actor:Node3D=world.get_node("Operator")
	var point:Vector2=world.camera.unproject_position(actor.global_position+Vector3(0,.8,0))
	records.append({"name":name,"camera_size":world.camera.size,"operator_screen":str(point),"viewport":str(root.size)})
	if not output.is_empty():
		RenderingServer.force_draw(false)
		check(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Save native camera comparison")
func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
		if argument=="--baseline":baseline=true
		if argument=="--exterior-two-step":exterior_two_step=true
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json";world.board_fixture="__empty_visual_fixture__";world.player_preferences_path=""
	root.add_child(world);await process_frame;await physics_frame
	# Explicit capture override retained for reproducing the stronger review.
	if exterior_two_step:world.zoom=34.0/pow(1.2,2)
	world.isolate_capture_input();world.hud.reduced=true;world.apply_settings()
	var actor:Node3D=world.get_node("Operator")
	var scale:=1.0 if baseline else 1.0/1.2
	var exterior_scale:float=1.0 if baseline else 1.0/pow(1.2,2)
	actor.position=Vector3(-3,0,-14.9);world.overview=actor.position;world._process(1)
	check(absf(world.camera.size-34.0*exterior_scale)<.01,"Outdoor starts at the requested review scale")
	await picture("exterior")
	world.adjust_zoom(-1);world._process(1);check(absf(world.camera.size-34.0*exterior_scale/1.2)<.01,"Manual zoom in remains relative to default")
	world.adjust_zoom(1);world._process(1);check(absf(world.camera.size-34.0*exterior_scale)<.01,"Manual zoom out restores default")
	world.colony_overview=true;world._process(1);check(absf(world.camera.size-142.0)<.01,"Map keeps its full colony framing")
	await picture("map");world.colony_overview=false
	world.enter_room("habitat");actor.position=world.active_room.to_global(Vector3(-3,0,0));world._process(1)
	await picture("habitat")
	var room_size:float=world.camera.size
	var authored_size:float=world.active_room.content.get_node("CameraFocus").get_meta("view_size",18.0)
	check(absf(room_size-authored_size*scale)<.01,"Habitat preserves its authored composition one zoom step closer")
	world.watch_crew("repair");world._process(1)
	check(absf(world.camera.size-8.8)<.01,"Explicit indoor crew watch retains authored scale")
	world.stop_watching();world._process(1)
	root.size=Vector2i(800,640);root.content_scale_size=root.size;world.hud.large_text=true;world.hud.scale_text()
	await picture("habitat-compact")
	var p:Vector2=world.camera.unproject_position(actor.global_position+Vector3(0,.8,0))
	check(Rect2(0,100,800,370).has_point(p),"Compact room operator stays in unobscured play area")
	world.hud.open_room_details("PIONEER HABITAT","Camera review fixture; no work is dispatched.")
	await picture("guide-compact")
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(world.hud.room_details.get_global_rect()),"Compact large-text guide stays inside viewport")
	world.hud.close_panels();world.exit_room();root.size=Vector2i(1280,800);root.content_scale_size=root.size;world.hud.large_text=false;world.hud.scale_text()
	actor.position=Vector3(-6,0,23);world.overview=actor.position;world._process(1)
	await picture("commons")
	check(absf(world.camera.size-13.5*scale)<.01,"Commons uses the same ordinary gameplay step")
	# Real exterior motion with reduced-motion fixed-camera room advancement.
	actor.position=Vector3(-3,0,-14.9);world.overview=actor.position
	world.route=world.travel_route(Vector3(-10,0,-14.9));check(not world.route.is_empty(),"Camera journey has a physical route")
	for tick in range(300):
		await physics_frame
		world._process(1)
		var point:Vector2=world.camera.unproject_position(actor.global_position+Vector3(0,.8,0))
		check(Rect2(168,96,1112,490).has_point(point),"Walking operator remains in unobscured wide play area")
		if world.route.is_empty():break
	check(actor.position.distance_to(Vector3(-10,0,-14.9))<.45,"Closer view preserves physical arrival")
	check(world.commands.payload.is_empty() and world.hud.operations.commands.payload.is_empty(),"Camera journey never dispatches")
	if not output.is_empty():
		var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"baseline":baseline,"exterior_two_step":exterior_two_step,"frames":records,"failures":failures},"  "))
	world.queue_free();await process_frame
	if failures.is_empty():print("CLOSER_CAMERA_PASSED")
	quit(0 if failures.is_empty() else 1)
