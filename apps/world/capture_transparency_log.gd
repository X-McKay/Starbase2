extends SceneTree
## Native sign-off captures for the Captain's Log (page 4), from the synthetic
## stream fixture and its paired full mission record only. No API connection or
## work dispatch. Run under a real renderer:
## xvfb-run -a -s "-screen 0 1440x900x24" godot --path apps/world --rendering-driver opengl3 --script capture_transparency_log.gd
const STREAM := "res://../../fixtures/world/transparency/stream.jsonl"
var output := "res://../../evidence/world/transparency-20261004"
var failures: Array[String] = []
var world: Node3D
var notes: Dictionary = {}
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void: run.call_deferred()

func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event

func picture(name: String) -> void:
	world.update_live_view(1.0)
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	check(image.save_png(ProjectSettings.globalize_path(output).path_join(name + ".png")) == OK, "Saved " + name)
	var log = world.hud.captains_log
	notes[name] = {"size":str(image.get_size()), "title":log.title_label.text, "meta":log.meta_label.text,
		"status":log.status_box.get_children().map(func(label): return label.text),
		"mode":"list" if log.list_mode else "timeline", "selected":log.detail_count.text + " · " + log.detail_title.text,
		"detail":log.detail_evidence.get_children().map(func(label): return label.text),
		"not_recorded":log.detail_missing.get_children().map(func(label): return label.text), "source":log.detail_source.text,
		"events":log.events().map(func(e): return preload("res://captains_log_model.gd").list_line(e)),
		"ticks":log.model.get("ticks", []).map(func(t): return t.label), "stream_state":world.event_stream.state}
	print("CAPTURED ", name, " ", JSON.stringify(notes[name]))

func resize(size: Vector2i) -> void:
	root.size = size
	root.content_scale_size = size
	for _frame in 6: await process_frame

func replay() -> void:
	world.restart_stream_fixture()
	var deadline := Time.get_ticks_msec() + 20000
	while not world.event_stream.fixture_done() and Time.get_ticks_msec() < deadline: await process_frame
	check(world.event_stream.fixture_done(), "Fixture replay finished")
	await process_frame
	world.update_live_view(1.0)

func timeline_checks(tag: String) -> void:
	var log = world.hud.captains_log
	check(log.visible and world.hud.is_open(), tag + " log open")
	check(log.title_label.text == "Mission 42 · Fix cache eviction", tag + " title: " + log.title_label.text)
	check(log.events().size() == 9 and log.pins.size() == 9, tag + " nine events: " + str(log.events().size()))
	var status: Array = log.status_box.get_children().map(func(label): return label.text)
	check(status.size() >= 2 and str(status[0]).begins_with("[~] LIVE") and str(status[0]).ends_with("SYNTHETIC REPLAY"), tag + " freshness line: " + str(status))
	check(str(status[1]) == "[=] Synthetic fixture record · 4 retained events", tag + " record line: " + str(status))

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if DisplayServer.get_name() == "headless":
		push_error("Native Captain's Log capture requires a renderer")
		quit(1)
		return
	create_timer(240).timeout.connect(func(): push_error("Captain's Log capture watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	await resize(Vector2i(1440, 900))
	world = load("res://main.tscn").instantiate()
	world.stream_fixture_path = STREAM
	root.add_child(world)
	world.isolate_capture_input()
	await process_frame
	check(world.event_stream.fixture_mode and world.event_stream.client == null, "No network stream")
	world.hud.close_panels()
	for _frame in 30: await process_frame
	# The world key binding opens the log (desktop input is isolated during capture).
	world._unhandled_key_input(key(KEY_G))
	var log = world.hud.captains_log
	check(log.visible, "G opens the Captain's Log")
	# The software renderer is slow: replay right before each picture so the
	# stream is still inside its heartbeat window when the frame is drawn.
	await replay()
	check(log.fixture_records.has("sdlc-42") and log.http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED, "Fixture record only; no request made")
	world.update_live_view(1.0)
	timeline_checks("1440")
	check(log.detail_title.text == "[x] Changes requested · 2 findings", "Opens on the newest record: " + log.detail_title.text)
	await picture("captains-log")
	# Select Rivet's patch with a click on its pin, then step with the keyboard.
	log.pins[2].pressed.emit()
	log._input(key(KEY_PERIOD))
	check(log.detail_title.text == "[/] Patch round 1 · +6 −2", "Patch selected: " + log.detail_title.text)
	await replay()
	timeline_checks("detail")
	check(log.detail_title.text == "[/] Patch round 1 · +6 −2", "Selection survives the record reread: " + log.detail_title.text)
	await picture("captains-log-detail")
	log._input(key(KEY_L))
	check(log.list_mode and log.list_items.size() == 9, "List view lists the same nine events")
	await replay()
	await picture("captains-log-list")
	log._input(key(KEY_L))
	await resize(Vector2i(960, 700))
	await replay()
	timeline_checks("960")
	await picture("captains-log-compact")
	world._unhandled_key_input(key(KEY_G))
	check(not log.visible and not world.hud.is_open(), "G closes the log")
	# Extend, never replace, the slice 3 capture notes.
	var path := ProjectSettings.globalize_path(output).path_join("captures.json")
	var existing = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var data: Dictionary = existing if existing is Dictionary else {}
	data["captains_log"] = {"fixture":STREAM, "record":"res://../../fixtures/world/transparency/mission-sdlc-42.json", "synthetic":true,
		"engine":Engine.get_version_info().string, "renderer":RenderingServer.get_current_rendering_driver_name(), "captures":notes}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CAPTAINS_LOG_CAPTURE_PASSED: timeline, detail, list and compact captures")
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
