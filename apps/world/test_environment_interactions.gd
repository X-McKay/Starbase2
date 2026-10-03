extends SceneTree
## Real snapshot projection, five physical journeys, and environment-contact gates.
## Per-rig contact geometry/cadence is checked separately by the animation tests.
var failures:Array[String]=[]
var revision:=Time.get_unix_time_from_system()+1000.0
var world
var measurements:Dictionary={}
const SEATED_ROLES:=["watchkeeper","reviewer"]
var seat_phases:Dictionary={"watchkeeper":[],"reviewer":[]}
var foot_samples:Dictionary={}
var foot_metrics:Dictionary={}
var foot_failures:Dictionary={}

func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	if not ok and message not in failures:failures.append(message);printerr(message)
func frames(count:int)->void:
	for tick in range(count):
		await physics_frame
		await process_frame
func snapshot(state:String="running",available:bool=true)->Dictionary:
	revision+=1
	var data:Dictionary={"schema_version":2,"observed_at":revision,"worker":{"available":available},"recent":[],"active":[],"repairs":[],"field_runs":[]}
	for kind in ["review","evaluation"]:
		data.active.append({"input":{"request":{"id":"contact-"+kind,"kind":kind}},"state":state,"updated_at":revision})
	data.repairs.append({"input":{"id":"contact-repair","scenario":"clamp-v1"},"state":state,"updated_at":revision})
	for kind in ["reviewer","watchkeeper"]:
		data.field_runs.append({"input":{"id":"contact-"+kind,"agent":kind},"state":state,"updated_at":revision})
	if state=="completed":
		for key in ["active","repairs","field_runs"]:
			for record in data[key]:
				record.summary={"outcome":"no_change"}
				record.report={"summary":{"outcome":"no_change"},"findings":[],"coverage":[]}
	return data
func contact_driver(actor):return actor.model_visual.get("environment_interaction")
func observe_seating()->void:
	for kind in SEATED_ROLES:
		var actor=world.crew_motions[kind].actor;var visual=actor.model_visual
		if visual.clip not in seat_phases[kind]:seat_phases[kind].append(visual.clip)
		if visual.clip=="social/sit_down" or actor.presentation_pose=="stand":
			no_contact(actor,kind+" seating transition")
			check(actor.motion.is_zero_approx(),kind+": body transition cannot slide the navigation root")
		if visual.get("seat_alignment_offset")!=null:
			var offset:Vector3=visual.seat_alignment_offset
			check(offset.is_finite() and Vector2(offset.x,offset.z).length()<=.4501,kind+": bounded cosmetic seat alignment")
			if not actor.motion.is_zero_approx():
				check(Vector2(offset.x,offset.z).length()<.001,kind+": standing alignment restored before travel")
				check(world.interaction_stations[kind].folded_ready(),kind+": chair tray folded before physical departure")
		observe_seated_feet(kind,visual)
func observe_seated_feet(kind:String,visual)->void:
	var feet=visual.get("seated_footwork")
	if feet==null:return
	var frame:int=Engine.get_process_frames()
	if not foot_metrics.has(kind):foot_metrics[kind]={"planted_samples":0,"step_samples":0,"max_planted_drift":0.0,"min_clearance":INF,"max_planted_clearance":0.0,"max_reach_error":0.0}
	var metric:Dictionary=foot_metrics[kind]
	metric.max_reach_error=maxf(metric.max_reach_error,float(feet.maximum_reach_error))
	for side in feet.foot_phase:
		var key:String=kind+side;var phase:String=feet.foot_phase[side]
		var point:Vector3=feet.sole_points[side]
		var clearance:float=feet.sole_clearances[side]
		check(point.is_finite() and is_finite(clearance),key+": finite deformed sole evidence")
		metric.min_clearance=minf(metric.min_clearance,clearance)
		check(clearance>=-.002,key+": actual sole does not penetrate sampled floor")
		if clearance<-.002:foot_diagnostic(key+"-penetration",visual,feet,point,clearance,0.0)
		if phase=="planted":
			metric.planted_samples+=1;metric.max_planted_clearance=maxf(metric.max_planted_clearance,clearance)
			check(clearance<.015,key+": planted sole stays within 15 mm of floor")
			if clearance>=.015:foot_diagnostic(key+"-clearance",visual,feet,point,clearance,0.0)
			if foot_samples.has(key):
				var previous:Dictionary=foot_samples[key]
				if previous.frame==frame-1 and previous.phase=="planted":
					var drift:float=Vector2(point.x-previous.point.x,point.z-previous.point.z).length()
					metric.max_planted_drift=maxf(metric.max_planted_drift,drift)
					check(drift<=.005,key+": planted stable skin probe moves no more than 5 mm per frame")
					if drift>.005:foot_diagnostic(key+"-drift",visual,feet,point,clearance,drift)
		else:metric.step_samples+=1
		foot_samples[key]={"frame":frame,"phase":phase,"point":point}
func foot_diagnostic(key:String,visual,feet,point:Vector3,clearance:float,drift:float)->void:
	if foot_failures.has(key):return
	foot_failures[key]=true
	print("SEATED_FOOT_FAILURE ",key," ",JSON.stringify({"frame":Engine.get_process_frames(),"clip":visual.clip,"social_pose":visual.social_pose,"social_elapsed":visual.social_elapsed,"finished":visual.social_transition_finished,"heading":visual.rotation.y,"seat_offset":visual.seat_alignment_offset,"actor":visual.get_parent().global_position,"motion":visual.get_parent().motion,"point":point,"clearance":clearance,"drift":drift,"reach_error":feet.maximum_reach_error,"phases":feet.foot_phase,"starts":feet.starts,"goals":feet.goals}))
func seated_hold(label:String)->void:
	observe_seating()
	for kind in SEATED_ROLES:
		var actor=world.crew_motions[kind].actor;var visual=actor.model_visual
		check(actor.get("seating_station")==world.interaction_stations[kind],kind+" "+label+": occupied physical seat retained")
		check(actor.presentation_pose=="sit" and visual.clip=="social/seated" and visual.social_transition_finished,kind+" "+label+": settled seated body remains valid")
		check(actor.motion.is_zero_approx(),kind+" "+label+": no body travel")
		if visual.get("seat_reference_error")!=null:
			check(is_finite(float(visual.seat_reference_error)) and float(visual.seat_reference_error)<=.015,kind+" "+label+": settled authored seat reference within 15 mm")
func set_bridge_state(data:Dictionary,kind:String,state:String)->void:
	for record in data.field_runs:
		if record.input.agent==kind:record.state=state
func interrupt_partial_sit(kind:String)->void:
	var actor=world.crew_motions[kind].actor;var visual=actor.model_visual
	# Queued crew may sit quietly, so first leave this chair through its real departure.
	var data:Dictionary=snapshot("queued");set_bridge_state(data,kind,"cancelled")
	world.receive_snapshot(data)
	var left_chair:=false
	for tick in range(180):
		await frames(1);observe_seating();no_contact(actor,kind+" preparing reentry")
		if actor.position.distance_to(world.crew_motions[kind].workstation)>.4:
			left_chair=true;break
	check(left_chair,kind+": reentry begins after a real chair departure")
	data=snapshot("queued");set_bridge_state(data,kind,"running")
	world.receive_snapshot(data)
	var reached_partial:=false
	for tick in range(1800):
		await frames(1);observe_seating()
		if world.crew_motions[kind].route_blocked:break
		if visual.clip=="social/sit_down" and not visual.social_transition_finished:
			var duration:float=visual.animation.get_animation("social/sit_down").length
			if visual.social_elapsed>=duration*.35:
				reached_partial=true;break
	check(reached_partial,kind+": reentry reaches an actual partial seated transition")
	if not reached_partial:return
	var hips:int=visual.skeleton.find_bone("Hips")
	var prior_hips:Vector3=visual.skeleton.to_global(visual.skeleton.get_bone_global_pose(hips).origin)
	data=snapshot("queued");set_bridge_state(data,kind,"cancelled");world.receive_snapshot(data)
	check(world.crew_motions[kind].intent.backend_state=="cancelled",kind+": partial-sit cancellation is authoritative immediately")
	var saw_stand:=false;var departed:=false;var prior:Vector3=actor.position
	for tick in range(180):
		await frames(1);observe_seating();no_contact(actor,kind+" cancelled partial sit")
		if visual.clip=="social/stand_up":saw_stand=true
		var now_hips:Vector3=visual.skeleton.to_global(visual.skeleton.get_bone_global_pose(hips).origin)
		check(now_hips.distance_to(prior_hips)<.09,kind+": partial-sit reversal does not pop pelvis to upright")
		prior_hips=now_hips
		check(actor.position.distance_to(prior)<1.3/60.0+.015,kind+": partial-sit departure preserves physical root speed")
		prior=actor.position
		if not actor.motion.is_zero_approx():departed=true;break
	check(saw_stand and departed,kind+": partial sit reverses through standing before bounded departure")
func no_contact(actor,label:String)->void:
	var driver=contact_driver(actor)
	if driver==null:return
	for key in driver.contact_weights:
		check(is_zero_approx(float(driver.contact_weights[key])),label+": no "+str(key)+" contact")
func all_inactive(label:String,neutral:bool=false)->void:
	for kind in world.crew_motions:
		var actor=world.crew_motions[kind].actor
		check(actor.get("interaction_station")==null,kind+" "+label+": no eligible station binding")
		no_contact(actor,kind+" "+label)
		var driver=contact_driver(actor)
		if neutral and driver!=null:check(driver.state=="neutral",kind+" "+label+": neutral immediately")
	for station in world.interaction_stations.values():
		for value in station.active_weights.values():check(is_zero_approx(float(value)),label+": station feedback resets")
func run()->void:
	world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json"
	world.board_fixture="__empty_visual_fixture__"
	world.player_preferences_path=""
	root.add_child(world)
	await frames(3)
	world.isolate_capture_input()
	world.hud.reduced=false;world.apply_settings()
	var registry=world.get("interaction_stations")
	check(registry is Dictionary and registry.size()==5,"All five real crew need authored interaction stations")
	for pair in world.crew_pairs():check(contact_driver(pair[1])!=null,str(pair[0])+": environment contact driver configured")
	if not failures.is_empty():await finish();return
	for kind in registry:
		var support:float=world.support_surface.height_at(registry[kind].global_position)
		check(absf(registry[kind].global_position.y-support)<.001,kind+": station rests on the same sampled room floor as crew")
		var contacts:Dictionary=registry[kind].contacts()
		for key in ["left_key","right_key","screen","control"]:
			check(contacts.has(key) and contacts[key] is Transform3D and contacts[key].is_finite(),kind+": finite world contact "+key)
		measurements[kind]={"distance":0.0,"previous":world.crew_motions[kind].actor.position,"contacts":[],"states":[],"max_contact_error":0.0,"closest_errors":{}}
		if kind in SEATED_ROLES:
			check(registry[kind].has_method("seat") and registry[kind].has_method("approach_point"),kind+": real chair exposes seat and collision-safe approach")
			if registry[kind].has_method("seat"):
				var seat:Dictionary=registry[kind].seat()
				check(seat.has("frame") and seat.frame is Transform3D and seat.frame.is_finite() and seat.has("floor_y") and is_finite(float(seat.floor_y)),kind+": finite world cushion frame and floor datum")
			if registry[kind].has_method("approach_point"):
				check(registry[kind].approach_point().distance_to(world.crew_motions[kind].workstation)<.001,kind+": motion targets authored safe standing approach")
	var data:Dictionary=snapshot()
	var untouched:Dictionary=data.duplicate(true)
	world.receive_snapshot(data)
	for tick in range(5400):
		await frames(1)
		observe_seating()
		var arrived:=true
		for kind in world.crew_motions:
			var motion=world.crew_motions[kind];var actor=motion.actor;var sample:Dictionary=measurements[kind]
			var step:float=actor.position.distance_to(sample.previous)
			sample.distance+=step;sample.previous=actor.position
			check(step<1.3/60.0+.015,kind+": contact approach preserves bounded physical movement")
			if not motion.path.is_empty() or not actor.motion.is_zero_approx() or actor.position.distance_to(motion.workstation)>=.025:
				arrived=false
				check(actor.get("interaction_station")==null,kind+": travel cannot bind a station")
				no_contact(actor,kind+" travel")
		if arrived:break
	for kind in world.crew_motions:
		var motion=world.crew_motions[kind]
		check(measurements[kind].distance>.2,kind+": actually traveled from home")
		check(not motion.route_blocked and motion.path.is_empty() and motion.actor.motion.is_zero_approx() and motion.actor.position.distance_to(motion.workstation)<.025,kind+": physical stopped workstation arrival within 25 mm")
	# Sample the shared read/type/gesture loop without depending on an exact artistic cadence.
	for tick in range(600):
		await frames(1)
		observe_seating()
		for kind in world.crew_motions:
			var actor=world.crew_motions[kind].actor;var driver=contact_driver(actor);var sample:Dictionary=measurements[kind]
			var settling:bool=kind in SEATED_ROLES and not actor.model_visual.social_transition_finished
			if settling:no_contact(actor,kind+" settling at chair")
			else:check(actor.get("interaction_station")==registry[kind],kind+": settled working binds its own station")
			if kind not in SEATED_ROLES:check(actor.presentation_pose=="console",kind+": standing crew keep appropriate standing work")
			if driver.state not in sample.states:sample.states.append(driver.state)
			if driver.state=="type" and driver.blend>=1 and not sample.has("rig"):
				var visual=actor.model_visual
				var contacts:Dictionary=registry[kind].contacts()
				sample.rig={"left_shoulder":driver.bone("LeftArm").origin,"right_shoulder":driver.bone("RightArm").origin,"left_key":contacts.left_key.origin,"right_key":contacts.right_key.origin,"lengths":driver.lengths,"scale":visual.global_basis.get_scale(),"ground_clearance":visual.ground_clearance,"visual_y":visual.position.y,"station_origin":registry[kind].global_position,"actor_origin":actor.global_position}
				print("ARRIVED_CONTACT_GEOMETRY ",kind," ",JSON.stringify(sample.rig))
			for key in driver.contact_errors:
				sample.closest_errors[key]=minf(float(sample.closest_errors.get(key,INF)),float(driver.contact_errors[key]))
			for key in driver.contact_weights:
				var weight:float=driver.contact_weights[key]
				check(is_finite(weight) and weight>=0 and weight<=1,kind+": finite bounded contact weight")
				if weight>0:
					if key not in sample.contacts:sample.contacts.append(key)
					check(driver.contact_errors.has(key),kind+": active contact has measured error")
					if driver.contact_errors.has(key):
						var error:float=driver.contact_errors[key]
						check(is_finite(error) and error<=.0091,kind+": feedback requires physical contact within 9 mm")
						sample.max_contact_error=maxf(sample.max_contact_error,error)
	for kind in measurements:
		for key in ["left_key","right_key"]:
			check(key in measurements[kind].contacts,kind+": arrived typing makes physical "+key+" contact")
	for kind in SEATED_ROLES:
		check("social/sit_down" in seat_phases[kind] and "social/seated" in seat_phases[kind],kind+": actual arrival leads through sitting transition to seated work")
		var visual=world.crew_motions[kind].actor.model_visual
		check(visual.get("seat_alignment_offset")!=null and visual.get("seat_reference_error")!=null,kind+": seated alignment is inspectable separately from skin audit")
		if visual.get("seat_reference_error")!=null:measurements[kind].seat_reference_error=visual.seat_reference_error
	seated_hold("active work")
	check(data==untouched,"Animation does not mutate authoritative snapshot records")
	# Invalidate work from authoritative state; no gesture may imply activity afterward.
	for state in ["queued","cancel_requested","unknown"]:
		world.receive_snapshot(snapshot(state));await frames(3);all_inactive(state);seated_hold(state)
	world.receive_snapshot(snapshot("running",false));await frames(3);all_inactive("stale worker");seated_hold("stale worker")
	world.receive_snapshot(snapshot());await frames(3)
	seated_hold("reconnected without replaying sit")
	world.disconnected=true;world.show_mission();await frames(3);all_inactive("disconnected");seated_hold("disconnected")
	world.receive_snapshot(snapshot());await frames(3)
	world.hud.reduced=true;world.apply_settings();await frames(3);all_inactive("reduced motion",true);seated_hold("reduced motion")
	world.hud.reduced=false;world.apply_settings();await frames(3)
	# A blocked final approach cannot authorize contact even inside arrival radius.
	for motion in world.crew_motions.values():motion.route_blocked=true;motion.path.clear()
	await frames(3);all_inactive("blocked final approach");seated_hold("blocked occupied seat")
	# Terminal records take effect immediately, while body-only standing is allowed to finish.
	world.receive_snapshot(snapshot("cancelled"))
	for kind in SEATED_ROLES:check(world.crew_motions[kind].intent.backend_state=="cancelled",kind+": cancellation is visible before stand animation completes")
	for tick in range(100):
		await frames(1);observe_seating();all_inactive("cancelled departure")
	for kind in SEATED_ROLES:check("social/stand_up" in seat_phases[kind],kind+": occupied chair departure uses standing transition")
	world.receive_snapshot(snapshot("failed"));await frames(3);all_inactive("failed")
	for kind in SEATED_ROLES:await interrupt_partial_sit(kind)
	world.receive_snapshot(snapshot("completed"))
	var home_arrivals:Dictionary={}
	for tick in range(7200):
		await frames(1)
		observe_seating()
		all_inactive("completed return")
		for kind in world.crew_motions:
			var motion=world.crew_motions[kind]
			if not home_arrivals.has(kind) and not motion.anchor.is_empty() and motion.path.is_empty() and motion.actor.motion.is_zero_approx() and motion.actor.position.distance_to(motion.destination)<.15:
				home_arrivals[kind]=motion.anchor.id
		if home_arrivals.size()==5:break
	check(home_arrivals.size()==5,"All five crew physically return to authored homes")
	check(world.commands.payload.is_empty() and world.commands.phase.is_empty(),"Environment interaction never dispatches a command")
	check(world.hud.board.commands.payload.is_empty(),"Environment interaction never dispatches field work")
	check(world.http.get_http_client_status()==HTTPClient.STATUS_DISCONNECTED,"Fixture test never makes a live snapshot request")
	for kind in SEATED_ROLES:
		check(foot_metrics.has(kind) and foot_metrics[kind].planted_samples>0 and foot_metrics[kind].step_samples>0,kind+": actual lifted adjustment and planted soles observed")
	print("ENVIRONMENT_INTERACTION_MEASUREMENTS ",JSON.stringify(measurements))
	print("ENVIRONMENT_SEAT_PHASES ",JSON.stringify(seat_phases))
	print("ENVIRONMENT_SEATED_FEET ",JSON.stringify(foot_metrics))
	await finish()
func finish()->void:
	world.queue_free();await process_frame
	if not failures.is_empty():print("ENVIRONMENT_INTERACTION_FAILURES ",JSON.stringify(failures))
	print("ENVIRONMENT_INTERACTIONS_PASSED" if failures.is_empty() else "ENVIRONMENT_INTERACTIONS_FAILED")
	quit(0 if failures.is_empty() else 1)
