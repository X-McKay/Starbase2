extends SceneTree
const Geography=preload("res://geography.gd")
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	world.set_physics_process(false)
	var landform=world.get_node("Terrace/Landform")
	for name in ["MainlandCoast","InlandPlateau"]:
		var mesh: MeshInstance3D=landform.get_node(name)
		check(mesh.get_aabb().size.x>=450,"Mainland must extend beyond the colony camera envelope")
		for vertex in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			if vertex.y>0:
				check(not Geography.contains(Vector2(vertex.x,vertex.z),0.0),"Mainland surface must not invade the playable shelf")
	check(landform.find_children("*","StaticBody3D",true,false).size()==Geography.OUTLINE.size()+1,"Backdrop must not add physical traversal surfaces")
	for destination in [Vector3(-48*1.4*1.35,0,-25*1.35),Vector3(48*1.4*1.35,0,-28*1.35),Vector3(0,0,-38*1.35)]:
		check(world.navigator.route(Vector3(0,0,5.5),destination).is_empty(),"Mainland scenery must remain outside click navigation")
	var operator=world.get_node("Operator")
	for probe in [[Vector3(-38*1.4*1.35,0,-28*1.35),Vector3(-4,0,0)],[Vector3(38*1.4*1.35,0,-28*1.35),Vector3(4,0,0)],[Vector3(0,0,-30*1.35),Vector3(0,0,-4)]]:
		operator.position=probe[0]
		operator.motion=probe[1]
		await create_timer(0.7).timeout
		operator.motion=Vector3.ZERO
		check(Geography.contains(Vector2(operator.position.x,operator.position.z),0.20),"Physical movement must stop at mainland connection")
		check(not world.navigator.route(operator.position,Vector3(0,0,5.5)).is_empty(),"Operator must be able to return from boundary contact")
	# Probe the reshaped eastern neck, southern headland/cove and western shoulder.
	for index in [29,47,55,65]:
		var a: Vector2=Geography.OUTLINE[index]
		var b: Vector2=Geography.OUTLINE[(index+1)%Geography.OUTLINE.size()]
		var tangent := (b-a).normalized()
		var inward := Vector2(-tangent.y,tangent.x)
		var start := (a+b)*0.5+inward*1.1
		operator.position=Vector3(start.x,0,start.y)
		operator.motion=Vector3(-inward.x,0,-inward.y)*8.0
		await create_timer(0.35).timeout
		operator.motion=Vector3.ZERO
		check(Geography.contains(Vector2(operator.position.x,operator.position.z),0.20),"Curved shelf edge must stop physical movement")
		check(not world.navigator.route(operator.position,Vector3(0,0,5.5)).is_empty(),"Operator must return from curved-edge contact")
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Coast checks passed: continuous backdrop extent, shelf clearance, fixed collision count, excluded mainland routes, seven boundary contacts and returns")
	quit(0 if failures.is_empty() else 1)
