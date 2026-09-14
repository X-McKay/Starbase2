extends Node3D
## Cosmetic equipment; never a progress display or a source of operational state.
var left_hand := -1
var right_hand := -1
var contact_span := 0.0
const PALM_OFFSET := Vector3(0,0.035,0.055)
var palm_offset := PALM_OFFSET
var grip_span_scale := 1.0

func configure(skeleton: Skeleton3D, offset: Vector3 = PALM_OFFSET, span_scale: float = 1.0) -> void:
	assert(offset.is_finite() and is_finite(span_scale) and span_scale>0)
	palm_offset=offset
	grip_span_scale=span_scale
	left_hand=skeleton.find_bone("LeftHand")
	right_hand=skeleton.find_bone("RightHand")
	add_child(preload("res://assets/props/field-slate/field-slate.glb").instantiate())
	visible=false

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
	if not visible: return
	var left:Vector3=skeleton.to_global(skeleton.get_bone_global_pose(left_hand).origin)
	var right:Vector3=skeleton.to_global(skeleton.get_bone_global_pose(right_hand).origin)
	contact_span=left.distance_to(right)
	# Fit the two grips to the real authored hand separation on each selected rig.
	# X follows the hands; the screen normal remains upward, avoiding wrist roll.
	var across:Vector3=(left-right).normalized()
	var forward:Vector3=across.cross(Vector3.UP).normalized()
	var up:Vector3=forward.cross(across).normalized()
	var width:=contact_span*grip_span_scale/0.912
	global_transform=Transform3D(Basis(across,up,forward).scaled(Vector3(width,width,width)),(left+right)*0.5+across*palm_offset.x+up*palm_offset.y+forward*palm_offset.z)
