extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	assert(not world.fixture_path.is_empty())
	assert(world.board_fixture.is_empty())
	world.hud.open_board()
	await process_frame
	assert(not world.hud.board.fixture.is_empty())
	assert(world.hud.board.launch.disabled and world.hud.board.watch_save.disabled)
	assert(world.hud.board.get_http.get_http_client_status()==HTTPClient.STATUS_DISCONNECTED)
	assert(world.hud.board.commands.phase.is_empty())
	world.queue_free(); await process_frame
	print("Visual fixture cannot open a live operational Command board or dispatch work")
	quit()
