extends Node3D
## One aligned tile field joins catalog-derived foundations and authored routes.
## Decorative, flush paving adds no navigation or operational restrictions.
const Buildings=preload("res://building_catalog.gd")
const Paths=preload("res://colony_paths.gd")
const Surface=preload("res://surface_layout.gd")
const Geography=preload("res://geography.gd")
const Kit=preload("res://kit_art.gd")
const TILE := Paths.TILE
const HEIGHT := 0.085
static var _cells: Dictionary = {}
static var _pad_cells: Dictionary = {}
static var _road_cells: Dictionary = {}

static func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x/TILE),floori(point.y/TILE))

static func center(cell: Vector2i) -> Vector2:
	return (Vector2(cell)+Vector2.ONE*0.5)*TILE

static func contains(point: Vector2) -> bool:
	return cells().has(cell_at(point))

static func foundations() -> Array[Rect2]:
	var result: Array[Rect2]=[]
	for placement in Buildings.placements():
		var definition=placement.definition
		var origin := Vector2(placement.position.x,placement.position.z)
		var bounds: Rect2=definition.collision_boxes[0]
		for rect in definition.collision_boxes: bounds=bounds.merge(rect)
		# A modest perimeter and a deep front apron accommodate the real door.
		var margin: Vector4=definition.pad_margin
		bounds=Rect2(bounds.position-Vector2(margin.x,margin.y),bounds.size+Vector2(margin.x+margin.z,margin.y+margin.w))
		bounds.end.y=maxf(bounds.end.y,definition.return_point.z+margin.w)
		result.append(Rect2(bounds.position+origin,bounds.size))
	for rect in Surface.UTILITY_BLOCKS: result.append(rect.grow(0.75))
	result.append(Rect2(Surface.LANDING_CENTER-Vector2.ONE*Surface.LANDING_RADIUS,Vector2.ONE*Surface.LANDING_RADIUS*2))
	return result

static func exclusions() -> Array[Rect2]:
	var result: Array[Rect2]=[]
	result.assign(Surface.NATURAL_BLOCKS+Surface.rock_bounds())
	for plot in Surface.RESERVED_PLOTS:
		result.append(Rect2(plot-Vector2(4.5,3.2),Vector2(9,6.4)).grow(-0.12))
	for crater in Surface.CRATERS:
		result.append(Rect2(Vector2(crater.x,crater.z)-Vector2.ONE*crater.y*1.1,Vector2.ONE*crater.y*2.2))
	return result

static func cells() -> Dictionary:
	if _cells.is_empty():
		_cells=pad_tiles().duplicate()
		_cells.merge(road_tiles())
	return _cells

static func add_rectangle(target: Dictionary, rect: Rect2i) -> void:
	for x in range(rect.position.x,rect.end.x):
		for y in range(rect.position.y,rect.end.y): target[Vector2i(x,y)]=true

static func pad_tiles() -> Dictionary:
	if _pad_cells.is_empty():
		for rect in foundation_cells(): add_rectangle(_pad_cells,rect)
	return _pad_cells

static func road_tiles() -> Dictionary:
	if _road_cells.is_empty():
		var candidates := {}
		for rect in route_cells(): add_rectangle(candidates,rect)
		for cell in candidates:
			if not pad_tiles().has(cell): _road_cells[cell]=true
	return _road_cells

static func foundation_cells() -> Array[Rect2i]:
	var result: Array[Rect2i]=[]
	for rect in foundations():
		var first := Vector2i((rect.position/TILE).floor())
		var end := Vector2i((rect.end/TILE).ceil())
		result.append(Rect2i(first,end-first))
	return result

static func centerline_rectangles() -> Array[Rect2]:
	var result: Array[Rect2]=[]
	var seen := {}
	for line in Paths.LINES:
		for i in range(line.size()-1):
			var a: Vector2=line[i]
			var b: Vector2=line[i+1]
			var direction := (b-a).normalized()
			var size := Vector2(0.9,0.14) if a.y==b.y else Vector2(0.14,0.9)
			for step in range(1,floori(a.distance_to(b)/TILE)):
				var at := a+direction*step*TILE
				var rect := Rect2(at-size*0.5,size)
				if seen.has(rect): continue
				var clear := true
				for corner in [rect.position,rect.end,Vector2(rect.position.x,rect.end.y),Vector2(rect.end.x,rect.position.y)]:
					if not road_tiles().has(cell_at(corner)): clear=false
				# Keep the small intersection/corner box free of conflicting paint.
				for other in Paths.LINES:
					for point in other:
						if at.distance_to(point)<TILE: clear=false
				if clear:
					seen[rect]=true
					result.append(rect)
	return result

static func route_cells() -> Array[Rect2i]:
	var result: Array[Rect2i]=[]
	for rect in Paths.rectangles():
		result.append(Rect2i(Vector2i((rect.position/TILE).round()),Vector2i((rect.size/TILE).round())))
	return result

static func quad(surface: SurfaceTool, rect: Rect2, height: float) -> void:
	var corners := [Vector3(rect.position.x,height,rect.end.y),Vector3(rect.position.x,height,rect.position.y),Vector3(rect.end.x,height,rect.position.y),Vector3(rect.end.x,height,rect.end.y)]
	var uv := [Vector2(0,1),Vector2.ZERO,Vector2(1,0),Vector2.ONE]
	for i in [0,1,2,0,2,3]:
		surface.set_normal(Vector3.UP)
		surface.set_uv(uv[i])
		surface.add_vertex(corners[i])

func _ready() -> void:
	var pads := SurfaceTool.new()
	var worn := SurfaceTool.new()
	var roads := SurfaceTool.new()
	var bed := SurfaceTool.new()
	var markings := SurfaceTool.new()
	for surface in [pads,worn,roads,bed,markings]: surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell in cells():
		var rect := Rect2(Vector2(cell)*TILE,Vector2.ONE*TILE)
		quad(bed,rect,HEIGHT-0.025)
		if pad_tiles().has(cell):
			# Stable per-cell hash: roughly one tile in five shows wear.
			quad(worn if (cell.x*73856093 ^ cell.y*19349663)%5==0 else pads,rect.grow(-0.018),HEIGHT)
		else: quad(roads,rect.grow(-0.018),HEIGHT)
	for rect in centerline_rectangles(): quad(markings,rect,HEIGHT+0.006)
	var substrate := StandardMaterial3D.new()
	substrate.albedo_color=Color("344651")
	substrate.roughness=0.95
	var road := ShaderMaterial.new()
	road.shader=preload("res://road_surface.gdshader")
	for parameter in ["atlas","region"]:
		road.set_shader_parameter(parameter,Kit.material("floor").get_shader_parameter(parameter))
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color=Color("efbf35")
	yellow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for part in [["TileField",pads,Kit.material("floor")],["WornTiles",worn,Kit.material("floor_worn")],["RoadTiles",roads,road],["JointBed",bed,substrate],["Centerline",markings,yellow]]:
		var instance := MeshInstance3D.new()
		instance.name=part[0]
		instance.mesh=part[1].commit()
		instance.material_override=part[2]
		instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
