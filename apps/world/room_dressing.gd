extends RefCounted
## Decorative interior dressing shared by every authored room. It runs before
## navigation blocks are derived, so any physical prop it adds is also a routing
## block. Nothing here reads or implies operational state.
const Art = preload("res://art.gd")
const Kit = preload("res://kit_art.gd")
const ACCENT := {"repair":"ff9a3c","review":"5fd3ff","gym":"c48cff"}
const WORN := {"repair":[Vector2(-2,-2),Vector2(2,0),Vector2(-4,2),Vector2(0,4),Vector2(4,-4)],
	"review":[Vector2(-4,-4),Vector2(2,2),Vector2(-2,4)],
	"gym":[Vector2(0,-4),Vector2(-4,4),Vector2(4,2),Vector2(2,-2)]}
const HAZARD := {"repair":[Vector2(-4,-2),Vector2(4,-2)],"review":[],"gym":[Vector2(-4,0),Vector2(4,0)]}
static var _screens: Dictionary = {}

static func accent(kind: String) -> Color:
	return Color(ACCENT.get(kind,"ffd27a"))

static func emissive(color: Color, energy: float = 2.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color=color.darkened(0.6)
	m.emission_enabled=true
	m.emission=color
	m.emission_energy_multiplier=energy
	return m

static func glow_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, energy: float = 2.4) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new(); mesh.size=size
	node.mesh=mesh; node.position=pos
	node.material_override=emissive(color,energy)
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func screen_material(strength: float) -> ShaderMaterial:
	if not _screens.has(strength):
		var m: ShaderMaterial=Kit.material("console").duplicate()
		m.set_shader_parameter("emission_strength",strength)
		_screens[strength]=m
	return _screens[strength]

static func lamp(parent: Node3D, pos: Vector3, color: Color, energy: float, range_m: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color=color
	light.light_energy=energy
	light.omni_range=range_m
	light.omni_attenuation=1.4
	light.shadow_enabled=false
	light.position=pos
	parent.add_child(light)
	return light

static func pipe(parent: Node3D, from: Vector3, to: Vector3, radius: float, color: String) -> void:
	var node := Art.cylinder(parent,(from+to)*0.5,radius,from.distance_to(to),color)
	node.look_at_from_position(node.position,to,Vector3.UP)
	node.rotate_object_local(Vector3.RIGHT,PI/2)

static func apply(content: Node3D, definition, reduced_motion: bool) -> Node3D:
	var kind := str(definition.id)
	var bounds: Rect2 = definition.interior_bounds
	var root := Node3D.new()
	root.name="Dressing"
	content.add_child(root)
	floor_detail(root,kind)
	wall_shade(root,bounds)
	ceiling(root,bounds,kind)
	back_wall(root,bounds,kind)
	side_walls(root,bounds,kind)
	props(root,bounds,kind)
	dust(root,reduced_motion)
	return root

static func floor_detail(root: Node3D, kind: String) -> void:
	for tile in WORN.get(kind,[]):
		Kit.panel(root,"floor_worn",Vector3(tile.x,0.014,tile.y),Vector2(1.98,1.98),Vector3(-90,0,0))
	for tile in HAZARD.get(kind,[]):
		Kit.panel(root,"floor_hazard",Vector3(tile.x,0.014,tile.y),Vector2(1.98,1.98),Vector3(-90,0,0))
	# A faint guide line from the door to the central console; paint, not a route.
	Art.box(root,Vector3(0,0.016,2.9),Vector3(0.06,0.004,2.2),"6f7e8a")

static func wall_shade(root: Node3D, bounds: Rect2) -> void:
	var material := ShaderMaterial.new()
	material.shader=preload("res://wall_shade.gdshader")
	for spec in [[Vector3(bounds.get_center().x,0.02,bounds.position.y+0.7),Vector2(bounds.size.x,1.4),0.0],
		[Vector3(bounds.position.x+0.7,0.02,bounds.get_center().y-1.5),Vector2(6.2,1.4),-90.0],
		[Vector3(bounds.end.x-0.7,0.02,bounds.get_center().y-1.5),Vector2(6.2,1.4),90.0]]:
		var plane := PlaneMesh.new()
		plane.size=spec[1]
		var node := MeshInstance3D.new()
		node.mesh=plane
		node.position=spec[0]
		node.rotation_degrees.y=spec[2]
		node.material_override=material
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(node)

static func ceiling(root: Node3D, bounds: Rect2, kind: String) -> void:
	var back := bounds.position.y-0.4
	Art.box(root,Vector3(0,3.08,back),Vector3(bounds.size.x+1.0,0.16,0.42),"2b3a48")
	for x in [bounds.position.x-0.4,bounds.end.x+0.4]:
		Art.box(root,Vector3(x,3.08,-0.8),Vector3(0.42,0.16,8.4),"2b3a48")
	for x: float in [-2.6,2.6]:
		Art.box(root,Vector3(x,3.02,-0.5),Vector3(0.18,0.12,9.0),"4a5f74")
		for z in [-2.7,1.3]:
			Art.box(root,Vector3(x,2.86,z),Vector3(1.0,0.07,0.32),"1c2632")
			glow_box(root,Vector3(x,2.81,z),Vector3(0.88,0.03,0.22),Color("fff0d2"),2.6)
			lamp(root,Vector3(x,2.55,z),Color("ffd8aa"),2.3,7.0)
	lamp(root,Vector3(0,2.3,-4.0),accent(kind),1.5,5.5)

static func back_wall(root: Node3D, bounds: Rect2, kind: String) -> void:
	var z := bounds.position.y-0.24
	var wide := bounds.size.x+0.6
	glow_box(root,Vector3(0,2.74,z),Vector3(wide-0.4,0.045,0.04),accent(kind),3.0)
	Art.box(root,Vector3(0,0.13,z+0.02),Vector3(wide,0.26,0.07),"1b2531")
	pipe(root,Vector3(-wide*0.5,2.52,z-0.02),Vector3(wide*0.5,2.52,z-0.02),0.055,"6b7986")
	pipe(root,Vector3(-wide*0.5,2.38,z),Vector3(wide*0.5,2.38,z),0.04,"8a6b4c")
	for x in [-3.3,2.7]:
		Art.box(root,Vector3(x,2.45,z+0.05),Vector3(0.26,0.26,0.18),"d97a2a")
	# One large status screen between the flanking consoles: decorative diagrams.
	Art.box(root,Vector3(0,1.85,z-0.02),Vector3(2.7,1.36,0.08),"121a24")
	var screen := Kit.panel(root,"console",Vector3(0,1.85,z+0.03),Vector2(2.5,1.2))
	screen.material_override=screen_material(0.55)
	for x in [-3.0,3.0]:
		Art.box(root,Vector3(x,2.16,z+0.02),Vector3(0.03,0.6,0.03),"3a4552")
	Art.box(root,Vector3(-1.9,0.55,z+0.12),Vector3(0.55,0.9,0.22),"3f4d5c")
	Art.box(root,Vector3(-1.9,0.9,z+0.24),Vector3(0.4,0.05,0.02),"7fdcff","",true)

static func side_walls(root: Node3D, bounds: Rect2, kind: String) -> void:
	for side: float in [-1.0,1.0]:
		var x: float = (bounds.position.x if side<0 else bounds.end.x)-side*0.2
		var facing: float = 90.0 if side<0 else -90.0
		Art.box(root,Vector3(x,1.75,-3.0),Vector3(0.14,1.3,0.9),"3f4d5c")
		Kit.panel(root,"hull",Vector3(x+side*-0.075,1.75,-3.0),Vector2(0.84,1.22),Vector3(0,facing,0))
		Art.box(root,Vector3(x+side*-0.09,1.05,-3.0),Vector3(0.02,0.04,0.8),"ffd27a","",true)
		Art.box(root,Vector3(x,0.13,-2.0),Vector3(0.07,0.26,6.4),"1b2531")
		Art.box(root,Vector3(x+side*-0.05,2.2,-0.6),Vector3(0.10,0.7,0.5),"2b3a48")
		Art.box(root,Vector3(x+side*-0.11,2.2,-0.6),Vector3(0.01,0.5,0.34),accent(kind).to_html(false),"",true)

static func crate(root: Node3D, pos: Vector3, size: Vector3, color: String) -> void:
	Art.box(root,pos+Vector3(0,size.y*0.5,0),size,color)
	Kit.panel(root,"hull",pos+Vector3(0,size.y*0.5,size.z*0.5+0.005),Vector2(size.x*0.92,size.y*0.9))
	Art.box(root,pos+Vector3(0,size.y+0.02,0),Vector3(size.x*0.85,0.04,size.z*0.85),"5c6a76")
	Art.collider(root,pos+Vector3(0,size.y*0.5,0),size)

static func drum(root: Node3D, pos: Vector3, color: String) -> void:
	Art.cylinder(root,pos+Vector3(0,0.42,0),0.3,0.84,color)
	Art.cylinder(root,pos+Vector3(0,0.3,0),0.31,0.05,"2b3a48")
	Art.cylinder(root,pos+Vector3(0,0.6,0),0.31,0.05,"2b3a48")
	Art.collider(root,pos+Vector3(0,0.42,0),Vector3(0.62,0.84,0.62))

static func props(root: Node3D, bounds: Rect2, kind: String) -> void:
	var left := bounds.position.x+0.55
	var right := bounds.end.x-0.55
	var front := bounds.end.y-0.6
	match kind:
		"repair":
			crate(root,Vector3(left,0,front),Vector3(0.85,0.7,0.85),"8a6b4c")
			crate(root,Vector3(left+0.1,0.72,front+0.05),Vector3(0.6,0.5,0.6),"7a5f45")
			drum(root,Vector3(right,0,front),"c9772b")
			drum(root,Vector3(right-0.7,0,front+0.05),"5f6b75")
		"review":
			crate(root,Vector3(left,0,front),Vector3(0.8,0.6,0.8),"55606c")
			Art.cylinder(root,Vector3(right,0.8,front),0.26,1.6,"2a3a4a")
			glow_box(root,Vector3(right,1.25,front),Vector3(0.56,0.06,0.56),accent(kind),2.2)
			glow_box(root,Vector3(right,0.55,front),Vector3(0.56,0.06,0.56),accent(kind),1.4)
			Art.collider(root,Vector3(right,0.8,front),Vector3(0.6,1.6,0.6))
		"gym":
			for x in [-3.5,3.5]:
				Art.cylinder(root,Vector3(x,0.02,0.5),0.9,0.03,"20293a")
				var ring := Art.ring(root,Vector3(x,0.05,0.5),0.86,0.03,"c48cff",true)
				ring.rotation.x=PI/2
			crate(root,Vector3(left,0,front),Vector3(0.8,0.55,0.8),"55606c")
			drum(root,Vector3(right,0,front),"7a8ca0")
		_:
			crate(root,Vector3(left,0,front),Vector3(0.8,0.6,0.8),"55606c")

static func dust(root: Node3D, reduced_motion: bool) -> void:
	var motes := CPUParticles3D.new()
	motes.name="Dust"
	motes.amount=28
	motes.lifetime=7.0
	motes.preprocess=4.0
	motes.emission_shape=CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents=Vector3(4.2,1.3,4.2)
	motes.position=Vector3(0,1.5,0)
	motes.direction=Vector3(0.3,0.1,0.1)
	motes.spread=180
	motes.gravity=Vector3.ZERO
	motes.initial_velocity_min=0.04
	motes.initial_velocity_max=0.16
	motes.scale_amount_min=0.6
	motes.scale_amount_max=1.3
	var mesh := QuadMesh.new()
	mesh.size=Vector2(0.045,0.045)
	var material := StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode=BaseMaterial3D.BILLBOARD_PARTICLES
	material.albedo_color=Color(1,0.93,0.78,0.26)
	mesh.material=material
	motes.mesh=mesh
	motes.emitting=not reduced_motion
	root.add_child(motes)
