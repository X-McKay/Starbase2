extends RefCounted
## Decorative mainland around the fixed playable shelf; never creates collision.
const Geography=preload("res://geography.gd")
const WEST := [Vector2(-322,-108),Vector2(-217,-47.25),Vector2(-147,-21.6),Vector2(-100.8,-8.1),Vector2(-95,-20.25)]
const EAST := [Vector2(105,-40.5),Vector2(117.6,-14.85),Vector2(165.2,-6.75),Vector2(231,-51.3),Vector2(322,-75.6)]

static func shoreline() -> PackedVector2Array:
	var anchors := PackedVector2Array(WEST)
	var north := Geography.north_rim()
	for p in north: anchors.append(p)
	anchors.append_array(PackedVector2Array(EAST))
	var points := PackedVector2Array()
	for i in range(anchors.size()-1):
		var count := maxi(1,ceili(anchors[i].distance_to(anchors[i+1])/5.0))
		for j in range(count):
			var t := float(j)/count
			var p := anchors[i].lerp(anchors[i+1],t)
			if p.x<north[0].x-1 or p.x>north[-1].x+1:
				p.y+=sin(t*PI)*sin(p.x*0.31)*1.6
			points.append(p)
	points.append(anchors[-1])
	return points

static func strip(rows: Array[PackedVector3Array]) -> PackedVector3Array:
	var triangles := PackedVector3Array()
	for level in range(rows.size()-1):
		for i in range(rows[level].size()-1):
			for p in [rows[level][i],rows[level+1][i],rows[level+1][i+1],rows[level][i],rows[level+1][i+1],rows[level][i+1]]: triangles.append(p)
	return triangles

static func height_at(x: float, depth: float) -> float:
	var rise := 1.0-exp(-depth*0.13)
	var ridge := 5.0*exp(-pow((depth-17.0-sin(x*0.065)*5.0)/7.0,2))
	var gully := 2.8*exp(-pow(sin(x*0.105+sin(depth*0.06)*0.5)*4.0,2))
	var folds := sin(x*0.15+depth*0.14)*1.8+sin(x*0.31-depth*0.22)*0.7
	return -0.035+rise*(6.0+ridge+folds-gully)+maxf(depth-25.0,0.0)*0.055

static func shore_z(coast: PackedVector2Array, x: float) -> float:
	for i in range(coast.size()-1):
		if coast[i].x<=x and coast[i+1].x>x:
			return lerpf(coast[i].y,coast[i+1].y,(x-coast[i].x)/(coast[i+1].x-coast[i].x))
	return coast[-1].y

static func smooth_mesh(rows: Array[PackedVector3Array], material: Material) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for level in range(rows.size()-1):
		for i in range(rows[level].size()-1):
			for index in [Vector2i(i,level),Vector2i(i,level+1),Vector2i(i+1,level+1),Vector2i(i,level),Vector2i(i+1,level+1),Vector2i(i+1,level)]:
				var u := rows[index.y][mini(index.x+1,rows[index.y].size()-1)]-rows[index.y][maxi(0,index.x-1)]
				var v := rows[mini(index.y+1,rows.size()-1)][index.x]-rows[maxi(0,index.y-1)][index.x]
				surface.set_normal(Vector3.UP if index.y==0 else u.cross(v).normalized())
				surface.add_vertex(rows[index.y][index.x])
	surface.index()
	var mesh := MeshInstance3D.new()
	mesh.mesh=surface.commit()
	mesh.material_override=material
	return mesh

static func build(landform) -> void:
	var coast := shoreline()
	var rows: Array[PackedVector3Array]=[]
	for level in range(4):
		var row := PackedVector3Array()
		for p in coast:
			var height: float=[-26.0,-17.0,-7.0,-0.035][level]
			var depth: float=[12.0,7.0,2.0,0.0][level]
			row.append(Vector3(p.x,height,p.y+depth))
		rows.append(row)
	landform.mesh_from_triangles(strip(rows),landform.strata("9d7355",0.55)).name="MainlandCoast"
	# One continuous soil/rock surface starts at the exact playable shelf elevation.
	var inland: Array[PackedVector3Array]=[]
	for depth in [0.0,1.0,2.0,4.0,6.0,8.0,10.0,13.0,16.0,20.0,25.0,31.0,38.0,47.0,58.0,72.0,90.0,112.0,140.0,175.0,215.0,235.0]:
		var row := PackedVector3Array()
		for p in coast: row.append(Vector3(p.x,height_at(p.x,depth),p.y-depth))
		inland.append(row)
	var material: ShaderMaterial=landform.get_node("WalkableShelf").material_override.duplicate()
	material.set_shader_parameter("upland",true)
	var uplands := smooth_mesh(inland,material)
	uplands.name="InlandPlateau"
	landform.add_child(uplands)
	# Buried outcrops define a few ridges; small chips and fronds collect below them.
	var groups := [Vector2(-59,16),Vector2(-33,9),Vector2(-21,18),Vector2(-6,12),Vector2(13,15),Vector2(30,10),Vector2(49,16)]
	for i in range(groups.size()):
		var g: Vector2=groups[i]
		var z := shore_z(coast,g.x)-g.y
		var y := height_at(g.x,g.y)
		landform.mass(Vector3(g.x,y+1.0,z),Vector3(7.0,4.0,4.5),9001+i,"a87850",0.0)
		landform.mass(Vector3(g.x+3.0,y+0.2,z+1.0),Vector3(4.0,2.3,3.0),9101+i,"9d7350",0.0)
		for j in range(4):
			var x := g.x-2.0+j*1.3
			var depth := g.y-3.8+sin(j*1.8)*0.5
			var point := Vector3(x,height_at(x,depth),shore_z(coast,x)-depth)
			landform.mass(point+Vector3(0,0.12,0),Vector3(0.8,0.5,0.65),9201+i*4+j,"a68c62",0.0)
			landform.get_parent().grass(point+Vector3(0.6,0.06,0),0.8)
	for i in range(2,coast.size()-2,4):
		var p := coast[i]
		if absf(p.x)>45:
			landform.mass(Vector3(p.x,-10.5,p.y+4.0),Vector3(14,12.0+sin(i)*3.0,9),6001+i,"957156",0.55)
