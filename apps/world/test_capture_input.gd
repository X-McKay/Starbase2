extends SceneTree
func _initialize() -> void: run.call_deferred()
func key(pressed:bool) -> void:
	var event:=InputEventKey.new(); event.physical_keycode=KEY_D; event.pressed=pressed
	Input.parse_input_event(event); Input.flush_buffered_events()
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json"; world.board_fixture="__empty_visual_fixture__"
	root.add_child(world)
	await process_frame; await physics_frame; await physics_frame
	assert(not world.capture_input_isolated and not root.gui_disable_input)
	assert(world.is_processing_unhandled_input() and world.is_processing_unhandled_key_input())
	world.route=world.travel_route(Vector3(-7,0,1.6)); assert(not world.route.is_empty())
	key(true)
	await physics_frame; await physics_frame
	assert(world.route.is_empty(),"Normal gameplay still allows manual movement to replace a route")
	key(false)
	world.isolate_capture_input()
	assert(root.gui_disable_input and not world.is_processing_unhandled_input() and not world.is_processing_unhandled_key_input())
	world.route=world.travel_route(Vector3(-7,0,1.6)); assert(not world.route.is_empty())
	key(true)
	for tick in range(300):
		await physics_frame
		if world.route.is_empty(): break
	key(false)
	assert(world.get_node("Operator").position.distance_to(Vector3(-7,0,1.6))<0.45,"Capture isolation retains real physical route despite desktop key state")
	world.hud.navigation_bar.get_child(2).pressed.emit()
	assert(world.hud.operations.visible,"Internal native button signal still opens operations")
	world.hud.close_panels(); world.enter_room("review")
	world.get_node("Operator").position=world.active_room.to_global(world.active_room.console_point)
	await physics_frame; await physics_frame
	var inspect_event:=InputEventKey.new(); inspect_event.physical_keycode=KEY_E; inspect_event.pressed=true
	world._unhandled_key_input(inspect_event)
	assert(world.hud.board.visible,"Explicit harness E still follows the native console action")
	world.queue_free(); await process_frame
	print("Capture input passed: default manual routing preserved, explicit GUI/input isolation, real collision route and internal UI signal")
	quit()
