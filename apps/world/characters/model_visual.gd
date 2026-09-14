extends Node3D
## Pure cosmetic projection of displacement. Never owns movement or run state.
var sole_contact=preload("res://characters/sole_contact.gd").new()
var ground_clearance:=0.0
var social_ground_start:=0.0
var contact_enabled:=true
var support_sample:Callable

var animation: AnimationPlayer
var model_source: PackedScene
var clip := ""
var heading := 0.0
var skeleton: Skeleton3D
var transition := 0.0
var idle_time := 0.0
var start_rotations: Array[Quaternion] = []
var start_positions: Array[Vector3] = []
var secondary = preload("res://characters/secondary_motion.gd").new()
var hair_bone := -1
var secondary_bones: Dictionary = {}
var secondary_rest_rotations: Dictionary = {}
var secondary_motion_bones := PackedStringArray(["HairSwing"])
var upper_spine_bone := "Spine02"
var model_animation_sources: Dictionary = {}
var use_legacy_animation_libraries := true
var preserve_source_materials := false
var secondary_motion_strength := 1.0
var secondary_motion_limit := 0.10
var social_transition_finished := true
var social_elapsed := 0.0
var social_pose := ""
var work_slate: Node3D
var work_slate_palm_offset := Vector3(0,0.035,0.055)
var work_slate_grip_span_scale := 1.0
var suit_materials: Array[ShaderMaterial] = []
var turn_velocity:=0.0
var locomotion_lean:=Vector2.ZERO
var spine_bone:=-1
var run_selected:=false
var motion_profile:="operator"
const MOTION_PROFILES:={
	"operator":Vector3(1.0,1.0,1.0),
	"mender":Vector3(0.75,0.80,1.15),
	"surveyor":Vector3(1.0,0.90,0.85),
	"trainer":Vector3(1.35,1.10,1.15),
	"watchkeeper":Vector3(0.85,0.80,0.70),
	"reviewer":Vector3(1.10,0.95,0.80)}

func set_motion_profile(profile:String) -> void:
	motion_profile=profile if MOTION_PROFILES.has(profile) else "operator"


func configure_definition(definition: Resource) -> void:
	work_slate_palm_offset=definition.work_slate_palm_offset
	work_slate_grip_span_scale=definition.work_slate_grip_span_scale
	preserve_source_materials=definition.preserve_source_materials
	secondary_motion_strength=definition.secondary_motion_strength
	secondary_motion_limit=definition.secondary_motion_limit
	model_animation_sources=definition.model_animation_sources
	use_legacy_animation_libraries=definition.use_legacy_animation_libraries
	upper_spine_bone=definition.upper_spine_bone
	secondary_motion_bones=definition.secondary_motion_bones
	configure(definition.model_scene,definition.model_scale,definition.model_floor_offset,definition.animation_family)
	var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://characters/sole_probes.json"))
	sole_contact.configure(self,profiles.get(definition.id,{}))

func configure(scene: PackedScene, scale_factor: float, floor_offset: float = -0.10, animation_family: String = "") -> void:
	model_source=scene
	var instance := scene.instantiate()
	instance.scale = Vector3.ONE * scale_factor
	instance.position.y = floor_offset * scale_factor
	add_child(instance)
	skeleton = instance.find_children("*", "Skeleton3D", true, false)[0]
	secondary_bones.clear()
	secondary_rest_rotations.clear()
	for bone_name in secondary_motion_bones:
		var bone:=skeleton.find_bone(bone_name)
		if bone>=0:
			var driver=preload("res://characters/secondary_motion.gd").new()
			driver.configure(secondary_motion_strength,secondary_motion_limit)
			secondary_bones[bone]=driver
			secondary_rest_rotations[bone]=skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	hair_bone = secondary_bones.keys()[0] if not secondary_bones.is_empty() else -1
	if hair_bone>=0: secondary=secondary_bones[hair_bone]
	spine_bone = skeleton.find_bone(upper_spine_bone)
	animation = instance.find_children("*", "AnimationPlayer", true, false)[0]
	for name in ["walk", "idle"]:
		assert(animation.has_animation(name), "Character model requires " + name)
		animation.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	for name in ["run", "console"]:
		if animation.has_animation(name): animation.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	# project() owns sampling and applies blends/secondary motion after seek().
	# A paused automatic player still reapplies raw tracks on the next frame.
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation.speed_scale = 0
	for library_name in model_animation_sources:
		_attach_scene_library(str(library_name),model_animation_sources[library_name])
	work_slate=preload("res://characters/work_slate.gd").new()
	add_child(work_slate)
	work_slate.configure(skeleton,work_slate_palm_offset,work_slate_grip_span_scale)

func _attach_scene_library(library_name: String, source: PackedScene, clips: Array = []) -> void:
	assert(not animation.has_animation_library(library_name),"Duplicate model animation library: "+library_name)
	if source==model_source:
		# This is already bound to the selected model: retain node/property/morph
		# channels as well as bones. Rebinding would discard contact correctives.
		var original:AnimationLibrary=animation.get_animation_library("")
		var own_library:=AnimationLibrary.new()
		var names:Array=clips if not clips.is_empty() else Array(original.get_animation_list())
		for name in names:
			if not original.has_animation(name):continue
			var own_clip:Animation=original.get_animation(name).duplicate(true)
			own_clip.loop_mode=Animation.LOOP_LINEAR if name in ["seated","field_slate"] else Animation.LOOP_NONE
			own_library.add_animation(name,own_clip)
		animation.add_animation_library(library_name,own_library)
		return
	var scene=source.instantiate()
	var player:AnimationPlayer=scene.find_children("*","AnimationPlayer",true,false)[0]
	if clips.is_empty(): clips=Array(player.get_animation_list())
	var library:=AnimationLibrary.new()
	var animation_root:Node=animation.get_node(animation.root_node)
	var bone_path:=str(animation_root.get_path_to(skeleton))
	for clip_name in clips:
		if not player.has_animation(clip_name): continue
		var imported:Animation=player.get_animation(clip_name).duplicate(true)
		for track in range(imported.get_track_count()-1,-1,-1):
			var track_path:=imported.track_get_path(track)
			if track_path.get_subname_count()==0: imported.remove_track(track); continue
			var bone_name:=str(track_path.get_subname(0))
			if skeleton.find_bone(bone_name)<0: imported.remove_track(track); continue
			imported.track_set_path(track,NodePath(bone_path+":"+bone_name))
		imported.loop_mode=Animation.LOOP_LINEAR if clip_name in ["seated","field_slate"] else Animation.LOOP_NONE
		library.add_animation(clip_name,imported)
	animation.add_animation_library(library_name,library)
	scene.free()

func project(displacement: Vector3, moving: bool, phase: float, reduced: bool, delta: float = 1.0/60.0, pose: String = "", facing_heading: float = INF) -> void:
	var previous_heading := rotation.y
	var motion_style:Vector3=MOTION_PROFILES[motion_profile]
	var valid_step:=delta>0.0 and delta<=0.25 and displacement.is_finite() and displacement.length()<=0.5
	var actual_moving:=moving and valid_step and Vector2(displacement.x,displacement.z).length()>0.0001
	var speed:=displacement.length()/maxf(delta,0.001) if actual_moving else 0.0
	if actual_moving:
		heading=atan2(displacement.x,displacement.z)
	if not actual_moving and is_finite(facing_heading): heading=facing_heading
	elif not actual_moving and pose=="console": heading=PI
	if reduced or not valid_step:
		rotation.y=heading
		turn_velocity=0.0
		locomotion_lean=Vector2.ZERO
	else:
		var remaining:=delta
		while remaining>0.000001:
			var dt:=minf(remaining,1.0/120.0)
			var difference:=angle_difference(rotation.y,heading)
			turn_velocity+=(difference*150.0*motion_style.x-turn_velocity*24.0*sqrt(motion_style.x))*dt
			turn_velocity=clampf(turn_velocity,-10.0,10.0)
			rotation.y+=turn_velocity*dt
			remaining-=dt
	var next := "walk" if actual_moving and not reduced else "idle"
	# Hysteresis prevents noisy measured speed from restarting blends at the threshold.
	if not actual_moving or reduced: run_selected=false
	elif speed>5.2: run_selected=true
	elif speed<4.7: run_selected=false
	if next=="walk" and run_selected and animation.has_animation("run"): next="run"
	if not actual_moving and not reduced and pose=="console":
		if animation.has_animation("work/field_slate"): next="work/field_slate"
		elif animation.has_animation("console"): next="console"
	if pose!=social_pose:
		social_ground_start=position.y
		social_pose=pose; social_elapsed=0.0
	social_elapsed+=delta
	var social_time:=-1.0
	social_transition_finished=true
	if not actual_moving and pose=="sit" and animation.has_animation("social/seated"):
		var sit_length:=animation.get_animation("social/sit_down").length if animation.has_animation("social/sit_down") else 0.0
		if reduced or social_elapsed>=sit_length:
			next="social/seated"; social_time=0.0 if reduced else fposmod(social_elapsed-sit_length,animation.get_animation(next).length)
		else:
			next="social/sit_down"; social_time=social_elapsed; social_transition_finished=false
	elif not actual_moving and pose=="stand" and animation.has_animation("social/stand_up"):
		var stand_length:=animation.get_animation("social/stand_up").length
		next="social/stand_up"; social_time=stand_length if reduced else minf(social_elapsed,stand_length)
		social_transition_finished=reduced or social_elapsed>=stand_length
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
	if social_time>=0 or clip=="work/field_slate": skeleton.reset_bone_poses()
	animation.seek(time,true)

	if not moving and not reduced:
		var spine := spine_bone
		if spine>=0:
			var spine_pose := skeleton.get_bone_pose_rotation(spine)
			skeleton.set_bone_pose_rotation(spine,spine_pose*Quaternion(Vector3.RIGHT,sin(idle_time*(1.65+motion_style.y*0.15))*0.012*motion_style.y))
	# Lean affects only the upper spine, never root height, hips or planted feet.
	# Social/contact poses use their exact authored channels without this overlay.
	var target_lean:=Vector2(clampf(speed*0.004,0,0.026),clampf(-turn_velocity*0.006,-0.035,0.035)) if actual_moving and not reduced and pose not in ["sit","stand"] else Vector2.ZERO
	target_lean*=motion_style.z
	locomotion_lean=locomotion_lean.lerp(target_lean,1.0-exp(-maxf(delta,0.0)*12.0)) if not reduced else Vector2.ZERO
	if pose in ["sit","stand"]: locomotion_lean=Vector2.ZERO
	if spine_bone>=0 and not reduced and locomotion_lean.length_squared()>0.0000001:
		var overlay:=Quaternion(Vector3.RIGHT,locomotion_lean.x)*Quaternion(Vector3.FORWARD,locomotion_lean.y)
		skeleton.set_bone_pose_rotation(spine_bone,skeleton.get_bone_pose_rotation(spine_bone)*overlay)
	if transition>0 and not reduced:
		transition=maxf(0,transition-delta)
		var blend := smoothstep(0,0.18,0.18-transition)
		for i in skeleton.get_bone_count():
			skeleton.set_bone_pose_rotation(i,start_rotations[i].slerp(skeleton.get_bone_pose_rotation(i),blend))
			skeleton.set_bone_pose_position(i,start_positions[i].lerp(skeleton.get_bone_pose_position(i),blend))
	for bone in secondary_bones:
		var turn := angle_difference(previous_heading,rotation.y)
		# Bone pose rotations are absolute local rotations, not rest-relative deltas.
		# Imported Head children commonly have nonidentity local rest orientations.
		var delta_rotation:Quaternion=secondary_bones[bone].step(displacement if actual_moving else Vector3.ZERO,turn,delta,reduced or not valid_step,phase)
		skeleton.set_bone_pose_rotation(bone,secondary_rest_rotations[bone]*delta_rotation)
	_apply_ground_contact(pose)
	work_slate.project(skeleton,not moving and not reduced and pose=="console" and clip=="work/field_slate" and transition<=0)

func apply_role(color: Color) -> void:
	work_slate.apply_role(color)
	if preserve_source_materials: return
	# Reuse each instance's shader on subsequent recolors; never modify imported art.
	for material in suit_materials: material.set_shader_parameter("role_color",color)
	if not suit_materials.is_empty(): return
	for mesh in find_children("*","MeshInstance3D",true,false):
		if work_slate.is_ancestor_of(mesh): continue
		for i in mesh.mesh.get_surface_count():
			var source=mesh.get_active_material(i)
			if source is StandardMaterial3D:
				if source.resource_name.begins_with("CrewGear_"): continue
				var material:=ShaderMaterial.new()
				material.shader=preload("res://characters/crew_presence.gdshader")
				material.set_shader_parameter("suit_texture",source.albedo_texture)
				material.set_shader_parameter("role_color",color)
				suit_materials.append(material)
				mesh.set_surface_override_material(i,material)

func _apply_ground_contact(pose:String) -> void:
	# Navigation remains planar. Correct only cosmetic support after every blend.
	# Authored social poses own their bench contact; never lift their pelvis.
	if not contact_enabled:
		position.y=0.0;ground_clearance=0.0
		return
	if pose=="sit":
		position.y=lerpf(social_ground_start,0.0,smoothstep(0.0,0.25,social_elapsed))
		if social_transition_finished:position.y=0.0
		ground_clearance=position.y
		return
	position.y=0.0
	if support_sample.is_valid():ground_clearance=sole_contact.required_lift(self,support_sample)
	else:ground_clearance=maxf(0.0,0.002-sole_contact.minimum_y(self))
	position.y=ground_clearance*(smoothstep(0.0,0.4,social_elapsed) if pose=="stand" and not social_transition_finished else 1.0)
