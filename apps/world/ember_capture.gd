extends RefCounted
## Native review of the approved ember workspaces. Read-only, doubly fenced fixtures.
var tree: SceneTree
var scene: Node3D
var output := ""
var started := 0
var stopped := false
var failures: Array[String] = []
var captures: Array[String] = []
var views: Array = []

func check(ok: bool, message: String) -> void:
	if not ok and message not in failures: failures.append(message)

func settle() -> void:
	for frame in range(3): await tree.process_frame

func picture(name: String, panel: Control = null) -> void:
	if stopped: return
	await settle()
	if stopped: return
	var viewport := tree.root.get_visible_rect()
	if panel != null:
		check(panel.is_visible_in_tree(), name+": workspace is visible")
		var bounds := panel.get_global_rect()
		check(viewport.grow(1).encloses(bounds), name+": workspace fits viewport "+str(bounds))
		# Vertical scrolling is intentional; actionable controls must never require
		# horizontal scrolling or extend beyond their containing workspace.
		for control in panel.find_children("*", "Control", true, false):
			if not control.is_visible_in_tree() or not (control is Button or control is LineEdit): continue
			var rect: Rect2 = control.get_global_rect()
			if rect.end.y <= bounds.position.y or rect.position.y >= bounds.end.y: continue
			check(rect.position.x >= bounds.position.x-1 and rect.end.x <= bounds.end.x+1,
				name+": action fits horizontally: "+str(control.get_path()))
		views.append({"name":name,"panel_rect":str(bounds),"viewport":str(viewport)})
	RenderingServer.force_draw(false)
	var screenshot := tree.root.get_texture().get_image()
	check(screenshot.save_png(output.path_join(name+".png")) == OK, name+": image saved")
	captures.append(name+".png")

func select_dossier(kind: String, index: int) -> void:
	scene.hud.open_place(kind)
	scene.show_mission()
	scene.hud.dossier_tabs.current_tab = index
	# A SubViewport portrait needs a rendered update after its crew changes.
	await settle()
	RenderingServer.force_draw(false)
	await settle()

func run(host: SceneTree, world: Node3D, directory: String) -> void:
	tree = host; scene = world; output = directory; started = Time.get_ticks_msec()
	if scene.fixture_path.is_empty() or scene.hud.board.fixture.is_empty() or not scene.capture_input_isolated:
		push_error("Ember capture requires isolated world AND board fixtures")
		tree.quit(1); return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create ember capture output"); tree.quit(1); return
	var watchdog := tree.create_timer(115.0)
	watchdog.timeout.connect(func():
		if not stopped:
			check(false, "Ember review exceeded 115-second watchdog")
			finish())
	tree.root.size = Vector2i(1280,800)
	tree.root.content_scale_size = Vector2i(1280,800)
	scene.hud.large_text = false
	scene.hud.scale_text()
	scene.hud.reduced = true
	scene.apply_settings()
	scene.hud.close_panels()
	await picture("00-colony")
	await select_dossier("reviewer",0)
	await picture("01-reviewer-dossier",scene.hud.dock)
	await select_dossier("repair",2)
	await picture("02-mender-practice",scene.hud.dock)
	check(scene.hud.submit.disabled,"Fixture repair practice cannot dispatch")
	scene.hud.dossier_tabs.current_tab = 1
	await picture("03-mender-evidence",scene.hud.dock)
	scene.hud.open_operations()
	for index in range(4):
		scene.hud.operations.tabs.current_tab = index
		await picture("%02d-work-%s" % [4+index,["review","compare","duties","history"][index]],scene.hud.operations)
	scene.hud.open_board()
	for index in range(5):
		scene.hud.board.tabs.current_tab = index
		if index == 3 and not scene.hud.board.fixture_details.is_empty():
			scene.hud.board.inspect(str(scene.hud.board.fixture_details.keys()[0]))
		await picture("%02d-field-%s" % [8+index,["observations","repositories","memory","evidence","duties"][index]],scene.hud.board)
	scene.open_station_records("review")
	await picture("13-station-records",scene.hud.station_records)
	scene.open_morning_briefing()
	await picture("14-habitat-briefing",scene.hud.briefing)
	scene.hud.toggle_directory()
	await picture("15-crew-places",scene.hud.directory)
	scene.enter_room("Habitat") # Isolated visual staging, not a travel qualification.
	scene.show_room_guide()
	await picture("16-habitat-room-guide",scene.hud.room_details)
	scene.hud.toggle_settings()
	for index in range(3):
		scene.hud.select_settings(index)
		await picture("%02d-settings-%s" % [17+index,["display","audio","controls"][index]],scene.hud.help)
	scene.hud.open_connection()
	scene.refresh_connection_panel()
	for index in range(2):
		scene.hud.connection_panel.tabs.current_tab = index
		await picture("%02d-connection-%s" % [20+index,["status","capabilities"][index]],scene.hud.connection_panel)
	tree.root.size = Vector2i(800,640)
	tree.root.content_scale_size = Vector2i(800,640)
	scene.hud.large_text = true
	scene.hud.scale_text()
	await select_dossier("reviewer",0)
	await picture("22-compact-dossier",scene.hud.dock)
	scene.hud.toggle_settings()
	scene.hud.select_settings(0)
	await picture("23-compact-settings",scene.hud.help)
	scene.hud.open_board()
	scene.hud.board.tabs.current_tab = 0
	await picture("24-compact-field",scene.hud.board)
	scene.open_station_records("review")
	await picture("25-compact-records",scene.hud.station_records)
	var actions: Array = scene.hud.station_records.reports.find_children("*","Button",true,false)
	if not actions.is_empty():
		var first: Button = actions[0]
		first.grab_focus()
		await settle()
		check(scene.hud.station_records.report_scroll.get_global_rect().grow(1).encloses(first.get_global_rect()),"Compact first Inspect is fully accessible")
	scene.disconnected = true
	scene.show_mission()
	await picture("26-compact-stale-records",scene.hud.station_records)
	check(scene.hud.station_records.freshness.text.contains("OFFLINE"),"Stale records retain explicit offline qualification")
	finish()

func finish() -> void:
	if stopped: return
	stopped = true
	var commands_sent: bool = not scene.commands.payload.is_empty() or not scene.hud.board.commands.payload.is_empty() or not scene.hud.operations.commands.payload.is_empty()
	var http_idle := true
	for request in [scene.http,scene.hud.board.get_http,scene.hud.board.detail_http,scene.hud.operations.history.page_http,scene.hud.operations.history.detail_http]:
		http_idle = http_idle and request.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED
	check(not commands_sent,"Ember fixture cannot dispatch commands")
	check(http_idle,"Ember fixture cannot issue live HTTP requests")
	var report := {"mode":"ember","status":"passed" if failures.is_empty() else "failed","fixture":true,
		"world_fixture":not scene.fixture_path.is_empty(),"board_fixture":not scene.hud.board.fixture.is_empty(),
		"commands_dispatched":commands_sent,"http_idle":http_idle,"captures":captures,"failures":failures,
		"views":views,"wall_ms":Time.get_ticks_msec()-started,"engine":Engine.get_version_info()}
	var file := FileAccess.open(output.path_join("ember-report.json"),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report,"  "))
	else: check(false,"Could not write ember report")
	for failure in failures: push_error(failure)
	print("EMBER_CAPTURE_PASSED" if failures.is_empty() else "EMBER_CAPTURE_FAILED")
	tree.quit(0 if failures.is_empty() else 1)
