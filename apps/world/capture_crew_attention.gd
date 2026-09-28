extends SceneTree
## Isolated native motion review. No API or work dispatch.
var output:=""
var stage:Node3D
var camera:Camera3D
var title:Label
var records:Array=[]
func _initialize() -> void:run.call_deferred()
func run() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
 if output.is_empty():push_error("Explicit capture directory required");quit(1);return
 DirAccess.make_dir_recursive_absolute(output)
 create_timer(55).timeout.connect(func():push_error("Attention capture watchdog");quit(1))
 root.size=Vector2i(1280,800);root.msaa_3d=Viewport.MSAA_4X
 stage=Node3D.new();root.add_child(stage)
 var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("242c35");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("e5daca");environment.environment.ambient_light_energy=.85;stage.add_child(environment)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-25,0);sun.light_energy=1.3;stage.add_child(sun)
 camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.6;stage.add_child(camera)
 camera.position=Vector3(1.6,2.5,5);camera.look_at(Vector3(0,1.1,0))
 var layer:=CanvasLayer.new();root.add_child(layer);title=Label.new();title.position=Vector2(24,20);title.add_theme_font_size_override("font_size",22);layer.add_child(title)
 for role in ["mender","surveyor","watchkeeper"]:
  var pair:Array=[]
  for enabled in [false,true]:
   var visual=preload("res://characters/model_visual.gd").new();stage.add_child(visual);visual.configure_definition(preload("res://characters/catalog.gd").get_definition(role));visual.set_motion_profile(role)
   visual.position.x=.7 if enabled else -.7;visual.work_attention.enabled=enabled;pair.append(visual)
  for frame in range(300):
   for visual in pair:visual.project(Vector3.ZERO,false,0,false,1.0/30.0,"console",0)
   if frame in [30,90,150,210,270]:
    title.text=role+" · authored pose (left) / work attention (right)\nCosmetic focus during work • identical hands and equipment • %.1f s"%[float(frame)/30]
    await process_frame;await process_frame;RenderingServer.force_draw(false)
    var name:String=role+"-"+str(frame)+".png";assert(root.get_texture().get_image().save_png(output.path_join(name))==OK)
    records.append({"role":role,"frame":frame,"capture":name,"offset":str(pair[1].work_attention.offset)})
  for visual in pair:visual.project(Vector3.ZERO,false,0,true,1.0/30.0,"console",0)
  title.text=role+" · reduced motion\nBoth poses still • handling disabled • no animation-derived status"
  await process_frame;await process_frame;RenderingServer.force_draw(false)
  assert(root.get_texture().get_image().save_png(output.path_join(role+"-reduced.png"))==OK)
  for visual in pair:visual.free()
  await process_frame
 var report:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);report.store_string(JSON.stringify({"records":records,"api_requests":0,"physical_journey":false},"  "));report.close()
 print("CREW_ATTENTION_CAPTURE_PASSED");quit()
