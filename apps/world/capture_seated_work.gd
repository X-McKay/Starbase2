extends SceneTree
var output:=""
var preview:=false
var records:Array=[]
func _initialize():run.call_deferred()
func run():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
  if arg=="--preview":preview=true
 assert(not output.is_empty());DirAccess.make_dir_recursive_absolute(output)
 create_timer(180).timeout.connect(func():push_error("Seatedwork capture timeout");quit(1))
 root.size=Vector2i(800,500) if preview else Vector2i(1280,800);root.content_scale_size=root.size
 var world=load("res://main.tscn").instantiate();world.fixture_path="res://../../fixtures/world/stale.json";world.board_fixture="__empty_visual_fixture__";world.player_preferences_path="";root.add_child(world)
 await process_frame;await physics_frame
 world.isolate_capture_input();world.set_process(false);world.set_physics_process(false);world.hud.root.hide();world.hud.reduced=false;world.apply_settings()
 for pair in world.crew_pairs():pair[1].set_physics_process(false)
 for role in ["watchkeeper","reviewer"]:
  var actor=world.get_node(world.MEMBERS[role]);var motion=world.crew_motions[role];var station=world.interaction_stations[role];var v=actor.model_visual
  assert(not station.seat().is_empty())
  actor.position=motion.workstation;actor.reduced_motion=false;actor.visible=true;actor.label.hide();actor.set_physics_process(false);v.support_sample=actor.support_sample
  motion.station.update_presentation(actor.position,1,true)
  station.seated_console.set_process(false)
  var heading:float=station.global_rotation.y;v.rotation.y=heading;v.heading=heading
  v.interaction_station=null;v.seating_station=null
  for frame in 30:v.project(Vector3.ZERO,false,0,false,1.0/30,"",heading)
  v.seating_station=station
  var focus:Vector3=station.seat().frame.origin+Vector3(0,.35,0)
  for frame in 390:
   var pose:="" if frame<15 else "sit" if frame<300 else "stand" if frame<360 else ""
   var active:bool=frame>=15 and frame<270
   v.interaction_station=station if active else null
   actor.reduced_motion=frame>=375
   v.project(Vector3.ZERO,false,0,actor.reduced_motion,1.0/30,pose,heading)
   station.seated_console.advance(1.0/30)
   await process_frame
   if (preview and frame%2==0) or (not preview and frame in [0,18,24,30,40,50,65,90,180,240,280,300,305,312,320,335,344,350,359,374,389]):
    var data:Dictionary={"role":role,"frame":frame,"pose":pose,"clip":v.clip,"phase":v.environment_interaction.state,"feedback":v.environment_interaction.contact_weights.duplicate(),"foot_phase":v.seated_footwork.foot_phase.duplicate(),"sole_clearances":v.seated_footwork.sole_clearances.duplicate(),"seat_reference_error_m":v.seat_reference_error,"offset":str(v.seat_alignment_offset),"tray_amount":station.seated_console.amount}
    if not preview and frame in [50,90,240,280,305,320,344,350]:data.skin=preload("res://probe_seated_skin_audit.gd").measure(v,station.seat(),world.support_surface.height_at)
    for angle in (["side"] if preview else ["front","side"]):
     world.camera.position=focus+station.global_basis*(Vector3(3.4,1.2,.2) if angle=="side" else Vector3(2.3,2.0,-2.4));world.camera.look_at(focus);world.camera.size=3.0
     await process_frame;RenderingServer.force_draw(false)
     var file:="%s-%03d-%s.png"%[role,frame,angle];assert(root.get_texture().get_image().save_png(output.path_join(file))==OK)
    records.append(data)
  v.seating_station=null;v.interaction_station=null
 var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"records":records,"direct_placed_fixture":true,"physical_route_verified":false,"api_requests":0,"preview":preview},"  "));file.close()
 world.queue_free();await process_frame;print("SEATED_WORK_CAPTURE_PASSED");quit()
