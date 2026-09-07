extends SceneTree
var frames := 0
var world: Node3D
var output := ""
var exterior := false
var console := false
var reduced := false
func _initialize() -> void: setup.call_deferred()
func setup() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
  if arg=="--exterior": exterior=true
  if arg=="--console": console=true
  if arg=="--reduced": reduced=true
 world=load("res://main.tscn").instantiate()
 root.add_child(world)
 await process_frame
 world.http.cancel_request()
 world.hud.reduced=reduced
 world.set_physics_process(false)
 world.set_process(false)
 var station=world.get_node("Structures/Workshop")
 var actor=world.get_node("Operator")
 if exterior:
  actor.position=station.return_position()+Vector3(0,0,1)
  station.update_presentation(actor.position+Vector3(0,0,4),1,true)
 else:
  world.enter_room("repair")
  actor.position=station.to_global(Vector3(-3.9,0,-0.2))
  station.update_presentation(actor.position,1,true)
 world.get_node("Mender").visible=not exterior
 actor.motion=Vector3.ZERO
 if console: world.get_node("Mender").presentation_pose="console"
 for pair in world.crew_pairs(): pair[1].reduced_motion=reduced
 world.hud.prompt.text="Engineering review · E inspect · F return"
 for pair in world.crew_pairs(): pair[1].motion=Vector3.ZERO
 world.camera_focus=station.to_global(Vector3(-1.95,1.6,-2.6))
 world.camera.position=world.camera_focus+Vector3(9,12,17)
 world.camera.look_at(world.camera_focus)
 world.camera.size=16.5
 frames=1
func _process(_delta: float) -> bool:
 if frames<=0: return false
 frames+=1
 if frames==90:
  frames=-1
  capture()
 return false

func capture() -> void:
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output)
 quit()
