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
	# A stand beside an authored station must not make the safe exact endpoint
	# unreachable just because its nearest half-metre grid cell lies toward the stand.
	var station:=Vector3(2.75,0,-1.65)
	var support:=Rect2(3.225,-1.95,.25,.6)
	nav.add_obstacle(support)
	var approach:=nav.route(Vector3(0,0,5.5),station)
	assert(not approach.is_empty(),"Safe off-grid station remains reachable")
	assert(nav.clear_start_segment(Vector2(approach[-1].x,approach[-1].z),Vector2(station.x,station.z)),"Recovered endpoint has a safe final segment")
	assert(nav.route(Vector3(0,0,5.5),Vector3(3.3,0,-1.65)).is_empty(),"Endpoint recovery must not enter the stand")
	assert(not nav.clear_start_segment(Vector2(2.75,-1.65),Vector2(3.5,-1.65)),"Physical segments cannot cross new furniture")
	print("Navigation checks passed: all crew, route around habitat, walls, colony boundary")
	quit()
