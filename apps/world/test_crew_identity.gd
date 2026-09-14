extends SceneTree
const Catalog=preload("res://characters/catalog.gd")
const Visual=preload("res://characters/model_visual.gd")
const IDS=["operator","mender","surveyor","trainer","watchkeeper","reviewer"]
const SELECTED_CAST={"operator":"wayfinder","mender":"rivet","surveyor":"moss-cartographer","trainer":"stillpoint","watchkeeper":"night-shift","reviewer":"prism"}
var failures:Array[String]=[]
func check(ok:bool,message:String) -> void:
	if not ok and message not in failures: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var paths:Array[String]=[]
	for id in IDS:
		check(Catalog.definitions().has(id),id+": explicit catalog identity")
		if not Catalog.definitions().has(id): continue
		var definition=Catalog.get_definition(id)
		check(definition.id==id and definition.motion_profile==id,id+": distinct identity/profile")
		check(definition.model_scene!=null,id+": real 3D model required")
		if definition.model_scene==null: continue
		var path:String=definition.model_scene.resource_path
		check(path not in paths,id+": unique selected character PackedScene")
		paths.append(path)
		var visual=Visual.new(); root.add_child(visual)
		visual.configure_definition(definition)
		visual.set_motion_profile(definition.motion_profile)
		var source_materials:Array=[]
		for mesh in visual.find_children("*","MeshInstance3D",true,false):
			if visual.work_slate.is_ancestor_of(mesh): continue
			for surface in mesh.mesh.get_surface_count(): source_materials.append([mesh,surface,mesh.get_active_material(surface)])
		visual.apply_role(definition.model_tint)
		if not definition.use_legacy_animation_libraries:
			var asset_root:String="res://assets/characters/"+SELECTED_CAST[id]+"/"
			check(path.begins_with(asset_root),id+": selected independent character path")
			check(definition.preserve_source_materials,id+": preserve authored body PBR")
			check(not source_materials.is_empty(),id+": body has material surfaces")
			for entry in source_materials:
				check(entry[2]!=null and entry[0].get_active_material(entry[1])==entry[2],id+": role color retains exact imported body material")
			for library_name in ["social","work"]:
				check(definition.model_animation_sources.has(library_name),id+": own "+library_name+" animation source")
				if definition.model_animation_sources.has(library_name):
					var source=definition.model_animation_sources[library_name]
					check(source is PackedScene and source.resource_path.begins_with(asset_root),id+": animation library belongs to selected character")
			for bone in definition.secondary_motion_bones:
				check(visual.skeleton.find_bone(bone)>=0,id+": declared secondary bone exists: "+bone)
			if not definition.upper_spine_bone.is_empty(): check(visual.spine_bone>=0,id+": declared upper spine exists")
		for clip in ["idle","walk","run","social/sit_down","social/seated","social/stand_up","work/field_slate"]:
			check(visual.animation.has_animation(clip),id+": required character clip "+clip)
		if not definition.use_legacy_animation_libraries:
			check_contact_reset(id,visual)
		for frame in range(90):
			var direction:=Vector3.BACK if frame<45 else Vector3.RIGHT
			visual.project(direction*0.1,true,float(frame%60)/60.0,false,1.0/60.0)
			for bone in visual.skeleton.get_bone_count():
				check(visual.skeleton.get_bone_global_pose(bone).origin.is_finite(),id+": finite pose during turn: "+visual.skeleton.get_bone_name(bone))
		for bone in visual.secondary_bones:
			var driver=visual.secondary_bones[bone]
			check(driver.angles.length()<=definition.secondary_motion_limit+0.00001,id+": response respects model-specific secondary envelope")
			if definition.secondary_motion_strength>0 and definition.secondary_motion_limit>0:
				check(driver.angles.length()>.001,id+": running drives configured secondary response")
		visual.project(Vector3.ZERO,false,0,true,1.0/60.0)
		check(visual.clip=="idle",id+": reduced motion selects stable idle")
		for bone in visual.secondary_bones:
			check(visual.skeleton.get_bone_pose_rotation(bone).is_equal_approx(visual.skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()),id+": reduced motion clears secondary bend")
		check(visual.motion_profile==id,id+": motion profile retained")
		check(visual.find_children("*","HTTPRequest",true,false).is_empty(),id+": cosmetic model owns no HTTP")
		visual.queue_free(); await process_frame
	check(paths.size()==6,"All six real model resources inspected")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CREW_IDENTITY_PASSED: six selected character resources, model-owned animation contract, material preservation and reduced motion; native physical review remains separate")
	quit(0 if failures.is_empty() else 1)

func check_contact_reset(id:String,visual:Node3D) -> void:
	var shapes:Array=[]
	for mesh in visual.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null or mesh.skin==null: continue
		for index in mesh.mesh.get_blend_shape_count(): shapes.append([mesh,index])
	check(not shapes.is_empty(),id+": authored seated skin corrections import")
	var sit_frames:=ceili(visual.animation.get_animation("social/sit_down").length*60)+30
	var active:=false
	for frame in range(sit_frames):
		visual.project(Vector3.ZERO,false,0,false,1.0/60.0,"sit",0)
		for shape in shapes:active=active or absf(shape[0].get_blend_shape_value(shape[1]))>.01
	check(active,id+": selected sit sequence evaluates real mesh correction")
	for pose in ["console",""]:
		for frame in range(30):visual.project(Vector3.ZERO,false,0,false,1.0/60.0,pose,0)
		for shape in shapes:check(absf(shape[0].get_blend_shape_value(shape[1]))<.00001,id+": leaving seat clears skin correction for "+pose)
