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
	for frame in range(90): await physics_frame
	check(world.get_node("Operator").position==player,"Watching never moves the operator")
	check(world.active_room==null,"Watching never changes the operator room context")
	check(building.cutaway<0.01 and building.room.visible,"Explicit watch reveals the crew's room")
	check(world.get_node(world.MEMBERS[chosen]).visible,"Home crew remains visible in watched cutaway")
	check(world.hud.crew_strip.watching.text.contains("WATCHING"),"Watch mode is explicit in UI")
	check(world.snapshot==records and world.commands.payload.is_empty(),"Camera actions leave records and commands unchanged")
	world.stop_watching()
	for frame in range(90): await physics_frame
	check(building.cutaway>0.99 and world.watched_crew.is_empty(),"Returning to operator restores room visibility")
	world.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CREW_WATCH_PASSED: opt-in camera, home cutaway, visible actor, no teleport/dispatch and reversible view")
	quit(0 if failures.is_empty() else 1)
