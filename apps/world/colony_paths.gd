extends RefCounted
## Tile-aligned orthogonal corridors. Width is two tiles (three world metres).
const TILE := 1.5
const WIDTH_TILES := 2
const LINES := [
	[Vector2(-24,10.5),Vector2(24,10.5)],
	[Vector2(-24,6),Vector2(-24,19.5)],
	[Vector2(-13.5,10.5),Vector2(-13.5,-22.5),Vector2(-16.5,-22.5),Vector2(-16.5,-25.5)],
	[Vector2(-13.5,-9),Vector2(-24,-9)],
	[Vector2(-13.5,-7.5),Vector2(-3,-7.5),Vector2(-3,-12)],
	[Vector2(15,10.5),Vector2(15,0),Vector2(27,0),Vector2(27,-4.5)],
	[Vector2(0,10.5),Vector2(0,28.5),Vector2(18,28.5),Vector2(18,24)],
	[Vector2(-24,19.5),Vector2(-24,28.5),Vector2(0,28.5)],
	[Vector2(0,18),Vector2(-7.5,18)]
]
static func points(line: Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for i in range(line.size()-1):
		var a: Vector2=line[i]
		var b: Vector2=line[i+1]
		var steps := maxi(1,ceili(a.distance_to(b)/0.5))
		for step in range(steps):
			var p := a.lerp(b,float(step)/steps)
			result.append(Vector3(p.x,0.045,p.y))
	result.append(Vector3(line[-1].x,0.045,line[-1].y))
	return result
static func rectangles() -> Array[Rect2]:
	var result: Array[Rect2]=[]
	var half := TILE*WIDTH_TILES*0.5
	for line in LINES:
		for i in range(line.size()-1):
			var a: Vector2=line[i]
			var b: Vector2=line[i+1]
			result.append(Rect2(a.min(b)-Vector2.ONE*half,(b-a).abs()+Vector2.ONE*half*2))
	return result
static func distance_to_paths(p: Vector2) -> float:
	var distance := INF
	for line in LINES:
		for i in range(line.size()-1):
			distance=minf(distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,line[i],line[i+1])))
	return distance
