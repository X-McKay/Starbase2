extends SceneTree
var failures: Array[String]=[]
func check(value: bool, message: String) -> void:
 if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var world=load("res://main.tscn").instantiate()
 root.add_child(world)
 await process_frame
 world.fixture_path="test-only"
 world.http.cancel_request()
 var station=world.get_node("Buildings/Workshop")
 var content=station.room.content
 check(content.has_node("Reactor"),"Hero reactor imports")
 check(not station.reveal_materials.is_empty(),"Authored interior has a reveal transition")
 var textured := false
 for material in station.cut_materials:
  if material.get_shader_parameter("use_albedo") and material.get_shader_parameter("use_normal"): textured=true
 check(textured,"Generated exterior retains PBR texture and normal maps")
 station.update_presentation(station.return_position()+Vector3(0,0,5),1,true)
 check(not station.room.visible,"Closed hull conceals interior furniture")
 world.enter_room("repair")
 await physics_frame
 await physics_frame
 check(station.room.visible,"Entering reveals interior furniture")
 check(not world.travel_route(station.room.to_global(station.room.console_point)).is_empty(),"Inspection console remains reachable")
 check(not content.hum.playing,"Reactor sound defaults off")
 world.hud.reduced=true
 await process_frame
 var before: float=content.phase
 for i in range(4): await process_frame
 check(content.phase==before,"Reduced motion freezes reactor machinery and lighting")
 world.hud.reduced=false
 var engineer=world.get_node("Mender")
 world.hud.open_place("repair")
 await physics_frame
 await physics_frame
 check(engineer.presentation_pose=="console","Inspection in Engineering triggers the local gesture")
 world.hud.close_panels()
 await physics_frame
 await physics_frame
 check(engineer.presentation_pose.is_empty(),"Closing inspection clears the gesture")
 var visual=engineer.model_visual
 for clip in ["idle","walk","run","console"]:
  check(visual.animation.has_animation(clip),"Engineer imports "+clip)
 engineer.set_physics_process(false)
 visual.project(Vector3(0,0,0.1),true,0.3,false,1.0/60.0)
 check(visual.clip=="run","Fast physical displacement selects running")
 visual.project(Vector3.ZERO,false,0,false,0.2,"console")
 check(visual.clip=="console","Local inspection gesture is available")
 visual.project(Vector3.ZERO,false,0,true,0.2,"console")
 check(visual.clip=="idle","Reduced motion suppresses console gesture")
 var rotation=visual.skeleton.get_bone_pose_rotation(0)
 visual.project(Vector3.ZERO,false,0.5,true,0.2,"console")
 check(rotation.is_equal_approx(visual.skeleton.get_bone_pose_rotation(0)),"Reduced pose stays fixed")
 check(world.commands.payload.is_empty(),"Cosmetic animation never dispatches backend work")
 world.queue_free()
 await process_frame
 for failure in failures: push_error(failure)
 if failures.is_empty(): print("ENGINEERING_POLISH_PASSED: PBR, route, cutaway, muted audio, reduced effects, four clips, run selection, no dispatch")
 quit(0 if failures.is_empty() else 1)
