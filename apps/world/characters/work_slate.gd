extends Node3D
## Cosmetic equipment; never a progress display or a source of operational state.
var left_hand := -1
var right_hand := -1
var contact_span := 0.0
const PALM_OFFSET := Vector3(0,0.035,0.055)
var palm_offset := PALM_OFFSET
var grip_span_scale := 1.0
const MAX_WRIST_TILT := PI / 12.0
var wrist_tilt := 0.0
var palm_normals: Array[Vector3] = []

func configure(skeleton: Skeleton3D, offset: Vector3 = PALM_OFFSET, span_scale: float = 1.0) -> void:
	assert(offset.is_finite() and is_finite(span_scale) and span_scale>0)
	palm_offset=offset
	grip_span_scale=span_scale
	left_hand=skeleton.find_bone("LeftHand")
	right_hand=skeleton.find_bone("RightHand")
	add_child(preload("res://assets/props/field-slate/field-slate.glb").instantiate())
	_style_equipment()
	visible=false

func _style_equipment() -> void:
	# Keep the static authored diagram: it is equipment dressing, not telemetry.
	# Muted ceramic and darker glass retain their edges under the colony lights.
	for mesh in find_children("*","MeshInstance3D",true,false):
		mesh.mesh=mesh.mesh.duplicate()
		for surface in mesh.mesh.get_surface_count():
			var material=mesh.get_active_material(surface)
			if not material is StandardMaterial3D: continue
			if material.resource_name not in ["Ceramic chassis","Neutral glass"]: continue
			var copy:StandardMaterial3D=material.duplicate()
			if material.resource_name=="Ceramic chassis":
				copy.albedo_color=Color("817568")
				copy.metallic=0.25
				copy.roughness=0.48
			else:
				copy.albedo_color=Color("142c32")
				copy.roughness=0.32
			mesh.mesh.surface_set_material(surface,copy)

func apply_role(color: Color) -> void:
	for mesh in find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var material=mesh.get_active_material(surface)
			if material is StandardMaterial3D and material.resource_name=="Role accent":
				var copy=material.duplicate()
				copy.albedo_color=color.lerp(Color("dcb375"),.35)
				mesh.set_surface_override_material(surface,copy)

func project(skeleton: Skeleton3D, working: bool) -> void:
	visible=working and left_hand>=0 and right_hand>=0
	if not visible:
		_reset_grip()
		return
	var left_pose:=skeleton.global_transform*skeleton.get_bone_global_pose(left_hand)
	var right_pose:=skeleton.global_transform*skeleton.get_bone_global_pose(right_hand)
	var left:=left_pose.origin
	var right:=right_pose.origin
	contact_span=left.distance_to(right)
	if not left_pose.is_finite() or not right_pose.is_finite() or contact_span<0.001 or _singular_basis(left_pose.basis) or _singular_basis(right_pose.basis):
		visible=false
		_reset_grip()
		return
	# Fit the two grips to the real authored hand separation on each selected rig.
	# Rotate only around the shared grip axis: both grip endpoints stay in place.
	var across:Vector3=(left-right).normalized()
	if absf(across.dot(Vector3.UP))>0.98:
		visible=false
		_reset_grip()
		return
	var forward:Vector3=across.cross(Vector3.UP).normalized()
	var up:Vector3=forward.cross(across).normalized()
	# Calibrate the authored neutral grip on entry, instead of assuming all rigs
	# use the same palm bone axes. Subsequent tilt follows real wrist animation.
	if palm_normals.is_empty():
		palm_normals.assign([left_pose.basis.inverse()*up,right_pose.basis.inverse()*up])
	var palm_normal:Vector3=left_pose.basis*palm_normals[0]+right_pose.basis*palm_normals[1]
	palm_normal-=across*palm_normal.dot(across)
	if palm_normal.length_squared()>0.000001:
		wrist_tilt=clampf(up.signed_angle_to(palm_normal.normalized(),across),-MAX_WRIST_TILT,MAX_WRIST_TILT)
		up=up.rotated(across,wrist_tilt)
		forward=forward.rotated(across,wrist_tilt)
	var width:=contact_span*grip_span_scale/0.912
	global_transform=Transform3D(Basis(across,up,forward).scaled(Vector3(width,width,width)),(left+right)*0.5+across*palm_offset.x+up*palm_offset.y+forward*palm_offset.z)

func _reset_grip() -> void:
	contact_span=0.0
	wrist_tilt=0.0
	palm_normals.clear()

func _singular_basis(basis: Basis) -> bool:
	# Normalize first: centimetre-based imported rigs have small valid determinants.
	return absf(Basis(basis.x.normalized(),basis.y.normalized(),basis.z.normalized()).determinant())<0.000001
