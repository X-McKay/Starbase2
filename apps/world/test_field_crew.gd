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
	assert(world.get_node("Watchkeeper").label.text.contains("[=] Evidence ready"))
	assert(StateView.crew_activity(world.missions,"watchkeeper",false)=="Findings")
	assert(world.get_node("Reviewer").label.text.contains("No recorded work"))
	var key:=InputEventKey.new()
	key.pressed=true
	key.physical_keycode=KEY_4
	world._unhandled_key_input(key)
	assert(world.hud.heading.text.contains("WES WALKER"))
	assert(world.hud.suit_label.text.contains("WATCHKEEPER"))
	assert(world.hud.selected_id=="cluster-test")
	assert(world.hud.evidence.text.contains("synthetic fixture"))
	assert(world.hud.evidence.text.contains("1 observed findings"))
	key.physical_keycode=KEY_5
	world._unhandled_key_input(key)
	assert(world.hud.heading.text.contains("PRISM"))
	assert(world.hud.suit_label.text.contains("REVIEWER"))
	for name in ["Watchkeeper","Reviewer"]:
		var actor=world.get_node(name)
		assert(not world.navigator.route(Vector3(0,0,5.5),actor.position).is_empty())
	world.disconnected=true
	world.show_mission()
	assert(world.get_node("Watchkeeper").label.text.contains("Unknown"))
	world.hud.large_text=true
	world.hud.scale_text()
	world.hud.toggle_directory()
	world.hud.set_crew_summary(true)
	await process_frame
	await process_frame
	# The summary now lives inside the scrollable station directory. Offscreen
	# menu content is intentional; the viewport and revealed summary must fit.
	var scroll:ScrollContainer=world.hud.roster.get_parent().get_parent()
	assert(root.get_visible_rect().encloses(scroll.get_global_rect()))
	scroll.ensure_control_visible(world.hud.roster)
	await process_frame
	assert(world.hud.roster.is_visible_in_tree())
	assert(scroll.get_global_rect().encloses(world.hud.roster.get_global_rect()))
	world.queue_free()
	await process_frame
	print("Field crew checks passed: two characters, reachable positions, keyboard directory inspectors, authoritative fixture and offline state")
	quit()
