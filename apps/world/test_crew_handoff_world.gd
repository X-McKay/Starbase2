extends SceneTree
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var world=load("res://main.tscn").instantiate();root.add_child(world);await process_frame;await physics_frame
	world.poll_timer.stop();world.http.cancel_request();world.isolate_capture_input()
	var panel=world.hud.board.sdlc_missions;panel.fixture=true;panel.timer.stop();panel.http.cancel_request()
	var mission={"id":"handoff-world","input":{"id":"handoff-world","repository":"X-McKay/algent"},"state":"testing","updated_at":1,"policy_generation":1,"events":[{"role":"lead","state":"investigating"},{"role":"implementer","state":"implementing"}]}
	var data={"schema_version":7,"verification_enabled":true,"missions":[mission],"enabled":true,"policy":{"enabled":true,"generation":1,"expires_at":Time.get_unix_time_from_system()+600}}
	panel.snapshot=data;panel.online=true;panel.received_at_msec=Time.get_ticks_msec()
	world.receive_snapshot({"schema_version":2,"recent":[],"worker":{"available":true},"observed_at":Time.get_unix_time_from_system()})
	assert(not world.crew_handoff.active(),"Existing handoff history stays still on first observation")
	# Preserve a real NavigationAgent journey without making the focused test cross the entire base.
	world.get_node("Mender").position=Vector3(-10.4,0,24.85)
	world.get_node("Reviewer").position=Vector3(-3.6,0,24.85)
	mission.events.append({"role":"reviewer","state":"testing"});mission.updated_at=2;panel.received_at_msec=Time.get_ticks_msec();world.update_crew_presentation()
	assert(world.crew_handoff.active())
	assert(world.crew_motions.repair.intent.goal=="handoff" and world.crew_motions.reviewer.intent.goal=="handoff")
	var shown:=false
	for tick in range(1500):
		await physics_frame
		if world.handoff_token.visible and world.get_node("Mender").presentation_pose=="handoff" and world.get_node("Reviewer").presentation_pose=="handoff":shown=true;break
	assert(shown,"Both assigned crew physically arrive before the recorded token appears")
	assert(world.crew_motions.repair.actor.position.distance_to(world.crew_motions.repair.destination)<.12)
	assert(world.crew_motions.reviewer.actor.position.distance_to(world.crew_motions.reviewer.destination)<.12)
	assert(world.commands.payload.is_empty() and world.hud.board.commands.payload.is_empty(),"Handoff presentation never dispatches work")
	world.hud.reduced=true;world.apply_settings();await physics_frame;await process_frame
	assert(not world.crew_handoff.active() and not world.handoff_token.visible,"Reduced motion immediately clears the exchange")
	assert(world.crew_motions.repair.intent.goal=="hold" and world.crew_motions.reviewer.intent.goal=="hold")
	world.queue_free();await process_frame
	print("CREW_HANDOFF_WORLD_PASSED: fresh event, two physical routes, shared contact token, no dispatch, reduced-motion clear")
	quit()
