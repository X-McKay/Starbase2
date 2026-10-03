extends SceneTree
## Native visual review for cinematic crew work and a recorded SDLC handoff.
## This is an isolated presentation fixture: it makes no network request or command.
const Handoff=preload("res://crew_handoff.gd")
var output:=""
var captures:Array=[]

func _initialize() -> void:run.call_deferred()

func capture(name:String) -> void:
	for frame in 8:await process_frame
	RenderingServer.force_draw(false)
	assert(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK)
	captures.append(name+".png")

func frame_camera(world:Node3D,focus:Vector3,offset:Vector3,size:float) -> void:
	world.camera_focus=focus;world.camera_offset=offset
	world.camera.position=focus+offset;world.camera.look_at(focus);world.camera.size=size

func reveal_containing_room(world:Node3D,point:Vector3) -> void:
	for structure in world.get_node("Structures").get_children():
		if not structure.contains(point):continue
		structure.cutaway=0.0;structure.room.visible=true
		for material in structure.cut_materials:material.set_shader_parameter("visibility",0.0)
		for material in structure.reveal_materials:material.set_shader_parameter("visibility",1.0)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=ProjectSettings.globalize_path(arg.trim_prefix("--output="))
	assert(not output.is_empty());assert(DirAccess.make_dir_recursive_absolute(output)==OK)
	create_timer(90).timeout.connect(func():push_error("Cinematic crew capture timed out");quit(1))
	root.size=Vector2i(1440,900);root.content_scale_size=root.size;root.msaa_3d=Viewport.MSAA_4X
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json";world.board_fixture="__empty_visual_fixture__";world.player_preferences_path=""
	root.add_child(world);await process_frame;await physics_frame
	world.isolate_capture_input();world.poll_timer.stop();world.http.cancel_request();world.set_process(false);world.set_physics_process(false)
	world.hud.root.hide()

	# Actual workstation, independent cast and contact solver; only placement is fixture-controlled.
	var role:="reviewer";var actor:Node3D=world.get_node(world.MEMBERS[role]);var motion=world.crew_motions[role]
	actor.position=motion.workstation;actor.set_physics_process(false);actor.visible=true
	motion.station.update_presentation(actor.position,1.0,true)
	var interaction:Node3D=world.interaction_stations[role]
	interaction.global_position=Vector3(actor.position.x,interaction.global_position.y,actor.position.z)
	actor.presentation_facing=interaction.facing_point();actor.presentation_pose="sit";actor.interaction_station=interaction;actor.seating_station=interaction
	actor.model_visual.interaction_station=interaction;actor.model_visual.seating_station=interaction
	reveal_containing_room(world,actor.position)
	for frame in 470:
		actor.model_visual.project(Vector3.ZERO,false,0.0,false,1.0/60.0,"sit",atan2(interaction.facing_point().x-actor.position.x,interaction.facing_point().z-actor.position.z))
		if frame in [180,300,450]:
			var shot_index:int=[180,300,450].find(frame);world.morning_director.shot=world.morning_director.SHOTS[shot_index]
			var composition:Dictionary=world.morning_director.composition(actor,interaction,true)
			frame_camera(world,composition.focus,composition.offset,float(composition.size))
			await capture("work-%02d-%s-%s"%[shot_index+1,world.morning_director.shot,actor.model_visual.environment_interaction.action])

	# One shared recorded token and two reachable hand contacts in the actual Commons.
	actor.visible=false
	var giver:Node3D=world.get_node(world.MEMBERS.repair);var receiver:Node3D=world.get_node(world.MEMBERS.reviewer)
	giver.visible=true;receiver.visible=true;giver.position=Handoff.WEST;receiver.position=Handoff.EAST
	giver.set_physics_process(false);receiver.set_physics_process(false)
	giver.model_visual.exchange_partner=receiver;giver.model_visual.exchange_role="giver"
	receiver.model_visual.exchange_partner=giver;receiver.model_visual.exchange_role="receiver"
	for frame in 100:
		giver.model_visual.project(Vector3.ZERO,false,0.0,false,1.0/60.0,"handoff",PI/2)
		receiver.model_visual.project(Vector3.ZERO,false,0.0,false,1.0/60.0,"handoff",-PI/2)
	world.handoff_token.global_position=(giver.global_position+receiver.global_position)*.5+Vector3(0,1.12,0);world.handoff_token.show()
	var center:Vector3=(giver.global_position+receiver.global_position)*.5+Vector3(0,.85,0)
	frame_camera(world,center,Vector3(3.8,2.5,4.8),3.4);await capture("handoff-close")
	frame_camera(world,center+Vector3(0,0,.5),Vector3(6.8,6.4,9.0),8.0);await capture("handoff-commons")

	var report:={"status":"captured","engine":Engine.get_version_info(),"captures":captures,"fixture":"isolated presentation placement","network_requests":0,"commands_dispatched":false,"work_actions":"deterministic role choreography","handoff_contacts":{"giver":giver.model_visual.environment_interaction.contact_errors.get("handoff"),"receiver":receiver.model_visual.environment_interaction.contact_errors.get("handoff")}}
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("CINEMATIC_CREW_CAPTURE_PASSED: ",JSON.stringify(report));world.queue_free();await process_frame;quit()
