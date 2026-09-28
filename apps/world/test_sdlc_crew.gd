extends SceneTree
const SdlcCrew=preload("res://sdlc_crew.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var idle=preload("res://crew_presentation.gd").new().update([],"repair",false,false,1)
	var mission={"id":"sdlc-test","input":{"id":"sdlc-test","repository":"x-mckay/algent"},"state":"implementing","updated_at":10,"policy_generation":1}
	var data={"schema_version":7,"verification_enabled":true,"missions":[mission],"enabled":true,"policy":{"enabled":true,"generation":1,"expires_at":Time.get_unix_time_from_system()+600}}
	assert(SdlcCrew.project({"schema_version":7,"enabled":true,"missions":[]},"repair",true,false,idle)==idle,"Policy alone does not make crew work")
	var intent=SdlcCrew.project(data,"repair",true,false,idle)
	assert(intent.pose=="console" and intent.goal=="workstation" and not intent.evidence_ready)
	assert(SdlcCrew.project(data,"reviewer",true,false,idle).goal=="hold","Unassigned reviewer waits")
	assert(SdlcCrew.project(data,"repair",false,false,idle).goal=="hold","Stale work does not animate")
	assert(SdlcCrew.project(data,"repair",true,true,idle).goal=="hold","Reduced motion holds")
	var concurrent:Dictionary=idle.duplicate(true); concurrent.active_count=1; concurrent.run_id="other"; concurrent.goal="workstation"; concurrent.task_markers=[{"run_id":"other","status":"active"}]
	var preserved=SdlcCrew.project(data,"reviewer",true,false,concurrent)
	assert(preserved.run_id=="other" and preserved.task_markers.size()==2,"A waiting teammate must not hide unrelated active work")
	for state in ["blocked","awaiting_review","submitted","publishing","cancel_requested"]:
		mission.state=state
		intent=SdlcCrew.project(data,"repair",true,false,idle)
		assert(intent.goal=="hold" and intent.pose=="" and not intent.evidence_ready,"No typing or celebration from waiting/publication")
	mission.state="implementing"; mission.cancel_requested=true
	intent=SdlcCrew.project(data,"repair",true,false,idle)
	assert(intent.goal=="hold" and intent.pose=="" and intent.backend_state=="cancel_requested","Cancellation boolean holds before worker changes stage")
	mission.cancel_requested=false
	for policy_state in ["disabled","expired","generation"]:
		data.policy.enabled=policy_state!="disabled"
		data.policy.expires_at=Time.get_unix_time_from_system()+(-1 if policy_state=="expired" else 600)
		data.policy.generation=2 if policy_state=="generation" else 1
		intent=SdlcCrew.project(data,"repair",true,false,idle)
		assert(intent.goal=="hold" and intent.pose=="" and intent.label.contains("authority hold"))
	data.policy={"enabled":true,"generation":1,"expires_at":Time.get_unix_time_from_system()+600}
	mission.state="investigating"
	assert(SdlcCrew.project(data,"review",true,false,idle).pose=="console")
	mission.state="testing"
	assert(SdlcCrew.project(data,"reviewer",true,false,idle).pose=="console")
	mission.state="awaiting_review"
	var verification={"id":"verify-1","input":{"id":"verify-1","head":"a".repeat(40)},"state":"verifying","policy_generation":1,"updated_at":20,"cancel_requested":false}
	mission.verifications=[verification]
	intent=SdlcCrew.project(data,"reviewer",true,false,idle)
	assert(intent.pose=="console" and intent.sdlc_verification_id=="verify-1" and intent.sdlc_mission_id=="sdlc-test")
	verification.state="repairing"
	assert(SdlcCrew.project(data,"repair",true,false,idle).pose=="console")
	assert(SdlcCrew.project(data,"reviewer",true,false,concurrent).run_id=="other")
	verification.cancel_requested=true
	assert(SdlcCrew.project(data,"repair",true,false,idle).goal=="hold")
	verification.cancel_requested=false
	assert(SdlcCrew.project(data,"repair",false,false,idle).unknown)
	assert(SdlcCrew.project(data,"repair",true,true,idle).pose=="")
	verification.policy_generation=0
	assert(SdlcCrew.project(data,"repair",true,false,idle).label.contains("authority hold"))
	verification.policy_generation=1
	data.verification_enabled=false
	assert(SdlcCrew.project(data,"repair",true,false,idle).label.contains("authority hold"))
	data.verification_enabled=true
	for stage in ["verified","reviewing","ready_to_update","updating","completed","blocked"]:
		verification.state=stage
		intent=SdlcCrew.project(data,"reviewer",true,false,idle)
		assert(intent.pose=="" and not intent.evidence_ready)
	verification.state="testing"
	var world=load("res://main.tscn").instantiate(); root.add_child(world); await process_frame
	world.poll_timer.stop(); world.http.cancel_request()
	var panel=world.hud.board.sdlc_missions; panel.fixture=true; panel.timer.stop(); panel.http.cancel_request()
	panel.snapshot=data; panel.online=true; panel.received_at_msec=Time.get_ticks_msec()
	world.receive_snapshot({"schema_version":2,"recent":[],"worker":{"available":true},"observed_at":Time.get_unix_time_from_system()})
	assert(world.crew_motions.reviewer.intent.pose=="console" and world.crew_motions.reviewer.intent.sdlc_mission_id=="sdlc-test")
	world.hud.open_place("reviewer")
	assert(world.hud.board.visible and world.hud.board.tabs.current_tab==5 and panel.selected=="sdlc-test","Crew inspection routes to its real V7 mission")
	panel.received_at_msec=Time.get_ticks_msec()-16000; world.update_crew_presentation()
	assert(world.crew_motions.reviewer.intent.unknown and world.crew_motions.reviewer.intent.goal=="hold")
	verification.state="completed"; panel.received_at_msec=Time.get_ticks_msec(); world.update_crew_presentation()
	assert(not world.crew_motions.reviewer.intent.evidence_ready and world.crew_motions.reviewer.intent.pose=="")
	world.queue_free(); await process_frame
	print("SDLC_CREW_PASSED: authoritative roles, waiting/stale/reduced hold, concurrent markers, no PR celebration, native crew inspection routing")
	quit()
