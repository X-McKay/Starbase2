extends SceneTree
## Isolated native deformed-skin review. No world route or operational state is simulated.
const Visual=preload("res://characters/model_visual.gd")
const Definition=preload("res://characters/definition.gd")
var ids:Array[String]=["wayfinder","rivet","moss-cartographer","stillpoint","night-shift","prism"]
var output:=""
var stage:Node3D
var camera:Camera3D
var visual:Node3D
var records:Array=[]
var captures:Array=[]
var errors:Array=[]
var done:=false
var current_id:=""
var current_scale:=1.0
var current_floor:=0.0
var support_checker:Callable

func _initialize() -> void: run.call_deferred()
func check(ok:bool,message:String) -> void:
	if not ok: errors.append(message)
func box(position:Vector3,size:Vector3,color:Color) -> void:
	var node:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.9
	node.mesh=mesh;node.material_override=mat;node.position=position;stage.add_child(node)
func advance(pose:String,count:int,reduced:bool=false) -> void:
	for frame in range(count):
		visual.project(Vector3.ZERO,false,0,reduced,1.0/30.0,pose,0.0)
		await process_frame
func points() -> Dictionary:
	var support_minimum:=INF
	var minimum:=INF;var slab_count:=0;var worst_slab:=0.0;var soles:={"left":INF,"right":INF};var slab_examples:Array=[]
	var skeleton:Skeleton3D=visual.skeleton
	var morph_records:Array=[]
	skeleton.force_update_all_bone_transforms()
	for instance in visual.find_children("*","MeshInstance3D",true,false):
		if instance.skin==null: continue
		var skin_transforms:Array[Transform3D]=[]
		var skin_names:Array[String]=[]
		for bind in instance.skin.get_bind_count():
			var bone:int=instance.skin.get_bind_bone(bind)
			if bone<0:bone=skeleton.find_bone(instance.skin.get_bind_name(bind))
			skin_transforms.append(skeleton.get_bone_global_pose(bone)*instance.skin.get_bind_pose(bind))
			skin_names.append(skeleton.get_bone_name(bone))
		for surface in instance.mesh.get_surface_count():
			var arrays:Array=instance.mesh.surface_get_arrays(surface)
			var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
			var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
			if verts.is_empty() or bones.is_empty(): continue
			var shapes:Array=instance.mesh.surface_get_blend_shape_arrays(surface)
			var active_shapes:Array=[]
			var total_weight:=0.0
			for shape_index in shapes.size():
				var weight:float=instance.get_blend_shape_value(shape_index)
				if absf(weight)<.000001:continue
				var shape_vertices:PackedVector3Array=shapes[shape_index][Mesh.ARRAY_VERTEX]
				if shape_vertices.size()!=verts.size():continue
				active_shapes.append([weight,shape_vertices]);total_weight+=weight
				morph_records.append({"mesh":instance.name,"surface":surface,"shape":instance.mesh.get_blend_shape_name(shape_index),"weight":weight,"mode":instance.mesh.blend_shape_mode})
			var influences:int=bones.size()/verts.size()
			for vertex in verts.size():
				var point:=Vector3.ZERO;var left_weight:=0.0;var right_weight:=0.0
				# NORMALIZED arrays contain absolute shape positions; RELATIVE contains deltas.
				var source_vertex:Vector3=verts[vertex]
				if instance.mesh.blend_shape_mode==Mesh.BLEND_SHAPE_MODE_NORMALIZED:source_vertex*=1.0-total_weight
				for shape in active_shapes:source_vertex+=shape[1][vertex]*shape[0]
				for influence in influences:
					var weight:float=weights[vertex*influences+influence]
					if weight<=0: continue
					var bind:int=bones[vertex*influences+influence]
					var bone_name:String=skin_names[bind]
					point+=(skin_transforms[bind]*source_vertex)*weight
					if bone_name in ["LeftFoot","LeftToeBase"]: left_weight+=weight
					if bone_name in ["RightFoot","RightToeBase"]: right_weight+=weight
				point=skeleton.to_global(point)
				minimum=minf(minimum,point.y)
				if support_checker.is_valid() and (left_weight+right_weight)>.05:
					support_minimum=minf(support_minimum,point.y-float(support_checker.call(point)))
				if left_weight>.5: soles.left=minf(soles.left,point.y)
				if right_weight>.5: soles.right=minf(soles.right,point.y)
				if absf(point.x)<.4 and point.z<-.35 and point.z>-.75 and point.y>.38 and point.y<.48:
					slab_count+=1;worst_slab=maxf(worst_slab,.48-point.y)
					if slab_examples.size()<12:slab_examples.append([point.x,point.y,point.z])
	var joints:={}
	for name in ["Hips","Head","LeftLeg","RightLeg","LeftFoot","RightFoot","LeftHand","RightHand"]:
		var bone:=skeleton.find_bone(name);var p:Vector3=skeleton.to_global(skeleton.get_bone_global_pose(bone).origin)
		joints[name]=[p.x,p.y,p.z]
	return {"surface_clearance":support_minimum,"floor_skin_min":minimum,"foot_weighted_skin_min":soles,"bench_slab_vertices":slab_count,"max_slab_depth":worst_slab,"slab_examples":slab_examples,"joints":joints,"active_blend_shapes":morph_records}
func sample(phase:String) -> void:
	var contact:=points();contact.identity=current_id;contact.model_scale=current_scale;contact.model_floor_offset=current_floor;contact.phase=phase;contact.clip=visual.clip;records.append(contact)
	for view in ["front","side"]:
		camera.position=Vector3(0,1.05,5) if view=="front" else Vector3(5,1.05,-.15)
		camera.look_at(Vector3(0,.85,-.18))
		for frame in range(3):await process_frame
		RenderingServer.force_draw(false)
		var name:String=current_id+"-"+phase+"-"+view+".png"
		check(root.get_texture().get_image().save_png(output.path_join(name))==OK,"Save "+name);captures.append(name)
func finish() -> void:
	if done:return
	done=true
	var report:={"status":"captured" if errors.is_empty() else "failed","engine":Engine.get_version_info(),"identities":ids,"runtime_source":"res://assets/characters/<id>/character.glb","transform_policy":"selected definition; per-record scale/floor offset","bench":{"center":[0,.43,-.55],"size":[.8,.1,.4],"top":.48},"physical_route_verified":false,"deformed_skin_visual_review_required":true,"network_requests":0,"records":records,"captures":captures,"errors":errors}
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("NEW_CAST_CONTACTS_CAPTURED" if errors.is_empty() else "NEW_CAST_CONTACTS_FAILED")
	quit(0 if errors.is_empty() else 1)
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
		if arg.begins_with("--cast="):ids.assign(arg.trim_prefix("--cast=").split(","))
	if output.is_empty():push_error("Explicit capture directory required");quit(1);return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(110).timeout.connect(func():check(false,"110 second watchdog");finish())
	root.size=Vector2i(1000,900);root.msaa_3d=Viewport.MSAA_4X
	stage=Node3D.new();root.add_child(stage)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("273342");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("cad9e7");env.environment.ambient_light_energy=.65;stage.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-25,0);sun.light_energy=1.4;sun.shadow_enabled=true;stage.add_child(sun)
	box(Vector3(0,-.025,0),Vector3(5,.05,4),Color("566774"))
	box(Vector3(0,.43,-.55),Vector3(.8,.1,.4),Color("a68257"))
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.4;stage.add_child(camera)
	for identity in ids:
		current_id=identity
		var source:PackedScene=load("res://assets/characters/"+identity+"/character.glb")
		if source==null:check(false,"Missing "+identity);finish();return
		var roles:Dictionary={"wayfinder":"operator","rivet":"mender","moss-cartographer":"surveyor","stillpoint":"trainer","night-shift":"watchkeeper","prism":"reviewer","cybercat-player":"cybercat"}
		var definition=preload("res://characters/catalog.gd").get_definition(roles[identity]).duplicate(true)
		check(definition.model_scene.resource_path==source.resource_path,"Selected definition owns "+identity)
		current_scale=definition.model_scale;current_floor=definition.model_floor_offset
		# Only decorative secondary motion is suppressed for isolated body contact review.
		definition.secondary_motion_bones=PackedStringArray([])
		visual=Visual.new();stage.add_child(visual);visual.configure_definition(definition)
		await advance("",12);await sample("idle")
		await advance("sit",18);await sample("sit-mid")
		await advance("sit",35);await sample("seated")
		await advance("stand",15);await sample("stand-mid")
		await advance("stand",25);await sample("standing-return")
		await advance("console",16);await sample("console")
		await advance("sit",1,true);await sample("reduced-seated")
		visual.queue_free();await process_frame
	finish()
