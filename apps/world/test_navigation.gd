extends SceneTree
const Navigation = preload("res://navigation.gd")
func _initialize() -> void:
	var nav := Navigation.new()
	for placement in Navigation.Structures.placements():
		var destination: Vector3=placement.position+placement.definition.return_point
		var path := nav.route(Vector3(0,0,5.5),destination)
		assert(not path.is_empty(),"Each crew and the back path must be reachable")
		assert(path[-1].distance_to(destination)<0.36)
		for p in path:
			for block in Navigation.BLOCKS:
				assert(not block.has_point(Vector2(p.x,p.z)),"Route may not cross a solid footprint")
	assert(nav.route(Vector3(0,0,5.5),Vector3(-24,0,1.5)).is_empty(),"Click inside hangar must not walk through its wall")
	assert(nav.route(Vector3(0,0,5.5),Vector3(63,0,0)).is_empty(),"Click beyond the survey ridge must not leave the basin")
	print("Navigation checks passed: all crew, route around habitat, walls, colony boundary")
	quit()
