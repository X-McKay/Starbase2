extends SceneTree
var world:Node3D
func _initialize() -> void:run.call_deferred()
func run() -> void:
 create_timer(55).timeout.connect(func():push_error("Station capture timed out");quit(1))
 root.size=Vector2i(1280,800);root.content_scale_size=root.size
 world=load("res://main.tscn").instantiate();world.fixture_path="res://../../fixtures/world/stale.json";world.board_fixture="__empty_visual_fixture__";world.player_preferences_path=""
 root.add_child(world);await process_frame;await physics_frame
 world.isolate_capture_input();world.set_process(false);world.set_physics_process(false);world.hud.root.hide()
 for role in world.MEMBERS:
  var actor=world.get_node(world.MEMBERS[role]);var motion=world.crew_motions[role]
  actor.position=motion.workstation;actor.set_physics_process(false)
  motion.station.update_presentation(actor.position,1,true)
  world.camera.position=actor.position+Vector3(4,3,5);world.camera.look_at(actor.position+Vector3(0,1,0));world.camera.size=4.0
  for frame in 5:await process_frame
  RenderingServer.force_draw(false)
  root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../.local/workstation-contacts-20260928/before-"+role+".png"))
  print("STATION ",role," ",actor.position)
 world.queue_free();await process_frame;print("EXISTING_STATIONS_CAPTURED");quit()
