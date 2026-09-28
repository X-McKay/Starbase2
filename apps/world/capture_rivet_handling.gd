extends SceneTree
## Native motion comparison, isolated from all API clients and mission dispatch.
var output:=""
var side:=false
var records:Array=[]
func _initialize():run.call_deferred()
func run():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
  if arg=="--side":side=true
 if output.is_empty():push_error("Explicit capture directory required");quit(1);return
 DirAccess.make_dir_recursive_absolute(output)
 create_timer(90).timeout.connect(func():push_error("Rivet capture watchdog");quit(1))
 root.size=Vector2i(1280,800);root.msaa_3d=Viewport.MSAA_4X
 var stage:=Node3D.new();root.add_child(stage)
 var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("242c35");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("e5daca");environment.environment.ambient_light_energy=.85;stage.add_child(environment)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-25,0);sun.light_energy=1.3;stage.add_child(sun)
 var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.6;stage.add_child(camera)
 camera.position=Vector3(5,1.8,0) if side else Vector3(1.0,2.0,5);camera.look_at(Vector3(0,1.0,0))
 var layer:=CanvasLayer.new();root.add_child(layer)
 var title:=Label.new();title.position=Vector2(24,20);title.add_theme_font_size_override("font_size",23);layer.add_child(title)
 var pair:Array=[]
 for treatment in ["precise","deliberate"]:
  var v=preload("res://characters/model_visual.gd").new();stage.add_child(v);v.configure_definition(preload("res://characters/catalog.gd").get_definition("mender"));v.set_motion_profile("mender");v.set_work_treatment(treatment)
  if side:v.position.z=.7 if treatment=="precise" else -.7
  else:v.position.x=-.7 if treatment=="precise" else .7
  pair.append(v)
 for frame in range(270):
  var work:bool=(frame>=30 and frame<120) or (frame>=180 and frame<240)
  var moving:bool=frame>=120 and frame<180
  var reduced:bool=frame>=240
  var label:="Docked" if frame<30 else "Reach / lift / use" if work else "Stow while walking" if moving else "Reduced motion · docked"
  for v in pair:
   v.project(Vector3(0,0,.035) if moving else Vector3.ZERO,moving,fposmod(float(frame)/30.0,1.0),reduced,1.0/30.0,"console" if work or reduced else "",0)
  title.text="Rivet · A Precise (left) / B Deliberate (right)\n"+label+" · authored cosmetic handling · "+("side" if side else "front")+" view"
  await process_frame
  if frame in [0,29,35,44,53,65,80,119,120,129,140,149,165,179,195,220,239,269]:
   RenderingServer.force_draw(false)
   var name:="frame-%03d.png"%frame;assert(root.get_texture().get_image().save_png(output.path_join(name))==OK)
   records.append({"frame":frame,"capture":name,"states":[pair[0].slate_choreography.state,pair[1].slate_choreography.state],"contact_error_m":[pair[0].slate_choreography.contact_error,pair[1].slate_choreography.contact_error]})
 var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"records":records,"api_requests":0,"translation":"Synthetic walking displacement; physical route checked separately","side":side},"  "));file.close()
 print("RIVET_HANDLING_CAPTURE_PASSED");quit()
