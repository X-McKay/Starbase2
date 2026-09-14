extends SceneTree
var failures:Array[String]=[]
func check(value:bool,message:String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json"
	world.board_fixture="__empty_visual_fixture__"
	root.add_child(world)
	await process_frame
	await physics_frame
	var player:Vector3=world.get_node("Operator").position
	var records:Dictionary=world.snapshot.duplicate(true)
	var chosen:=""
	var building:Node3D
	for pair in world.crew_pairs():
		for station in world.get_node("Structures").get_children():
			if station.contains(pair[1].position): chosen=pair[0]; building=station; break
		if not chosen.is_empty(): break
	check(not chosen.is_empty(),"Crew begins at an authored home inside a building")
	world.watch_crew(chosen)
	for frame in range(150): await process_frame
	check(world.get_node("Operator").position==player,"Watching never moves the operator")
	check(world.active_room==null,"Watching never changes the operator room context")
	check(building.cutaway<0.01 and building.room.visible,"Explicit watch reveals the crew's room")
	check(world.get_node(world.MEMBERS[chosen]).visible,"Home crew remains visible in watched cutaway")
	check(world.hud.crew_strip.watching.text.contains("WATCHING"),"Watch mode is explicit in UI")
	check(world.snapshot==records and world.commands.payload.is_empty(),"Camera actions leave records and commands unchanged")
	var watched=world.get_node(world.MEMBERS[chosen])
	check(world.camera_focus.distance_to(watched.position+Vector3(0,.85,0))<.1,"Explicit watch frames its crew, not the room center: %s vs %s"%[world.camera_focus,watched.position+Vector3(0,.85,0)])
	check(absf(world.camera.size-8.8*world.zoom_factor)<.05,"Indoor watch has readable crew framing: %s factor %s"%[world.camera.size,world.zoom_factor])
	check(not watched.label.visible and world.hud.prompt.text.contains(str(world.crew_motions[chosen].intent.get("label","Unknown"))),"Watch status stays in the structured caption without covering the model")
	for pair in world.crew_pairs():
		if world.LivingCommons.FOOTPRINT.has_point(Vector2(pair[1].position.x,pair[1].position.z)):
			world.watch_crew(pair[0])
			for frame in range(150):await process_frame
			check(world.get_node("LivingCommons").canopy_visibility<.01,"Commons watch reveals its subject even while the operator is elsewhere")
			check(world.camera_focus.distance_to(pair[1].position+Vector3(0,.85,0))<.1 and absf(world.camera.size-10.0*world.zoom_factor)<.05,"Outdoor watch centers the crew at readable scale: focus %s subject %s size %s factor %s"%[world.camera_focus,pair[1].position,world.camera.size,world.zoom_factor])
			break
	world.stop_watching()
	for frame in range(150): await process_frame
	check(building.cutaway>0.99 and world.watched_crew.is_empty(),"Returning to operator restores room visibility")
	check(world.get_node("LivingCommons").canopy_visibility>.99,"Returning to distant operator restores commons canopy")
	world.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CREW_WATCH_PASSED: opt-in camera, home cutaway, visible actor, no teleport/dispatch and reversible view")
	quit(0 if failures.is_empty() else 1)
