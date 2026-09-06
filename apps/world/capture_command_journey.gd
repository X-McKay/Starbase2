extends SceneTree
## Explicit visual QA replay; fixture arguments disable operational commands.
var world: Node3D
var frame := 0
func _initialize() -> void: setup.call_deferred()
func setup() -> void:
	world=load("res://main.tscn").instantiate()
	root.add_child(world)
	assert(not world.fixture_path.is_empty() and not world.board_fixture.is_empty())
	world.hud.sound_enabled=true
	world.apply_settings()
	process_frame.connect(step)
func step() -> void:
	frame+=1
	if frame==10:
		world.get_node("Operator").position=world.get_node(world.STATIONS["review"]).return_position()+Vector3(0,0,3)
		world.route=world.travel_route(world.get_node(world.STATIONS["review"]).entrance())
	if frame==70: world.enter_room("review")
	if frame==85: world.route=world.active_room.route(world.get_node("Operator").position,world.active_room.position+world.active_room.console_point)
	if frame==140: world.hud.open_board()
	if frame==165: world.hud.board.inspect("pr-first")
	if frame in [55,125,180]:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../../evidence/command-district/journey-"+str(frame)+".png")
	if frame==230: quit()
