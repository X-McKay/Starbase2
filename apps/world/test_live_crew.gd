extends SceneTree
## Actual five-actor physics against the authored world, with fixture-only connection.
var failures: Array[String]=[]
func check(ok:bool,message:String) -> void:
	if not ok and not failures.has(message): failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json"
	world.board_fixture="__empty_visual_fixture__"
	root.add_child(world)
	await process_frame
	await physics_frame
	for i in range(120): await physics_frame
	var operator_start:Vector3=world.get_node("Operator").position
	var camera_start:Vector3=world.camera.position
	var command=world.crew_motions.reviewer.station
	var crew_opened_airlock:=false
	var data={"schema_version":2,"observed_at":Time.get_unix_time_from_system()+1,"worker":{"available":true},"recent":[],"active":[],"repairs":[{"input":{"id":"crew-repair","scenario":"clamp-v1"},"state":"executing","updated_at":1}],"field_runs":[]}
	for kind in ["review","evaluation"]:
		data.active.append({"input":{"request":{"id":"crew-"+kind,"kind":kind}},"state":"running","updated_at":1})
	for kind in ["reviewer","watchkeeper"]:
		data.field_runs.append({"input":{"id":"crew-"+kind,"agent":kind},"state":"running","updated_at":1})
	var previous:Dictionary={}
	var distance:Dictionary={}
	for kind in world.crew_motions:
		var motion=world.crew_motions[kind]
		previous[kind]=motion.actor.position; distance[kind]=0.0
		if kind in ["reviewer","watchkeeper"]:
			check(not motion.station.contains(motion.actor.position),kind+" begins outside Command")
	world.receive_snapshot(data)
	for kind in world.crew_motions:
		check(not world.crew_motions[kind].path.is_empty(),kind+" initial physical route exists")
	for tick in range(5400):
		await physics_frame
		if command.openness>0.8:
			crew_opened_airlock=true
			check(command.cutaway>0.999 and not command.room.visible,"NPC airlock entry keeps operator-only room cutaway closed")
			check(world.active_room==null,"NPC room entry does not move operator room context")
			check(world.camera.position.distance_to(camera_start)<0.05,"NPC room entry does not redirect operator camera")
			check(world.get_node("Operator").position.is_equal_approx(operator_start),"NPC travel never moves operator")
		var all_arrived:=true
		for kind in world.crew_motions:
			var m=world.crew_motions[kind]
			var traveled:float=m.actor.position.distance_to(previous[kind])
			check(traveled<=1.3/60.0+0.015,kind+" moves continuously within crew speed")
			distance[kind]+=traveled;previous[kind]=m.actor.position
			if m.actor.presentation_pose!="console": all_arrived=false
			else: check(m.actor.position.distance_to(m.workstation)<0.3,kind+" poses only at workstation")
		if all_arrived: break
	for kind in world.crew_motions:
		var m=world.crew_motions[kind]
		print("CREW_ARRIVAL ",kind," distance=",m.actor.position.distance_to(m.workstation)," traveled=",distance[kind]," path=",m.path.size()," stalled=",m.stalled)
		check(distance[kind]>0.2,kind+" actually traveled")
		check(m.actor.position.distance_to(m.workstation)<0.3,kind+" reached authored workstation")
		check(m.actor.motion.length()<0.01 and m.actor.presentation_pose=="console",kind+" arrived stopped in work pose")
	check(crew_opened_airlock,"Outside Command crew physically open their airlock")
	world.hud.reduced=true;world.apply_settings()
	await physics_frame;await physics_frame
	for m in world.crew_motions.values():
		check(m.actor.motion.is_zero_approx() and m.actor.presentation_pose.is_empty(),"Reduced motion holds all actors without work pose")
	world.hud.reduced=false;world.apply_settings()
	await physics_frame;await physics_frame
	world.disconnected=true;world.show_mission()
	await physics_frame;await physics_frame
	for m in world.crew_motions.values():
		check(m.actor.motion.is_zero_approx() and m.actor.presentation_pose.is_empty(),"Outage holds all actors")
		check(m.intent.label.begins_with("Unknown"),"Outage retains explicit unknown state")
	data.observed_at+=1
	for key in ["active","repairs","field_runs"]:
		for run_record in data[key]:
			run_record.state="completed";run_record.updated_at=2
			run_record.summary={"outcome":"no_change"}
			run_record.report={"summary":{"outcome":"no_change"},"findings":[],"coverage":[]}
	world.receive_snapshot(data)
	for m in world.crew_motions.values():
		check(m.intent.goal=="home" and m.intent.evidence_ready,"Completion exposes evidence immediately and returns home")
	var home_arrivals:Dictionary={}
	for tick in range(7200):
		await physics_frame
		for kind in world.crew_motions:
			var m=world.crew_motions[kind]
			if not home_arrivals.has(kind) and not m.anchor.is_empty() and m.path.is_empty() and m.actor.motion.is_zero_approx() and m.actor.position.distance_to(m.destination)<0.15:
				home_arrivals[kind]={"anchor":m.anchor.id,"distance":m.actor.position.distance_to(m.destination)}
		if home_arrivals.size()==world.crew_motions.size(): break
	var occupied:Dictionary={}
	for kind in world.crew_motions:
		var m=world.crew_motions[kind]
		print("CREW_HOME ",kind," first_stopped_arrival=",home_arrivals.get(kind,{})," blocked=",m.route_blocked)
		check(home_arrivals.has(kind) and not m.route_blocked,kind+" returned physically to authored home")
		check(not occupied.has(m.anchor.get("id","")),kind+" reserves distinct home anchor")
		occupied[m.anchor.get("id","")]=true
	check(world.commands.payload.is_empty() and world.commands.phase.is_empty(),"Crew presentation never issues a command")
	check(world.http.get_http_client_status()==HTTPClient.STATUS_DISCONNECTED,"Fixture world makes no live snapshot request")
	check(world.hud.board.commands.payload.is_empty(),"Board fixture never dispatches")
	world.queue_free();await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("LIVE_CREW_PASSED: five home/work/home routes, reservations, speed/arrival/pose, Command exterior entry, reduced/outage and no dispatch")
	quit(0 if failures.is_empty() else 1)
