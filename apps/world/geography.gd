extends RefCounted
## One authored shelf outline for the cap, cliff, collision and route clearance.
## Authored headlands and coves, baked for stability.
## East/south headlands expanded 12% for the larger inhabited districts.
const OUTLINE := [
	Vector2(-75.60000,-30.37500),Vector2(-75.60000,-34.42500),Vector2(-73.71000,-38.13750),Vector2(-69.93000,-41.51250),
	Vector2(-64.73250,-44.21250),Vector2(-58.11750,-46.23750),Vector2(-50.55750,-47.58750),Vector2(-42.05250,-48.26250),
	Vector2(-34.02000,-47.92500),Vector2(-26.46000,-46.57500),Vector2(-18.90000,-45.22500),Vector2(-11.34000,-43.87500),
	Vector2(-3.78000,-43.36880),Vector2(4.23360,-43.70630),Vector2(13.23000,-45.05630),Vector2(22.75560,-47.41880),
	Vector2(33.33960,-49.27500),Vector2(44.98200,-50.62500),Vector2(55.56600,-50.28750),Vector2(65.09160,-48.26250),
	Vector2(73.55880,-45.22500),Vector2(80.96760,-41.17500),Vector2(86.25960,-36.78750),Vector2(89.43480,-32.06250),
	Vector2(91.41236,-27.00000),Vector2(89.52584,-21.60000),Vector2(84.32874,-16.53750),Vector2(77.71413,-11.81250),
	Vector2(70.63205,-7.42500),Vector2(63.88780,-3.37500),Vector2(60.76000,1.13400),Vector2(59.97600,6.42600),
	Vector2(60.36800,11.71800),Vector2(61.93600,17.01000),Vector2(63.11200,22.30200),Vector2(63.89600,27.59400),
	Vector2(62.72000,32.50800),Vector2(59.58400,37.04400),Vector2(55.66400,40.82400),Vector2(50.96000,43.84800),
	Vector2(45.47200,45.73800),Vector2(39.20000,46.49400),Vector2(33.71200,47.62800),Vector2(29.00800,49.14000),
	Vector2(24.69600,52.16400),Vector2(20.77600,56.70000),Vector2(16.07200,60.10200),Vector2(10.58400,62.37000),
	Vector2(5.09600,62.37000),Vector2(-0.35000,60.10200),Vector2(-4.20000,56.70000),Vector2(-7.00000,52.16400),
	Vector2(-10.85000,49.51800),Vector2(-15.75000,48.76200),Vector2(-20.65000,50.27400),Vector2(-25.55000,54.05400),
	Vector2(-30.45000,55.18800),Vector2(-35.35000,53.67600),Vector2(-39.90000,51.40800),Vector2(-44.10000,48.38400),
	Vector2(-47.95000,44.22600),Vector2(-51.45000,38.93400),Vector2(-54.60000,34.77600),Vector2(-57.40000,31.75200),
	Vector2(-59.85000,27.21600),Vector2(-61.95000,21.16800),Vector2(-63.00000,15.87600),Vector2(-63.00000,11.34000),
	Vector2(-61.95000,6.80400),Vector2(-59.85000,2.26800),Vector2(-58.91729,-2.70000),Vector2(-61.37479,-8.10000),
	Vector2(-66.07157,-12.82500),Vector2(-71.85468,-16.87500),Vector2(-75.60708,-21.26250),Vector2(-76.04145,-25.98750)
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
