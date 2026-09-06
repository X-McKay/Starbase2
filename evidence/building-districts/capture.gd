extends SceneTree
## Reproduce native district captures with the real scene and disconnected API.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	world.capture_path=""
	world.hud.follow=true
	world.hud.reduced=true
	world.zoom=42.0
	for name in ["Workshop","Commons","Gym","Habitat","Greenhouse"]:
		var station=world.get_node("Buildings/"+name)
		world.get_node("Operator").position=station.entrance()+Vector3(2,0,1.5)
		for frame in range(90): await process_frame
		await RenderingServer.frame_post_draw
		var target="res://../../evidence/building-districts/"+name.to_lower()+".png"
		root.get_texture().get_image().save_png(target)
		print("Captured ",name," at ",world.get_node("Operator").position)
	world.queue_free()
	await process_frame
	quit()
