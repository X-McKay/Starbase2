extends "res://shift_change_capture.gd"
## Isolated native acceptance: one ordinary minute, then retained evidence.
## Only the initial fixture setup changes actor positions. All later travel is physics.
var chosen: RefCounted
var operator_start := Vector3.ZERO
var prior_position := Vector3.ZERO
var prior_frame := 0
var continuous_samples: Array = []
var next_sample_ms := 0
var next_capture_ms := 15000
var physically_moving_frames := 0

func tick() -> bool:
	if not await super.tick(): return false
	if chosen == null: return true
	var actor: Node3D = chosen.actor
	var physics_frames := Engine.get_physics_frames()
	var elapsed := maxi(1, physics_frames-prior_frame)
	var displacement := actor.position.distance_to(prior_position)
	check(displacement <= 1.3*float(elapsed)/60.0+0.06, "Crew movement exceeds authored speed or teleports")
	if displacement > 0.005: physically_moving_frames += 1
	prior_position = actor.position
	prior_frame = physics_frames
	check(scene.get_node("Operator").position.distance_to(operator_start)<0.01, "Observation/evidence must not move the operator")
	var wall := Time.get_ticks_msec()-started
	if wall >= next_sample_ms:
		continuous_samples.append({"wall_ms":wall, "crew_position":str(actor.position), "camera_focus":str(scene.camera_focus), "clip":actor.model_visual.clip,
			"state":chosen.intent.get("backend_state"), "goal":chosen.intent.get("goal"), "watched":scene.watched_crew})
		next_sample_ms = wall+1000
	if wall >= next_capture_ms and wall <= 65000:
		await picture("minute-%02d"%int(next_capture_ms/1000))
		next_capture_ms += 15000
	return true

func picture(name: String) -> void:
	# Let newly opened native controls complete layout before forced rendering.
	await tree.process_frame
	await tree.process_frame
	await super.picture(name)

func keyboard(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	# Same public input handler, directly invoked because native review isolates
	# incidental operator keyboard input. No global input injection is used.
	scene._unhandled_key_input(event)

func record(id: String, state: String) -> Dictionary:
	var result := super.record(id, state)
	result.input.target = "morning-offline-repository"
	result.detail = "ISOLATED FIXTURE · ordinary morning acceptance"
	if state == "completed":
		result.report = {"findings":[], "coverage":[], "memory":{"status":"disabled"}, "advisory":{"status":"not_requested"}}
		result.snapshot = {"data":{"simulation":true}, "source_observed_at":observation}
	return result

func run(host: SceneTree, world: Node3D, directory: String, _mode: String = "morning") -> void:
	tree = host; scene = world; output = directory; started = Time.get_ticks_msec()
	observation = Time.get_unix_time_from_system()+10
	if scene.fixture_path.is_empty() or scene.hud.board.fixture.is_empty() or not scene.capture_input_isolated:
		push_error("Morning capture requires isolated world, board and input fixtures")
		tree.quit(1); return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create morning capture output"); tree.quit(1); return
	var watchdog := tree.create_timer(179.0)
	watchdog.timeout.connect(func():
		if not stopped:
			check(false, "Morning capture watchdog expired")
			finish("morning"))
	var anchors: Array = load("res://shift_change_anchors.gd").collect(scene)
	var by_id: Dictionary = {}
	for anchor in anchors: by_id[anchor.id] = anchor
	var homes := ["GalleyConversation", "LoungeConversation", "QuietReader", "GardenWest", "DoorwayPause"]
	check(homes.all(func(id):return by_id.has(id)), "Morning requires all five initial home anchors")
	if not failures.is_empty(): finish("morning"); return
	var index := 0
	for kind in scene.crew_motions:
		var motion: RefCounted = scene.crew_motions[kind]
		motion.release_anchor()
		var anchor: Dictionary = by_id[homes[index]]
		motion.configure_home(kind, [anchor], motion.rooms, {})
		motion.actor.position = anchor.position+Vector3(0, 0, 1)
		motion.intent = {}; motion.destination = Vector3(INF, 0, 0); motion.path.clear()
		index += 1
	project([])
	scene.enter_room("Habitat") # Explicit initial operator/camera staging only.
	operator_start = scene.get_node("Operator").position
	chosen = scene.crew_motions.reviewer
	prior_position = chosen.actor.position; prior_frame = Engine.get_physics_frames()
	for step in range(360):
		if not await tick(): finish("morning"); return
		if chosen.actor.model_visual.clip == "social/seated": break
	check(chosen.actor.model_visual.clip == "social/seated", "Crew physically settles into a real seat")
	await picture("01-inhabited-habitat"); sample("home", chosen)
	keyboard(KEY_V)
	check(scene.morning_director.enabled, "V starts opt-in colony observation")
	for step in range(120):
		if not await tick(): finish("morning"); return
	var task := "morning-acceptance-long"
	project([record(task, "running")])
	for step in range(48):
		if not await tick(): finish("morning"); return
		sample("departure", chosen)
		if step in [8, 24, 40]: await picture("02-standing-%02d"%step)
	check(samples.any(func(value):return str(value.clip) == "social/stand_up"), "Assignment visibly interrupts seating with stand-up")
	var departed: Vector3 = chosen.actor.position
	while chosen.actor.presentation_pose != "console":
		if not await tick(): finish("morning"); return
		if chosen.route_blocked: check(false, "Physical morning workstation route blocked"); finish("morning"); return
	check(chosen.actor.position.distance_to(departed)>2, "Assigned crew physically traverses colony")
	check(chosen.actor.position.distance_to(chosen.workstation)<0.3, "Work gesture requires actual workstation arrival")
	for step in range(120):
		if not await tick(): finish("morning"); return
	sample("working", chosen); await picture("03-workstation")
	var slate = chosen.actor.model_visual.get("work_slate")
	if slate != null: check(slate.visible, "Station work uses the real held slate")
	# The isolated job remains running for a complete observation minute. This is
	# staged timing, not a measured real-backend work duration or productivity claim.
	while Time.get_ticks_msec()-started < 62000:
		if not await tick(): finish("morning"); return
	var terminal := record(task, "completed")
	scene.hud.board.fixture_details[task] = terminal.duplicate(true)
	project([terminal])
	check(chosen.intent.evidence_ready and chosen.intent.goal == "home", "Completion evidence appears immediately before the physical return")
	sample("result-ready", chosen); await picture("04-result-ready")
	keyboard(KEY_K)
	check(scene.hud.briefing.visible, "K opens the native historical briefing")
	check(not scene.morning_director.enabled, "Briefing returns camera control to the operator")
	for step in range(5):
		if not await tick(): finish("morning"); return
	check(scene.hud.briefing.summary.text.contains("HISTORICAL") and scene.hud.briefing.freshness.text.contains("FIXTURE"), "Briefing distinguishes historical fixture evidence")
	await picture("05-morning-briefing")
	var actions: Array = scene.hud.briefing.reports.find_children("*", "Button", true, false)
	check(not actions.is_empty(), "Briefing exposes focusable evidence action")
	if not actions.is_empty():
		actions[0].grab_focus()
		check(actions[0].has_focus(), "Evidence action accepts keyboard focus")
		actions[0].pressed.emit()
		check(scene.hud.board.selected == task, "Briefing opens the exact retained field record")
		check(scene.hud.board.visible and scene.hud.board.tabs.current_tab == 3, "Evidence remains inside native Command")
		await picture("06-retained-evidence")
	keyboard(KEY_ESCAPE)
	check(not scene.hud.is_open() and not scene.morning_director.enabled, "Escape closes native panels and observation")
	# Explicit watch follows the actual returning actor without another operator visit.
	scene.watch_crew("reviewer")
	while chosen.actor.model_visual.clip != "social/seated":
		if not await tick(): finish("morning"); return
		if chosen.route_blocked: check(false, "Physical morning home route blocked"); finish("morning"); return
	for step in range(120):
		if not await tick(): finish("morning"); return
	sample("home-again", chosen); await picture("07-home-again")
	project([record("morning-brief", "running"), terminal])
	for step in range(12):
		if not await tick(): finish("morning"); return
	project([record("morning-brief", "completed"), terminal])
	check(chosen.intent.evidence_ready and chosen.intent.goal == "home", "A fast result never waits for workstation arrival")
	scene.disconnected = true; scene.update_crew_presentation(); scene.show_mission()
	for step in range(5):
		if not await tick(): finish("morning"); return
	check(chosen.actor.motion.is_zero_approx() and chosen.actor.presentation_pose.is_empty(), "Disconnected presentation stops confident motion and work")
	keyboard(KEY_K)
	check(scene.hud.briefing.freshness.text.contains("OFFLINE / STALE"), "Historical reports remain available with stale caption")
	sample("offline", chosen); await picture("08-stale-briefing")
	scene.hud.large_text = true; scene.hud.scale_text()
	scene.hud.reduced = true; scene.apply_settings()
	var held: Vector3 = chosen.actor.position
	keyboard(KEY_ESCAPE); keyboard(KEY_V)
	for step in range(30):
		if not await tick(): finish("morning"); return
	check(chosen.actor.position.distance_to(held)<0.02, "Reduced motion holds crew without teleport")
	check(not scene.morning_director.enabled, "Reduced motion prevents automatic camera directing")
	keyboard(KEY_K)
	for step in range(5):
		if not await tick(): finish("morning"); return
	sample("reduced", chosen); await picture("09-reduced-large-text")
	project([terminal])
	check(chosen.intent.evidence_ready and chosen.intent.goal in ["home", "hold"], "Reconnect retains terminal result under reduced motion")
	sample("reconnected", chosen)
	check(physically_moving_frames>100, "The ordinary minute contains sustained actual locomotion")
	check(continuous_samples.size()>=55, "At least a minute of continuous native state is sampled")
	keyboard(KEY_ESCAPE); keyboard(KEY_I)
	check(scene.hud.station_records.visible,"I opens native records across every station role")
	check(scene.hud.station_records.model.reports.size()==1,"Station inspector includes the exact retained field record")
	await picture("10-station-records")
	tree.root.size=Vector2i(800,640); tree.root.content_scale_size=Vector2i(800,640)
	for step in range(5):
		if not await tick(): finish("morning"); return
	await picture("11-station-compact")
	var station_actions:Array=scene.hud.station_records.reports.find_children("*","Button",true,false)
	check(not station_actions.is_empty(),"Station records expose keyboard inspection")
	if not station_actions.is_empty():
		station_actions[0].grab_focus(); station_actions[0].pressed.emit()
		check(scene.hud.board.selected==task and scene.hud.board.visible,"Station evidence opens the exact field record inside Godot")
	keyboard(KEY_ESCAPE)
	tree.root.size=Vector2i(1280,800); tree.root.content_scale_size=Vector2i(1280,800)
	finish("morning")

func finish(mode: String) -> void:
	if stopped: return
	var commands_sent: bool = not scene.commands.payload.is_empty() or not scene.hud.board.commands.payload.is_empty() or not scene.hud.operations.commands.payload.is_empty()
	var http_idle: bool = scene.http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED and scene.hud.board.get_http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED and scene.hud.board.detail_http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED
	check(not commands_sent and http_idle, "Morning fixture cannot dispatch effects or live API requests")
	var evidence := FileAccess.open(output.path_join("minute-samples.json"), FileAccess.WRITE)
	if evidence != null: evidence.store_string(JSON.stringify({"fixture":true, "world_fixture":not scene.fixture_path.is_empty(), "board_fixture":not scene.hud.board.fixture.is_empty(), "commands_dispatched":commands_sent, "http_idle":http_idle, "fixture_memory_status":"disabled", "initial_setup_only_teleports":true, "operator_position":str(operator_start), "moving_frames":physically_moving_frames, "samples":continuous_samples}, "  "))
	super.finish(mode)
