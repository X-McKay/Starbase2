extends Node3D
const StateView = preload("res://state.gd")
const HUD = preload("res://hud.gd")
const Navigation = preload("res://navigation.gd")
const Commands = preload("res://commands.gd")
const Art = preload("res://art.gd")
var http := HTTPRequest.new()
var api := "http://127.0.0.1:8787"
var hud: CanvasLayer
var commands: Node
var camera := Camera3D.new()
var navigator := Navigation.new()
var route := PackedVector3Array()
var missions: Array = []
var disconnected := true
var last_received := 0
var snapshot: Dictionary = {}
var capture_path := ""
var capture_frames := 180
var frame_times: Array[float] = []
var frame_count := 0
var first_frame_ms := 0
var compact := false
var inspect_on_start := false
var initial_crew := "repair"
var fixture_path := ""
var walk_test := false
var walk_reached := false
var overview := Vector3(0,0,0)
var camera_focus := Vector3.ZERO
var zoom := 34.0
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
var guide_on_start := false
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
const Buildings = preload("res://building_catalog.gd")
var STATIONS: Dictionary = Buildings.station_paths()
var active_building: Node3D
const MEMBERS := {"repair":"Mender", "review":"Surveyor", "gym":"Trainer", "watchkeeper":"Watchkeeper", "reviewer":"Reviewer"}
const TITLES := {"repair":"Mender", "review":"Surveyor", "gym":"Trainer", "watchkeeper":"Watchkeeper", "reviewer":"PR Reviewer"}

func crew_pairs() -> Array:
	return MEMBERS.keys().map(func(kind): return [kind,get_node(MEMBERS[kind])])

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
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
		if arg == "--guide": guide_on_start = true
	if "--verify-package" in OS.get_cmdline_user_args() and fixture_path.is_empty():
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
	sun.rotation_degrees = Vector3(-52,-32,-8)
	sun.light_color = Color("e7d7cf")
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = room_environment
	room_environment.background_color=Color("0d1828")
	env.environment.background_mode = Environment.BG_CANVAS
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("97b3d8")
	env.environment.ambient_light_energy = 0.40
	add_child(env)
	marker = Art.cylinder(self,Vector3(0,0.07,0),0.24,0.025,"f5d295")
	marker.hide()
	# Cosmetic cabinet slots light only from the core's retained achievement list.
	Art.box(self,Vector3(-4.3,0.65,-1.1),Vector3(0.9,1.3,0.45),"3a5263")
	for i in range(2):
		var trophy := Art.cylinder(self,Vector3(-4.5+i*0.4,1.40,-1.1),0.12,0.24,"eac58d")
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
	hud.journal_requested.connect(func(): OS.shell_open(api))
	hud.settings_changed.connect(apply_settings)
	hud.map_requested.connect(toggle_map)
	hud.room_requested.connect(enter_room)
	hud.set_buildings($Buildings.get_children())
	hud.exit_requested.connect(exit_room)
	hud.repair_requested.connect(launch_repair)
	hud.cancel_requested.connect(cancel_selected)
	commands = Commands.new()
	commands.api = api
	add_child(commands)
	commands.feedback.connect(func(message: String,pending: bool):
		hud.set_command_status(message,pending)
		if not pending: hud.notify(message,"failed" if message.begins_with("Request rejected") or message.begins_with("Could not") else "unknown" if message.begins_with("Outcome unknown") else "verified")
		show_mission())
	commands.accepted.connect(func(id: String): pending_selection_id=id; poll())
	add_child(http)
	http.timeout = 2.0
	http.body_size_limit = 4194304
	http.request_completed.connect(on_response)
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(poll)
	add_child(timer)
	if fixture_path != "":
		var data = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
		if data is Dictionary: receive_snapshot(data)
		hud.set_connection("Visual test fixture · not live operational activity","fixture")
	else:
		timer.start()
		poll()
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
	if guide_on_start: hud.toggle_help()
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
	show_mission()
	if "--verify-package" in OS.get_cmdline_user_args():
		call_deferred("_verify_package")

func _verify_package() -> void:
	var check=load("res://package_check.gd").new()
	await check.run(get_tree(),self)

func enter_room(kind: String) -> void:
	if kind in ["watchkeeper","reviewer"]: kind="review"
	var station: Node3D=get_node_or_null(STATIONS.get(kind,"Buildings/"+kind))
	if station==null or station.definition.interior_scene.is_empty(): return
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

func exit_room() -> void:
	if active_room == null: return
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

func toggle_map() -> void:
	if active_room != null: exit_room()
	colony_overview=not colony_overview

func travel_route(destination: Vector3) -> PackedVector3Array:
	if active_room != null: return active_room.route($Operator.position,destination)
	return navigator.route($Operator.position,destination)

func apply_settings() -> void:
	foley.enabled=hud.sound_enabled
	foley.reduced=hud.reduced
	$Terrace/PavingLights.reduced_motion = hud.reduced
	$Terrace/MineralBasin.reduced_motion = hud.reduced
	$Terrace/Landform.reduced_motion = hud.reduced
	for member in [$Operator]+MEMBERS.values().map(func(label): return get_node(label)):
		member.reduced_motion = hud.reduced
	if hud.reduced: hud.follow = false

func launch_repair(scenario: String, mode: String) -> void:
	var id := "world-" + Crypto.new().generate_random_bytes(12).hex_encode()
	commands.submit("/v3/repairs",{"id":id,"scenario":scenario,"mode":mode},id)

func cancel_selected() -> void:
	var m := selected_mission()
	if m.is_empty(): return
	var prefix := "/v3/repairs/" if m["input"].get("kind") == "repair" else "/v2/runs/"
	if m["input"].get("kind") in ["watchkeeper","reviewer"]: prefix="/v4/runs/"
	commands.submit(prefix+hud.selected_id+"/cancel",{},hud.selected_id)

func poll() -> void:
	if fixture_path != "" or http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED: return
	if http.request(api+"/v2/snapshot") != OK:
		disconnected = true
		hud.set_connection("Disconnected · last-known records only","offline")
		show_mission()

func on_response(result: int, response: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response != 200:
		disconnected = true
		hud.set_connection("Disconnected · last-known records only","offline")
		show_mission()
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or data.get("schema_version") != 2 or not data.get("recent") is Array:
		disconnected = true
		hud.set_connection("Unknown · unsupported snapshot","unknown")
		show_mission()
		return
	receive_snapshot(data)

func receive_snapshot(data: Dictionary) -> void:
	disconnected = false
	last_received = Time.get_ticks_msec()
	snapshot = data
	missions = StateView.project(data)
	if pending_selection_id != "" and missions.any(func(m): return m["input"]["id"] == pending_selection_id):
		hud.selected_id = pending_selection_id
		pending_selection_id = ""
	hud.set_connection("Live core · observed " + Time.get_datetime_string_from_unix_time(int(data.get("observed_at",0))).replace("T"," ") + " UTC","live")
	show_mission()

func selected_mission() -> Dictionary:
	for m in missions:
		if m["input"]["id"] == hud.selected_id: return m
	return {}

func show_mission() -> void:
	if hud == null: return
	hud.update_list(missions)
	var mission := selected_mission()
	hud.set_status(StateView.describe(mission,disconnected),StateView.tone(mission,disconnected))
	hud.details.text = str(mission.get("detail","No snapshot available; work is unknown." if disconnected else "No run recorded here. Open the journal for reviews and gym campaigns."))
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
		hud.evidence.text += "\n"+str(summary.get("qualification","No qualification recorded"))+"\nFull provenance in the journal."
	else:
		hud.evidence.text = "No verified evidence retained."
	var progress = snapshot.get("progression")
	if progress is Dictionary:
		var xp := int(progress.get("xp",0))
		var achievements: Array = progress.get("achievements",[])
		var ledger := "Mender · Level %d · %d verified XP" % [progress.get("level",1),xp]
		if not achievements.is_empty(): ledger += "\n" + " · ".join(achievements)
		if disconnected: ledger += "\nLast-known progression · core unavailable"
		hud.set_progression(ledger,"offline" if disconnected else "verified" if not achievements.is_empty() else "idle")
		if initial_xp >= 0 and xp > initial_xp and not disconnected:
			award_notice = "Verified achievement retained · inspect Mender’s evidence"
			hud.notify(award_notice,"verified",8.0)
		initial_xp = xp
		for i in range(trophies.size()):
			trophies[i].visible = not disconnected and progress.get("achievements",[]).size() > i
	else:
		hud.set_progression("Progression unknown · no retained ledger","unknown")
		for trophy in trophies: trophy.hide()
	hud.submit.disabled = disconnected or hud.command_pending or fixture_path != ""
	hud.stop.disabled = disconnected or hud.command_pending or mission.is_empty() or mission.get("state") in ["completed","failed","cancelled"] or fixture_path != ""
	var entries: Array = []
	for pair in crew_pairs():
		var activity := StateView.crew_activity(missions,pair[0],disconnected)
		pair[1].label.text = pair[1].display_name + "\n" + activity
		entries.append([TITLES[pair[0]],activity,StateView.crew_tone(missions,pair[0],disconnected)])
	hud.set_roster(entries)
	if active_room != null:
		active_room.activity.text=StateView.crew_activity(missions,room_kind,disconnected) if MEMBERS.has(room_kind) else "Colony interior · scenery"
		if fixture_path!="": active_room.activity.text="FIXTURE · "+active_room.activity.text

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_B: hud.open_board()
		KEY_4: hud.open_place("watchkeeper")
		KEY_5: hud.open_place("reviewer")
		KEY_TAB: hud.toggle_directory()
		KEY_ESCAPE: hud.close_panels()
		KEY_E:
			if active_room!=null and room_kind=="review" and nearest=="review": hud.open_board()
			elif nearest != "": hud.open_place(nearest)
		KEY_F:
			if active_room != null: exit_room()
			elif near_door != "" and not hud.is_open(): enter_room(near_door)
		KEY_1: hud.open_place("repair")
		KEY_2: hud.open_place("review")
		KEY_3: hud.open_place("gym")
		KEY_J: OS.shell_open(api)
		KEY_H: hud.toggle_help()
		KEY_C:
			colony_overview = false
			if not hud.reduced: hud.follow = not hud.follow
		KEY_M: toggle_map()
		KEY_ENTER:
			if hud.dock.visible: hud.evidence.visible = not hud.evidence.visible

func crew_hit_rect(actor: Node3D) -> Rect2:
	var sprite: AnimatedSprite3D = actor.get("sprite")
	var texture: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame)
	var center := actor.position+sprite.position+camera.global_basis.x*sprite.offset.x*sprite.pixel_size+camera.global_basis.y*sprite.offset.y*sprite.pixel_size
	var half_right := camera.global_basis.x*texture.get_width()*sprite.pixel_size*0.5
	var half_up := camera.global_basis.y*texture.get_height()*sprite.pixel_size*0.5
	var top_left := camera.unproject_position(center-half_right+half_up)
	var bottom_right := camera.unproject_position(center+half_right-half_up)
	return Rect2(top_left,bottom_right-top_left).grow(4)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom-2,20,52)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom+2,20,52)
		elif event.button_index == MOUSE_BUTTON_LEFT and not hud.is_open():
			for pair in crew_pairs():
				if (active_room == null or pair[0]==room_kind) and crew_hit_rect(pair[1]).has_point(event.position):
					hud.open_place(pair[0])
					return
			var hit = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(event.position),camera.project_ray_normal(event.position))
			if hit != null:
				route = travel_route(hit)
				marker.visible = not route.is_empty()
				if marker.visible: marker.position = route[-1]+Vector3(0,0.07,0)

func _physics_process(_delta: float) -> void:
	if hud == null: return
	var move := Vector3.ZERO
	if not hud.is_open():
		var x := float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		var y := float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
		if x != 0 or y != 0:
			route.clear()
			move = Vector3(x,0,y).normalized()*3.7
		elif not route.is_empty():
			var diff: Vector3 = route[0]-$Operator.position
			diff.y = 0
			if diff.length() < 0.18:
				route.remove_at(0)
			else: move = diff.normalized()*3.7
	$Operator.motion = move
	if route.is_empty(): marker.hide()
	nearest = ""
	var distance := 2.2
	for pair in crew_pairs():
		var d: float = $Operator.position.distance_to(pair[1].position)
		if d < distance:
			nearest = pair[0]
			distance = d
		# Tiny ambient strolls remain local and don't invent operational activity.
		var actor = pair[1]
		if active_room != null or hud.reduced:
			actor.motion = Vector3.ZERO
		else:
			var cycle := fposmod(uptime+float(actor.home.x)*0.2,20.0)
			var target: Vector3 = actor.home+Vector3(0.85 if cycle>8 and cycle<15 else 0.0,0,0)
			var displacement: Vector3 = target-actor.position
			actor.motion = displacement.normalized()*0.65 if displacement.length()>0.08 else Vector3.ZERO
			if actor.motion == Vector3.ZERO: actor.facing = 0
	near_door=""
	if active_room != null:
		if MEMBERS.has(room_kind) and $Operator.position.distance_to(active_room.position+active_room.console_point)<1.5: nearest=room_kind
	else:
		for station in $Buildings.get_children():
			if not station.definition.interior_scene.is_empty() and $Operator.position.distance_to(station.entrance())<2.0: near_door=str(station.name)
	var parts: Array = [["WASD","Explore the colony"],"·",["M","Overview"]]
	if nearest != "":
		parts = [["E","Inspect " + {"repair":"Mender’s workshop","review":"Surveyor’s briefing","gym":"Trainer’s gym","watchkeeper":"Watchkeeper’s cluster watch","reviewer":"PR Reviewer’s drafts"}[nearest]]]
	if active_room != null:
		parts = ([["E","Inspect console / crew"]] if nearest!="" else ["Explore "+active_building.definition.title])+["·",["F","Return to colony"]]
	elif near_door!="":
		parts = [["F","Enter "+get_node("Buildings/"+near_door).definition.title],"·",["E","Inspect nearby crew"]]
	hud.set_prompt(parts)
	if walk_test and $Operator.position.distance_to(walk_destination) < 0.65: walk_reached = true

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
	if absf($Operator.position.x-overview.x)>zoom*0.32 or absf($Operator.position.z-overview.z)>zoom*0.22:
		overview = $Operator.position
	var desired: Vector3 = $Operator.position if hud.follow else overview
	if colony_overview: desired = Vector3(0,-4,0)
	camera_focus = camera_focus.lerp(desired,1-exp(-delta*4)) if not hud.reduced else desired
	camera.position = camera_focus+Vector3(10,36,46)
	camera.look_at(camera_focus)
	camera.size = 90.0 if colony_overview else zoom
	if active_room != null:
		# Explicit room cut, including reduced-motion mode; no fly-through void.
		camera_focus=active_room.position+Vector3(0,1.5,0)
		if hud.dock.visible: camera_focus+=Vector3(2.6,0,0)
		camera.position=camera_focus+Vector3(5,14,18)
		camera.look_at(camera_focus)
		camera.size=22.0 if compact and hud.dock.visible else 18.0
	if fixture_path == "" and last_received > 0 and Time.get_ticks_msec()-last_received > 5000 and not disconnected:
		disconnected = true
		hud.connection.text = "STALE · no snapshot for five seconds"
		show_mission()
	if capture_path != "" and frame_count == capture_frames:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture_path)
		frame_times.sort()
		var metrics := {"frames":frame_times.size(),"median_ms":frame_times[frame_times.size()/2],"p95_ms":frame_times[int(frame_times.size()*0.95)],"engine":Engine.get_version_info(),"startup_to_first_frame_ms":first_frame_ms,"viewport":str(get_viewport().get_visible_rect().size),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"visual_fixture":fixture_path!="","walk_test":walk_test,"colony_overview":colony_overview,"colony_walk_test":colony_walk_test,"camera_focus":str(camera_focus),"walk_reached":walk_reached,"player_position":str($Operator.position),"room":room_kind,"frame_sampling":"monotonic process intervals", "selected_id":hud.selected_id,"command_message":hud.command_status.text}
		var file := FileAccess.open(capture_path+".json",FileAccess.WRITE)
		file.store_string(JSON.stringify(metrics,"  "))
		if walk_test and not walk_reached:
			push_error("Scripted movement did not reach its destination")
			get_tree().quit(1)
		else: get_tree().quit()
