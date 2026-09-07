extends Node3D
## Authored colony scenery. No resources, buildings or construction are operational state.
const Art = preload("res://art.gd")
const Kit = preload("res://kit_art.gd")
const Navigation = preload("res://navigation.gd")
const Surface = preload("res://surface_layout.gd")
const Paving = preload("res://colony_paving.gd")
var rng := RandomNumberGenerator.new()

func rock(pos: Vector3, size: Vector3, color: String) -> void:
	# A common fractured outline continues through five ledges: slabs, not pebbles.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline := PackedVector2Array()
	for i in range(7):
		var angle := TAU*i/7.0
		outline.append(Vector2(cos(angle),sin(angle))*rng.randf_range(0.85,1.12))
	var rings: Array[PackedVector3Array] = []
	var radii := [0.53,0.56,0.47,0.45,0.40]
	var heights := [-0.5,-0.16,-0.10,0.37,0.44]
	for level in range(5):
		var points := PackedVector3Array()
		for i in range(7):
			points.append(Vector3(outline[i].x*size.x*radii[level],size.y*heights[level],outline[i].y*size.z*radii[level]))
		rings.append(points)
	for level in range(4):
		for i in range(7):
			var j := (i+1)%7
			surface.set_color(Color(rng.randf_range(0.55,1.0),1,1))
			for point in [rings[level][i],rings[level+1][j],rings[level+1][i],rings[level][i],rings[level][j],rings[level+1][j]]: surface.add_vertex(point)
	surface.set_color(Color.WHITE)
	for i in range(7):
		for point in [rings[4][i],rings[4][(i+1)%7],Vector3(0,size.y*0.44,0)]: surface.add_vertex(point)
	surface.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh = surface.commit()
	node.position = pos
	node.rotation.y = rng.randf_range(0,TAU)
	var material := ShaderMaterial.new()
	material.shader = preload("res://strata.gdshader")
	material.set_shader_parameter("stone",preload("res://art/geology/sandstone-v1.png"))
	material.set_shader_parameter("rock_color",Color(color))
	if pos.y< -1.0: material.set_shader_parameter("canyon_haze",0.70)
	node.material_override = material
	add_child(node)

func grass(pos: Vector3, size: float) -> void:
	# Clustered, still golden fronds. Low enough to remain traversable groundcover.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(5):
		var angle := rng.randf_range(0,TAU)
		var foot := Vector3(cos(angle)*0.18,0,sin(angle)*0.18)*size
		var right := Vector3(cos(angle+PI/2),0,sin(angle+PI/2))*0.07*size
		var tip := foot+Vector3(cos(angle)*0.25,rng.randf_range(0.45,0.8),sin(angle)*0.25)*size
		for point in [foot-right,tip,foot+right]: surface.add_vertex(point)
	surface.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh=surface.commit()
	node.position=pos
	var material := Art.mat("c7b85f").duplicate()
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	node.material_override=material
	add_child(node)

func plot(pos: Vector3, number: String) -> void:
	for x in [-4.5,4.5]:
		for z in [-3.2,3.2]:
			Art.box(self,pos+Vector3(x,0.5,z),Vector3(0.14,1,0.14),"d6ac69")
			Art.box(self,pos+Vector3(x,1,z),Vector3(0.25,0.1,0.25),"a8d8d5","",true)
	for z in [-3.2,3.2]: Art.box(self,pos+Vector3(0,0.035,z),Vector3(9,0.03,0.08),"c4ac7b")
	for x in [-4.5,4.5]: Art.box(self,pos+Vector3(x,0.035,0),Vector3(0.08,0.03,6.4),"c4ac7b")
	Art.sign(self,"SITE "+number+" / RESERVED",pos+Vector3(0,0.3,0),"d8c294",17)

func _ready() -> void:
	rng.seed = 70421
	var landform := Node3D.new()
	landform.set_script(preload("res://cliff_landform.gd"))
	landform.name="Landform"
	add_child(landform)
	# Lower isolated columns appear far beneath the exposed shelf, not as barriers.
	for pos in preload("res://cliff_landform.gd").SEA_STACKS:
		rock(pos,Vector3(9,12,8),"779093")
	var paving := Paving.new()
	paving.name="Paving"
	add_child(paving)
	var lights := preload("res://paving_lights.gd").new()
	lights.name="PavingLights"
	add_child(lights)
	for pos in [Vector3(-12,0,6),Vector3(-18,0,12),Vector3(14,0,7),Vector3(11,0,8),Vector3(2,0,12),Vector3(2,0,22)]: Art.lamp(self,pos)
	# A clearly marked arrival apron; the former blockout shuttle is removed.
	var arrival := Vector3(Surface.LANDING_CENTER.x,0,Surface.LANDING_CENTER.y)
	Art.ring(self,arrival+Vector3(0,0.105,0),4.7,0.07,"e5c78b")
	for x in [-1.25,1.25]: Art.box(self,arrival+Vector3(x,0.115,0),Vector3(0.24,0.035,3.3),"e5c78b")
	Art.box(self,arrival+Vector3(0,0.115,0),Vector3(2.6,0.035,0.24),"e5c78b")
	for x in [-4.5,4.5]:
		for z in [-4.5,4.5]:
			Art.box(self,arrival+Vector3(x,0.16,z),Vector3(0.3,0.12,0.3),"deb571")
	Art.sign(self,"01 / LANDING PAD",arrival+Vector3(0,0.35,5.0),"ead6ad",28)
	# Solar utility field and communications mast: static infrastructure props.
	for x in [-27,-20]:
		for z in [-16.0,-13.3]:
			var panel := Art.box(self,Vector3(x,1.0,z),Vector3(5.7,0.12,2.2),"ffffff","solar")
			panel.rotation.x = -0.20
			Art.box(self,Vector3(x,0.45,z),Vector3(0.2,0.9,1.2),"62777a")
	Art.sign(self,"SOLAR FIELD",Vector3(-23,0.4,-10.5),"d6c9a9",20)
	Art.hull(self,Vector3(-16.5,0.6,-27),Vector3(2,1.2,2),"70858a")
	Art.box(self,Vector3(-16.5,3.5,-27),Vector3(0.3,6,0.3),"bbc5b8")
	var dish := Art.hull(self,Vector3(-16.5,6.4,-27),Vector3(2.8,0.25,2.8),"d5d8c2")
	dish.rotation_degrees.x = 35
	Art.sign(self,"SURVEY RIDGE",Vector3(-16.5,0.4,-30),"ddd0b4",20)
	for i in range(Surface.RESERVED_PLOTS.size()):
		var at: Vector2=Surface.RESERVED_PLOTS[i]
		plot(Vector3(at.x,0,at.y),"%02d" % (i+2))
	# A small freight staging area uses low, nonblocking ground details.
	for x in [-10,-8,-6]:
		Art.box(self,Vector3(x-20,0.11,6),Vector3(1.5,0.05,1.1),"718681")
	# Keep established seating and physical footprints alongside the central crew.
	for x in [-5.5,5.5]:
		Art.box(self,Vector3(x,0.48,6),Vector3(2,0.18,0.65),"42576e")
		Art.box(self,Vector3(x,0.83,6.3),Vector3(2,0.48,0.13),"93a9b8")
	# All collidable scenery uses the same explicit rectangles as the route grid.
	for rect in Navigation.PROPS:
		var center: Vector2 = rect.get_center()
		Art.collider(self,Vector3(center.x,1.2,center.y),Vector3(rect.size.x,2.4,rect.size.y))
	# Alien vegetation is low, readable groundcover; tall crystals are blocked.
	for i in range(95):
		var p := Vector3(rng.randf_range(-37,37),0,rng.randf_range(-29,29))
		var occupied := false
		for block in Navigation.BLOCKS:
			if block.has_point(Vector2(p.x,p.z)): occupied = true
		if preload("res://colony_paths.gd").distance_to_paths(Vector2(p.x,p.z))<2.1: continue
		if Paving.contains(Vector2(p.x,p.z)): continue
		if occupied or not preload("res://geography.gd").contains(Vector2(p.x,p.z),1.0): continue
		if absf(p.x)<15 and p.z>-10 and p.z<27: continue
		if p.x>16 and p.z>-14 and p.z<12: continue
		if p.x < -16 and p.z>-18 and p.z<18: continue
		for j in range(3):
			var offset := Vector3(rng.randf_range(-0.5,0.5),0.16,rng.randf_range(-0.5,0.5))
			grass(p+Vector3(offset.x,0.03,offset.z),rng.randf_range(0.6,1.2))
	for i in range(7):
		var p := Vector3(rng.randf_range(31.4,34.5),0.6,rng.randf_range(19.4,22.5))
		rock(p,Vector3(0.8,rng.randf_range(1.4,2.8),0.9),"76bebc")
	planet_landmarks()
	surface_scatter()
	set_dressing()
	Art.sign(self,"BASIN / ASTER",Vector3(0,0.4,10),"ead7b2",22)

func planet_landmarks() -> void:
	# A turquoise mineral spring occupies a conservative shared blocked footprint.
	var spring := preload("res://mineral_basin.gd").new()
	spring.name="MineralBasin"
	spring.position=Vector3(30,0,-27)
	add_child(spring)
	for i in range(11):
		var angle := TAU*i/11.0
		rock(Vector3(30+cos(angle)*5.45,0.17,-27+sin(angle)*4.40),Vector3(0.6,0.26,0.5),"a89775")
	# Original weathered standing stones: visual history, no portal or mission.
	for pos in [Vector3(8.8,2.6,-23),Vector3(11.1,1.8,-23)]:
		var height: float = pos.y*2.0
		Art.hull(self,pos,Vector3(1.3,height,1.4),"554958")
		Art.hull(self,pos+Vector3(0,height*0.48,0),Vector3(1.5,0.18,1.6),"9f7e73")
		Art.box(self,pos+Vector3(0,0,0.74),Vector3(0.06,height*0.65,0.025),"71b6b7","",true)
	for i in range(3):
		Art.box(self,Vector3(9.5+i*0.6,0.08,-21.4),Vector3(0.4,0.1,0.65),"8e7170")
	# Group small eroded debris and fronds into patches, leaving every route clear.
	for patch in [Vector3(-30,0,24),Vector3(20,0,22),Vector3(-5,0,-17),Vector3(32,0,-6)]:
		for i in range(22):
			var offset := Vector3(rng.randf_range(-3,3),0,rng.randf_range(-2,2))
			if Paving.contains(Vector2(patch.x+offset.x,patch.z+offset.z)): continue
			if preload("res://colony_paths.gd").distance_to_paths(Vector2(patch.x+offset.x,patch.z+offset.z))<2.0: continue
			grass(patch+offset,rng.randf_range(0.5,1.0))
		for i in range(5):
			var offset := Vector3(rng.randf_range(-2,2),0.1,rng.randf_range(-2,2))
			if Paving.contains(Vector2(patch.x+offset.x,patch.z+offset.z)): continue
			if preload("res://colony_paths.gd").distance_to_paths(Vector2(patch.x+offset.x,patch.z+offset.z))<2.0: continue
			rock(patch+offset,Vector3(0.55,0.25,0.6),"9f594a")

func surface_scatter() -> void:
	# A separate seed keeps this layer stable when other scenery changes.
	rng.seed=92051
	for item in Surface.OUTCROPS:
		var at: Vector2=item.at
		var size: Vector3=item.size
		var center := Vector3(at.x,0,at.y)
		# Each cluster fits its shared rectangular footprint, including satellites.
		rock(center+Vector3(-size.x*0.12,size.y*0.5,-size.z*0.1),Vector3(size.x*0.58,size.y,size.z*0.55),"99633f")
		rock(center+Vector3(size.x*0.25,size.y*0.22,size.z*0.22),Vector3(size.x*0.30,size.y*0.44,size.z*0.30),"b47f51")
		rock(center+Vector3(-size.x*0.22,size.y*0.13,size.z*0.30),Vector3(size.x*0.22,size.y*0.26,size.z*0.20),"895c42")
		Art.collider(self,center+Vector3(0,size.y*0.5,0),size)
		for i in range(4):
			var offset := Vector3(rng.randf_range(-0.38,0.38)*size.x,0.06,rng.randf_range(-0.38,0.38)*size.z)
			rock(center+offset,Vector3(0.22,0.12,0.20),"a4724c")
	for definition in Surface.CRATERS:
		crater(Vector3(definition.x,0,definition.z),definition.y)

func crater(center: Vector3, radius: float) -> void:
	# Shallow, walkable impact scar: raised eroded lip, not a deep traversable hole.
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array]=[]
	var count := 40
	var radii := [0.0,0.40,0.59,0.71,0.83,1.0]
	var heights := [0.055,0.06,0.08,0.19,0.095,0.055]
	for level in range(radii.size()):
		var ring := PackedVector3Array()
		for i in range(count):
			var angle := TAU*i/count
			var variation := 1.0+sin(angle*3.0+center.x)*0.045+cos(angle*7.0)*0.025
			ring.append(Vector3(cos(angle)*radii[level]*radius*variation,heights[level],sin(angle)*radii[level]*radius*0.86*variation))
		rings.append(ring)
	for level in range(rings.size()-1):
		for i in range(count):
			var j := (i+1)%count
			for point in [rings[level][i],rings[level+1][i],rings[level+1][j],rings[level][i],rings[level+1][j],rings[level][j]]:
				mesh.set_uv(Vector2(point.x/radius,point.z/(radius*0.86))*0.5+Vector2.ONE*0.5)
				mesh.add_vertex(point)
	mesh.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh=mesh.commit()
	instance.position=center
	var material := ShaderMaterial.new()
	material.shader=preload("res://crater.gdshader")
	material.set_shader_parameter("stone",preload("res://art/geology/sandstone-v1.png"))
	instance.material_override=material
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	# A few low ejecta chips, all inside the crater's decorative extent.
	for i in range(5):
		var angle := rng.randf_range(0,TAU)
		var p := center+Vector3(cos(angle)*radius*0.86,0.07,sin(angle)*radius*0.73)
		rock(p,Vector3(0.28,0.14,0.24),"a77750")

func container(pos: Vector3, size: Vector3, color: String, yaw: float = 0.0) -> void:
	var body := Art.box(self,pos+Vector3(0,size.y*0.5,0),size,color)
	body.rotation.y=yaw
	var face := Kit.panel(body,"hull",Vector3(0,0,size.z*0.5+0.006),Vector2(size.x*0.9,size.y*0.86))
	face.position.y=0
	var back := Kit.panel(body,"hull",Vector3(0,0,-size.z*0.5-0.006),Vector2(size.x*0.9,size.y*0.86),Vector3(0,180,0))
	back.position.y=0
	for x in [-size.x*0.5+0.12,size.x*0.5-0.12]:
		Art.box(body,Vector3(x,0,0),Vector3(0.08,size.y+0.04,size.z+0.04),"2b3a48")
	Art.box(body,Vector3(0,size.y*0.5+0.02,0),Vector3(size.x*0.9,0.04,size.z*0.9),"5c6a76")

func drum(pos: Vector3, color: String) -> void:
	Art.cylinder(self,pos+Vector3(0,0.42,0),0.3,0.84,color)
	for y in [0.3,0.6]: Art.cylinder(self,pos+Vector3(0,y,0),0.31,0.05,"2b3a48")

func conduit(from: Vector3, to: Vector3, radius: float, color: String) -> void:
	var node := Art.cylinder(self,(from+to)*0.5,radius,from.distance_to(to),color)
	node.look_at_from_position(node.position,to,Vector3.UP)
	node.rotate_object_local(Vector3.RIGHT,PI/2)

func set_dressing() -> void:
	# Cargo yard: containers, drums and a work light on the freight staging pad.
	var yard: Rect2=Surface.CARGO_YARD
	var origin := Vector3(yard.get_center().x,0,yard.get_center().y)
	container(origin+Vector3(-1.1,0,-0.5),Vector3(2.2,1.1,1.0),"7c6a4e")
	container(origin+Vector3(-1.0,1.1,-0.45),Vector3(1.9,0.9,0.95),"6c7a86")
	container(origin+Vector3(1.3,0,-0.6),Vector3(1.6,1.0,1.0),"8a4f3a",0.12)
	for i in range(3): drum(origin+Vector3(0.6+i*0.66,0,0.85),["c9772b","5f6b75","c9772b"][i])
	Art.box(self,origin+Vector3(-1.6,0.11,0.9),Vector3(1.2,0.22,0.8),"3f4d5c")
	Art.lamp(self,origin+Vector3(2.1,0,1.2))
	Art.box(self,origin+Vector3(0,0.02,0),Vector3(yard.size.x,0.02,yard.size.y),"5a4a3c")
	# Parked survey rover on the landing apron.
	var rover: Rect2=Surface.ROVER
	var at := Vector3(rover.get_center().x,0,rover.get_center().y)
	for x in [-0.85,0.85]:
		for z in [-0.65,0.65]:
			var wheel := Art.cylinder(self,at+Vector3(x,0.32,z),0.32,0.3,"2b3038")
			wheel.rotation.x=PI/2
	Art.box(self,at+Vector3(0,0.62,0),Vector3(2.4,0.42,1.3),"9aa6ad")
	Kit.panel(self,"hull",at+Vector3(0,0.62,0.66),Vector2(2.1,0.36))
	Art.box(self,at+Vector3(-0.45,1.05,0),Vector3(1.1,0.55,1.2),"2f4a5c")
	Art.box(self,at+Vector3(-0.45,1.1,0.61),Vector3(0.9,0.3,0.02),"7fdcff","",true)
	Art.box(self,at+Vector3(0.75,0.95,0),Vector3(0.7,0.3,1.0),"c9772b")
	Art.box(self,at+Vector3(0.95,1.55,-0.4),Vector3(0.04,0.9,0.04),"bbc5b8")
	Art.box(self,at+Vector3(0.95,2.0,-0.4),Vector3(0.28,0.02,0.28),"d5d8c2")
	# Utility conduit and a junction cabinet along the solar field.
	conduit(Vector3(-29.5,0.16,-11.7),Vector3(-17.2,0.16,-11.7),0.09,"6b7986")
	for x in [-27.0,-23.0,-19.0]: Art.box(self,Vector3(x,0.12,-11.7),Vector3(0.3,0.24,0.34),"2b3a48")
	Art.box(self,Vector3(-17.0,0.65,-13.6),Vector3(0.9,1.3,0.7),"5c6a76")
	Art.box(self,Vector3(-17.0,0.9,-13.24),Vector3(0.5,0.08,0.02),"ffb347","",true)
	Art.box(self,Vector3(-17.0,1.33,-13.6),Vector3(0.96,0.06,0.76),"2b3a48")
	# Freight staging: strapped pallets beside the low ground details.
	for x in [-30.0,-28.0]:
		Art.box(self,Vector3(x,0.32,8.4),Vector3(1.1,0.42,0.9),"7c6a4e")
		Art.box(self,Vector3(x,0.56,8.4),Vector3(1.14,0.03,0.12),"d97a2a")
	# Wind-laid dust drifting across the basin; still under reduced motion.
	var dust := CPUParticles3D.new()
	dust.name="Dust"
	dust.amount=70
	dust.lifetime=11.0
	dust.preprocess=6.0
	dust.emission_shape=CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents=Vector3(42,1.6,32)
	dust.position=Vector3(0,1.8,0)
	dust.direction=Vector3(1,0.05,0.25)
	dust.spread=12
	dust.gravity=Vector3.ZERO
	dust.initial_velocity_min=0.9
	dust.initial_velocity_max=1.8
	dust.scale_amount_min=0.7
	dust.scale_amount_max=1.6
	var mesh := QuadMesh.new()
	mesh.size=Vector2(0.11,0.11)
	var material := StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode=BaseMaterial3D.BILLBOARD_PARTICLES
	material.albedo_color=Color(0.86,0.62,0.42,0.30)
	mesh.material=material
	dust.mesh=mesh
	add_child(dust)
