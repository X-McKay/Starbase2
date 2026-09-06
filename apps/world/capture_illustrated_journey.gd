extends SceneTree
## Fixture-only integration replay through the actual colony actor and route logic.
var world:Node3D
var frame:=0
func _initialize() -> void: setup.call_deferred()
func setup() -> void:
	world=load("res://main.tscn").instantiate(); root.add_child(world)
	assert(not world.fixture_path.is_empty(),"Recording requires fixture data")
	world.zoom=20
	world.hud.sound_enabled=true; world.apply_settings()
	process_frame.connect(step)
func step() -> void:
	frame+=1
	var actor=world.get_node("Operator")
	if frame==10:
		actor.position=Vector3(-10,0,15)
		world.camera_focus=actor.position
	if frame==30: world.route=[Vector3(8,0,15)]
	if frame==130:
		world.route.clear(); actor.motion=Vector3.ZERO
	if frame==165:
		world.enter_room("review")
		actor.position=world.active_room.position+Vector3(-2.5,0,1.5)
	if frame==185:
		world.route=[world.active_room.position+Vector3(2.5,0,1.5)]
	if frame==225: world.route.clear(); actor.motion=Vector3.ZERO
	if frame in [90,150,210,245]:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../../evidence/illustrated-walk/integration/colony-"+str(frame)+".png")
	if frame==270: quit()
