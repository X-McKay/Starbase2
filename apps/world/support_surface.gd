extends RefCounted
## Read-only support height projection for actors.
##
## Interior support comes from authored Floor* mesh triangles.  The paving and
## terrain fallbacks are explicit so a room-wide maximum can never lift an
## actor over a lower inlay or a threshold.
const Paving = preload("res://colony_paving.gd")
const PAVING_HEIGHT: float = Paving.HEIGHT
const TERRAIN_HEIGHT := 0.0
const CELL_SIZE := 0.25

var triangles: Array = []
var cells: Dictionary = {}
var paving_rects: Array[Rect2] = []
var paving_cells: Dictionary = {}
var threshold_boxes: Array = []
var paving_contains: Callable

func configure(world_root: Node, paving: Variant = null, sills: Array = []) -> void:
	triangles.clear(); cells.clear(); paving_rects.clear(); paving_cells.clear(); threshold_boxes.clear(); paving_contains=Callable()
	if paving is Callable:
		paving_contains=paving
	elif paving is Array:
		for value in paving:
			if value is Rect2:
				paving_rects.append(value)
				_index_paving(value)
	for sill in sills:
		add_threshold_box(sill)
	if world_root == null: return
	for mesh_node in world_root.find_children("*", "MeshInstance3D", true, false):
		var name := str(mesh_node.name).to_lower()
		if not name.begins_with("floor"): continue
		_extract_mesh(mesh_node)

func add_threshold_box(value: Variant) -> void:
	if value is Dictionary:
		var position: Vector3 = value.get("position", Vector3.ZERO)
		var size: Vector3 = value.get("size", Vector3.ZERO)
		var height: float = float(value.get("height", position.y))
		threshold_boxes.append({"rect":Rect2(position.x-size.x*0.5,position.z-size.z*0.5,size.x,size.z),"height":height})
	elif value is AABB:
		threshold_boxes.append({"rect":Rect2(value.position.x,value.position.z,value.size.x,value.size.z),"height":value.end.y})

func _extract_mesh(mesh_node: MeshInstance3D) -> void:
	var mesh: Mesh = mesh_node.mesh
	if mesh == null: return
	var faces := mesh.get_faces()
	var transform := mesh_node.global_transform
	for index in range(0, faces.size()-2, 3):
		var a: Vector3 = transform * faces[index]
		var b: Vector3 = transform * faces[index+1]
		var c: Vector3 = transform * faces[index+2]
		# Decorative raised furniture can be named Floor by imported assets; the
		# authored support contract only accepts plausible room-floor triangles.
		if maxf(a.y,maxf(b.y,c.y)) > 0.35: continue
		# Vertical faces have no support height in the planar projection.
		if absf((b-a).cross(c-a).y)<0.000001:continue
		_add_triangle(a,b,c)

func _cell(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x/CELL_SIZE),floori(point.z/CELL_SIZE))

func _index_paving(rect: Rect2) -> void:
	var min_x := floori(rect.position.x/CELL_SIZE)
	var max_x := floori(rect.end.x/CELL_SIZE)
	var min_z := floori(rect.position.y/CELL_SIZE)
	var max_z := floori(rect.end.y/CELL_SIZE)
	for x in range(min_x,max_x+1):
		for z in range(min_z,max_z+1): paving_cells[Vector2i(x,z)]=true

func _add_triangle(a: Vector3,b: Vector3,c: Vector3) -> void:
	var index := triangles.size()
	triangles.append([a,b,c])
	var min_x := floori(minf(a.x,minf(b.x,c.x))/CELL_SIZE)
	var max_x := floori(maxf(a.x,maxf(b.x,c.x))/CELL_SIZE)
	var min_z := floori(minf(a.z,minf(b.z,c.z))/CELL_SIZE)
	var max_z := floori(maxf(a.z,maxf(b.z,c.z))/CELL_SIZE)
	for x in range(min_x,max_x+1):
		for z in range(min_z,max_z+1):
			var key := Vector2i(x,z)
			if not cells.has(key): cells[key]=[]
			cells[key].append(index)

static func _height_on_triangle(point: Vector3, triangle: Array) -> Variant:
	var a: Vector3=triangle[0]; var b: Vector3=triangle[1]; var c: Vector3=triangle[2]
	var v0:=Vector2(b.x-a.x,b.z-a.z); var v1:=Vector2(c.x-a.x,c.z-a.z); var v2:=Vector2(point.x-a.x,point.z-a.z)
	var denominator:=v0.x*v1.y-v1.x*v0.y
	if is_zero_approx(denominator): return null
	var v: float=(v2.x*v1.y-v1.x*v2.y)/denominator
	var w: float=(v0.x*v2.y-v2.x*v0.y)/denominator
	var u: float=1.0-v-w
	if u < -0.0001 or v < -0.0001 or w < -0.0001: return null
	return a.y*u+b.y*v+c.y*w

func height_at(global_position: Vector3) -> float:
	var point := global_position
	var best: float = TERRAIN_HEIGHT
	var key := _cell(point)
	for index in cells.get(key,[]):
		var value = _height_on_triangle(point,triangles[index])
		if value != null: best=maxf(best,float(value))
	for sill in threshold_boxes:
		if sill.rect.has_point(Vector2(point.x,point.z)): best=maxf(best,float(sill.height))
	var on_paving := paving_cells.has(key)
	if on_paving:
		for paving in paving_rects:
			if paving.has_point(Vector2(point.x,point.z)): best=maxf(best,PAVING_HEIGHT); break
	if paving_contains.is_valid() and paving_contains.call(Vector2(point.x,point.z)): best=maxf(best,PAVING_HEIGHT)
	return best
