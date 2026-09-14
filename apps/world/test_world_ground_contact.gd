extends "res://capture_new_cast_contacts.gd"
var world:Node3D
var actor:Node3D
var failures:Array=[]
var measurements:Array=[]
func measure(label:String) -> void:
	visual=actor.model_visual
	var contact:Dictionary=points()
	measurements.append({"label":label,"position":str(actor.position),"surface_clearance":contact.surface_clearance,"clip":visual.clip,"lift":visual.position.y})
	if contact.surface_clearance<-.004:failures.append(label+": skin below actual support "+str(contact.surface_clearance))
func travel(target:Vector3,label:String) -> void:
	world.route=world.travel_route(target)
	if world.route.is_empty():failures.append(label+": route unavailable");return
	for tick in 900:
		await physics_frame
		await process_frame
		if tick%40==0:measure(label+"-"+str(tick))
		if world.route.is_empty():break
	for tick in 3:await physics_frame
	measure(label+"-stopped")
	if actor.position.distance_to(target)>.45:failures.append(label+": did not arrive")
func run() -> void:
	world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json";world.board_fixture="__empty_visual_fixture__"
	root.add_child(world);await process_frame
	actor=world.get_node("Operator");support_checker=world.support_surface.height_at
	for station in world.get_node("Structures").get_children():
		actor.position=station.return_position();actor.last_position=actor.position;actor.motion=Vector3.ZERO
		await physics_frame
		await travel(station.room.content.get_node("WalkTarget").global_position,str(station.name)+"-enter")
		await travel(station.return_position()+Vector3(0,0,3),str(station.name)+"-exit")
	var file=FileAccess.open("/tmp/starbase-world-ground.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"measurements":measurements,"failures":failures},"  "));file.close()
	for failure in failures:push_error(failure)
	print("WORLD_GROUND_CONTACT failures=",failures.size());world.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
