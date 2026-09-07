extends RefCounted
## Original modular geometry and SVG pixel art. No operational state lives here.
static var materials: Dictionary = {}

static func mat(color: String, texture: String = "", glow: bool = false) -> StandardMaterial3D:
	var key := color + texture + str(glow)
	if materials.has(key):
		return materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = 0.9
	if texture != "":
		m.albedo_texture = load("res://assets/kits/frontier-surfaces/" + texture + ".svg")
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if glow:
		m.emission_enabled = true
		m.emission = Color(color)
		m.emission_energy_multiplier = 0.45
	materials[key] = m
	return m

static func box(parent: Node3D, pos: Vector3, size: Vector3, color: String, texture: String = "", glow: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = pos
	node.material_override = mat(color, texture, glow)
	parent.add_child(node)
	return node

static func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	node.mesh = mesh
	node.position = pos
	node.material_override = mat(color)
	parent.add_child(node)
	return node

static func sprite(parent: Node3D, asset: String, pos: Vector3, scale_px: float = 0.045) -> Sprite3D:
	var s := Sprite3D.new()
	var category := "environment/frontier-plants" if asset in ["tree", "plant"] else "characters/frontier-crew"
	s.texture = load("res://assets/" + category + "/" + asset + ".svg")
	s.position = pos
	s.pixel_size = scale_px
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(s)
	return s

static func sign(parent: Node3D, text: String, pos: Vector3, color: String = "e8e5cc", size: int = 25) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = size
	l.pixel_size = 0.014
	l.modulate = Color(color)
	l.outline_size = 5
	l.outline_modulate = Color("243b4c")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(l)
	return l

static func collider(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	parent.add_child(body)

static func lamp(parent: Node3D, pos: Vector3) -> void:
	cylinder(parent, pos + Vector3(0, 0.08, 0), 0.24, 0.16, "435d6b")
	box(parent, pos + Vector3(0, 0.75, 0), Vector3(0.10, 1.5, 0.10), "405667")
	box(parent, pos + Vector3(0, 1.55, 0), Vector3(0.34, 0.42, 0.34), "ffd896", "", true)
	box(parent, pos + Vector3(0, 1.8, 0), Vector3(0.48, 0.12, 0.48), "3d5265")

static func hull(parent: Node3D, pos: Vector3, size: Vector3, color: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = size.y
	mesh.radial_segments = 8
	node.mesh = mesh
	node.position = pos
	node.scale = Vector3(size.x,1,size.z)
	node.rotation.y = PI/8
	node.material_override = mat(color)
	parent.add_child(node)
	return node

static func ring(parent: Node3D, pos: Vector3, radius: float, thickness: float, color: String, glow: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius-thickness
	mesh.outer_radius = radius+thickness
	mesh.rings = 48
	mesh.ring_segments = 8
	node.mesh = mesh
	node.position = pos
	node.material_override = mat(color,"",glow)
	parent.add_child(node)
	return node
