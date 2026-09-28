extends SceneTree
var world:Node3D
var output:="res://../../.local/workstation-contacts-20260928/current-geometry"
var repair_shift:=0.0
var working:=false
func _initialize() -> void:run.call_deferred()
func run() -> void:
 create_timer(55).timeout.connect(func():push_error("Station capture timed out");quit(1))
 for arg in OS.get_cmdline_user_args():
  if arg=="--working":working=true
  if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
  if arg.begins_with("--repair-shift="):repair_shift=float(arg.trim_prefix("--repair-shift="))
 output=ProjectSettings.globalize_path(output);DirAccess.make_dir_recursive_absolute(output)
 root.size=Vector2i(1280,800);root.content_scale_size=root.size
 world=load("res://main.tscn").instantiate();world.fixture_path="res://../../fixtures/world/stale.json";world.board_fixture="__empty_visual_fixture__";world.player_preferences_path=""
 root.add_child(world);await process_frame;await physics_frame
 world.isolate_capture_input();world.set_process(false);world.set_physics_process(false);world.hud.root.hide()
 if working:
  world.hud.reduced=false;world.apply_settings()
  var stamp:=Time.get_unix_time_from_system()+1000
  var data:Dictionary={"schema_version":2,"observed_at":stamp,"worker":{"available":true},"recent":[],"active":[],"repairs":[],"field_runs":[]}
  for kind in ["review","evaluation"]:data.active.append({"input":{"request":{"id":"native-fit-"+kind,"kind":kind}},"state":"running","updated_at":stamp})
  data.repairs.append({"input":{"id":"native-fit-repair","scenario":"clamp-v1"},"state":"running","updated_at":stamp})
  for kind in ["reviewer","watchkeeper"]:data.field_runs.append({"input":{"id":"native-fit-"+kind,"agent":kind},"state":"running","updated_at":stamp})
  world.receive_snapshot(data)

 # Seated Command rigs use the dedicated seated-work capture and its chair context.
 for role in ["repair","review","gym"]:
  var actor=world.get_node(world.MEMBERS[role]);var motion=world.crew_motions[role]
  actor.position=motion.workstation;actor.set_physics_process(false);actor.visible=true
  if role=="repair":actor.position.x+=repair_shift
  motion.station.update_presentation(actor.position,1,true)
  var accessory:Node3D
  for node in world.find_children("*","Node3D",true,false):
   if node.get_script()==load("res://workstations/interaction_station.gd") and node.actor==actor:accessory=node;break
  if accessory==null:
   accessory=load("res://workstations/interaction_station.gd").new();accessory.position=actor.position;world.add_child(accessory);accessory.configure(role,actor)
  accessory.global_position=Vector3(actor.position.x,accessory.global_position.y,actor.position.z)
  actor.presentation_facing=accessory.facing_point();actor.model_visual.project(Vector3.ZERO,false,0.0,true,0.0,"",atan2(accessory.facing_point().x-actor.position.x,accessory.facing_point().z-actor.position.z))
  if working:
   # Explicit native fit fixture: direct placement, not a physical-journey claim.
   motion.path.clear();motion.route_blocked=false;actor.motion=Vector3.ZERO;actor.presentation_pose="console"
   world.project_environment_interaction(role)
   actor.model_visual.interaction_station=actor.interaction_station
   assert(actor.interaction_station==accessory)
   for frame in 90:actor.model_visual.project(Vector3.ZERO,false,0.0,false,1.0/60.0,"console",atan2(accessory.facing_point().x-actor.position.x,accessory.facing_point().z-actor.position.z))
  world.camera.position=actor.position+Vector3(4,3,5);world.camera.look_at(actor.position+Vector3(0,1,0));world.camera.size=4.0
  for frame in 5:await process_frame
  RenderingServer.force_draw(false)
  root.get_texture().get_image().save_png(output.path_join(role+"-normal.png"))
  world.camera.position=actor.position+Vector3(.4,2,1.6);world.camera.look_at(actor.position+Vector3(0,1,.0));world.camera.size=2.3
  for frame in 5:await process_frame
  RenderingServer.force_draw(false)
  root.get_texture().get_image().save_png(output.path_join(role+"-close.png"))
  print("STATION ",role," ",actor.position)
 world.queue_free();await process_frame;print("FITTED_STATIONS_CAPTURED");quit()
