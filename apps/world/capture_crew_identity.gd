extends SceneTree
## Isolated native art studio. This is a posed treadmill, not a physical world journey.
const Catalog=preload("res://characters/catalog.gd")
const Visual=preload("res://characters/model_visual.gd")
const Gait=preload("res://characters/gait.gd")
var IDS=["operator","mender","surveyor","trainer","watchkeeper","reviewer"]
const SELECTED_CAST={"operator":"wayfinder","mender":"rivet","surveyor":"moss-cartographer","trainer":"stillpoint","watchkeeper":"night-shift","reviewer":"prism","cybercat":"cybercat-player"}
var stage:Node3D
var camera:Camera3D
var models:Array=[]
var gaits:Array=[]
var definitions:Array=[]
var cast_records:Array=[]
var captions:Array=[]
var title:Label
var note:Label
var output:=""
var captures:Array[String]=[]
var samples:Array=[]
var failures:Array[String]=[]
var started:=0
var stopped:=false
var lighting_probe:=false
var motion_audit:=false
var player_comparison:=false

func _initialize() -> void: run.call_deferred()
func check(ok:bool,message:String) -> void:
	if not ok and message not in failures: failures.append(message)
func settle() -> void:
	for frame in range(3): await process_frame
func save_picture(name:String) -> void:
	if stopped: return
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Save "+name)
	captures.append(name+".png")
func frame_camera(target:Vector3,offset:Vector3,view_size:float) -> void:
	camera.size=view_size; camera.position=target+offset; camera.look_at(target)
func aim_all(heading:float) -> void:
	for visual in models:
		visual.project(Vector3.ZERO,false,0,true,1.0/60.0,"",heading)
func cast_label(index:int) -> String:
	var id:String=IDS[index]
	var selected:String=SELECTED_CAST[id]
	if definitions[index].model_scene.resource_path.begins_with("res://assets/characters/"+selected+"/"):
		return definitions[index].display_name.to_upper()+" · "+("OPERATOR" if id=="cybercat" else id.to_upper())
	return id.to_upper()+" · CURRENT MODEL"

func lineup() -> void:
	for index in range(models.size()):
		models[index].visible=true; models[index].position=Vector3((index-(models.size()-1)/2.0)*1.5,0,0)
		captions[index].visible=true; captions[index].position=Vector3((index-(models.size()-1)/2.0)*1.5,2.32,0)
	frame_camera(Vector3(0,1.25,0),Vector3(0,.8,12),3.7 if player_comparison else 5.8)
func finish() -> void:
	if stopped: return
	stopped=true
	check(stage.find_children("*","HTTPRequest",true,false).is_empty(),"Studio owns no HTTP requests")
	var file:=FileAccess.open(output.path_join("crew-identity-report.json"),FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","mode":"crew-identity",
			"posed_treadmill":true,"physical_world_route_verified":false,"commands_dispatched":false,"http_requests":0,
			"fixed_simulation_dt":1.0/30.0,"movie_fps":30,"movie_frame_count":0 if lighting_probe else (720 if motion_audit else 240),"lighting_probe":lighting_probe,"identities":IDS,"cast":cast_records,
			"captures":captures,"samples":samples,"failures":failures,"wall_ms":Time.get_ticks_msec()-started,
			"engine":Engine.get_version_info()},"  "))
	for failure in failures: push_error(failure)
	print("CREW_IDENTITY_CAPTURE_PASSED" if failures.is_empty() else "CREW_IDENTITY_CAPTURE_FAILED")
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): output=arg.trim_prefix("--capture-dir=")
		if arg=="--lighting-probe": lighting_probe=true
		if arg=="--motion-audit": motion_audit=true
		if arg=="--player-comparison": player_comparison=true; IDS=["operator","cybercat"]
	if output.is_empty(): push_error("Crew studio requires explicit --capture-dir output"); quit(1); return
	if DirAccess.make_dir_recursive_absolute(output.path_join("motion"))!=OK: push_error("Cannot create studio output"); quit(1); return
	started=Time.get_ticks_msec()
	create_timer(240 if motion_audit else 115).timeout.connect(func():
		if not stopped: check(false,"Studio exceeded bounded capture watchdog"); finish())
	root.size=Vector2i(1440,900); root.content_scale_size=Vector2i(1440,900)
	root.msaa_3d=Viewport.MSAA_4X
	stage=Node3D.new(); root.add_child(stage)
	var env:=WorldEnvironment.new(); var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR; settings.background_color=Color("181411")
	settings.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("e5d9cd"); settings.ambient_light_energy=0.18
	env.environment=settings; stage.add_child(env)
	for light_spec in [[Vector3(-3,6,5),Color("fff0df"),0.3],[Vector3(4,4,-3),Color("ff9a75"),0.1]]:
		var light:=DirectionalLight3D.new(); stage.add_child(light)
		light.position=light_spec[0]; light.look_at(Vector3(0,1,0)); light.light_color=light_spec[1]; light.light_energy=light_spec[2]
		light.shadow_enabled=true
	var floor_mesh:=MeshInstance3D.new(); floor_mesh.mesh=BoxMesh.new(); floor_mesh.mesh.size=Vector3(35,0.1,25)
	floor_mesh.position.y=-0.05; var material:=StandardMaterial3D.new(); material.albedo_color=Color("302824"); material.roughness=0.9
	floor_mesh.material_override=material; stage.add_child(floor_mesh)
	camera=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.current=true; stage.add_child(camera)
	var canvas:=CanvasLayer.new(); root.add_child(canvas)
	var heading:=VBoxContainer.new(); heading.position=Vector2(28,20); canvas.add_child(heading)
	title=Label.new(); title.add_theme_font_size_override("font_size",28); heading.add_child(title)
	note=Label.new(); note.add_theme_font_size_override("font_size",18); note.text="OFFLINE ART STUDIO · actual selected character assets · no task state or network"; heading.add_child(note)
	for id in IDS:
		check(Catalog.definitions().has(id),id+": catalog identity exists")
		if not Catalog.definitions().has(id): finish(); return
		var definition=Catalog.get_definition(id); definitions.append(definition)
		check(definition.model_scene!=null,id+": 3D character required")
		if definition.model_scene==null: finish(); return
		var visual=Visual.new(); stage.add_child(visual)
		visual.configure_definition(definition)
		visual.set_motion_profile(definition.motion_profile); visual.apply_role(definition.model_tint)
		models.append(visual); gaits.append(Gait.new())
		var sources:Dictionary={}
		for library_name in definition.model_animation_sources:
			sources[library_name]=definition.model_animation_sources[library_name].resource_path
		cast_records.append({"role":id,"selected_asset":SELECTED_CAST[id],"model":definition.model_scene.resource_path,
			"animation_sources":sources,"legacy_libraries":definition.use_legacy_animation_libraries,
			"preserve_source_materials":definition.preserve_source_materials,
			"secondary_bones":Array(definition.secondary_motion_bones),"secondary_strength":definition.secondary_motion_strength,
			"secondary_limit_radians":definition.secondary_motion_limit})
		var label:=Label3D.new(); label.text=cast_label(models.size()-1).replace(" · ","\n"); label.font_size=28; label.pixel_size=0.0048
		label.modulate=Color("fff0df"); label.outline_modulate=Color("181411"); label.outline_size=9
		label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; stage.add_child(label); captions.append(label)
	lineup(); aim_all(0); title.text="STARBASE2 / PLAYER CHARACTERS" if player_comparison else "STARBASE2 / SIX CREW CHARACTERS"
	await settle(); save_picture("00-lineup-front")
	aim_all(PI); await settle(); save_picture("01-lineup-back")
	for index in range(models.size()):
		for other in range(models.size()): models[other].visible=other==index; captions[other].visible=false
		models[index].position=Vector3.ZERO
		for view in [["front",0.0],["side",PI/2],["back",PI]]:
			title.text=cast_label(index)+" / "+str(view[0]).to_upper()+" · ACTUAL NATIVE MODEL"
			aim_all(float(view[1])); frame_camera(Vector3(0,1.25,0),Vector3(0,0.4,5),3.5)
			await settle(); save_picture("%02d-%s-%s"%[index+2,IDS[index],view[0]])
	if lighting_probe: finish(); return
	lineup(); aim_all(0)
	note.text="POSED TREADMILL · simulated displacement drives the real gait · not world-route evidence"
	for frame in range(720 if motion_audit else 240):
		if stopped: return
		var speed:=0.0; var direction:=Vector3.BACK; var reduced:=false; var phase_name:="IDLE"; var pose:=""
		if motion_audit:
			if frame<30: phase_name="IDLE"
			elif frame<120: speed=2.0; phase_name="WALK / LOOP CONTINUITY"
			elif frame<210: speed=6.0; phase_name="RUN / LOOP CONTINUITY"
			elif frame<270:
				speed=4.0; direction=Vector3(sin((frame-210)/60.0*TAU),0,cos((frame-210)/60.0*TAU)); phase_name="TURN"
			elif frame<300: phase_name="STOP / SETTLE"
			elif frame<390: pose="console"; phase_name="WORK / SLATE"
			elif frame<420: phase_name="WORK TO IDLE"
			elif frame<540: pose="sit"; phase_name="SIT / SEATED (POSE REVIEW; NO BENCH)"
			elif frame<600: pose="stand"; phase_name="STAND UP"
			elif frame<630: speed=2.0; phase_name="RETURN TO WALK"
			elif frame<660: pose="sit"; phase_name="SIT INTERRUPTED NEXT"
			elif frame<690: speed=2.0; phase_name="INTERRUPT TO WALK"
			else: reduced=true; phase_name="REDUCED MOTION"
		elif frame<60: speed=2.0; phase_name="WALK"
		elif frame<120: speed=6.0; phase_name="RUN / FAST TRAVEL"
		elif frame<180:
			speed=4.0; direction=Vector3(sin((frame-120)/60.0*TAU),0,cos((frame-120)/60.0*TAU)); phase_name="TURN"
		elif frame<210: phase_name="STOP / SETTLE"
		else: reduced=true; phase_name="REDUCED MOTION"
		title.text="STARBASE2 / "+phase_name
		for index in range(models.size()):
			var visual=models[index]; var gait=gaits[index]; var definition=definitions[index]
			var stride:float=definition.model_run_stride if speed>5 and visual.animation.has_animation("run") else definition.model_stride
			var travel:=direction*speed/30.0
			gait.advance(travel.length(),stride)
			visual.project(travel,gait.moving,gait.phase,reduced,1.0/30.0,pose,0.0 if motion_audit else INF)
			if frame%30==0: samples.append({"frame":frame,"identity":IDS[index],"mode":phase_name,"clip":visual.clip,"gait_phase":gait.phase,"heading":visual.rotation.y,"secondary_bones":Array(definition.secondary_motion_bones),"secondary_angle":visual.secondary.angles.length(),"secondary_limit_radians":definition.secondary_motion_limit})
		await process_frame
		save_picture("motion/frame-%04d"%frame)
	finish()
