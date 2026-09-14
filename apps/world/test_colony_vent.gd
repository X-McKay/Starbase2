extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func run() -> void:
	var colony := preload("res://structures/colony.tscn").instantiate()
	root.add_child(colony)
	var attached := 0
	for station in colony.get_children():
		var fan = preload("res://colony_vent.gd").attach(station)
		if str(station.definition.id) == "repair":
			check(fan == null, "Engineering must retain its existing machinery only")
			continue
		check(fan != null, "All four non-Engineering asset IDs must attach, including scenery")
		if fan == null: continue
		attached += 1
		check(preload("res://colony_vent.gd").attach(station) == fan, "Repeated attachment must return the same fan")
		check(station.room.find_children("ColonyVent", "Node3D", false, false).size() == 1, "Room must have exactly one fan")
	check(attached == 4, "Exactly four colony interiors receive ventilation")
	colony.queue_free()
	await process_frame
	var room := Node3D.new()
	root.add_child(room)
	var vent := preload("res://colony_vent.gd").new()
	room.add_child(vent)
	check(vent.rotor != null, "Authored Rotor must import")
	check(vent.rotor.position.length() < 0.001, "Rotor pivot must be at housing center")
	check(vent.find_children("*", "CollisionObject3D", true, false).is_empty(), "Decorative fan must not add collision")
	await create_timer(0.1).timeout
	check(vent.phase > 0.0, "Visible fan rotates")
	var frozen: float = vent.phase
	vent.reduced_motion = true
	await create_timer(0.1).timeout
	check(vent.phase == frozen, "Reduced motion freezes fan")
	vent.reduced_motion = false
	room.visible = false
	await create_timer(0.1).timeout
	check(vent.phase == frozen, "Hidden room freezes fan")
	room.visible = true
	await create_timer(0.1).timeout
	check(vent.phase > frozen, "Visible room resumes fan")
	if DisplayServer.get_name() != "headless":
		var camera := Camera3D.new()
		camera.position = Vector3(1.3, 0.8, 3.0)
		room.add_child(camera)
		camera.look_at(Vector3.ZERO)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-25,-25,0)
		room.add_child(light)
		root.size = Vector2i(900,600)
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		frame.convert(Image.FORMAT_RGB8)
		frame.save_png("res://../../evidence/world/inhabited-polish/vent/native.png")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Colony vent passed: imported centered rotor, visible rotation, reduced/hidden freeze, resume, no collision")
	quit(0 if failures.is_empty() else 1)
