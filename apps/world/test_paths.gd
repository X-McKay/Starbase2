extends SceneTree
const Paths=preload("res://colony_paths.gd")
const Navigation=preload("res://navigation.gd")
const Geography=preload("res://geography.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var failures: Array[String]=[]
	var nav := Navigation.new()
	for line in Paths.LINES:
		for point in line:
			if not (point/Paths.TILE).is_equal_approx((point/Paths.TILE).round()): failures.append("Route turns must align with tile boundaries")
		for i in range(line.size()-1):
			var delta: Vector2=line[i+1]-line[i]
			if delta.is_zero_approx() or (delta.x!=0 and delta.y!=0): failures.append("Walkways require nonzero orthogonal segments")
		var centers := Paths.points(line)
		for center in centers:
			var p := Vector2(center.x,center.z)
			if not Geography.contains(p,0.5): failures.append("Path leaves cliff shelf: "+str(p))
			for block in Navigation.BLOCKS:
				if block.has_point(p): failures.append("Path crosses physical obstacle: "+str(p))
		var endpoint: Vector3=centers[-1]
		if nav.route(Vector3(0,0,5.5),endpoint).is_empty(): failures.append("Unreachable path destination: "+str(endpoint))
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Path checks passed: every orthogonal centerline stays on shelf, clears obstacles and ends at a reachable destination")
	quit(0 if failures.is_empty() else 1)
