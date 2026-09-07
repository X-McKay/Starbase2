extends SceneTree
## Complements the full continuous journeys with all-four prop/edge contact.
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	world.fixture_path="test-only"
	world.http.cancel_request()
	world.hud.reduced=true
	var actor: CharacterBody3D=world.get_node("Operator")
	for station in world.get_node("Structures").get_children():
		var id := str(station.definition.id)
		if id not in ["review","gym","habitat","greenhouse"]: continue
		world.enter_room(str(station.name))
		await physics_frame
		await physics_frame
		var room=station.room
		check(world.active_building==station,id+": direct visit selects its own structure")
		check(station.cutaway==0 and room.visible,id+": reduced-motion cutaway reveals interior")
		check(not room.blocks.is_empty(),id+": furnished interior has physical obstacles")
		if station.interaction_kind.is_empty():
			check(room.activity.text.contains("scenery"),id+": scenery invents no operational state")
		world.set_physics_process(false)
		for block in room.blocks:
			var center: Vector3=room.global_position+Vector3(block.get_center().x,0,block.get_center().y)
			check(world.travel_route(center).is_empty(),id+": navigation refuses solid furniture")
			actor.position=center+Vector3(0,0,block.size.y/2+0.8)
			actor.motion=Vector3(0,0,-3.7)
			for tick in range(25): await physics_frame
			check(actor.position.z>center.z+block.size.y/2+0.26,id+": furniture stops physical movement")
			actor.motion=Vector3.ZERO
		var bounds: Rect2=room.definition.interior_bounds
		actor.position=room.global_position+Vector3(bounds.end.x-0.5,0,bounds.end.y-1)
		actor.motion=Vector3(3.7,0,0)
		for tick in range(25): await physics_frame
		check(actor.position.x<room.global_position.x+bounds.end.x,id+": faded side wall blocks physical movement")
		actor.motion=Vector3.ZERO
		world.set_physics_process(true)
		world.exit_room()
		await physics_frame
		check(actor.position.distance_to(station.return_position())<0.1,id+": exit returns to matching threshold")
		print("STRUCTURE_CONTACT ",id)
	check(world.commands.payload.is_empty(),"Travel and contact cannot dispatch work")
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("REMAINING_STRUCTURES_PASSED: all-four furniture contact, side walls, direct visits, cutaways, scenery and no dispatch")
	quit(0 if failures.is_empty() else 1)
