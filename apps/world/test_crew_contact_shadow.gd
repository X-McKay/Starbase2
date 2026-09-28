extends SceneTree
## Verify real actor grounding and optional same-camera native old/new contact cue.
var output:=""
var failures:Array[String]=[]
func check(value:bool,message:String) -> void:
	if not value:failures.append(message);push_error(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	var world=load("res://main.tscn").instantiate();world.fixture_path="res://../../fixtures/world/stale.json";world.board_fixture="__empty_visual_fixture__";world.player_preferences_path=""
	root.add_child(world);await process_frame;await physics_frame
	world.isolate_capture_input();world.hud.reduced=true;world.apply_settings()
	var actor:Node3D=world.get_node("Operator")
	var shadow:MeshInstance3D=actor.contact_shadow
	check(shadow.mesh is PlaneMesh and shadow.material_override is ShaderMaterial,"Crew uses a translucent planar contact cue")
	check(shadow.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and shadow.find_children("*","CollisionObject3D",true,false).is_empty(),"Contact cue has no collision or cast shadow")
	var plane:=shadow.mesh;var material:=shadow.material_override
	for location in ["soil","habitat"]:
		if location=="habitat":world.enter_room("habitat");actor.position=world.active_room.to_global(Vector3(-3,0,0))
		else:actor.position=Vector3(15,0,12)
		actor.motion=Vector3.ZERO
		for frame in range(12):await physics_frame
		var ground:float=actor.support_sample.call(actor.global_position)
		check(absf(shadow.global_position.y-ground-.015)<.0001,"Contact follows actual support surface in "+location)
		var before:Transform3D=shadow.global_transform
		for frame in range(6):await physics_frame
		check(shadow.global_transform.is_equal_approx(before),"Reduced motion keeps contact stable in "+location)
		if output.is_empty():continue
		world.process_mode=Node.PROCESS_MODE_DISABLED;world.hud.root.hide();actor.label.hide()
		var focus:Vector3=actor.global_position+Vector3(0,.9,0)
		world.camera.size=4.8;world.camera.position=focus+Vector3(3.5,4,6);world.camera.look_at(focus)
		for treatment in ["opaque-before","soft-after"]:
			if treatment=="opaque-before":
				var old:=CylinderMesh.new();old.top_radius=.36;old.bottom_radius=.36;old.height=.015;old.radial_segments=12
				shadow.mesh=old;shadow.material_override=load("res://art.gd").mat("456169")
			else:shadow.mesh=plane;shadow.material_override=material
			await process_frame;RenderingServer.force_draw(false)
			check(root.get_texture().get_image().save_png(output.path_join(location+"-"+treatment+".png"))==OK,"Save contact-shadow comparison")
		world.process_mode=Node.PROCESS_MODE_INHERIT
	check(world.commands.payload.is_empty(),"Contact cue does not dispatch work")
	world.queue_free();await process_frame
	if failures.is_empty():print("CREW_CONTACT_SHADOW_PASSED")
	quit(0 if failures.is_empty() else 1)
