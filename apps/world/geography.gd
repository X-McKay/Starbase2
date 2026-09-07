extends RefCounted
## One authored shelf outline for the cap, cliff, collision and route clearance.
## Authored headlands and coves with one corner-softening pass, baked for stability.
const OUTLINE := [
	Vector2(-75.60000,-30.375),Vector2(-75.60000,-34.425),Vector2(-73.71000,-38.1375),Vector2(-69.93000,-41.5125),
	Vector2(-64.73250,-44.2125),Vector2(-58.11750,-46.2375),Vector2(-50.55750,-47.5875),Vector2(-42.05250,-48.2625),
	Vector2(-34.02000,-47.925),Vector2(-26.46000,-46.575),Vector2(-18.90000,-45.225),Vector2(-11.34000,-43.875),
	Vector2(-3.78000,-43.3688),Vector2(3.78000,-43.7063),Vector2(11.81250,-45.0563),Vector2(20.31750,-47.4188),
	Vector2(29.76750,-49.275),Vector2(40.16250,-50.625),Vector2(49.61250,-50.2875),Vector2(58.11750,-48.2625),
	Vector2(65.67750,-45.225),Vector2(72.29250,-41.175),Vector2(77.01750,-36.7875),Vector2(79.85250,-32.0625),
	Vector2(81.61818,-27),Vector2(79.93379,-21.6),Vector2(75.29352,-16.5375),Vector2(69.38762,-11.8125),
	Vector2(63.06433,-7.425),Vector2(57.04268,-3.375),Vector2(54.25000,1.0125),Vector2(53.55000,5.7375),
	Vector2(53.90000,10.4625),Vector2(55.30000,15.1875),Vector2(56.35000,19.9125),Vector2(57.05000,24.6375),
	Vector2(56.00000,29.025),Vector2(53.20000,33.075),Vector2(49.70000,36.45),Vector2(45.50000,39.15),
	Vector2(40.60000,40.8375),Vector2(35.00000,41.5125),Vector2(30.10000,42.525),Vector2(25.90000,43.875),
	Vector2(22.05000,46.575),Vector2(18.55000,50.625),Vector2(14.35000,53.6625),Vector2(9.45000,55.6875),
	Vector2(4.55000,55.6875),Vector2(-0.35000,53.6625),Vector2(-4.20000,50.625),Vector2(-7.00000,46.575),
	Vector2(-10.85000,44.2125),Vector2(-15.75000,43.5375),Vector2(-20.65000,44.8875),Vector2(-25.55000,48.2625),
	Vector2(-30.45000,49.275),Vector2(-35.35000,47.925),Vector2(-39.90000,45.9),Vector2(-44.10000,43.2),
	Vector2(-47.95000,39.4875),Vector2(-51.45000,34.7625),Vector2(-54.60000,31.05),Vector2(-57.40000,28.35),
	Vector2(-59.85000,24.3),Vector2(-61.95000,18.9),Vector2(-63.00000,14.175),Vector2(-63.00000,10.125),
	Vector2(-61.95000,6.075),Vector2(-59.85000,2.025),Vector2(-58.91729,-2.7),Vector2(-61.37479,-8.1),
	Vector2(-66.07157,-12.825),Vector2(-71.85468,-16.875),Vector2(-75.60708,-21.2625),Vector2(-76.04145,-25.9875)
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
