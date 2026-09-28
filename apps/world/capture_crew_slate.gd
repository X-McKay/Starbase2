extends SceneTree
## Isolated authored equipment-pose review; no API, mission or route authority.
const Visual=preload("res://characters/model_visual.gd")
var output:=""
var stage:Node3D
var camera:Camera3D
var records:Array=[]
var title:Label
func _initialize() -> void: run.call_deferred()
func run() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
 if output.is_empty():push_error("Explicit capture directory required");quit(1);return
 DirAccess.make_dir_recursive_absolute(output)
 create_timer(50).timeout.connect(func():push_error("Crew slate capture watchdog");quit(1))
 root.size=Vector2i(1080,900);root.msaa_3d=Viewport.MSAA_4X
 stage=Node3D.new();root.add_child(stage)
 var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("242c35");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("e5daca");environment.environment.ambient_light_energy=.85;stage.add_child(environment)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-25,0);sun.light_energy=1.3;stage.add_child(sun)
 camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.25;stage.add_child(camera)
 var layer:=CanvasLayer.new();root.add_child(layer);title=Label.new();title.position=Vector2(24,20);title.add_theme_font_size_override("font_size",24);layer.add_child(title)
 for role in ["mender","surveyor","watchkeeper"]:
  var visual=Visual.new();stage.add_child(visual);visual.configure_definition(preload("res://characters/catalog.gd").get_definition(role))
  for frame in range(120):
   visual.project(Vector3.ZERO,false,0,false,1.0/30.0,"console",0)
   if frame in [30,60,90]:
    var slate:Node3D=visual.work_slate
    var focus:Vector3=slate.global_position+Vector3(0,.18,0)
    camera.position=focus+Vector3(2.5,1.3,3.0);camera.look_at(focus)
    title.text=role+" / authored equipment pose / frame "+str(frame)+"\nDecorative inspection • no operational state"
    await process_frame;await process_frame;RenderingServer.force_draw(false)
    var name:String=role+"-"+str(frame)+".png";assert(root.get_texture().get_image().save_png(output.path_join(name))==OK)
    records.append({"role":role,"frame":frame,"capture":name,"slate_visible":slate.visible,"grip_span":slate.contact_span,"slate_basis":str(slate.global_basis)})
  visual.project(Vector3.ZERO,false,0,true,1.0/30.0,"console",0)
  assert((visual.slate_choreography!=null and visual.slate_choreography.state=="docked") or not visual.work_slate.visible,"Reduced motion stops handling; Rivet retains static docked equipment")
  visual.free();await process_frame
 var report:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);report.store_string(JSON.stringify({"records":records,"api_requests":0,"reduced_motion":"handling disabled; static dock retained on supported Rivet rig","physical_journey":false},"  "));report.close()
 print("CREW_SLATE_CAPTURE_PASSED");quit()
