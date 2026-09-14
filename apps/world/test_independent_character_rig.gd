extends SceneTree
const Visual = preload("res://characters/model_visual.gd")
const Definition = preload("res://characters/definition.gd")

func _initialize() -> void:
	run.call_deferred()

func rig_scene(clips: Array[String], with_shape:bool=false) -> PackedScene:
	var model:=Node3D.new()
	var rig:=Skeleton3D.new(); rig.name="OwnRig"; model.add_child(rig); rig.owner=model
	for bone in ["OwnSpine","LooseStrand"]: rig.add_bone(bone)
	rig.set_bone_rest(1,Transform3D(Basis(Quaternion(Vector3.RIGHT,.45)),Vector3(0,1,0)))
	rig.reset_bone_poses()
	var mesh:=MeshInstance3D.new(); mesh.name="ImportedBody"; mesh.mesh=BoxMesh.new()
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color("6983a6"); material.metallic=0.42; material.roughness=0.73
	material.normal_enabled=true; material.normal_scale=0.6
	if with_shape:
		var shape_mesh:=ArrayMesh.new();shape_mesh.add_blend_shape("SeatClearance")
		var vertices:=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
		var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices
		var shape:Array=[];shape.resize(Mesh.ARRAY_MAX);shape[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.BACK,Vector3.RIGHT,Vector3.UP])
		shape_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[shape]);shape_mesh.surface_set_material(0,material);mesh.mesh=shape_mesh
	else:mesh.mesh.material=material
	model.add_child(mesh); mesh.owner=model
	var player:=AnimationPlayer.new(); model.add_child(player); player.owner=model
	var library:=AnimationLibrary.new()
	for clip in clips:
		var motion:=Animation.new(); motion.length=2.0
		var track:=motion.add_track(Animation.TYPE_ROTATION_3D)
		motion.track_set_path(track,NodePath("OwnRig:OwnSpine"))
		motion.rotation_track_insert_key(track,0,Quaternion(Vector3.RIGHT,0.2))
		if with_shape:
			var shape_track:=motion.add_track(Animation.TYPE_BLEND_SHAPE)
			motion.track_set_path(shape_track,NodePath("ImportedBody:SeatClearance"))
			motion.blend_shape_track_insert_key(shape_track,0,0.75 if clip=="seated" else 0.0)
		library.add_animation(clip,motion)
	player.add_animation_library("",library)
	var packed:=PackedScene.new(); packed.pack(model); model.free()
	return packed

func run() -> void:
	var visual=Visual.new(); root.add_child(visual)
	if not visual.has_method("configure_definition"):
		printerr("FAILED: independent rigs need explicit definition configuration")
		visual.free(); quit(1); return
	var definition=Definition.new()
	definition.model_scene=rig_scene(["idle","walk"])
	definition.use_legacy_animation_libraries=false
	definition.model_animation_sources={"social":rig_scene(["sit_down","seated","stand_up"])}
	definition.upper_spine_bone="OwnSpine"
	definition.secondary_motion_bones=PackedStringArray(["LooseStrand"])
	if not "preserve_source_materials" in definition:
		printerr("FAILED: character definitions cannot preserve imported PBR materials")
		visual.free(); quit(1); return
	definition.preserve_source_materials=true
	definition.secondary_motion_strength=2.0
	definition.secondary_motion_limit=0.16
	visual.configure_definition(definition)
	var mesh:MeshInstance3D=visual.find_child("ImportedBody",true,false)
	var original:Material=mesh.get_active_material(0)
	visual.apply_role(Color.RED)
	visual.apply_role(Color.BLUE)
	assert(mesh.get_surface_override_material(0)==null and mesh.get_active_material(0)==original,"Role updates retain imported PBR rather than replacing it with the suit shader")
	assert(original.albedo_color==Color("6983a6") and is_equal_approx(original.metallic,0.42) and is_equal_approx(original.roughness,0.73) and original.normal_enabled and is_equal_approx(original.normal_scale,0.6))
	assert(visual.animation.has_animation("social/seated"))
	assert(not visual.animation.has_animation("work/field_slate"),"Independent rigs cannot inherit Vanguard work clips")
	assert(visual.spine_bone==0 and visual.hair_bone==1,"Optional secondary bones come from this model")
	visual.project(Vector3.ZERO,false,0,true,1.0/60.0,"sit")
	assert(visual.clip=="social/seated")
	assert(visual.skeleton.get_bone_pose_rotation(0).is_equal_approx(Quaternion(Vector3.RIGHT,0.2)),"Source tracks bind to this rig")
	assert(visual.skeleton.get_bone_pose_rotation(1).is_equal_approx(visual.skeleton.get_bone_rest(1).basis.get_rotation_quaternion()),"Reduced motion retains the actual nonidentity secondary rest orientation")
	visual.project(Vector3.ZERO,false,0,false,0.1,"stand")
	for tick in range(12): visual.project(Vector3.ZERO,false,0,false,0.1,"stand")
	assert(not visual.social_transition_finished,"Independent stand duration is not the old one-second constant")
	for tick in range(8): visual.project(Vector3.ZERO,false,0,false,0.1,"stand")
	assert(visual.social_transition_finished)
	var baseline=Visual.new(); root.add_child(baseline)
	definition.secondary_motion_strength=1.0
	definition.secondary_motion_limit=0.1
	baseline.configure_definition(definition)
	var baseline_peak:=0.0; var configured_peak:=0.0
	for tick in range(120):
		var phase:=float(tick)/60.0
		visual.project(Vector3(0.05,0,0),true,phase,false)
		baseline.project(Vector3(0.05,0,0),true,phase,false)
		configured_peak=maxf(configured_peak,visual.secondary.angles.length())
		baseline_peak=maxf(baseline_peak,baseline.secondary.angles.length())
		assert(visual.secondary.angles.length()<=0.160001,"Model-specific spring output stays within its configured envelope")
	assert(configured_peak>baseline_peak*1.4,"Configured strength changes the actual response")
	visual.secondary.configure(5.0,0.025)
	var limited_peak:=0.0
	for tick in range(60):
		visual.project(Vector3(0.05,0,0),true,float(tick)/60.0,false)
		limited_peak=maxf(limited_peak,visual.secondary.angles.length())
		assert(visual.secondary.angles.length()<=0.025001)
	assert(limited_peak>=0.024,"A strong response saturates at the requested limit")
	visual.project(Vector3.ZERO,false,0,true)
	assert(visual.secondary.angles==Vector2.ZERO and visual.secondary.velocity==Vector2.ZERO)
	assert(visual.skeleton.get_bone_pose_rotation(1).is_equal_approx(visual.skeleton.get_bone_rest(1).basis.get_rotation_quaternion()))
	baseline.free(); visual.free()
	var own_base=rig_scene(["idle","walk","seated"],true)
	definition.model_scene=own_base;definition.model_animation_sources={"social":own_base,"work":own_base}
	var corrected=Visual.new();root.add_child(corrected);corrected.configure_definition(definition)
	var seated:Animation=corrected.animation.get_animation("social/seated")
	assert(seated.get_track_count()==2,"Same-source aliases retain skeletal AND corrective blendshape tracks")
	assert(corrected.animation.get_animation("work/seated").get_track_count()==2,"Second namespace uses bare source clips rather than nesting prior aliases")
	corrected.project(Vector3.ZERO,false,0,true,1.0/60.0,"sit")
	var corrected_mesh:MeshInstance3D=corrected.find_child("ImportedBody",true,false)
	assert(is_equal_approx(corrected_mesh.get_blend_shape_value(0),0.75),"Corrective shape is evaluated in the actual selected model")
	corrected.project(Vector3.ZERO,false,0,true)
	assert(is_zero_approx(corrected_mesh.get_blend_shape_value(0)),"Source idle clears the seated corrective")
	corrected.free()
	var hands:=Skeleton3D.new();root.add_child(hands)
	hands.add_bone("LeftHand");hands.set_bone_pose_position(0,Vector3(.2,1,0))
	hands.add_bone("RightHand");hands.set_bone_pose_position(1,Vector3(-.2,1,0))
	var slate=preload("res://characters/work_slate.gd").new();root.add_child(slate)
	slate.configure(hands,Vector3(0,-.045,.068),.88);slate.project(hands,true)
	assert(slate.visible and slate.global_position.is_equal_approx(Vector3(0,.955,.068)),"Authored palm offset aligns equipment independently from old wrist offsets")
	assert(is_equal_approx(slate.global_basis.x.length(),.4*.88/.912),"Grip spacing follows model-specific palm span")
	slate.project(hands,false);assert(not slate.visible,"Attachment tuning cannot keep work equipment visible outside its pose")
	slate.free();hands.free()
	print("INDEPENDENT_CHARACTER_RIG_CHECKS_PASSED")
	quit()
