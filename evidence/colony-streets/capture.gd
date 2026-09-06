extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	world.capture_path=""
	world.hud.follow=true
	world.hud.reduced=true
	world.zoom=42.0
	for view in [["arrival",Vector3(-20,0,12)],["commons",Vector3(0,0,5.5)],["east",Vector3(20,0,25)]]:
		world.get_node("Operator").position=view[1]
		for frame in range(90): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../../evidence/colony-streets/"+view[0]+".png")
		print("Captured ",view[0])
	world.queue_free()
	await process_frame
	quit()
