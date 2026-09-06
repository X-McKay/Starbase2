extends SceneTree
const StateView=preload("res://state.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.content_scale_size=Vector2i(960,720)
	root.size=Vector2i(960,720)
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var fixture={"schema_version":2,"recent":[],"worker":{"available":true},"field_runs":[{"input":{"id":"cluster-test","agent":"watchkeeper","target":"training"},"state":"completed","snapshot":{"data":{"simulation":true}},"report":{"findings":[{}],"coverage":[],"memory":{"status":"available"}}}]}
	world.receive_snapshot(fixture)
	assert(world.get_node("Watchkeeper").label.text.contains("Findings"))
	assert(world.get_node("Reviewer").label.text.contains("No recorded work"))
	var key:=InputEventKey.new()
	key.pressed=true
	key.physical_keycode=KEY_4
	world._unhandled_key_input(key)
	assert(world.hud.heading.text.contains("WATCHKEEPER"))
	assert(world.hud.selected_id=="cluster-test")
	assert(world.hud.evidence.text.contains("synthetic fixture"))
	key.physical_keycode=KEY_5
	world._unhandled_key_input(key)
	assert(world.hud.heading.text.contains("PR REVIEWER"))
	for name in ["Watchkeeper","Reviewer"]:
		var actor=world.get_node(name)
		assert(not world.navigator.route(Vector3(0,0,5.5),actor.position).is_empty())
	world.disconnected=true
	world.show_mission()
	assert(world.get_node("Watchkeeper").label.text.contains("Unknown"))
	world.hud.large_text=true
	world.hud.scale_text()
	await process_frame
	await process_frame
	for control in world.hud.roster.get_parent().get_children():
		assert(control.get_global_rect().end.y <= root.get_visible_rect().size.y)
	world.queue_free()
	await process_frame
	print("Field crew checks passed: two characters, reachable positions, keyboard directory inspectors, authoritative fixture and offline state")
	quit()
