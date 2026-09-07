extends SceneTree
## Native offline visual evidence. No operational actions are submitted.
var world: Node3D
var output := ""
var only := ""
func _initialize() -> void: run.call_deferred()
func capture(name: String) -> void:
	for tick in range(12): await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(output.path_join(name+".png"))
	assert(result==OK,"Capture must be written: "+name)
	print("CAPTURE ",name)
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg.begins_with("--only="): only=arg.trim_prefix("--only=")
	assert(not output.is_empty())
	world=load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	assert(not world.fixture_path.is_empty(),"Offline fixture is required")
	world.set_physics_process(false)
	world.set_process(false)
	world.hud.reduced=true
	var actor=world.get_node("Operator")
	actor.motion=Vector3.ZERO
	world.camera_focus=Vector3(0,0,0)
	world.camera.position=Vector3(38,56,72)
	world.camera.look_at(world.camera_focus)
	world.camera.size=85
	await capture("colony")
	for id in ["review","gym","habitat","greenhouse"]:
		if not only.is_empty() and id!=only: continue
		var station: Node3D
		for placed in world.get_node("Structures").get_children():
			if str(placed.definition.id)==id: station=placed
		assert(station!=null,"Catalog structure must exist: "+id)
		var bounds: Rect2=station.definition.collision_boxes[0]
		world.camera_focus=station.to_global(Vector3(bounds.get_center().x,1.0,bounds.get_center().y))
		world.camera.position=world.camera_focus+Vector3(9,12,17)
		world.camera.look_at(world.camera_focus)
		world.camera.size=maxf(bounds.size.x,bounds.size.y)*1.3
		actor.position=station.return_position()+Vector3(0,0,3)
		station.update_presentation(actor.position+Vector3(0,0,5),1,true)
		world.hud.prompt.text=station.definition.title+" · exterior · offline fixture"
		await capture(id+"-exterior")
		world.enter_room(str(station.name))
		station.update_presentation(actor.position,1,true)
		world.hud.prompt.text=station.definition.title+" · interior · reduced motion · offline fixture"
		await capture(id+"-interior")
		world.exit_room()
		station.update_presentation(actor.position+Vector3(0,0,5),1,true)
	print("REMAINING_STRUCTURES_CAPTURE_PASSED")
	quit()
