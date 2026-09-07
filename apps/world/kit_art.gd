extends RefCounted
## Runtime UV sampling: no bitmap rewriting and no material-per-instance copies.
const MANIFEST_PATH := "res://assets/kits/aster-v1/manifest.json"
static var manifest: Dictionary = {}
static var materials: Dictionary = {}
static func definition() -> Dictionary:
	if manifest.is_empty(): manifest=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	return manifest
static func material(surface: String) -> ShaderMaterial:
	if materials.has(surface): return materials[surface]
	var data := definition()
	assert(data.surfaces.has(surface),"Unknown kit surface: "+surface)
	var texture: Texture2D = load(data.atlas)
	var r: Array = data.surfaces[surface]
	var inset := Vector2.ONE*float(data.inset_source_pixels)/Vector2(texture.get_size())
	var m := ShaderMaterial.new()
	m.shader=preload("res://kit_surface.gdshader")
	m.set_shader_parameter("atlas",texture)
	m.set_shader_parameter("region",Vector4(r[0]+inset.x,r[1]+inset.y,r[2]-2*inset.x,r[3]-2*inset.y))
	m.set_shader_parameter("emission_strength",0.12 if surface=="console" else 0.0)
	materials[surface]=m
	return m
static func panel(parent: Node3D, surface: String, position: Vector3, size: Vector2, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size=size
	node.mesh=mesh
	node.position=position
	node.rotation_degrees=rotation
	node.material_override=material(surface)
	parent.add_child(node)
	return node
