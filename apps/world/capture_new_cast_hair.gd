extends SceneTree
## Paired native deformed-skin studio; diagnostic translation has no physics/route authority.
const Visual=preload("res://characters/model_visual.gd")
const Definition=preload("res://characters/definition.gd")
const CAST={"wayfinder":{"height":1.78,"limit":.45},"moss-cartographer":{"height":1.63,"limit":.42},"stillpoint":{"height":1.61,"limit":.38},"night-shift":{"height":1.90,"limit":.38},"prism":{"height":1.67,"limit":.45},"cybercat-player":{"height":1.85,"limit":.18}}
const ROLES={"wayfinder":"operator","moss-cartographer":"surveyor","stillpoint":"trainer","night-shift":"watchkeeper","prism":"reviewer","cybercat-player":"cybercat"}
const DT=1.0/30.0
const FIXED_PHASE=0.25
var ids:Array[String]=["wayfinder","moss-cartographer","stillpoint","night-shift","prism"]
var output:=""
var configurations:Dictionary={}
var animate_gait:=false
var view:="rear"
var panels:Array=[]
var records:Array=[]
var errors:Array[String]=[]
var title:Label
var done:=false
var completed:Array[String]=[]

func _initialize() -> void: run.call_deferred()
func check(ok:bool,message:String) -> void:
	if not ok and message not in errors: errors.append(message)
func box(stage:Node3D,position:Vector3,size:Vector3,color:Color) -> void:
	var node:=MeshInstance3D.new();node.mesh=BoxMesh.new();node.mesh.size=size;node.position=position
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.95
	node.material_override=material;stage.add_child(node)
func panel(close:bool) -> Dictionary:
	var container:=SubViewportContainer.new();container.position=Vector2(720 if close else 0,90);container.size=Vector2(720,810);root.add_child(container)
	var viewport:=SubViewport.new();viewport.size=Vector2i(720,810);viewport.own_world_3d=true;viewport.msaa_3d=Viewport.MSAA_4X;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;container.add_child(viewport)
	var stage:=Node3D.new();viewport.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("211e20")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("e7e1d8");environment.environment.ambient_light_energy=.8;stage.add_child(environment)
	for spec in [[Vector3(-40,-25,0),1.5],[Vector3(-25,145,0),.7]]:
		var light:=DirectionalLight3D.new();light.rotation_degrees=spec[0];light.light_energy=spec[1];stage.add_child(light)
	box(stage,Vector3(0,-.025,10),Vector3(40,.05,60),Color("41383a"))
	for z in range(-10,31): box(stage,Vector3(0,.001,z),Vector3(15,.003,.015),Color("81746a"))
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.25 if close else 2.55;stage.add_child(camera)
	return {"container":container,"stage":stage,"camera":camera,"close":close,"models":[]}
func populate(item:Dictionary,source:PackedScene,config:Dictionary) -> void:
	var definition=Definition.new();definition.model_scene=source;definition.model_scale=config.model_scale;definition.model_floor_offset=config.model_floor_offset
	definition.use_legacy_animation_libraries=false;definition.preserve_source_materials=true
	definition.secondary_motion_bones=PackedStringArray(config.bones);definition.secondary_motion_limit=config.limit
	for enabled in [false,true]:
		definition.secondary_motion_strength=config.strength if enabled else 0.0
		var visual=Visual.new();item.stage.add_child(visual);visual.configure_definition(definition);visual.set_motion_profile(config.motion_profile)
		visual.position.x=(.24 if item.close else .5)*(1 if enabled else -1)*(1 if view=="front" else -1)
		for name in config.bones: check(visual.skeleton.find_bone(name)>=0,"Missing weighted secondary bone "+name+" in "+source.resource_path)
		check(visual.animation.has_animation("run"),"Missing run clip in "+source.resource_path)
		item.models.append(visual)
func finish() -> void:
	if done:return
	done=true
	var report={"status":"captured" if errors.is_empty() else "failed","visual_acceptance":"requires native frame/movie review","requested":ids,"completed":completed,"view":view,"fixed_gait_phase":null if animate_gait else FIXED_PHASE,"gait_phase_policy":"shared actual diagnostic displacement" if animate_gait else "fixed pose","fixed_dt":DT,"fps":30,"frames_per_model":180,"configurations":configurations,"bone_names_by_character":configurations.keys().map(func(id):return {"id":id,"bones":configurations[id].bones}),"pair":"left off; right on","views":["full body","close head"],"actual_node_translation":true,"physics_collision_or_world_route_verified":false,"operational_state_or_commands":false,"samples":records,"errors":errors,"engine":Engine.get_version_info()}
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"  "));file.close()
	else: errors.append("Could not write report")
	for error in errors:push_error(error)
	print("NEW_CAST_HAIR_CAPTURED" if errors.is_empty() else "NEW_CAST_HAIR_FAILED")
	quit(0 if errors.is_empty() else 1)
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
		if arg.begins_with("--cast="):ids.assign(arg.trim_prefix("--cast=").split(","))
		if arg.begins_with("--view="):view=arg.trim_prefix("--view=")
		if arg=="--animate-gait":animate_gait=true
	if output.is_empty():push_error("Explicit capture directory required");quit(1);return
	if DirAccess.make_dir_recursive_absolute(output)!=OK:push_error("Cannot create capture directory");quit(1);return
	check(view in ["front","rear"],"View must be front or rear")
	for id in ids:
		check(CAST.has(id),"Unknown selected hair model: "+id)
		check(ResourceLoader.exists("res://assets/characters/"+id+"/character.glb"),"Missing selected model: "+id)
		if not CAST.has(id):continue
		var selected:Resource=load("res://characters/definitions/"+ROLES[id]+".tres")
		check(selected.model_scene.resource_path=="res://assets/characters/"+id+"/character.glb","Definition must select expected model: "+id)
		configurations[id]={"height":CAST[id].height,"strength":selected.secondary_motion_strength,"limit":selected.secondary_motion_limit,"stride":selected.model_run_stride,"motion_profile":selected.motion_profile,"bones":Array(selected.secondary_motion_bones),"model_scale":selected.model_scale,"model_floor_offset":selected.model_floor_offset}
	if not errors.is_empty():finish();return
	root.size=Vector2i(1440,900);root.content_scale_size=Vector2i(1440,900)
	var canvas:=CanvasLayer.new();root.add_child(canvas)
	title=Label.new();title.position=Vector2(20,8);title.add_theme_font_size_override("font_size",23);canvas.add_child(title)
	var note:=Label.new();note.position=Vector2(20,42);note.text=("ANIMATED GAIT" if animate_gait else "FIXED POSE")+" · DIAGNOSTIC TRANSLATION · no physics journey · each view: LEFT secondary OFF / RIGHT ON";note.add_theme_font_size_override("font_size",16);canvas.add_child(note)
	create_timer(240).timeout.connect(func():check(false,"240-second capture watchdog");finish())
	for id in ids:
		var folder:String=output.path_join(id);DirAccess.make_dir_recursive_absolute(folder)
		var source:PackedScene=load("res://assets/characters/"+id+"/character.glb")
		for close in [false,true]:
			var item=panel(close);panels.append(item);populate(item,source,configurations[id])
		if not errors.is_empty():finish();return
		var position:=Vector3.ZERO
		var gait_phase:=FIXED_PHASE
		for frame in range(180):
			if done:return
			var displacement:=Vector3.ZERO;var phase_name:="STOP / SETTLE"
			if frame<60:displacement=Vector3(0,0,6*DT);phase_name="RUN"
			elif frame<120:
				var heading:=float(frame-60)/60.0*TAU
				displacement=Vector3(sin(heading),0,cos(heading))*6*DT;phase_name="TURN"
			position+=displacement
			if animate_gait:gait_phase=fposmod(gait_phase+displacement.length()/configurations[id].stride,1.0)
			title.text=id.replace("-"," ").to_upper()+" / "+phase_name+" · "+view.to_upper()+" · FULL BODY (left panel) / HEAD DETAIL (right panel)"
			for item in panels:
				for visual in item.models:
					visual.position+=displacement
					visual.project(displacement,displacement.length()>0,gait_phase,false,DT)
				var target:Vector3=position+Vector3(0,CAST[id].height-.12 if item.close else CAST[id].height*.5,0)
				item.camera.position=target+Vector3(0,0,4 if view=="front" else -4);item.camera.look_at(target)
			await process_frame
			RenderingServer.force_draw(false)
			check(root.get_texture().get_image().save_png(folder.path_join("frame-%04d.png"%frame))==OK,"Save "+id+" frame "+str(frame))
			if frame%6==0:
				var visual=panels[0].models[1]
				var angles:Dictionary={}
				for bone in visual.secondary_bones:angles[visual.skeleton.get_bone_name(bone)]=visual.secondary_bones[bone].angles.length()
				records.append({"asset":id,"path":source.resource_path,"frame":frame,"phase":phase_name,"position":[position.x,position.y,position.z],"clip":visual.clip,"gait_phase":gait_phase,"secondary_angle_radians":angles})
		completed.append(id)
		for item in panels:item.container.queue_free()
		panels.clear();await process_frame
	finish()
