extends SceneTree
func _initialize() -> void:
	run.call_deferred()

func shot(name: String) -> void:
	for frame in range(60): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../../evidence/meshy-blender/"+name+".png")

func run() -> void:
	var world = load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	world.capture_path = ""
	world.hud.follow = true
	world.hud.reduced = true
	world.zoom = 24.0
	var station = world.get_node("Buildings/Workshop")
	world.get_node("Operator").position = station.entrance()+Vector3(1.5,0,1.5)
	await shot("engineering-exterior")
	world.enter_room("repair")
	await shot("engineering-interior")
	world.hud.large_text = true
	world.hud.scale_text()
	world.disconnected = true
	world.show_mission()
	world.hud.open_place("repair")
	await shot("engineering-inspection")
	world.queue_free()
	await process_frame
	quit()
