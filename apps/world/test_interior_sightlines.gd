extends SceneTree
## Cutaways expose the working floor while retaining the far-wall roof silhouette.
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for id in ["review", "gym"]:
		var station = load("res://station.gd").new()
		station.definition = load("res://structures/definitions/"+id+".tres")
		station.position = Vector3(27,0,-19)
		root.add_child(station)
		await physics_frame
		var room = station.room
		var collision_count = station.find_children("*", "CollisionShape3D", true, false).size()
		station.update_presentation(room.to_global(room.spawn_point), 1, true)
		var clipped := 0
		var other := 0
		for mesh in station.find_children("InteriorReveal*", "MeshInstance3D", true, false):
			var roof_batch: bool = str(mesh.name).begins_with("InteriorRevealBridge") or str(mesh.name).begins_with("InteriorRevealVault")
			for surface in mesh.mesh.get_surface_count():
				var material: ShaderMaterial = mesh.get_active_material(surface)
				check(is_equal_approx(float(material.get_shader_parameter("visibility")), 1.0), id+": retained reveal did not open")
				if roof_batch:
					clipped += 1
					check(material.get_shader_parameter("sightline_clip")==true, id+": middle roof span still obscures cutaway")
					check(is_equal_approx(float(material.get_shader_parameter("sightline_ceiling")),3.2), id+": clip must preserve low perimeter supports")
					check(is_equal_approx(float(material.get_shader_parameter("sightline_rear")),station.definition.interior_bounds.position.y+1.0), id+": rear silhouette band changed")
					var local_frame: Transform3D = material.get_shader_parameter("sightline_to_station")
					check((station.global_transform*local_frame).is_equal_approx(mesh.global_transform), id+": clip coordinates must follow translated station")
				else:
					other += 1
					check(material.get_shader_parameter("sightline_clip")!=true, id+": unrelated wall reveal was clipped")
		check(clipped > 0 and other > 0, id+": both roof and wall reveal batches must be checked")
		for point in [room.spawn_point, room.console_point, room.crew_point]:
			check(room.clear(Vector2(point.x,point.z)), id+": room interaction anchor obstructed")
			check(not room.route(room.to_global(room.spawn_point),room.to_global(point)).is_empty(), id+": room interaction route obstructed")
		station.update_presentation(station.return_position()+Vector3(0,0,8), 1, true)
		check(not room.visible, id+": room did not close after leaving")
		for material in station.reveal_materials:
			check(is_zero_approx(float(material.get_shader_parameter("visibility"))), id+": reveal leaked into exterior")
		check(station.find_children("*", "CollisionShape3D", true, false).size()==collision_count, id+": cutaway changed collision boundaries")
		station.queue_free()
		await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("INTERIOR_SIGHTLINES_PASSED: clear middle spans, retained rear silhouette, unchanged room routes and collision boundaries")
	quit(0 if failures.is_empty() else 1)
