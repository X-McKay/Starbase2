extends SceneTree
const Actor=preload("res://actor.gd")
const Catalog=preload("res://characters/catalog.gd")
const Handoff=preload("res://crew_handoff.gd")
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var stage:=Node3D.new();root.add_child(stage)
	var giver=Actor.new();giver.character_definition=Catalog.get_definition("mender");stage.add_child(giver)
	var receiver=Actor.new();receiver.character_definition=Catalog.get_definition("reviewer");stage.add_child(receiver)
	await process_frame
	giver.set_physics_process(false);receiver.set_physics_process(false)
	giver.position=Handoff.WEST;receiver.position=Handoff.EAST
	giver.model_visual.exchange_partner=receiver;giver.model_visual.exchange_role="giver"
	receiver.model_visual.exchange_partner=giver;receiver.model_visual.exchange_role="receiver"
	for frame in range(90):
		giver.model_visual.project(Vector3.ZERO,false,0,false,1.0/60.0,"handoff",PI/2)
		receiver.model_visual.project(Vector3.ZERO,false,0,false,1.0/60.0,"handoff",-PI/2)
	var giver_driver=giver.model_visual.environment_interaction
	var receiver_driver=receiver.model_visual.environment_interaction
	print("HANDOFF_POSE_MEASUREMENTS ",JSON.stringify({"giver_unreachable":giver_driver.unreachable_targets,"receiver_unreachable":receiver_driver.unreachable_targets,"giver_error":giver_driver.contact_errors.get("handoff"),"receiver_error":receiver_driver.contact_errors.get("handoff"),"giver_lengths":giver_driver.lengths,"receiver_lengths":receiver_driver.lengths}))
	assert(giver_driver.state=="exchange" and receiver_driver.state=="exchange")
	assert(giver_driver.unreachable_targets.is_empty() and receiver_driver.unreachable_targets.is_empty())
	assert(giver_driver.contact_errors.handoff<.014 and receiver_driver.contact_errors.handoff<.014)
	assert(giver_driver.action=="handoff_give" and receiver_driver.action=="handoff_receive")
	giver.model_visual.project(Vector3.ZERO,false,0,true,1.0/60.0,"handoff",PI/2)
	assert(giver_driver.state=="neutral" and giver_driver.action=="neutral")
	print("CREW_HANDOFF_POSE_PASSED: two selected rigs meet one bounded token contact, gaze toward partner, reduced-motion reset")
	quit()
