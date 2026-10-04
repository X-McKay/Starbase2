extends SceneTree
## Native sign-off captures for page 2 (workstation console) and page 3 (handoff
## dialogue), from the synthetic round-2 stream fixture only. No API connection
## or work dispatch. Run under a real renderer:
## xvfb-run -a -s "-screen 0 1440x900x24" godot --path apps/world --rendering-driver opengl3 --script capture_transparency_workstation.gd
const STREAM := "res://../../fixtures/world/transparency/round2-stream.jsonl"
var output := "res://../../evidence/world/transparency-20261004"
var failures: Array[String] = []
var world: Node3D
var notes: Dictionary = {}
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void: run.call_deferred()

func texts(lines: Array) -> Array:
	return lines.map(func(item): return str(item.text))

func picture(name: String) -> void:
	# Refresh immediately before drawing so captured text matches the captured state.
	world.update_live_view(1.0)
	# Rebuilt panes need one frame of layout before they draw.
	await process_frame
	world.update_live_view(1.0)
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	check(image.save_png(ProjectSettings.globalize_path(output).path_join(name + ".png")) == OK, "Saved " + name)
	var hud = world.hud
	var entry := {"size":str(image.get_size()), "stream_state":world.event_stream.state, "record_status":world.transparency.record.status,
		"v7_snapshot_age_s":(Time.get_ticks_msec() - hud.board.sdlc_missions.received_at_msec) / 1000.0}
	if hud.workstation_screen.visible:
		var model: Dictionary = hud.workstation_screen.model
		entry.merge({"title":model.title, "subtitle":model.subtitle, "badge":hud.workstation_screen.badge.text, "banner":texts(model.banner),
			"plan":texts(model.plan), "asks":[model.asks_title] + texts(model.asks), "why":texts(model.why), "diff_header":model.diff.get("header", ""),
			"diff_rows":model.diff.get("rows", []).size(), "tests":texts(model.tests.get("lines", [])), "spend":texts(model.spend),
			"receipts":model.receipts.items.map(func(item): return item.glyph + " " + item.tool + " · " + item.detail)})
	if hud.handoff_dialogue.visible:
		var model: Dictionary = hud.handoff_dialogue.model
		entry.merge({"heading":model.heading, "detail":model.detail, "badge":hud.handoff_dialogue.heading_badge.text,
			"cards":model.cards.map(func(card): return {"who":card.name + " · " + card.role, "status":card.status.text, "lines":texts(card.lines), "list":texts(card.list), "foot":card.foot}),
			"track":model.track.map(func(item): return item.text + " [" + item.status + "]"), "footer":model.footer_detail})
	notes[name] = entry
	print("CAPTURED ", Time.get_ticks_msec(), " ", name, " ", JSON.stringify(entry))

func settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until: await process_frame

func resize(size: Vector2i) -> void:
	root.size = size
	root.content_scale_size = size
	for _frame in 6: await process_frame

func replay() -> void:
	world.restart_stream_fixture()
	var deadline := Time.get_ticks_msec() + 20000
	while not world.event_stream.fixture_done() and Time.get_ticks_msec() < deadline: await process_frame
	check(world.event_stream.fixture_done(), "Fixture replay finished")
	await settle(0.3)
	world.update_live_view(1.0)

func console_checks(tag: String) -> void:
	var screen = world.hud.workstation_screen
	check(screen.visible and screen.title.text == "RIVET · IMPLEMENTER CONSOLE", tag + " console title: " + screen.title.text)
	check(screen.badge.text.begins_with("[~] LIVE") and screen.badge.text.ends_with("SYNTHETIC REPLAY"), tag + " live synthetic badge: " + screen.badge.text)
	check(world.transparency.record.status == "fixture", tag + " full record from fixture")
	check(screen.model.diff.rows.size() == 15 and screen.model.receipts.items.size() == 7, tag + " diff and receipts")
	check(texts(screen.model.why)[0] == "[?] Not recorded", tag + " reasoning not recorded")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if DisplayServer.get_name() == "headless":
		push_error("Native transparency capture requires a renderer")
		quit(1)
		return
	create_timer(240).timeout.connect(func(): push_error("Workstation capture watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	await resize(Vector2i(1440, 900))
	world = load("res://main.tscn").instantiate()
	world.stream_fixture_path = STREAM
	root.add_child(world)
	world.isolate_capture_input()
	await process_frame
	check(world.fixture_path.ends_with("world-snapshot.json") and world.event_stream.fixture_mode and world.event_stream.client == null, "Offline fixtures only, no network stream")
	world.hud.close_panels()
	world.watch_crew("repair")
	await settle(2.0)
	# Open each page before its replay: llvmpipe frames are slow, and the live
	# window (heartbeat x 2 + 1 s) starts at the fixture's last frame.
	world.transparency.open_workstation("repair")
	await replay()
	console_checks("1440")
	await picture("workstation-screen")
	# Replay again so the stale window starts from the last frame, then go silent.
	await replay()
	world.event_stream.pause_fixture()
	var deadline := Time.get_ticks_msec() + 20000
	while world.event_stream.state != "stale" and Time.get_ticks_msec() < deadline: await process_frame
	world.update_live_view(1.0)
	var screen = world.hud.workstation_screen
	check(screen.badge.text.begins_with("[?] STALE"), "Stale badge: " + screen.badge.text)
	check(screen.model.banner[0].text.begins_with("[?] LAST KNOWN"), "Stale banner: " + str(screen.model.banner[0].text))
	await picture("workstation-screen-stale")
	world.transparency.open_handoff()
	await replay()
	var dialogue = world.hud.handoff_dialogue
	check(dialogue.visible and dialogue.heading.text == "Prism returns the candidate to Rivet", "Handoff heading: " + dialogue.heading.text)
	check(dialogue.model.cards.size() == 2 and dialogue.model.cards[1].status.text == "[=] round 2 submitted", "Reply card")
	await picture("handoff-dialogue")
	await resize(Vector2i(960, 700))
	world.transparency.open_workstation("repair")
	await replay()
	console_checks("960")
	check(screen.columns.vertical, "Compact console stacks its columns")
	await picture("workstation-screen-compact")
	world.transparency.open_handoff()
	await replay()
	await picture("handoff-dialogue-compact")
	# Merge into the shared evidence index without dropping the page 1 entries.
	var index_path := ProjectSettings.globalize_path(output).path_join("captures.json")
	var index = JSON.parse_string(FileAccess.get_file_as_string(index_path)) if FileAccess.file_exists(index_path) else null
	if not index is Dictionary: index = {"captures":{}}
	var captures: Dictionary = index.get("captures", {})
	for name in notes: captures[name] = notes[name].merged({"fixture":STREAM})
	index.captures = captures
	index.synthetic = true
	index.engine = Engine.get_version_info().string
	index.renderer = RenderingServer.get_current_rendering_driver_name()
	var file := FileAccess.open(index_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(index, "  "))
	file.close()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("WORKSTATION_CAPTURE_PASSED: console live, stale and compact; handoff wide and compact")
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
