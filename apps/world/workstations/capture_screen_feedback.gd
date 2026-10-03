extends SceneTree
## Isolated native comparison of Command input contact and display-local feedback.
var output:=""

func _initialize() -> void:run.call_deferred()

func capture(name:String) -> void:
 for frame in 8:await process_frame
 RenderingServer.force_draw(false)
 assert(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK)

func run() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):output=ProjectSettings.globalize_path(arg.trim_prefix("--output="))
 assert(not output.is_empty())
 assert(DirAccess.make_dir_recursive_absolute(output)==OK)
 create_timer(55).timeout.connect(func():push_error("Screen feedback capture timed out");quit(1))
 root.size=Vector2i(1440,900);root.content_scale_size=root.size;root.msaa_3d=Viewport.MSAA_4X
 var world=load("res://main.tscn").instantiate()
 world.fixture_path="res://../../fixtures/world/stale.json";world.board_fixture="__empty_visual_fixture__";world.player_preferences_path=""
 root.add_child(world);await process_frame;await physics_frame
 world.isolate_capture_input();world.poll_timer.stop();world.http.cancel_request();world.set_process(false);world.set_physics_process(false);world.hud.root.hide()
 var role:="reviewer";var actor:Node3D=world.get_node(world.MEMBERS[role]);var motion=world.crew_motions[role]
 actor.position=motion.workstation;actor.set_physics_process(false);actor.visible=true
 motion.station.update_presentation(actor.position,1.0,true)
 var station:Node3D=world.interaction_stations[role]
 station.global_position=Vector3(actor.position.x,station.global_position.y,actor.position.z)
 station.seated_console.amount=1.0;station.seated_console.target=1.0;station.seated_console.apply_fold()
 actor.presentation_facing=station.facing_point();actor.presentation_pose="sit";actor.interaction_station=station;actor.seating_station=station
 actor.model_visual.interaction_station=station;actor.model_visual.seating_station=station
 for structure in world.get_node("Structures").get_children():
  if not structure.contains(actor.position):continue
  structure.cutaway=0.0;structure.room.visible=true
  for material in structure.cut_materials:material.set_shader_parameter("visibility",0.0)
  for material in structure.reveal_materials:material.set_shader_parameter("visibility",1.0)
 for frame in 130:actor.model_visual.project(Vector3.ZERO,false,0.0,false,1.0/60.0,"sit",atan2(station.facing_point().x-actor.position.x,station.facing_point().z-actor.position.z))
 var focus:Vector3=station.contacts().screen.origin+Vector3(0,-.2,0)
 world.camera.position=focus+Vector3(1.5,1.2,2.0);world.camera.look_at(focus);world.camera.size=2.8
 station.present_contacts({});await capture("display-idle")
 station.present_contacts({"left_key":1.0});await capture("display-key-contact")
 print("SCREEN_FEEDBACK_CAPTURE_PASSED: cue=",station.cue.global_position," screen=",station.contacts().screen.origin," pixel=",world.camera.unproject_position(station.cue.global_position)," visible=",station.cue.visible," commands=",world.commands.payload.is_empty())
 assert(world.commands.payload.is_empty());world.queue_free();await process_frame;quit()
