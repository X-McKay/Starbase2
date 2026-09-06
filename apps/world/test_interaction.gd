extends SceneTree
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func key(code: Key, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world = load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	key(KEY_TAB)
	await process_frame
	check(world.hud.directory.visible,"Tab opens the crew directory")
	key(KEY_ENTER)
	await process_frame
	key(KEY_ENTER,false)
	await process_frame
	check(world.hud.board.visible,"Enter on first directory item opens Command")
	key(KEY_ESCAPE)
	await process_frame
	check(not world.hud.is_open(),"Escape returns to walking")
	var start: Vector3 = world.get_node("Operator").position
	key(KEY_D)
	await create_timer(0.3).timeout
	key(KEY_D,false)
	check(world.get_node("Operator").position.x > start.x+0.5,"Held D moves the operator")
	world.get_node("Operator").position = world.get_node("Mender").position+Vector3(0,0,1)
	await physics_frame
	await physics_frame
	key(KEY_E)
	await process_frame
	check(world.hud.dock.visible and world.hud.filter_kind=="repair","E at Mender opens the same inspector")
	key(KEY_ESCAPE)
	await process_frame
	key(KEY_3)
	await process_frame
	check(world.hud.filter_kind=="gym" and not world.hud.repair_form.visible,"3 reaches gym without travel or repair form")
	key(KEY_ESCAPE)
	await process_frame
	key(KEY_C)
	await process_frame
	check(not world.hud.follow,"C switches from follow to room camera")
	key(KEY_M)
	await process_frame
	check(world.colony_overview,"M opens colony overview")
	key(KEY_M)
	await process_frame
	check(not world.colony_overview,"M returns to walking view")
	world.hud.reduced = true
	world.apply_settings()
	check(not world.hud.follow and world.get_node("Mender").reduced_motion,"Reduced motion disables camera follow and crew animation")
	world.receive_snapshot({"schema_version":2,"recent":[],"worker":{"available":true},"observed_at":0})
	world.hud.open_place("repair")
	world.hud.repair_requested.disconnect(world.launch_repair)
	var calls: Array = []
	world.hud.repair_requested.connect(func(scenario,mode): calls.append([scenario,mode]))
	world.hud.submit.grab_focus()
	key(KEY_ENTER)
	await process_frame
	key(KEY_ENTER,false)
	await process_frame
	check(calls==[["clamp-v1","control-good"]],"Keyboard activates the explicit synthetic control with no implicit inference")
	world.disconnected=true
	world.show_mission()
	check(world.hud.submit.disabled and world.hud.stop.disabled,"Offline state disables dispatch and cancellation")
	world.hud.large_text = true
	world.hud.scale_text()
	await process_frame
	await process_frame
	check(world.hud.dock.get_global_rect().end.x <= root.get_visible_rect().size.x,"Larger text must not push the inspector offscreen")
	world.hud.close_panels()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = world.camera.unproject_position(world.get_node("Buildings/Workshop").return_position()+Vector3(4,0,5))
	# Headless mouse injection targets the viewport, which has no OS pointer focus.
	root.push_input(click,true)
	await process_frame
	check(not world.route.is_empty(),"Click on a clear path creates a walking route")
	var helmet_click := InputEventMouseButton.new()
	helmet_click.button_index=MOUSE_BUTTON_LEFT
	helmet_click.pressed=true
	helmet_click.position=world.camera.unproject_position(world.get_node("Mender").position+Vector3(0,2.65,0))
	root.push_input(helmet_click,true)
	await process_frame
	check(world.hud.dock.visible and world.hud.filter_kind=="repair","Clicking the taller character's helmet opens its inspector")
	# The larger world must remain traversable with reduced-motion room cuts.
	world.hud.close_panels()
	world.set_physics_process(false)
	var operator = world.get_node("Operator")
	operator.motion = Vector3.ZERO
	operator.position = Vector3(30,0,15)
	await process_frame
	await process_frame
	check(world.camera_focus.distance_to(operator.position)<0.1,"Reduced-motion room camera reaches distant districts without interpolation")
	operator.position = Vector3(37,0,0)
	operator.motion = Vector3(6,0,0)
	await create_timer(0.4).timeout
	check(preload("res://geography.gd").contains(Vector2(operator.position.x,operator.position.z),0.20),"Physical survey boundary stops keyboard movement at the reshaped edge")
	# The retired blockout shuttle may not leave an invisible obstacle.
	operator.position=Vector3(-24,0,11)
	operator.motion=Vector3(0,0,-5)
	await create_timer(0.5).timeout
	check(operator.position.z<9,"Former shuttle footprint is physically walkable")
	var greenhouse=world.get_node("Buildings/Greenhouse")
	operator.position = greenhouse.return_position()
	operator.motion = Vector3(0,0,-10)
	await create_timer(0.5).timeout
	check(operator.position.z>greenhouse.global_position.z+greenhouse.definition.collision_boxes[0].end.y+0.2,"Greenhouse collision agrees with its blocked navigation footprint")
	operator.position = Vector3(30,0,-20)
	operator.motion = Vector3(0,0,-10)
	await create_timer(0.4).timeout
	check(operator.position.z>-21.8,"Mineral pool prevents walking onto the water")
	operator.position = Vector3(10,0,-18)
	operator.motion = Vector3(0,0,-10)
	await create_timer(0.5).timeout
	check(operator.position.z>-20.8,"Weathered landmark blocks physical movement")
	operator.position = Vector3(0,0,28)
	operator.motion = Vector3(0,0,10)
	await create_timer(0.6).timeout
	check(preload("res://geography.gd").contains(Vector2(operator.position.x,operator.position.z),0.20),"Near cliff edge stops the operator on the shelf")
	operator.position = Vector3(36,0,25)
	operator.motion = Vector3(8,0,6)
	await create_timer(0.6).timeout
	check(preload("res://geography.gd").contains(Vector2(operator.position.x,operator.position.z),0.20),"Oblique cliff collision agrees with the polygon")
	check(not world.navigator.route(operator.position,Vector3(0,0,27)).is_empty(),"Click-to-walk can return from physical contact with the cliff rim")
	operator.motion = Vector3.ZERO
	world.queue_free()
	await process_frame
	if failures.is_empty():
		print("Interaction checks passed: keyboard directory, spatial interaction, walking, gym, camera, reduced motion, explicit form, offline fencing")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
