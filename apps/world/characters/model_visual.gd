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

func configure(scene: PackedScene, scale_factor: float, floor_offset: float = -0.10) -> void:
	var instance := scene.instantiate()
	instance.scale = Vector3.ONE * scale_factor
	instance.position.y = floor_offset * scale_factor
	add_child(instance)
	skeleton = instance.find_children("*", "Skeleton3D", true, false)[0]
	animation = instance.find_children("*", "AnimationPlayer", true, false)[0]
	for name in ["walk", "idle"]:
		assert(animation.has_animation(name), "Character model requires " + name)
		animation.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	for name in ["run", "console"]:
		if animation.has_animation(name): animation.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	animation.speed_scale = 0

func project(displacement: Vector3, moving: bool, phase: float, reduced: bool, delta: float = 1.0/60.0, pose: String = "") -> void:
	if moving:
		heading = atan2(displacement.x, displacement.z)
	if not moving and pose=="console": heading=PI
	rotation.y = heading if reduced else rotate_toward(rotation.y,heading,delta*10.0)
	var next := "walk" if moving and not reduced else "idle"
	if next == "walk" and displacement.length()/maxf(delta,0.001)>5.0 and animation.has_animation("run"): next="run"
	if not moving and not reduced and pose=="console" and animation.has_animation("console"): next="console"
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

func apply_role(color: Color) -> void:
	# Per-instance material copies retain the detailed source textures.
	for mesh in find_children("*","MeshInstance3D",true,false):
		for i in mesh.mesh.get_surface_count():
			var source=mesh.get_active_material(i)
			if source is StandardMaterial3D:
				var material=source.duplicate()
				material.albedo_color=color
				mesh.set_surface_override_material(i,material)
