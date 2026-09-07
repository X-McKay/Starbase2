extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var scene:=Node3D.new()
 root.add_child(scene)
 var environment:=WorldEnvironment.new()
 environment.environment=Environment.new()
 environment.environment.background_mode=Environment.BG_COLOR
 environment.environment.background_color=Color(0.055,0.075,0.095)
 environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 environment.environment.ambient_light_color=Color.WHITE
 environment.environment.ambient_light_energy=0.65
 scene.add_child(environment)
 var light:=DirectionalLight3D.new()
 light.rotation_degrees=Vector3(-45,-30,0)
 light.light_energy=1.2
 scene.add_child(light)
 var camera:=Camera3D.new()
 scene.add_child(camera)
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL
 camera.size=10
 camera.position=Vector3(0,3.6,10)
 camera.look_at(Vector3(0,1.1,0))
 var model_path:=""
 var single:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--single="): single=arg.trim_prefix("--single=")
  if arg.begins_with("--model="): model_path=arg.trim_prefix("--model=")
 var actors: Array[Node3D]=[]
 var clips: Array[String]=["idle","walk","run","console"]
 for i in range(4):
  var actor=load("res://actor.gd").new()
  actor.character_definition=load("res://characters/definitions/mender.tres").duplicate()
  if not model_path.is_empty(): actor.character_definition.model_scene=load(model_path)
  actor.position=Vector3((i-1.5)*2.35,0,0)
  actor.display_name=clips[i].to_upper()
  scene.add_child(actor)
  actors.append(actor)
  actor.set_physics_process(false)
  var visual=actor.model_visual
  for step in range(20): visual.project(Vector3(0,0,0.1 if i==2 else 0.035),i in [1,2],0.3,false,1.0/60.0,"console" if i==3 else "")
  visual.rotation.y=0
  if not single.is_empty():
   actor.visible=clips[i]==single
   if actor.visible:
    camera.size=3.1
    camera.position=Vector3(actor.position.x,2.5,6)
    camera.look_at(Vector3(actor.position.x,1.2,0))
 var motion_dir:=""
 var output:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--motion-dir="): motion_dir=arg.trim_prefix("--motion-dir=")
  if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
 for i in range(30): await process_frame
 await RenderingServer.frame_post_draw
 if not output.is_empty(): root.get_texture().get_image().save_png(output)
 if not motion_dir.is_empty():
  DirAccess.make_dir_recursive_absolute(motion_dir)
  for frame in range(48):
   for i in range(4):
    var visual=actors[i].model_visual
    var phase: float=fposmod(float(frame)/24.0/visual.animation.get_animation(clips[i]).length,1.0)
    visual.project(Vector3(0,0,0.25 if i==2 else 0.08),i in [1,2],phase,false,1.0/24.0,"console" if i==3 else "")
    visual.rotation.y=0
   await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(motion_dir+"/%03d.png"%frame)
 quit()
