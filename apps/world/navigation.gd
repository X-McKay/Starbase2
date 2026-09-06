extends RefCounted
## Physical prop bounds are shared by the colony builder and click routing.
const Geography = preload("res://geography.gd")
const Surface = preload("res://surface_layout.gd")
const Buildings = preload("res://building_catalog.gd")
static var STRUCTURES: Array[Rect2] = Buildings.structure_bounds()
const PROPS := Surface.NATURAL_BLOCKS+Surface.UTILITY_BLOCKS+[Rect2(-6.5,5.6,2,0.85),Rect2(4.5,5.6,2,0.85),Rect2(-4.8,-1.4,1,0.7)]
static var BLOCKS: Array[Rect2] = inflated_blocks()
var grid := AStarGrid2D.new()

static func inflated_blocks() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for rect in STRUCTURES+PROPS+Surface.rock_bounds(): result.append(rect.grow(0.4))
	return result

func _init() -> void:
	var extent := Geography.bounds()
	var first := Vector2i(floori(extent.position.x*2),floori(extent.position.y*2))
	var last := Vector2i(ceili(extent.end.x*2),ceili(extent.end.y*2))
	grid.region = Rect2i(first,last-first+Vector2i.ONE)
	grid.cell_size = Vector2(0.5,0.5)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for x in range(grid.region.position.x,grid.region.end.x):
		for y in range(grid.region.position.y,grid.region.end.y):
			var p := Vector2(x,y)*0.5
			if not Geography.contains(p): grid.set_point_solid(Vector2i(x,y))
			for block in BLOCKS:
				if block.has_point(p): grid.set_point_solid(Vector2i(x,y))

func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := Vector2i(roundi(from.x*2), roundi(from.z*2))
	var b := Vector2i(roundi(to.x*2), roundi(to.z*2))
	# Physical edge contact can round into a conservatively padded grid cell.
	# Recover a nearby clear start without letting the connecting segment cut a rim.
	if grid.is_in_boundsv(a) and grid.is_point_solid(a):
		var best := INF
		var snapped := a
		for dx in range(-1,2):
			for dy in range(-1,2):
				var candidate := a+Vector2i(dx,dy)
				if not grid.is_in_boundsv(candidate) or grid.is_point_solid(candidate): continue
				var target := Vector2(candidate)*0.5
				var start := Vector2(from.x,from.z)
				if start.distance_squared_to(target)<best and clear_start_segment(start,target):
					best=start.distance_squared_to(target)
					snapped=candidate
		a=snapped
	if not grid.is_in_boundsv(a) or not grid.is_in_boundsv(b) or grid.is_point_solid(b) or grid.is_point_solid(a):
		return PackedVector3Array()
	var path := PackedVector3Array()
	for p in grid.get_point_path(a,b): path.append(Vector3(p.x,0,p.y))
	return path

func clear_start_segment(start: Vector2, end: Vector2) -> bool:
	for i in range(9):
		var point := start.lerp(end,i/8.0)
		if not Geography.contains(point,0.25): return false
		for rect in STRUCTURES+PROPS+Surface.rock_bounds():
			if rect.grow(0.25).has_point(point): return false
	return true
