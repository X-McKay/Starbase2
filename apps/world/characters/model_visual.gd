extends Node3D
## Pure cosmetic projection of displacement. Never owns movement or run state.
var animation: AnimationPlayer
var clip := ""
var heading := 0.0
var skeleton: Skeleton3D
var transition := 0.0
var idle_time := 0.0
var start_rotations: Array[Quaternion] = []
var start_positions: Array[Vector3] = []
var secondary = preload("res://characters/secondary_motion.gd").new()
var hair_bone := -1
var social_transition_finished := true
var social_elapsed := 0.0
var social_pose := ""

func configure(scene: PackedScene, scale_factor: float, floor_offset: float = -0.10) -> void:
	var instance := scene.instantiate()
	instance.scale = Vector3.ONE * scale_factor
	instance.position.y = floor_offset * scale_factor
	add_child(instance)
	skeleton = instance.find_children("*", "Skeleton3D", true, false)[0]
	hair_bone = skeleton.find_bone("HairSwing")
	animation = instance.find_children("*", "AnimationPlayer", true, false)[0]
	for name in ["walk", "idle"]:
		assert(animation.has_animation(name), "Character model requires " + name)
		animation.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	for name in ["run", "console"]:
		if animation.has_animation(name): animation.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	animation.speed_scale = 0
	var asset_path:=scene.resource_path
	var identity:="sentinel" if "cybercat-sentinel" in asset_path else "engineer" if "engineering-specialist" in asset_path else "vanguard"
	var social_path:="res://assets/characters/shift-social/"+identity+"-social.glb"
	if ResourceLoader.exists(social_path):
		var social_scene=load(social_path).instantiate()
		var social_player:AnimationPlayer=social_scene.find_children("*","AnimationPlayer",true,false)[0]
		var library:=AnimationLibrary.new()
		var animation_root:Node=animation.get_node(animation.root_node)
		var bone_path:=str(animation_root.get_path_to(skeleton))
		for clip_name in ["sit_down","seated","stand_up"]:
			if not social_player.has_animation(clip_name): continue
			var social:Animation=social_player.get_animation(clip_name).duplicate(true)
			for track in range(social.get_track_count()-1,-1,-1):
				var path:=social.track_get_path(track)
				if path.get_subname_count()==0: social.remove_track(track); continue
				var bone_name:=str(path.get_subname(0))
				if skeleton.find_bone(bone_name)<0: social.remove_track(track); continue
				social.track_set_path(track,NodePath(bone_path+":"+bone_name))
			social.loop_mode=Animation.LOOP_LINEAR if clip_name=="seated" else Animation.LOOP_NONE
			library.add_animation(clip_name,social)
		animation.add_animation_library("social",library)
		social_scene.free()

func project(displacement: Vector3, moving: bool, phase: float, reduced: bool, delta: float = 1.0/60.0, pose: String = "", facing_heading: float = INF) -> void:
	var previous_heading := rotation.y
	if moving:
		heading = atan2(displacement.x, displacement.z)
	if not moving and is_finite(facing_heading): heading=facing_heading
	elif not moving and pose=="console": heading=PI
	rotation.y = heading if reduced else rotate_toward(rotation.y,heading,delta*10.0)
	var next := "walk" if moving and not reduced else "idle"
	if next == "walk" and displacement.length()/maxf(delta,0.001)>5.0 and animation.has_animation("run"): next="run"
	if not moving and not reduced and pose=="console" and animation.has_animation("console"): next="console"
	if pose!=social_pose:
		social_pose=pose; social_elapsed=0.0
	social_elapsed+=delta
	var social_time:=-1.0
	social_transition_finished=true
	if not moving and pose=="sit" and animation.has_animation("social/seated"):
		if reduced or social_elapsed>=1.2:
			next="social/seated"; social_time=0.0 if reduced else fposmod(social_elapsed-1.2,3.0)
		else:
			next="social/sit_down"; social_time=social_elapsed; social_transition_finished=false
	elif not moving and pose=="stand" and animation.has_animation("social/stand_up"):
		next="social/stand_up"; social_time=1.0 if reduced else minf(social_elapsed,1.0)
		social_transition_finished=reduced or social_elapsed>=1.0
	if not reduced: idle_time+=delta
	if clip != next:
		start_rotations.clear()
		start_positions.clear()
		for i in skeleton.get_bone_count():
			start_rotations.append(skeleton.get_bone_pose_rotation(i))
			start_positions.append(skeleton.get_bone_pose_position(i))
		transition=0.18
		clip = next
		animation.play(clip)
	var time := 0.0
	if not reduced:
		time=phase*animation.get_animation(clip).length if clip in ["walk","run"] else fposmod(idle_time,animation.get_animation(clip).length)
	if social_time>=0: time=social_time
	# Imported social clips omit constant rest channels; clear prior clip poses.
	if social_time>=0: skeleton.reset_bone_poses()
	animation.seek(time,true)

	if not moving and not reduced:
		var spine := skeleton.find_bone("Spine02")
		if spine>=0:
			var spine_pose := skeleton.get_bone_pose_rotation(spine)
			skeleton.set_bone_pose_rotation(spine,spine_pose*Quaternion(Vector3.RIGHT,sin(idle_time*1.8)*0.012))
	if transition>0 and not reduced:
		transition=maxf(0,transition-delta)
		var blend := smoothstep(0,0.18,0.18-transition)
		for i in skeleton.get_bone_count():
			skeleton.set_bone_pose_rotation(i,start_rotations[i].slerp(skeleton.get_bone_pose_rotation(i),blend))
			skeleton.set_bone_pose_position(i,start_positions[i].lerp(skeleton.get_bone_pose_position(i),blend))
	if hair_bone>=0:
		var turn := angle_difference(previous_heading,rotation.y)
		skeleton.set_bone_pose_rotation(hair_bone,secondary.step(displacement,turn,delta,reduced))

func apply_role(color: Color) -> void:
	# Per-instance material copies retain the detailed source textures.
	for mesh in find_children("*","MeshInstance3D",true,false):
		for i in mesh.mesh.get_surface_count():
			var source=mesh.get_active_material(i)
			if source is StandardMaterial3D:
				var material=source.duplicate()
				material.albedo_color=color
				# Imported material omitted metallicFactor (glTF defaults to 1) and
				# reused full-strength albedo as emission. Keep textures, read as fabric.
				material.metallic=0.0
				material.metallic_specular=0.25
				material.roughness=0.8
				material.emission_enabled=false
				mesh.set_surface_override_material(i,material)
