extends SceneTree
const CAST={"mender":"repair","surveyor":"review","trainer":"gym"}
var output:=""
var baseline:=false
var preview:=false
func _initialize():run.call_deferred()
func run():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
  if arg=="--baseline":baseline=true
  if arg=="--preview":preview=true
 assert(not output.is_empty());DirAccess.make_dir_recursive_absolute(output)
 create_timer(120).timeout.connect(func():push_error("Environment animation capture timeout");quit(1))
 root.size=Vector2i(640,400) if preview else Vector2i(1280,800);root.msaa_3d=Viewport.MSAA_4X
 var stage:=Node3D.new();root.add_child(stage)
 var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("293542");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("e5daca");environment.environment.ambient_light_energy=.85;stage.add_child(environment)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-25,0);sun.light_energy=1.3;stage.add_child(sun)
 var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.4;stage.add_child(camera)
 var layer:=CanvasLayer.new();root.add_child(layer);var title:=Label.new();title.position=Vector2(24,20);title.add_theme_font_size_override("font_size",13 if preview else 23);layer.add_child(title)
 var records:Array=[]
 for id in ({"surveyor":"review"} if preview else CAST):
  var v=preload("res://characters/model_visual.gd").new();stage.add_child(v);v.configure_definition(preload("res://characters/catalog.gd").get_definition(id));v.set_motion_profile(id)
  var station=preload("res://workstations/interaction_station.gd").new();stage.add_child(station);station.configure(CAST[id],v);station.rotation.y=0
  for settle in 30:v.project(Vector3.ZERO,false,0,false,1.0/30,"",0)
  if not baseline:v.interaction_station=station
  for frame in range(270):
   var reduced:bool=frame>=255
   var active:bool=frame<240
   v.project(Vector3.ZERO,false,0,reduced,1.0/30.0,"console" if active else "",0)
   await process_frame
   if (preview and frame%2==0) or (not preview and frame in ([60] if baseline else [0,5,14,40,120,171,183,230,242,250,269])):
    for angle in (["side"] if preview else ["front","side"]):
     camera.position=Vector3(1.8,2.1,3.5) if angle=="front" else Vector3(3.5,1.65,.2);camera.look_at(Vector3(0,1.0,.15))
     title.text=id+" · "+("existing field slate" if baseline else v.environment_interaction.state)+" · "+angle+"\nCosmetic workstation interaction · native actual rig"
     await process_frame
     RenderingServer.force_draw(false)
     var file:="%s-%03d-%s.png"%[id,frame,angle];assert(root.get_texture().get_image().save_png(output.path_join(file))==OK)
     records.append({"id":id,"frame":frame,"angle":angle,"state":v.environment_interaction.state,"contacts":v.environment_interaction.contact_errors.duplicate(),"weights":v.environment_interaction.contact_weights.duplicate(),"capture":file})
  v.free();station.free()
 var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"baseline":baseline,"preview":preview,"records":records,"api_requests":0},"  "));file.close()
 print("ENVIRONMENT_ANIMATION_CAPTURE_PASSED");quit()
