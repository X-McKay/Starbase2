extends Node3D
## Decorative shelter and garden. No operational state or mission authority.
const ORIGIN := Vector3(-7, 0, 23)
const FOOTPRINT := Rect2(-12, 19.6, 10, 7.1)
const BLOCKS: Array[Rect2] = [
	Rect2(-11.85, 19.9, 1.0, 6.5),
	Rect2(-3.15, 19.9, 1.0, 6.5),
	Rect2(-9.4, 25.65, 4.8, 0.85),
	Rect2(-7.7, 22.0, 1.4, 2.1),
]
const HEIGHTS := [3.2, 3.2, 1.21, 2.2]
const MODEL := "res://assets/environment/living-commons/living-commons.glb"
var foliage_materials: Array[ShaderMaterial] = []
var canopy_materials: Array[ShaderMaterial] = []
var canopy_visibility := 1.0

func update_presentation(point:Vector3,delta:float,reduced:bool) -> void:
	var target := 0.0 if FOOTPRINT.has_point(Vector2(point.x,point.z)) else 1.0
	canopy_visibility=target if reduced else move_toward(canopy_visibility,target,delta*2.5)
	for material in canopy_materials: material.set_shader_parameter("visibility",canopy_visibility)

func set_reduced_motion(reduced:bool) -> void:
	for material in foliage_materials: material.set_shader_parameter("motion_enabled",not reduced)

func _foliage_material(source: Material) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://living_foliage.gdshader")
	if source is StandardMaterial3D:
		material.set_shader_parameter("color", source.albedo_color)
		material.set_shader_parameter("roughness", source.roughness)
		material.set_shader_parameter("metallic", source.metallic)
		if source.albedo_texture != null:
			material.set_shader_parameter("albedo_map", source.albedo_texture)
			material.set_shader_parameter("use_albedo", true)
	return material

func _ready() -> void:
	position = ORIGIN
	var packed := load(MODEL) as PackedScene
	if packed == null:
		push_error("Living commons model is unavailable")
		return
	add_child(packed.instantiate())
	for mesh in find_children("*","MeshInstance3D",true,false):
		var foliage := "Leaf" in str(mesh.name)
		var roof := str(mesh.name).begins_with("CanopySlats")
		if not foliage and not roof: continue
		for surface in mesh.mesh.get_surface_count():
			var material := _foliage_material(mesh.get_active_material(surface)) if foliage else preload("res://structures/materials.gd").cutaway(mesh.get_active_material(surface))
			material.set_shader_parameter("breeze_strength",0.025 if foliage else 0.0)
			mesh.set_surface_override_material(surface,material)
			if foliage: foliage_materials.append(material)
			if roof: canopy_materials.append(material)
	for index in range(BLOCKS.size()):
		var bounds := BLOCKS[index]
		var body := StaticBody3D.new()
		body.name = "GardenBoundary%d" % index
		var center := bounds.get_center()
		body.position = Vector3(center.x, HEIGHTS[index] / 2.0, center.y) - ORIGIN
		var shape := BoxShape3D.new()
		shape.size = Vector3(bounds.size.x, HEIGHTS[index], bounds.size.y)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
	for x in [-2.3, 2.3]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x, 3.0, 0.1)
		lamp.light_color = Color(1.0, 0.72, 0.40)
		lamp.light_energy = 0.45
		lamp.omni_range = 4.5
		lamp.shadow_enabled = false
		add_child(lamp)
