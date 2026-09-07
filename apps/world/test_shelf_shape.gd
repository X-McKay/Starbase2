extends SceneTree
const Geography=preload("res://geography.gd")
const Navigation=preload("res://navigation.gd")
func _initialize() -> void:
	var failures: Array[String]=[]
	var outline := PackedVector2Array(Geography.OUTLINE)
	for i in range(outline.size()):
		if outline[i].distance_to(outline[(i+1)%outline.size()])>14:
			failures.append("Shelf still has a long straight edge")
	if Geography.contains(Vector2(-39*1.4*1.35,-31*1.35),0.0): failures.append("Old square northwest corner must be eroded")
	var nav := Navigation.new()
	for destination in [Vector3(5*1.4,0,38*1.35),Vector3(-42*1.4,0,8*1.35)]:
		if nav.route(Vector3(0,0,5.5),destination).is_empty(): failures.append("Natural headland must be reachable: "+str(destination))
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Shelf shape checks passed: broken long edges, eroded corner and reachable headlands")
	quit(0 if failures.is_empty() else 1)
