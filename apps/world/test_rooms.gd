extends SceneTree
var failures: Array[String] = []
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
func key(world: Node,code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode=code
	event.pressed=true
	world._unhandled_key_input(event)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world = load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	world.fixture_path="test-only"
	world.http.cancel_request()
	world.hud.reduced=true
	world.apply_settings()
	var operator: CharacterBody3D=world.get_node("Operator")
	var snapshot := {"schema_version":2,"recent":[],"repairs":[{"input":{"id":"room-record","scenario":"clamp-v1"},"state":"executing","summary":null}],"worker":{"available":false}}
	world.receive_snapshot(snapshot)
	for kind in ["repair","review","gym"]:
		var station: Node3D=world.get_node(world.STATIONS[kind])
		operator.position=station.entrance()
		await physics_frame
		await physics_frame
		check(world.near_door==str(station.name),"Door proximity must select "+kind)
		key(world,KEY_F)
		await physics_frame
		# process_frame fires before Node._process; wait through a completed update
		# before asserting the camera or projecting a physical click.
		await process_frame
		await process_frame
		check(world.active_room!=null and world.room_kind==kind,"F enters "+kind)
		if world.active_room==null: continue
		var room: Node3D=world.active_room
		check(world.hud.room_exit.visible,"Interior must expose return control and cutaway backdrop")
		check(world.sky_layer.visible and world.get_node("Terrace").visible,"Continuous interior retains exterior sky and canyon scenery")
		var expected_focus:Vector3=room.global_position+Vector3(room.definition.interior_bounds.get_center().x,1,room.definition.interior_bounds.get_center().y)
		if room.content.has_node("CameraFocus"): expected_focus=room.content.get_node("CameraFocus").global_position
		check(world.camera_focus.distance_to(expected_focus)<0.01,"Reduced-motion entry uses an immediate authored room camera cut")
		check(world.commands.phase=="" and world.commands.payload.is_empty(),"Room entry must never dispatch work")
		if kind=="repair": check(room.activity.text.contains("Stale"),"Room activity must preserve stale authoritative work")
		var goal: Vector3 = room.content.get_node("WalkTarget").global_position
		var click := InputEventMouseButton.new()
		click.button_index=MOUSE_BUTTON_LEFT
		click.pressed=true
		click.position=world.camera.unproject_position(goal)
		world._unhandled_input(click)
		check(not world.route.is_empty(),"Route around room worktable must exist")
		for point in world.route:
			check(room.clear(Vector2(point.x-room.global_position.x,point.z-room.global_position.z)),"Route intersects furniture")
		for tick in range(360):
			await physics_frame
			if world.route.is_empty(): break
		check(operator.position.distance_to(goal)<0.35,"Physical route must reach behind worktable in "+kind)
		var block: Rect2=room.blocks[0]
		var center := room.global_position+Vector3(block.get_center().x,0,block.get_center().y)
		check(world.travel_route(center).is_empty(),"Clicking solid furniture rejects movement")
		# Test real contact against the authored first prop, then route recovery.
		world.set_physics_process(false)
		operator.position=center+Vector3(0,0,block.size.y/2+1)
		operator.motion=Vector3(0,0,-3.7)
		for tick in range(30): await physics_frame
		check(operator.position.z>center.z+block.size.y/2+0.26,"Authored furniture stops walking")
		operator.motion=Vector3.ZERO
		check(not world.travel_route(station.return_position()).is_empty(),"Route recovers from prop contact")
		var bounds: Rect2=room.definition.interior_bounds
		operator.position=room.global_position+Vector3(bounds.end.x-0.5,0,bounds.end.y-1)
		operator.motion=Vector3(3.7,0,0)
		for tick in range(25): await physics_frame
		check(operator.position.x<room.global_position.x+bounds.end.x,"Faded side wall retains collision")
		operator.motion=Vector3.ZERO
		operator.position=room.global_position+room.console_point
		world.set_physics_process(true)
		await physics_frame
		await physics_frame
		key(world,KEY_E)
		check(world.hud.board.visible if kind=="review" else world.hud.dock.visible and world.hud.filter_kind==kind,"Console E opens Command board or crew inspector")
		check(world.hud.submit.disabled,"Fixture must never enable a live command")
		world.disconnected=true
		world.show_mission()
		check(room.activity.text.contains("Unknown"),"Interior label must become unknown when disconnected")
		world.hud.close_panels()
		key(world,KEY_F)
		await physics_frame
		check(world.active_room==null and not world.hud.room_exit.visible,"F exits "+kind)
		check(world.sky_layer.visible and world.get_node("Terrace").visible,"Exit must restore exterior scenery")
		check(operator.position.distance_to(station.return_position())<0.1,"Exit must return to its matching door")
		check(not world.navigator.route(operator.position,Vector3(0,0,5.5)).is_empty(),"Exterior navigation survives room exit")
		world.receive_snapshot(snapshot)
	# Non-spatial visit buttons and the map must work without a door approach.
	world.hud.open_place("review")
	world.hud.room_requested.emit("review")
	await process_frame
	check(world.room_kind=="review" and not world.hud.is_open(),"Inspector visit button enters its selected room")
	var crew_before_switch:Vector3=world.get_node("Surveyor").position
	world.enter_room("gym")
	await process_frame
	check(world.room_kind=="gym","Direct room switching replaces the prior interior")
	check(world.get_node("Surveyor").position.distance_to(crew_before_switch)<0.1,"Switching rooms preserves crew position instead of teleporting it from home")
	key(world,KEY_M)
	check(world.active_room==null and world.colony_overview,"Map exits the room into colony overview")
	check(world.commands.payload.is_empty(),"All travel and inspection remained free of dispatch")
	# A new unbound place can reuse the same host and scene without a UI branch.
	var annex=preload("res://station.gd").new()
	annex.name="VisitorAnnex"
	annex.definition=load("res://structures/definitions/repair.tres").duplicate()
	annex.definition.id=&"visitor-annex-fixture"
	annex.definition.title="VISITOR ANNEX"
	annex.position=Vector3(28,0,12)
	world.get_node("Structures").add_child(annex)
	world.hud.set_structures(world.get_node("Structures").get_children())
	world.hud.building_search.text="visitor annex"
	world.hud.filter_buildings("visitor annex")
	var visible_places=world.hud.building_list.get_children().filter(func(entry): return entry.visible)
	check(visible_places.size()==1,"Building search isolates the new place")
	visible_places[0].pressed.emit()
	await process_frame
	check(world.active_room!=null and world.room_kind=="","New unbound building enters without an operational type branch")
	check(world.active_room.activity.text.contains("scenery"),"Unbound room must not invent agent activity")
	check(world.commands.payload.is_empty(),"Unbound room cannot dispatch work")
	world.exit_room()
	check(operator.position.distance_to(annex.return_position())<0.1,"Unbound building retains its own return anchor")
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Room checks passed: three door journeys, prop/edge physics, route recovery, console inspection, stale/offline state, direct visits, map exit, no dispatch")
	quit(0 if failures.is_empty() else 1)
