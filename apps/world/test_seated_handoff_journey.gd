extends SceneTree
## Physical continuation from a seated Command shift into a recorded Commons handoff.
var failures:Array[String]=[]
func check(ok:bool,message:String) -> void:
	if not ok and not failures.has(message):failures.append(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json"
	world.board_fixture="__empty_visual_fixture__"
	root.add_child(world);await process_frame;await physics_frame
	world.isolate_capture_input()
	var panel=world.hud.board.sdlc_missions;panel.fixture=true;panel.timer.stop();panel.http.cancel_request()
	var mission={"id":"seated-handoff","input":{"id":"seated-handoff","repository":"X-McKay/algent"},"state":"testing","updated_at":1,"policy_generation":1,"events":[{"role":"lead","state":"investigating"},{"role":"implementer","state":"implementing"},{"role":"reviewer","state":"testing"}]}
	panel.snapshot={"schema_version":7,"verification_enabled":true,"missions":[mission],"enabled":true,"policy":{"enabled":true,"generation":1,"expires_at":Time.get_unix_time_from_system()+600}}
	panel.online=true;panel.received_at_msec=Time.get_ticks_msec()
	var reviewer=world.crew_motions.reviewer
	var mender=world.crew_motions.repair
	reviewer.actor.position=reviewer.workstation
	mender.actor.position=Vector3(-10.4,0,24.85)
	world.receive_snapshot({"schema_version":2,"recent":[],"worker":{"available":true},"observed_at":Time.get_unix_time_from_system()})
	check(not world.crew_handoff.active(),"Retained review stage does not replay a handoff")
	var seated:=false
	for tick in range(500):
		await physics_frame
		if reviewer.at_work_seat and reviewer.actor.presentation_pose=="sit" and reviewer.actor.model_visual.social_transition_finished:
			seated=true;break
	check(seated,"Prism physically settles into the authored chair before a new event")
	check(reviewer.actor.interaction_station!=null,"Fresh retained review activates seated workstation contact")
	mission.events.append({"role":"implementer","state":"repairing"});mission.state="implementing";mission.updated_at=2
	panel.received_at_msec=Time.get_ticks_msec();world.update_crew_presentation()
	check(world.crew_handoff.active(),"New reviewer-to-implementer event starts recorded presentation")
	check(reviewer.intent.goal=="handoff" and mender.intent.goal=="handoff","Both actual crew receive the physical rendezvous")
	check(reviewer.standing_from_work,"Prism must stand before leaving the occupied chair")
	var premature_motion:=false
	var departed:=false
	var exchanged:=false
	for tick in range(6000):
		await physics_frame
		if reviewer.standing_from_work and reviewer.actor.motion.length()>0.01:premature_motion=true
		if reviewer.actor.position.distance_to(reviewer.workstation)>0.5:departed=true
		if world.handoff_token.visible and reviewer.actor.presentation_pose=="handoff" and mender.actor.presentation_pose=="handoff":
			exchanged=true;break
	check(not premature_motion,"Departure waits for the seated body to stand")
	check(departed,"Prism physically travels from Command to Commons")
	check(exchanged,"Both crew arrive before the shared token is shown")
	check(reviewer.actor.position.distance_to(reviewer.destination)<.12 and mender.actor.position.distance_to(mender.destination)<.12,"Shared contact follows stopped arrivals")
	check(world.commands.payload.is_empty() and world.hud.board.commands.payload.is_empty(),"Presentation never dispatches work")
	world.queue_free();await process_frame
	for failure in failures:push_error(failure)
	if failures.is_empty():print("SEATED_HANDOFF_JOURNEY_PASSED: seated work, stand, Command-to-Commons route, two-crew contact, no dispatch")
	quit(0 if failures.is_empty() else 1)
