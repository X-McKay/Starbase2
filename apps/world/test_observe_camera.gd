extends SceneTree
## Offline Observe journey: a fresh two-crew exchange receives one readable
## composition, camera movement eases, and view changes never dispatch work.
const Handoff=preload("res://crew_handoff.gd")
var failures:Array[String]=[]
var output:=""
var candidate_review:=false

func check(ok:bool,message:String) -> void:
	if not ok:failures.append(message);push_error(message)

func _initialize() -> void:run.call_deferred()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=ProjectSettings.globalize_path(arg.trim_prefix("--output="))
		if arg=="--candidates":candidate_review=true
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1440,900);root.content_scale_size=root.size
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json";world.board_fixture="__empty_visual_fixture__";world.player_preferences_path=""
	root.add_child(world);await process_frame;await physics_frame
	world.isolate_capture_input();world.poll_timer.stop();world.http.cancel_request();world.set_physics_process(false)
	var giver:Node3D=world.get_node(world.MEMBERS.repair)
	var receiver:Node3D=world.get_node(world.MEMBERS.reviewer)
	giver.position=Handoff.WEST;receiver.position=Handoff.EAST
	giver.visible=true;receiver.visible=true
	giver.set_physics_process(false);receiver.set_physics_process(false)
	giver.model_visual.exchange_partner=receiver;giver.model_visual.exchange_role="giver"
	receiver.model_visual.exchange_partner=giver;receiver.model_visual.exchange_role="receiver"
	for frame in 80:
		giver.model_visual.project(Vector3.ZERO,false,0.0,false,1.0/60.0,"handoff",PI/2)
		receiver.model_visual.project(Vector3.ZERO,false,0.0,false,1.0/60.0,"handoff",-PI/2)
	world.handoff_token.global_position=(giver.global_position+receiver.global_position)*.5+Vector3(0,1.12,0)
	world.handoff_token.show()
	world.crew_handoff.current={"giver":"repair","receiver":"reviewer","mission_id":"fixture"}
	world.morning_director.start();world.morning_director.selected="repair";world.watched_crew="repair"
	var before:float=world.camera_focus.distance_to((giver.position+receiver.position)*.5+Vector3(0,.95,0))
	world._process(1.0/60.0)
	var after:float=world.camera_focus.distance_to((giver.position+receiver.position)*.5+Vector3(0,.95,0))
	check(after<before and after>0.0,"Observe eases toward the exchange")
	for frame in 5:world._process(1.0)
	var composition:Dictionary=world.morning_director.composition_pair(giver,receiver,world.get_world_3d().direct_space_state)
	check(composition.offset==Vector3(3.5,1.7,-2.0),"Commons handoff uses the clear full-body side angle")
	check(world.camera_focus.distance_to(composition.focus)<.02,"Observe frames both arriving crew")
	check(absf(world.camera.size-composition.size*world.zoom_factor)<.02,"Handoff uses its own close two-person scale")
	check(world.commands.payload.is_empty() and world.hud.operations.commands.payload.is_empty(),"Camera movement does not dispatch work")
	if not output.is_empty():
		world.hud.root.hide()
		for frame in 8:await process_frame
		RenderingServer.force_draw(false)
		check(root.get_texture().get_image().save_png(output.path_join("observe-handoff.png"))==OK,"Save native handoff frame")
		if candidate_review:
			world.set_process(false)
			var offsets:Array=[Vector3(2.6,1.8,1.0),Vector3(3.0,2.2,-1.5),Vector3(-2.8,2.1,-.4),Vector3(3.5,2.0,0.0),Vector3(3.5,1.7,-2.0)]
			for index in offsets.size():
				world.camera.position=composition.focus+offsets[index]
				world.camera.look_at(composition.focus)
				world.camera.size=4.7
				for frame in 3:await process_frame
				RenderingServer.force_draw(false)
				check(root.get_texture().get_image().save_png(output.path_join("candidate-%d.png"%index))==OK,"Save camera candidate")
	world.handoff_token.hide();world._process(1.0)
	check(world.camera_focus.distance_to(composition.focus)>0.02,"After exchange Observe returns to single-subject framing")
	world.crew_handoff.current.clear()
	giver.hide();world.watched_crew="reviewer";world.morning_director.shot="over_shoulder"
	receiver.position=world.crew_motions.reviewer.workstation
	world.crew_motions.reviewer.intent={"goal":"workstation","unknown":false,"active_count":1}
	var interaction:Node3D=world.interaction_stations.reviewer
	interaction.global_position=Vector3(receiver.position.x,interaction.global_position.y,receiver.position.z)
	receiver.model_visual.interaction_station=interaction;receiver.model_visual.seating_station=interaction
	for structure in world.get_node("Structures").get_children():
		if not structure.contains(receiver.position):continue
		structure.cutaway=0.0;structure.room.visible=true
		for material in structure.cut_materials:material.set_shader_parameter("visibility",0.0)
		for material in structure.reveal_materials:material.set_shader_parameter("visibility",1.0)
	for frame in 90:
		receiver.model_visual.project(Vector3.ZERO,false,0.0,false,1.0/60.0,"sit",atan2(interaction.facing_point().x-receiver.position.x,interaction.facing_point().z-receiver.position.z))
	for frame in 5:world._process(1.0)
	var work:Dictionary=world.morning_director.composition(receiver,interaction,true,world.get_world_3d().direct_space_state)
	check(world.camera_focus.distance_to(work.focus)<.02 and work.offset.is_finite(),"Observe settles on the workstation shot")
	if not output.is_empty():
		for frame in 8:await process_frame
		RenderingServer.force_draw(false)
		check(root.get_texture().get_image().save_png(output.path_join("observe-work.png"))==OK,"Save native workstation frame")
	world.queue_free();await process_frame
	if failures.is_empty():print("OBSERVE_CAMERA_PASSED: smooth arrival, two-person scale, return, no dispatch")
	quit(0 if failures.is_empty() else 1)
