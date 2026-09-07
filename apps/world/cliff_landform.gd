extends Node3D
const Art = preload("res://art.gd")
const Geography = preload("res://geography.gd")
const SEA_STACKS := [Vector3(-36,-19,47),Vector3(-15,-22,56),Vector3(17,-20,49),Vector3(42,-18,38)]
var reduced_motion := false
var water_time := 0.0
var river_material := ShaderMaterial.new()

func mesh_from_triangles(points: PackedVector3Array, material: Material) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in points: surface.add_vertex(point)
	surface.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh=surface.commit()
	instance.material_override=material
	add_child(instance)
	return instance

func strata(color: String, haze: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader=preload("res://strata.gdshader")
	m.set_shader_parameter("stone",preload("res://assets/environment/sandstone/sandstone-v1.png"))
	m.set_shader_parameter("rock_color",Color(color))
	m.set_shader_parameter("canyon_haze",haze)
	return m

func mass(center: Vector3, size: Vector3, seed_value: int, color: String, haze: float = 0.6) -> void:
	# Lobed, staggered blocks create real recesses and overhangs below the rim.
	var random := RandomNumberGenerator.new()
	random.seed=seed_value
	var rings: Array[PackedVector3Array]=[]
	var facets := 7+seed_value%3
	var phase := random.randf_range(0,TAU)
	var shear := Vector2(random.randf_range(-0.16,0.16),random.randf_range(-0.12,0.12))
	var profile := [0.89,1.0,0.87,0.91,0.74,0.79,0.66]
	var elevations := [-0.5,-0.31,-0.23,0.04,0.12,0.37,0.5]
	for level in range(profile.size()):
		var ring := PackedVector3Array()
		for i in range(facets):
			var angle := TAU*i/facets+phase
			var radius: float=profile[level]
			var asymmetry := 1.0+sin(i*2.37+seed_value)*0.17
			var height: float=elevations[level]
			if level>0 and level<6: height+=sin(i*1.9+seed_value)*0.035
			ring.append(center+Vector3((cos(angle)*radius*0.5*asymmetry+shear.x*(height+0.5))*size.x,height*size.y,(sin(angle)*radius*0.5*asymmetry+shear.y*(height+0.5))*size.z))
		rings.append(ring)
	var points := PackedVector3Array()
	for level in range(rings.size()-1):
		for i in range(facets):
			var j := (i+1)%facets
			for point in [rings[level][i],rings[level+1][j],rings[level+1][i],rings[level][i],rings[level][j],rings[level+1][j]]: points.append(point)
	for i in range(facets):
		for point in [rings[6][i],rings[6][(i+1)%facets],center+Vector3(shear.x*size.x,size.y*0.5,shear.y*size.z)]: points.append(point)
	mesh_from_triangles(points,strata(color,haze))

func _ready() -> void:
	var outline := PackedVector2Array(Geography.OUTLINE)
	var cap_vertices := PackedVector3Array()
	for index in Geometry2D.triangulate_polygon(outline):
		cap_vertices.append(Vector3(outline[index].x,-0.035,outline[index].y))
	var ground_material := ShaderMaterial.new()
	ground_material.shader=preload("res://terrain.gdshader")
	ground_material.set_shader_parameter("stone",preload("res://assets/environment/sandstone/sandstone-v1.png"))
	var cap := mesh_from_triangles(cap_vertices,ground_material)
	cap.name="WalkableShelf"
	cap.create_trimesh_collision()
	# Vertical edge stops align with the actual rim, including the oblique corners.
	for i in range(outline.size()):
		var a := outline[i]
		var b := outline[(i+1)%outline.size()]
		var center := (a+b)*0.5
		var edge := Node3D.new()
		edge.position=Vector3(center.x,0,center.y)
		edge.rotation.y=atan2(b.x-a.x,b.y-a.y)
		add_child(edge)
		Art.collider(edge,Vector3(0,1,0),Vector3(0.12,2,(b-a).length()+0.12))
	# Subdivide long edges into jointed rock columns, while keeping the top exact.
	var rim := PackedVector2Array()
	var rim_exposed: Array[bool]=[]
	for i in range(outline.size()):
		var a := outline[i]
		var b := outline[(i+1)%outline.size()]
		var count := maxi(1,ceili(a.distance_to(b)/3.5))
		for j in range(count):
			rim.append(a.lerp(b,(float(j)+(sin(i*13.0+j*2.37)*0.28 if j>0 else 0.0))/count))
			rim_exposed.append(i<Geography.NORTH_RIM_START or i>=Geography.NORTH_RIM_POINTS-1)
	# A feathered band of exposed caprock joins soil to the cliff at the same rim.
	var rim_surface := SurfaceTool.new()
	rim_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(rim.size()):
		if not rim_exposed[i]: continue
		var a := rim[i]
		var b := rim[(i+1)%rim.size()]
		var inner_a := a-a.normalized()*(1.1+sin(i*2.3)*0.22)
		var inner_b := b-b.normalized()*(1.1+sin((i+1)*2.3)*0.22)
		var positions := [inner_a,a,b,inner_a,b,inner_b]
		var blend := [0.0,1.0,1.0,0.0,1.0,0.0]
		for n in range(6):
			rim_surface.set_uv(Vector2(blend[n],0))
			rim_surface.add_vertex(Vector3(positions[n].x,0.015,positions[n].y))
	rim_surface.generate_normals()
	var rim_mesh := MeshInstance3D.new()
	rim_mesh.mesh=rim_surface.commit()
	var rim_material := ShaderMaterial.new()
	rim_material.shader=preload("res://cliff_rim.gdshader")
	rim_material.set_shader_parameter("stone",preload("res://assets/environment/sandstone/sandstone-v1.png"))
	rim_mesh.material_override=rim_material
	rim_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim_mesh)
	var tiers: Array[PackedVector3Array] = []
	for level in range(5):
		var ring := PackedVector3Array()
		for i in range(rim.size()):
			var outward := rim[i].normalized()
			var extension: float = [0.0,0.65,1.7,4.5,8.5][level]
			var step: float = extension*(0.8+0.2*sin(i*2.3))+(sin(i*2.399)*0.9 if level>0 else 0.0)
			var p := rim[i]+outward*step
			var height: float = [0.0,-4.2,-8.0,-16.0,-24.0][level]
			if level>0: height+=sin(i*1.7)*0.65
			ring.append(Vector3(p.x,height,p.y))
		tiers.append(ring)
	var colors := ["ac7250","905c43","754b40","59494b"]
	for level in range(4):
		var triangles := PackedVector3Array()
		for i in range(rim.size()):
			if not rim_exposed[i]: continue
			var j := (i+1)%rim.size()
			for point in [tiers[level][i],tiers[level+1][j],tiers[level+1][i],tiers[level][i],tiers[level][j],tiers[level+1][j]]: triangles.append(point)
		mesh_from_triangles(triangles,strata(colors[level],0.72))
	# Chunky cap shoulders and staggered buttresses give the exposed face depth.
	for i in range(rim.size()):
		var p := rim[i]
		if not rim_exposed[i]: continue
		var outward := p.normalized()
		var height := 8.5+sin(i*1.91)*3.8
		mass(Vector3(p.x+outward.x*0.7,-height*0.5-0.12,p.y+outward.y*0.7),Vector3(5.7+sin(i*2.83)*2.1,height,4.8+cos(i*1.73)*1.1),i+701,"b77953")
		if i%3!=1:
			mass(Vector3(p.x,-4.0,p.y),Vector3(8.5+sin(i)*1.3,2.0+cos(i)*0.6,6.2),i+3701,"986846")
		if i%2==0:
			mass(Vector3(p.x+outward.x*1.3,-14.0,p.y+outward.y*1.3),Vector3(7.8,13+sin(i*1.13)*3,6.7),i+1701,"915e4a",0.8)
	# Low talus shelves root the promontory into the water; all remain below the rim.
	for i in range(0,rim.size(),4):
		var p := rim[i]
		if p.y<0: continue
		var outward := p.normalized()
		mass(Vector3(p.x+outward.x*7.5,-22.8,p.y+outward.y*7.5),Vector3(7.0+sin(i)*1.5,3.8,6.2),8001+i,"807668",0.65)
	preload("res://coastal_backdrop.gd").build(self)
	# A distant cool canyon floor gives the exposed face scale and atmospheric depth.
	var river := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size=Vector2(360,360)
	river.mesh=plane
	river.position.y=-25
	river_material.shader=preload("res://canyon.gdshader")
	var waterlines := PackedVector4Array()
	for pos in SEA_STACKS: waterlines.append(Vector4(pos.x,pos.z,4.0,3.6))
	river_material.set_shader_parameter("sea_stacks",waterlines)
	river.name="CanyonWater"
	river.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	river.material_override=river_material
	add_child(river)

func _process(delta: float) -> void:
	if reduced_motion or not is_visible_in_tree(): return
	water_time+=delta
	river_material.set_shader_parameter("water_time",water_time)
