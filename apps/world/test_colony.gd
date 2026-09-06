extends SceneTree
const Navigation = preload("res://navigation.gd")
func _initialize() -> void:
	var nav := Navigation.new()
	var failures: Array[String] = []
	for destination in [Vector3(-24,0,15),Vector3(23,0,9),Vector3(4.5,0,20),Vector3(-15,0,-25),Vector3(38,0,-22),Vector3(7,0,-19),Vector3(0,0,32.5),Vector3(-20,0,32.5)]:
		if nav.route(Vector3(0,0,5.5),destination).is_empty():
			failures.append("Colony landmark unreachable: "+str(destination))
	for obstacle in [Vector3(30,0,-22),Vector3(10,0,-23),Vector3(38,0,30)]:
		if not nav.route(Vector3(0,0,5.5),obstacle).is_empty():
			failures.append("Route entered water, standing stone or the exposed cliff")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Colony routes reach landing, habitat, expansion and survey districts")
	quit(0 if failures.is_empty() else 1)
