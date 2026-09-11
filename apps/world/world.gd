extends Node3D
const StateView = preload("res://state.gd")
const HUD = preload("res://hud.gd")
const Navigation = preload("res://navigation.gd")
const Commands = preload("res://commands.gd")
const Art = preload("res://art.gd")
const ConnectionStatus = preload("res://connection_status.gd")
const CrewPresentation = preload("res://crew_presentation.gd")
const CrewMotion = preload("res://crew_motion.gd")
var crew_presentations:Dictionary={}
var crew_motions:Dictionary={}
var home_reservations:Dictionary={}
var watched_crew := ""
var life_ui_timer := 0.0
var connection_message:="Waiting for the Core snapshot"
var poll_timer:Timer
const LivingCommons = preload("res://living_commons.gd")
var http := HTTPRequest.new()
var api := "http://127.0.0.1:8787"
var decorative_vents: Array[Node3D] = []
var hud: CanvasLayer
var commands: Node
var camera := Camera3D.new()
var navigator := Navigation.new()
var route := PackedVector3Array()
var missions: Array = []
var disconnected := true
var last_received := 0
var snapshot: Dictionary = {}
var live_reviewer:RefCounted
var live_capture_directory := ""
var capture_path := ""
var capture_frames := 180
var frame_times: Array[float] = []
var frame_count := 0
var first_frame_ms := 0
var compact := false
var inspect_on_start := false
var initial_crew := "repair"
var fixture_path := ""
var capture_input_isolated := false
var walk_test := false
var walk_reached := false
var overview := Vector3(0,0,0)
var camera_focus := Vector3.ZERO
var camera_offset := Vector3(10,36,46)
const TRAVEL_SPEED := 6.0
var zoom := 34.0
var zoom_factor := 1.0
var colony_overview := false
var colony_walk_test := false
var walk_destination := Vector3(-7,0,1.4)
var uptime := 0.0
var nearest := ""
var marker: MeshInstance3D
var trophies: Array[MeshInstance3D] = []
var test_command := ""
var board_fixture := ""
var board_on_start := false
var board_tab := 0
var board_evidence := ""
var foley: Node
var large_on_start := false
var reduced_on_start := false
var directory_on_start := false
var pending_selection_id := ""
var initial_xp := -1
var award_notice := ""
var active_room: Node3D
var room_environment := Environment.new()
var sky_layer: CanvasLayer
var room_kind := ""
var room_on_start := ""
var near_door := ""
var crew_return := Vector3.ZERO
var room_return := Vector3.ZERO
var frame_usec := 0
const Room = preload("res://colony_room.gd")
const Structures = preload("res://structure_catalog.gd")
var STATIONS: Dictionary = Structures.station_paths()
var active_building: Node3D
const MEMBERS := {"repair":"Mender", "review":"Surveyor", "gym":"Trainer", "watchkeeper":"Watchkeeper", "reviewer":"Reviewer"}

func crew_pairs() -> Array:
	return MEMBERS.keys().map(func(kind): return [kind,get_node(MEMBERS[kind])])

func setup_crew_presentation() -> void:
	var anchors:=collect_home_anchors()
	home_reservations.clear()
	for pair in crew_pairs():
		var kind:String=pair[0]
		var station=get_node(STATIONS.get(kind,STATIONS["review"]))
		var point:Vector3=station.room.to_global(station.room.crew_point)
		if kind=="reviewer": point=station.room.to_global(Vector3(-3.0,0,-6.5))
		if kind=="watchkeeper": point=station.room.to_global(Vector3(3.0,0,-6.5))
		var controller:=CrewPresentation.new()
		var motion:=CrewMotion.new()
		motion.configure(pair[1],navigator,station,point)
		motion.configure_home(kind,anchors,$Structures.get_children(),home_reservations)
		if not anchors.is_empty():
			motion.project({"goal":"home"})
			pair[1].position=motion.destination
			pair[1].home=motion.destination
			motion.previous=motion.destination
			motion.path.clear()
		crew_presentations[kind]=controller
		crew_motions[kind]=motion

func collect_home_anchors() -> Array:
	return preload("res://shift_change_anchors.gd").collect(self)

func duty_state_for(kind:String) -> Dictionary:
	if disconnected or not hud.board.online: return {}
	var data:Dictionary=hud.board.snapshot
	var seen:=float(data.get("observed_at",0))
	if seen<=0 or Time.get_unix_time_from_system()-seen>5: return {}
	var agent: String={"reviewer":"reviewer","watchkeeper":"watchkeeper"}.get(kind,"")
	var relevant:Array=data.get("duties",[]).filter(func(d):return d.get("agent")==agent)
	if relevant.is_empty(): return {}
	return {"known":true,"enabled":relevant.any(func(d):return d.get("enabled",false))}

func update_crew_presentation() -> void:
	for kind in crew_presentations:
		var intent:Dictionary=crew_presentations[kind].update(missions,kind,disconnected,hud.reduced,float(snapshot.get("observed_at",0)),duty_state_for(kind))
		crew_motions[kind].project(intent)
		get_node(MEMBERS[kind]).project_assignment(intent,hud.large_text)
		if hud.crew_strip!=null: hud.crew_strip.project(kind,intent)

func watch_crew(kind:String) -> void:
	if not MEMBERS.has(kind): return
	watched_crew=kind
	colony_overview=false
	route.clear(); $Operator.motion=Vector3.ZERO
	hud.close_panels(); hud.crew_strip.set_watching(kind)

func stop_watching() -> void:
	watched_crew=""
	hud.crew_strip.set_watching("")

func command_unresolved() -> bool:
	return commands.phase!="" or commands.uncertain or hud.board.commands.phase!="" or hud.board.commands.uncertain or hud.operations.unresolved()

func refresh_connection_panel() -> void:
	if hud.connection_panel==null or commands==null: return
	hud.connection_panel.refresh(api,snapshot,disconnected,not fixture_path.is_empty(),last_received,connection_message,command_unresolved())


func connect_to_core(endpoint:String) -> void:
	if not Commands.local_origin(endpoint) or command_unresolved():
		hud.connection_panel.feedback.text="Resolve pending commands before changing the local Core address."
		return
	http.cancel_request()
	api=endpoint; fixture_path=""; board_fixture=""
	snapshot={}; missions=[]; disconnected=true; last_received=0
	initial_xp=-1; pending_selection_id=""; hud.selected_id=""
	commands.api=api; hud.api=api
	hud.operations.configure(api,"")
	if hud.board.has_method("set_api"): hud.board.set_api(api)
	else:
		hud.board.get_http.cancel_request(); hud.board.detail_http.cancel_request()
		hud.board.api=api; hud.board.commands.api=api; hud.board.fixture=""
		hud.board.snapshot={}; hud.board.online=false; hud.board.signature=""
	for kind in crew_presentations: crew_presentations[kind]=CrewPresentation.new()
	connection_message="Connecting to "+api
	hud.connection_panel.feedback.text=connection_message
	hud.connection.text=connection_message
	show_mission()
	poll_timer.start()
	poll()

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--live-capture="): live_capture_directory=arg.trim_prefix("--live-capture=")
		if arg.begins_with("--capture="): capture_path = arg.trim_prefix("--capture=")
		if arg.begins_with("--api="): api = arg.trim_prefix("--api=").trim_suffix("/")
		if arg.begins_with("--frames="): capture_frames = maxi(60,int(arg.trim_prefix("--frames=")))
		if arg.begins_with("--fixture="): fixture_path = arg.trim_prefix("--fixture=")
		if arg.begins_with("--board-tab="): board_tab=int(arg.trim_prefix("--board-tab="))
		if arg.begins_with("--board-evidence="): board_evidence=arg.trim_prefix("--board-evidence=")
		if arg=="--board": board_on_start=true
		if arg.begins_with("--board-fixture="): board_fixture=arg.trim_prefix("--board-fixture=")
		if arg.begins_with("--test-command="): test_command = arg.trim_prefix("--test-command=")
		if arg.begins_with("--room="): room_on_start=arg.trim_prefix("--room=")
		if arg == "--inspect": inspect_on_start = true
		if arg.begins_with("--crew=") and MEMBERS.has(arg.trim_prefix("--crew=")): initial_crew=arg.trim_prefix("--crew=")
		if arg == "--compact": compact = true
		if arg == "--walk-test": walk_test = true
		if arg == "--cliff-walk-test":
			walk_test = true
			walk_destination = Vector3(0,0,27)
		if arg == "--surface-walk-test":
			walk_test = true
			walk_destination = Vector3(21,0,-16)
		if arg == "--colony-overview": colony_overview = true
		if arg == "--colony-walk-test":
			walk_test = true
			colony_walk_test = true
			walk_destination = Vector3(-24,0,15)
		if arg == "--large-text": large_on_start = true
		if arg == "--reduced-motion": reduced_on_start = true
		if arg == "--directory": directory_on_start = true
	var package_capture_directory := ""
	var shift_capture_directory := ""
	var shift_capture_mode := "domestic"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-package="): package_capture_directory=arg.trim_prefix("--capture-package=")
		if arg.begins_with("--shift-change-capture="): shift_capture_directory=arg.trim_prefix("--shift-change-capture=")
		if arg.begins_with("--shift-change-mode="): shift_capture_mode=arg.trim_prefix("--shift-change-mode=")
	if not capture_path.is_empty() or not package_capture_directory.is_empty() or not live_capture_directory.is_empty() or not shift_capture_directory.is_empty():
		isolate_capture_input()
	if ("--verify-package" in OS.get_cmdline_user_args() or not package_capture_directory.is_empty() or not shift_capture_directory.is_empty()) and fixture_path.is_empty():
		push_error("Package verification requires an offline fixture")
		# These nodes are normally parented later in _ready; release on refusal.
		http.free(); camera.free()
		get_tree().quit(1)
		return
	if compact:
		get_window().content_scale_size = Vector2i(960,720)
		get_window().size = Vector2i(960,720)
	# A screen-space sky keeps scenery behind the real 3D scene at every zoom.
	var sky := CanvasLayer.new()
	sky_layer=sky
	sky.layer = -1
	add_child(sky)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://space.gdshader")
	backdrop.material = sm
	sky.add_child(backdrop)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = zoom
	camera.position = Vector3(10,36,46)
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34,-38,-8)
	sun.light_color = Color("f6d8b8")
	sun.light_energy = 0.48
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = room_environment
	room_environment.background_color=Color("0d1828")
	env.environment.background_mode = Environment.BG_CANVAS
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("97b3d8")
	env.environment.ambient_light_energy = 0.28
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var commons := LivingCommons.new()
	commons.name = "LivingCommons"
	add_child(commons)
	var room_sound := preload("res://room_ambience.gd").new()
	room_sound.name = "RoomAmbience"
	add_child(room_sound)
	marker = Art.cylinder(self,Vector3(0,0.07,0),0.24,0.025,"f5d295")
	marker.hide()
	# Cosmetic cabinet slots light only from the core's retained achievement list.
	Art.box(self,Vector3(-11,0.65,3),Vector3(0.9,1.3,0.45),"3a5263")
	for i in range(2):
		var trophy := Art.cylinder(self,Vector3(-11.2+i*0.4,1.40,3),0.12,0.24,"eac58d")
		trophy.hide()
		trophies.append(trophy)
	foley=preload("res://footfall.gd").new(); foley.actor=$Operator; add_child(foley)
	hud = HUD.new()
	hud.compact = compact
	hud.api=api; hud.board_fixture=board_fixture
	if not fixture_path.is_empty() and board_fixture.is_empty(): hud.board_fixture="__empty_visual_fixture__"
	add_child(hud)
	hud.place_selected.connect(func(_kind): show_mission())
	hud.selection_changed.connect(func(_id): show_mission())
	hud.connect_requested.connect(connect_to_core)
	hud.settings_changed.connect(apply_settings)
	hud.map_requested.connect(toggle_map)
	hud.zoom_requested.connect(adjust_zoom)
	hud.room_requested.connect(enter_room)
	hud.watch_requested.connect(watch_crew)
	hud.set_structures($Structures.get_children())
	for station in $Structures.get_children():
		var vent = preload("res://colony_vent.gd").attach(station)
		if vent != null: decorative_vents.append(vent)
	hud.exit_requested.connect(exit_room)
	hud.repair_requested.connect(launch_repair)
	hud.cancel_requested.connect(cancel_selected)
	commands = Commands.new()
	commands.api = api
	add_child(commands)
	commands.feedback.connect(func(message: String,pending: bool):
		hud.command_status.text = message
		hud.command_pending = pending
		show_mission())
	commands.accepted.connect(func(id: String): pending_selection_id=id; poll())
	add_child(http)
	http.timeout = 2.0
	http.max_redirects = 0
	http.body_size_limit = 4194304
	http.request_completed.connect(on_response)
	var timer := Timer.new()
	poll_timer=timer
	timer.wait_time = 1.0
	timer.timeout.connect(poll)
	add_child(timer)
	if fixture_path != "":
		var data = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
		if data is Dictionary: receive_snapshot(data)
		hud.connection.text = "VISUAL TEST FIXTURE · not live operational activity"
	else:
		timer.start()
		poll()
	# Crew inhabit their authored rooms; direct inspection remains available.
	for kind in ["repair","review","gym"]:
		var station=get_node(STATIONS[kind])
		if station.room!=null:
			var member=get_node(MEMBERS[kind])
			member.position=station.room.to_global(station.room.crew_point)
			member.home=member.position
	setup_crew_presentation()
	if inspect_on_start:
		hud.open_place(initial_crew)
		hud.evidence.visible = true
	if large_on_start:
		hud.large_text = true
		hud.scale_text()
	if reduced_on_start:
		hud.reduced = true
		apply_settings()
	if directory_on_start: hud.toggle_directory()
	if walk_test:
		route = navigator.route($Operator.position, walk_destination)
	if test_command != "":
		# Explicit QC opt-in only; never runs during normal startup.
		hud.open_place("repair")
		commands.submit("/v3/repairs",{"id":test_command,"scenario":"clamp-v1","mode":"control-good"},test_command)
	if not room_on_start.is_empty():
		enter_room(room_on_start)
		if inspect_on_start: hud.open_place(room_on_start)
	if board_on_start:
		hud.open_board()
		hud.board.tabs.current_tab=clampi(board_tab,0,3)
		if not board_evidence.is_empty(): hud.board.inspect(board_evidence)
	# Normal live launch enters the inhabited home. Explicit review/test journeys
	# keep their requested starting point and never acquire production data.
	if get_tree().current_scene==self and fixture_path.is_empty() and room_on_start.is_empty() and capture_path.is_empty() and live_capture_directory.is_empty() and not inspect_on_start and not board_on_start and not walk_test and not colony_overview:
		enter_room("habitat")
	show_mission()
	if not shift_capture_directory.is_empty():
		call_deferred("_capture_shift_change",shift_capture_directory,shift_capture_mode)
	elif not live_capture_directory.is_empty():
		call_deferred("_capture_live",live_capture_directory)
	elif "--verify-package" in OS.get_cmdline_user_args():
		call_deferred("_verify_package")
	elif not package_capture_directory.is_empty():
		call_deferred("_capture_package",package_capture_directory)

func _capture_shift_change(directory:String, mode:String) -> void:
	await preload("res://shift_change_capture.gd").new().run(get_tree(),self,directory,mode)

func _capture_live(directory:String) -> void:
	live_reviewer=preload("res://live_capture.gd").new()
	await live_reviewer.run(self,directory)

func _capture_package(directory:String) -> void:
	var capture=load("res://package_capture.gd").new()
	await capture.run(get_tree(),self,directory)

func _verify_package() -> void:
	var check=load("res://package_check.gd").new()
	await check.run(get_tree(),self)

func enter_room(kind: String) -> void:
	stop_watching()
	if kind in ["watchkeeper","reviewer"]: kind="review"
	var station: Node3D=get_node_or_null(STATIONS.get(kind,"Structures/"+kind))
	if station==null or station.definition.interior_scene.is_empty(): return
	if station.definition.seamless:
		$Operator.position=station.room.global_position+station.room.spawn_point
		$Operator.motion=Vector3.ZERO
		route.clear()
		marker.hide()
		hud.close_panels()
		colony_overview=false
		set_room_context(station)
		return
	if active_room != null: exit_room()
	route.clear()
	marker.hide()
	active_building=station
	room_kind=station.interaction_kind
	room_return=station.return_position()
	var member: Node3D=get_node(MEMBERS[room_kind]) if MEMBERS.has(room_kind) else null
	if member!=null: crew_return=member.position
	active_room=Room.new()
	active_room.definition=station.definition
	active_room.position=Vector3(0,0,120)
	add_child(active_room)
	$Operator.position=active_room.position+active_room.spawn_point
	foley.interior=true; foley.doorway()
	$Operator.motion=Vector3.ZERO
	if member!=null:
		member.position=active_room.position+active_room.crew_point
		member.motion=Vector3.ZERO
	colony_overview=false
	hud.close_panels()
	hud.room_exit.show()
	room_environment.background_mode=Environment.BG_COLOR
	sky_layer.hide()
	$Terrace.hide()
	camera_focus=active_room.position+Vector3(0,1,0)
	show_mission()

func set_room_context(station: Node3D) -> void:
	if active_building==station: return
	active_building=station
	active_room=station.room if station!=null else null
	room_kind=station.interaction_kind if station!=null else ""
	foley.interior=station!=null
	foley.doorway()
	hud.room_exit.visible=station!=null
	if station!=null: room_return=station.return_position()
	show_mission()

func exit_room() -> void:
	if active_room == null: return
	if active_room.definition.seamless:
		$Operator.position=room_return
		$Operator.motion=Vector3.ZERO
		route.clear()
		marker.hide()
		hud.close_panels()
		set_room_context(null)
		return
	if MEMBERS.has(room_kind):
		get_node(MEMBERS[room_kind]).position=crew_return
		get_node(MEMBERS[room_kind]).motion=Vector3.ZERO
	$Operator.position=room_return
	foley.interior=false; foley.doorway()
	$Operator.motion=Vector3.ZERO
	route.clear()
	marker.hide()
	remove_child(active_room)
	active_room.queue_free()
	active_room=null
	active_building=null
	room_kind=""
	hud.room_exit.hide()
	room_environment.background_mode=Environment.BG_CANVAS
	sky_layer.show()
	$Terrace.show()
	hud.close_panels()
	overview=room_return
	camera_focus=room_return

func adjust_zoom(direction: int) -> void:
	zoom_factor=clampf(zoom_factor*pow(1.2,direction),0.4,2.0)

func toggle_map() -> void:
	stop_watching()
	if active_room != null: exit_room()
	colony_overview=not colony_overview

func travel_route(destination: Vector3) -> PackedVector3Array:
	if active_room != null and not active_room.definition.seamless: return active_room.route($Operator.position,destination)
	return navigator.route($Operator.position,destination)

func apply_settings() -> void:
	for vent in decorative_vents: vent.reduced_motion = hud.reduced
	foley.enabled=hud.sound_enabled
	foley.reduced=hud.reduced
	$LivingCommons.set_reduced_motion(hud.reduced)
	update_ambience()
	$Terrace/PavingLights.reduced_motion = hud.reduced
	$Terrace/MineralBasin.reduced_motion = hud.reduced
	$Terrace/Landform.reduced_motion = hud.reduced
	for member in [$Operator]+MEMBERS.values().map(func(label): return get_node(label)):
		member.reduced_motion = hud.reduced
	if hud.reduced: hud.follow = false
	update_crew_presentation()

func launch_repair(scenario: String, mode: String) -> void:
	if disconnected or not fixture_path.is_empty() or not ConnectionStatus.enabled(snapshot,"repair") or (mode=="inference" and not ConnectionStatus.enabled(snapshot,"inference")):
		hud.command_status.text="Practice unavailable · "+ConnectionStatus.reason(snapshot,"repair")
		return
	var id := "world-" + Crypto.new().generate_random_bytes(12).hex_encode()
	commands.submit("/v3/repairs",{"id":id,"scenario":scenario,"mode":mode},id)

func update_ambience() -> void:
	var in_garden := LivingCommons.FOOTPRINT.has_point(Vector2($Operator.position.x,$Operator.position.z))
	$RoomAmbience.configure(str(active_building.definition.id) if active_building!=null else "",in_garden,hud.sound_enabled)

func cancel_selected() -> void:
	if disconnected or not fixture_path.is_empty(): return
	var m := selected_mission()
	if m.is_empty(): return
	var prefix := "/v3/repairs/" if m["input"].get("kind") == "repair" else "/v2/runs/"
	if m["input"].get("kind") in ["watchkeeper","reviewer"]: prefix="/v4/runs/"
	commands.submit(prefix+hud.selected_id+"/cancel",{},hud.selected_id)

func poll() -> void:
	if fixture_path != "" or http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED: return
	if http.request(api+"/v2/snapshot") != OK:
		disconnected = true
		connection_message="Core unavailable at "+api+". Open Connection [O] for setup."
		hud.connection.text = "DISCONNECTED · last-known records only"
		show_mission()

func on_response(result: int, response: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response != 200:
		disconnected = true
		connection_message="Core unavailable at "+api+". Open Connection [O] for setup."
		hud.connection.text = "DISCONNECTED · last-known records only"
		show_mission()
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not ConnectionStatus.valid(data):
		disconnected = true
		connection_message="UNKNOWN · unsupported snapshot"
		hud.connection.text = connection_message
		show_mission()
		return
	receive_snapshot(data)

func receive_snapshot(data: Dictionary) -> void:
	disconnected = false
	last_received = Time.get_ticks_msec()
	snapshot = data
	connection_message="Observed "+Time.get_datetime_string_from_unix_time(int(data.get("observed_at",0))).replace("T"," ")+" UTC"
	missions = StateView.project(data)
	if pending_selection_id != "" and missions.any(func(m): return m["input"]["id"] == pending_selection_id):
		hud.selected_id = pending_selection_id
		pending_selection_id = ""
	hud.connection.text = ConnectionStatus.headline(snapshot,disconnected,not fixture_path.is_empty())
	show_mission()

func selected_mission() -> Dictionary:
	for m in missions:
		if m["input"]["id"] == hud.selected_id: return m
	return {}

func show_mission() -> void:
	if hud == null: return
	hud.update_list(missions)
	hud.operations.update_snapshot(snapshot,disconnected,commands.phase!="" or commands.uncertain or hud.board.commands.phase!="" or hud.board.commands.uncertain)
	refresh_connection_panel()
	if hud.board.has_method("set_installation"): hud.board.set_installation(snapshot,disconnected)
	update_crew_presentation()
	var mission := selected_mission()
	hud.status.text = StateView.describe(mission,disconnected)
	hud.details.text = str(mission.get("detail","No snapshot available; work is unknown." if disconnected else "No run recorded here. Open the journal for reviews and gym campaigns."))
	if mission.get("state")=="cancelled": hud.details.text="Cancellation acknowledged.\nLast recorded message: "+hud.details.text
	var evidence = mission.get("evidence")
	if evidence != null:
		var summary: Dictionary = evidence.get("summary",{})
		hud.evidence.text = "Outcome: %s\nInput: %s\n" % [summary.get("outcome","unknown"),StateView.input_label(summary)]
		if summary.has("candidate_passed"):
			hud.evidence.text += "Baseline %d/%d · Candidate %d/%d\n" % [summary["baseline_passed"],summary["cases"],summary["candidate_passed"],summary["cases"]]
		elif summary.get("source_kind")=="field":
			hud.evidence.text += "%s observed findings\n" % summary.get("finding_count",0)
		else:
			hud.evidence.text += "%s files · %s static warnings\n" % [summary.get("files_reviewed",0),summary.get("finding_count",0)]
		hud.evidence.text += "\n"+str(summary.get("qualification","No qualification recorded"))
		hud.evidence.text += "\nOpen Command [B] for the retained observation." if summary.get("source_kind")=="field" else "\nOpen Operations [J] to inspect retained review history."
	else:
		hud.evidence.text = "No verified evidence retained."
	var progress = snapshot.get("progression")
	if progress is Dictionary:
		var xp := int(progress.get("xp",0))
		hud.progression.text = "Mender · Level %d · %d verified XP\n%s" % [progress.get("level",1),xp," · ".join(progress.get("achievements",[]))]
		if disconnected: hud.progression.text += "\nLast-known progression · core unavailable"
		if initial_xp >= 0 and xp > initial_xp and not disconnected:
			award_notice = "Verified achievement retained · inspect Mender’s evidence"
		initial_xp = xp
		for i in range(trophies.size()):
			trophies[i].visible = not disconnected and progress.get("achievements",[]).size() > i
	else:
		hud.progression.text = "Progression unknown · no retained ledger"
		for trophy in trophies: trophy.hide()
	hud.submit.disabled = disconnected or hud.command_pending or fixture_path != "" or not ConnectionStatus.enabled(snapshot,"repair") or (hud.mode.selected==1 and not ConnectionStatus.enabled(snapshot,"inference"))
	hud.submit.tooltip_text=ConnectionStatus.reason(snapshot,"repair")
	hud.stop.disabled = disconnected or hud.command_pending or mission.is_empty() or mission.get("state") in ["completed","failed","cancelled"] or fixture_path != ""
	var labels: Array[String] = []
	for pair in crew_pairs():
		var activity := StateView.crew_activity(missions,pair[0],disconnected)
		labels.append(pair[1].display_name.capitalize()+": "+activity)
	hud.roster.text = "    /    ".join(labels.slice(0,3))+"\n"+"    /    ".join(labels.slice(3))
	if active_room != null:
		active_room.activity.text=StateView.crew_activity(missions,room_kind,disconnected) if MEMBERS.has(room_kind) else "Colony interior · scenery"
		if fixture_path!="": active_room.activity.text="FIXTURE · "+active_room.activity.text

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: adjust_zoom(-1)
		KEY_MINUS, KEY_KP_SUBTRACT: adjust_zoom(1)
		KEY_R: hud.open_operations()
		KEY_O: hud.open_connection()
		KEY_B: hud.open_board()
		KEY_4: hud.open_place("watchkeeper")
		KEY_5: hud.open_place("reviewer")
		KEY_TAB: hud.toggle_directory()
		KEY_ESCAPE:
			hud.close_panels()
			stop_watching()
		KEY_L: enter_room("habitat")
		KEY_E:
			if active_room!=null and room_kind=="review" and nearest=="review": hud.open_board()
			elif nearest != "": hud.open_place(nearest)
			elif active_building != null and room_kind == "":
				show_room_guide()
		KEY_F:
			if active_room != null: exit_room()
			elif near_door != "" and not hud.is_open(): enter_room(near_door)
		KEY_1: hud.open_place("repair")
		KEY_2: hud.open_place("review")
		KEY_3: hud.open_place("gym")
		KEY_J: hud.open_operations()
		KEY_H:
			var was: bool = hud.help.visible
			hud.close_panels()
			hud.help.visible = not was
		KEY_C:
			colony_overview = false
			if not hud.reduced: hud.follow = not hud.follow
		KEY_M: toggle_map()
		KEY_ENTER:
			if hud.dock.visible: hud.evidence.visible = not hud.evidence.visible

func crew_hit_rect(actor: Node3D) -> Rect2:
	if actor.model_visual!=null:
		var top := camera.unproject_position(actor.global_position+Vector3(0,2.6,0))
		var bottom := camera.unproject_position(actor.global_position)
		var width := camera.unproject_position(actor.global_position+camera.global_basis.x*0.55).distance_to(bottom)
		return Rect2(Vector2(minf(top.x,bottom.x)-width,top.y),Vector2(absf(top.x-bottom.x)+width*2,bottom.y-top.y)).grow(4)
	var sprite: AnimatedSprite3D = actor.get("sprite")
	var texture: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame)
	var center := actor.position+sprite.position+camera.global_basis.x*sprite.offset.x*sprite.pixel_size+camera.global_basis.y*sprite.offset.y*sprite.pixel_size
	var half_right := camera.global_basis.x*texture.get_width()*sprite.pixel_size*0.5
	var half_up := camera.global_basis.y*texture.get_height()*sprite.pixel_size*0.5
	var top_left := camera.unproject_position(center-half_right+half_up)
	var bottom_right := camera.unproject_position(center+half_right-half_up)
	return Rect2(top_left,bottom_right-top_left).grow(4)

func show_room_guide() -> void:
	if active_building==null: return
	var description := ""
	match str(active_building.definition.id):
		"habitat": description="A shared frontier home. Sleeping alcoves frame a communal galley, dining table and quiet lounge.\n\nLinen panels and low partitions shelter the sleeping spaces while keeping the shared room connected.\n\nThis is a descriptive room guide. The furnishings do not report crew needs or operational activity."
		"greenhouse": description="A working conservatory organized around two cultivation beds and a research bench. Overhead irrigation connects the water reservoir to the planted aisles.\n\nThe greenery and grow lights are environmental art; no live crop or water measurements are connected."
	if not description.is_empty(): hud.open_room_details(active_building.definition.title,description)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			adjust_zoom(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			adjust_zoom(1)
		elif event.button_index == MOUSE_BUTTON_LEFT and not hud.is_open():
			for pair in crew_pairs():
				if pair[1].visible and crew_hit_rect(pair[1]).has_point(event.position):
					hud.open_place(pair[0])
					return
			var hit = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
			if hit != null:
				stop_watching()
				route = travel_route(hit)
				marker.visible = not route.is_empty()
				if marker.visible: marker.position = route[-1]+Vector3(0,0.07,0)

func _physics_process(_delta: float) -> void:
	if hud == null: return
	$LivingCommons.update_presentation($Operator.position,_delta,hud.reduced)
	var viewing:Vector3=get_node(MEMBERS[watched_crew]).position if MEMBERS.has(watched_crew) else $Operator.position
	var containing: Node3D=null
	for station in $Structures.get_children():
		station.update_presentation(viewing,_delta,hud.reduced,crew_pairs().map(func(pair): return pair[1].position)+[$Operator.position])
		if station.contains($Operator.position): containing=station
	if active_room==null or active_room.definition.seamless: set_room_context(containing)
	var move := Vector3.ZERO
	if not hud.is_open():
		var x := 0.0 if capture_input_isolated else float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		var y := 0.0 if capture_input_isolated else float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
		if x != 0 or y != 0:
			stop_watching()
			route.clear()
			move = Vector3(x,0,y).normalized()*TRAVEL_SPEED
		elif not route.is_empty():
			var diff: Vector3 = route[0]-$Operator.position
			diff.y = 0
			if diff.length() < 0.18:
				route.remove_at(0)
			else: move = diff.normalized()*minf(TRAVEL_SPEED,diff.length()/_delta)
	$Operator.motion = move
	if route.is_empty(): marker.hide()
	nearest = ""
	var distance := 2.2
	for pair in crew_pairs():
		var d: float = $Operator.position.distance_to(pair[1].position)
		pair[1].label.visible = not colony_overview and (d < 3.0 or watched_crew==pair[0] or (hud.dock.visible and hud.filter_kind == pair[0]))
		if d < distance:
			nearest = pair[0]
			distance = d
		if crew_motions.has(pair[0]):
			crew_motions[pair[0]].advance(_delta)
			pair[1].presentation_facing=crew_motions[pair[0]].ambient_facing
	near_door=""
	if active_room != null:
		if MEMBERS.has(room_kind) and $Operator.position.distance_to(active_room.global_position+active_room.console_point)<1.5: nearest=room_kind
	else:
		for station in $Structures.get_children():
			if not station.definition.interior_scene.is_empty() and $Operator.position.distance_to(station.entrance())<2.0: near_door=str(station.name)
	if nearest != "":
		hud.prompt.text = "E  ·  Inspect " + {"repair":"Mender’s workshop","review":"Surveyor’s briefing","gym":"Trainer’s gym","watchkeeper":"Watchkeeper’s cluster watch","reviewer":"PR Reviewer’s drafts"}[nearest]
	else:
		hud.prompt.text = award_notice if award_notice != "" else "WASD / arrows · Explore the colony · M overview"
	if active_room != null:
		var destination := "mission table" if room_kind == "review" else "station / crew"
		hud.prompt.text=("E · Inspect "+destination+"   ·   " if nearest!="" else "Explore "+active_building.definition.title+"   ·   ")+"F · Return to colony"
		if room_kind == "" and nearest=="": hud.prompt.text="E · Room guide   ·   F · Return to colony"
	elif near_door!="":
		hud.prompt.text="F · Enter "+get_node("Structures/"+near_door).definition.title+"   ·   E · Inspect nearby crew"
	if walk_test and $Operator.position.distance_to(walk_destination) < 0.65: walk_reached = true
	hud.set_location(active_building.definition.title if active_building != null else ("CONSERVATORY COMMONS" if LivingCommons.FOOTPRINT.has_point(Vector2($Operator.position.x,$Operator.position.z)) else "ASTER COLONY"))
	if not watched_crew.is_empty():
		hud.prompt.text="Watching "+str(get_node(MEMBERS[watched_crew]).display_name)+" · Esc / move to return · 1–5 inspect"
		hud.set_location("CREW VIEW")
	life_ui_timer+=_delta
	if life_ui_timer>=0.5:
		life_ui_timer=0
		for kind in crew_motions:
			var life=crew_motions[kind]
			var activity: String="At home" if not life.anchor.is_empty() else "Between assignments"
			if not life.path.is_empty(): activity="Walking home" if life.intent.get("goal")=="home" else "Heading to station"
			elif life.ambient_activity=="sit": activity="Taking a break"
			hud.crew_strip.project(kind,life.intent,activity,life.route_blocked)
	$Operator.label.visible = false
	update_ambience()

func _process(delta: float) -> void:
	if hud == null: return
	uptime += delta
	frame_count += 1
	if frame_count == 1: first_frame_ms = Time.get_ticks_msec()
	var now := Time.get_ticks_usec()
	if frame_count > 30 and frame_usec>0: frame_times.append((now-frame_usec)/1000.0)
	frame_usec=now
	# Fixed-camera mode advances by rooms, so reduced motion never strands the
	# operator offscreen. Map view is explicit and never dispatches work.
	if absf($Operator.position.x-overview.x)>zoom*zoom_factor*0.32 or absf($Operator.position.z-overview.z)>zoom*zoom_factor*0.22:
		overview = $Operator.position
	var subject:Vector3=get_node(MEMBERS[watched_crew]).position if MEMBERS.has(watched_crew) else $Operator.position
	var view_room:Node3D=active_room
	if not watched_crew.is_empty():
		view_room=null
		for station in $Structures.get_children():
			if station.contains(subject): view_room=station.room
	var desired: Vector3 = subject if hud.follow or not watched_crew.is_empty() else overview
	if colony_overview: desired = Vector3(0,-4,0)
	var desired_offset := Vector3(10,36,46)
	var desired_size := 142.0 if colony_overview else zoom
	if not watched_crew.is_empty(): desired_size=20.0; desired_offset=Vector3(8,18,23)
	if view_room == null and not colony_overview and LivingCommons.FOOTPRINT.has_point(Vector2(subject.x,subject.z)):
		desired = LivingCommons.ORIGIN+Vector3(0,1,0)
		desired_offset = Vector3(7,11,15)
		desired_size = 13.5
	if view_room != null and not colony_overview:
		desired=view_room.global_position+Vector3(view_room.definition.interior_bounds.get_center().x,1.0,view_room.definition.interior_bounds.get_center().y)
		desired_offset=Vector3(5,14,18)
		desired_size=22.0 if compact and hud.dock.visible else 18.0
		var focus: Node3D = view_room.content.get_node_or_null("CameraFocus")
		var view: Node3D = view_room.content.get_node_or_null("CameraPosition")
		if focus != null and view != null:
			desired = focus.global_position
			desired_offset = view.global_position-focus.global_position
			desired_size = float(focus.get_meta("view_size",18.0))
		if hud.dock.visible or hud.board.visible or hud.room_details.visible:
			# Keep the interaction destination in the unobscured left workspace.
			desired += camera.global_basis.x * (4.8 if hud.board.visible else 2.8)
			if room_kind == "review" and hud.board.visible: desired_size = 15.5
	desired_size*=zoom_factor
	var blend := 1.0 if hud.reduced else 1-exp(-delta*4)
	camera_focus=camera_focus.lerp(desired,blend)
	camera_offset=camera_offset.lerp(desired_offset,blend)
	camera.position=camera_focus+camera_offset
	camera.look_at(camera_focus)
	camera.size=lerpf(camera.size,desired_size,blend)
	if fixture_path == "" and last_received > 0 and Time.get_ticks_msec()-last_received > 5000 and not disconnected:
		disconnected = true
		connection_message="STALE · no snapshot for five seconds"
		hud.connection.text = connection_message
		show_mission()
	if hud.connection_panel.visible: refresh_connection_panel()
	if capture_path != "" and frame_count == capture_frames:
		RenderingServer.force_draw(false)
		get_viewport().get_texture().get_image().save_png(capture_path)
		frame_times.sort()
		var metrics := {"frames":frame_times.size(),"median_ms":frame_times[frame_times.size()/2],"p95_ms":frame_times[int(frame_times.size()*0.95)],"engine":Engine.get_version_info(),"startup_to_first_frame_ms":first_frame_ms,"viewport":str(get_viewport().get_visible_rect().size),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"visual_fixture":fixture_path!="","walk_test":walk_test,"capture_input_isolated":capture_input_isolated,"colony_overview":colony_overview,"colony_walk_test":colony_walk_test,"camera_focus":str(camera_focus),"walk_reached":walk_reached,"player_position":str($Operator.position),"room":room_kind,"frame_sampling":"monotonic process intervals", "selected_id":hud.selected_id,"command_message":hud.command_status.text}
		var file := FileAccess.open(capture_path+".json",FileAccess.WRITE)
		file.store_string(JSON.stringify(metrics,"  "))
		if walk_test and not walk_reached:
			push_error("Scripted movement did not reach its destination")
			get_tree().quit(1)
		else: get_tree().quit()

func isolate_capture_input() -> void:
	# Only explicit automated capture opts in. Direct harness button signals and
	# method calls still exercise normal interaction; desktop events cannot steal routes.
	capture_input_isolated=true
	get_viewport().gui_disable_input=true
	set_process_unhandled_input(false)
	set_process_unhandled_key_input(false)
