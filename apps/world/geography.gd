extends RefCounted
## One authored shelf outline for the cap, cliff, collision and route clearance.
## Authored headlands and coves with one corner-softening pass, baked for stability.
const OUTLINE := [
	Vector2(-40,-22.5),Vector2(-40,-25.5),Vector2(-39,-28.25),Vector2(-37,-30.75),
	Vector2(-34.25,-32.75),Vector2(-30.75,-34.25),Vector2(-26.75,-35.25),Vector2(-22.25,-35.75),
	Vector2(-18,-35.5),Vector2(-14,-34.5),Vector2(-10,-33.5),Vector2(-6,-32.5),
	Vector2(-2,-32.125),Vector2(2,-32.375),Vector2(6.25,-33.375),Vector2(10.75,-35.125),
	Vector2(15.75,-36.5),Vector2(21.25,-37.5),Vector2(26.25,-37.25),Vector2(30.75,-35.75),
	Vector2(34.75,-33.5),Vector2(38.25,-30.5),Vector2(40.75,-27.25),Vector2(42.25,-23.75),
	Vector2(43.5,-20),Vector2(44.5,-16),Vector2(44.75,-12.25),Vector2(44.25,-8.75),
	Vector2(42.75,-5.5),Vector2(40.25,-2.5),Vector2(38.75,0.75),Vector2(38.25,4.25),
	Vector2(38.5,7.75),Vector2(39.5,11.25),Vector2(40.25,14.75),Vector2(40.75,18.25),
	Vector2(40,21.5),Vector2(38,24.5),Vector2(35.5,27),Vector2(32.5,29),
	Vector2(29,30.25),Vector2(25,30.75),Vector2(21.5,31.5),Vector2(18.5,32.5),
	Vector2(15.75,34.5),Vector2(13.25,37.5),Vector2(10.25,39.75),Vector2(6.75,41.25),
	Vector2(3.25,41.25),Vector2(-0.25,39.75),Vector2(-3,37.5),Vector2(-5,34.5),
	Vector2(-7.75,32.75),Vector2(-11.25,32.25),Vector2(-14.75,33.25),Vector2(-18.25,35.75),
	Vector2(-21.75,36.5),Vector2(-25.25,35.5),Vector2(-28.5,34),Vector2(-31.5,32),
	Vector2(-34.25,29.25),Vector2(-36.75,25.75),Vector2(-39,23),Vector2(-41,21),
	Vector2(-42.75,18),Vector2(-44.25,14),Vector2(-45,10.5),Vector2(-45,7.5),
	Vector2(-44.25,4.5),Vector2(-42.75,1.5),Vector2(-41.75,-2),Vector2(-41.25,-6),
	Vector2(-41.5,-9.5),Vector2(-42.5,-12.5),Vector2(-42.25,-15.75),Vector2(-40.75,-19.25)
]
# This ordered arc also owns the connection to the decorative mainland.
const NORTH_RIM_START := 1
const NORTH_RIM_POINTS := 24
static func north_rim() -> PackedVector2Array:
	return PackedVector2Array(OUTLINE.slice(NORTH_RIM_START,NORTH_RIM_POINTS))
static func bounds() -> Rect2:
	var rect := Rect2(OUTLINE[0],Vector2.ZERO)
	for point in OUTLINE: rect=rect.expand(point)
	return rect
static func contains(point: Vector2, clearance: float = 0.4) -> bool:
	if not Geometry2D.is_point_in_polygon(point,PackedVector2Array(OUTLINE)): return false
	for i in range(OUTLINE.size()):
		var nearest := Geometry2D.get_closest_point_to_segment(point,OUTLINE[i],OUTLINE[(i+1)%OUTLINE.size()])
		if point.distance_to(nearest)<clearance: return false
	return true
