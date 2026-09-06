extends SceneTree
const Geography=preload("res://geography.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var mesh: MeshInstance3D=world.get_node("Terrace/Landform/InlandPlateau")
	var vertices: PackedVector3Array=mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var failures: Array[String]=[]
	for point in Geography.north_rim():
		var seam := Vector3(point.x,-0.035,point.y)
		var matched := false
		for vertex in vertices:
			if vertex.distance_to(seam)<0.0001:
				matched=true
				break
		if not matched: failures.append("Upland mesh must meet the exact plateau edge: "+str(seam))
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Upland seam checks passed: every northern boundary vertex matches the plateau position and elevation")
	quit(0 if failures.is_empty() else 1)
