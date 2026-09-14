extends SceneTree
## Fixed-60-Hz acceptance; optional --output=<directory> records the live native journey.
const Surface = preload("res://surface_layout.gd")
var failures: Array[String] = []
var records: Array[Dictionary] = []
var output := ""
var moving_frames := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func key(world: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	world._unhandled_key_input(event)
func capture(world: Node, label: String) -> void:
	if output.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	var error = root.get_texture().get_image().save_png(output.path_join(label + ".png"))
	check(error == OK, "Native frame saves: " + label)
	records.append({"frame": label, "actor": str(world.get_node("Operator").position), "camera": str(world.camera.position), "location": world.hud.location.text})
func walk(world: Node, target: Vector3, record_motion := false) -> void:
	var actor = world.get_node("Operator")
	world.route = world.travel_route(target)
	check(not world.route.is_empty(), "Physical route exists: " + str(target))
	var previous: Vector3 = actor.position
	var previous_tick = Engine.get_physics_frames()
	for tick in range(1800):
		await physics_frame
		var elapsed = Engine.get_physics_frames() - previous_tick
		var traveled = actor.position.distance_to(previous)
		check(traveled <= 6.0 * float(elapsed) / 60.0 + 0.035, "Traversal respects 6 m/s without teleport")
		if traveled > 0.04: moving_frames += 1
		previous = actor.position
		previous_tick = Engine.get_physics_frames()
		if record_motion and tick in [12, 24, 36]: await capture(world, "movement-%s-%s" % [int(target.x), tick])
		if world.route.is_empty(): break
	await physics_frame
	await physics_frame
	check(actor.position.distance_to(target) < 0.45, "Physical arrival: " + str(target))
	check(actor.motion.length() < 0.01, "Arrival stops motion")
	check(actor.model_visual.clip == "idle", "Arrival returns to idle")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	var world = load("res://main.tscn").instantiate()
	world.fixture_path = "res://../../fixtures/world/stale.json"
	world.board_fixture = "__empty_visual_fixture__"
	root.add_child(world)
	await process_frame
	await physics_frame
	var actor = world.get_node("Operator")
	await walk(world, Vector3(0, 0, 12))
	await walk(world, Vector3(0, 0, 16), true)
	check(actor.facing == 0, "Southward route faces south")
	await walk(world, Vector3(-5, 0, 16), true)
	check(actor.facing == 2, "Orthogonal turn faces west")
	check(moving_frames > 50, "Journey contains sustained physical movement")
	await capture(world, "plateau-stopped")
	var basin = world.get_node("Terrace/MineralBasin")
	var river = world.get_node("Terrace/Landform")
	var water_block: Rect2 = Surface.NATURAL_BLOCKS[0]
	var shore := Vector3(water_block.get_center().x, 0, water_block.end.y + 2.0)
	await walk(world, shore)
	check(world.travel_route(Vector3(water_block.get_center().x, 0, water_block.get_center().y)).is_empty(), "Spring water rejects travel destinations")
	world.set_physics_process(false)
	actor.motion = Vector3(0, 0, -3.7)
	for tick in range(45): await physics_frame
	check(actor.position.z > water_block.end.y + 0.26, "Spring bank physically stops attempted water entry")
	actor.motion = Vector3.ZERO
	world.set_physics_process(true)
	await walk(world, shore)
	var basin_before: float = basin.water_time
	var river_before: float = river.water_time
	for tick in range(30): await process_frame
	check(basin.water_time > basin_before and river.water_time > river_before, "Both water presentations advance with normal motion")
	await capture(world, "water-moving")
	world.hud.reduced = true
	world.apply_settings()
	basin_before = basin.water_time
	river_before = river.water_time
	for tick in range(30): await process_frame
	check(is_equal_approx(basin.water_time, basin_before) and is_equal_approx(river.water_time, river_before), "Reduced motion freezes both water presentations")
	await capture(world, "water-reduced-motion")
	world.hud.reduced = false
	world.apply_settings()
	var habitat: Node
	for station in world.get_node("Structures").get_children():
		if str(station.definition.id) == "habitat": habitat = station
	check(habitat != null, "Habitat exists")
	if habitat != null:
		await walk(world, habitat.return_position())
		await capture(world, "habitat-exterior")
		await walk(world, habitat.room.content.get_node("Console").global_position)
		check(world.active_building == habitat, "Walking to furniture console enters Habitat")
		for block in habitat.room.blocks:
			var local := Vector3(block.get_center().x, 0, block.get_center().y)
			check(world.travel_route(habitat.room.to_global(local)).is_empty(), "Habitat furniture rejects navigation")
		for tick in range(150): await process_frame
		check(world.camera_focus.distance_to(habitat.room.content.get_node("CameraFocus").global_position) < 0.08, "Live Habitat camera settles on authored focus")
		await capture(world, "habitat-interior")
		key(world, KEY_E)
		check(world.hud.room_details.visible, "E opens Habitat guide")
		var guide: String = world.hud.room_detail_body.text
		check(not guide.is_empty(), "Habitat guide has descriptive content")
		await capture(world, "habitat-guide")
		key(world, KEY_ESCAPE)
		check(not world.hud.room_details.visible, "Escape closes Habitat guide")
		world.exit_room()
		world.enter_room(str(habitat.name))
		await physics_frame
		await physics_frame
		key(world, KEY_E)
		check(world.hud.room_details.visible and world.hud.room_detail_body.text == guide, "Direct visit exposes identical Habitat guide")
		key(world, KEY_ESCAPE)
	check(world.commands.payload.is_empty() and world.hud.board.commands.payload.is_empty(), "Movement and inspection never dispatch")
	if not output.is_empty():
		var file = FileAccess.open(output.path_join("inhabited-journey.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"live_world_presentation": true, "records": records, "moving_frames": moving_frames, "failures": failures}, "\t"))
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("INHABITED_JOURNEY_PASSED: physical run/stop/turn, water temporal accessibility, Habitat furniture console and equivalent no-dispatch inspection")
	quit(0 if failures.is_empty() else 1)
