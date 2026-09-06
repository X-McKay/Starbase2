extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	world.capture_path=""
	world.hud.reduced=true
	world.apply_settings()
	world.hud.follow=true
	world.zoom=42.0
	world.get_node("Operator").position=Vector3(-20,0,12)
	for frame in range(60): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../../evidence/colony-edge-lights/arrival.png")
	# Hold the camera still while sampling a real runway lens across a full cycle.
	world.get_node("Operator").position=Vector3(-12,0,25)
	world.zoom=32.0
	for frame in range(60): await process_frame
	var lights=world.get_node("Terrace/PavingLights")
	var nearest: Vector2=lights.beacons()[0]
	for lamp in lights.beacons():
		if lamp.distance_to(Vector2(-12,29.85))<nearest.distance_to(Vector2(-12,29.85)): nearest=lamp
	var at=Vector3(nearest.x,preload("res://paving_lights.gd").HEIGHT+0.012,nearest.y)
	var pixel: Vector2i=Vector2i(world.camera.unproject_position(at))
	var results := {}
	for mode in ["pulse","steady"]:
		lights.reduced_motion=mode=="steady"
		var low := 2.0
		var high := -1.0
		for frame in range(180):
			await process_frame
			if frame%6!=0: continue
			await RenderingServer.frame_post_draw
			var shot=root.get_texture().get_image()
			var color=shot.get_pixelv(pixel)
			var value=(color.r+color.g+color.b)/3.0
			if value<low:
				low=value
				if mode=="pulse": shot.save_png("res://../../evidence/colony-edge-lights/pulse-dim.png")
			if value>high:
				high=value
				shot.save_png("res://../../evidence/colony-edge-lights/"+("pulse-bright" if mode=="pulse" else "reduced-motion")+".png")
		results[mode]={"min":low,"max":high,"range":high-low}
	results["pixel"]=str(pixel)
	results["passed"]=results.pulse.range>0.1 and results.steady.range<0.02
	var file=FileAccess.open("res://../../evidence/colony-edge-lights/render-check.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"  "))
	print(results)
	world.queue_free()
	await process_frame
	quit(0 if results.passed else 1)
