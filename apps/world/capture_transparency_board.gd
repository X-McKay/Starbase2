extends SceneTree
## Native sign-off captures for the crew board (page 5) and crew dialogue
## (page 6), from the synthetic crew board stream fixture only. No API
## connection or work dispatch. Run under a real renderer:
## xvfb-run -a -s "-screen 0 1440x900x24" godot --path apps/world --rendering-driver opengl3 --script capture_transparency_board.gd
const STREAM := "res://../../fixtures/world/transparency/crew-board-stream.jsonl"
var output := "res://../../evidence/world/transparency-20261004"
var failures: Array[String] = []
var world: Node3D
var notes: Dictionary = {}
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void: run.call_deferred()

func visible_texts(rows: Array, keys: Array) -> Array:
	return rows.filter(func(row): return row.row.visible if row.has("row") else row.panel.visible).map(func(row): return " ".join(keys.map(func(key): return row[key].text)))

## Each frame is taken right after a fresh replay so the stream reads live.
func picture(name: String) -> void:
	await replay()
	world.update_live_view(1.0)
	for _frame in 2: await process_frame
	check(world.hud.freshness_badge.text.begins_with("[~] LIVE · last event"), name + " is live: " + world.hud.freshness_badge.text)
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	check(image.save_png(ProjectSettings.globalize_path(output).path_join(name + ".png")) == OK, "Saved " + name)
	var board = world.hud.crew_board
	var talk = world.hud.crew_dialogue
	var note := {"size":str(image.get_size()), "badge":world.hud.freshness_badge.text, "board_freshness":board.freshness.text,
		"needs_title":board.needs_title.text, "needs":visible_texts(board.need_rows, ["glyph", "title", "detail", "action"]),
		"chips":board.chips.filter(func(c): return c.button.visible).map(func(c): return c.button.text),
		"feed_title":board.feed_title.text, "feed":visible_texts(board.feed_rows, ["time", "who", "glyph", "text"]),
		"crew":board.crew_buttons.values().map(func(b): return b.text), "selected":board.selected,
		"day":[board.day_name.text, board.day_state.text, board.day_counts.text, board.day_now.text, board.day_next.text, board.day_done_title.text, board.day_done.text, board.talk.text, board.watch.text],
		"action_status":board.action_status.text if board.action_status.visible else "", "stream_state":world.event_stream.state}
	if talk.visible:
		note.dialogue = {"heading":talk.heading.text, "summary":talk.summary.text, "speaker":talk.speaker.text, "subtitle":talk.subtitle.text,
			"line":talk.line.text, "based_on":talk.based_on.text, "options":talk.options.map(func(o): return o.text)}
	notes[name] = note
	print("CAPTURED ", name, " ", JSON.stringify(note))

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

func board_checks(tag: String) -> void:
	var board = world.hud.crew_board
	check(board.visible and world.hud.workspace_label.text in ["CREW BOARD", "CREW DIALOGUE"], tag + " board open")
	check(board.freshness.text.begins_with("[~] LIVE · last event") and board.freshness.text.ends_with("SYNTHETIC REPLAY"), tag + " board freshness: " + board.freshness.text)
	check(board.needs_title.text == "[!] NEEDS YOU · 2 known · 1 unknown · oldest first", tag + " needs heading: " + board.needs_title.text)
	check(board.need_rows[0].title.text == "Review PR #118 on algent" and board.need_rows[0].action.text == "Open PR", tag + " PR need")
	check(board.need_rows[1].title.text == "Publish policy ends in 2d 14h" and board.need_rows[1].action.text == "Extend", tag + " policy need")
	check(board.need_rows[2].title.text == "Memory notes · not in these records", tag + " memory unknown")
	check(board.chips[0].button.text == "[x] Next mission blocked: active_mission" and board.chips[1].button.text.begins_with("[/] Wes silent "), tag + " chips: " + board.chips[1].button.text)
	check(board.crew_buttons.repair.text.contains("[>] working · [>] Running tests"), tag + " Rivet row: " + board.crew_buttons.repair.text)
	check(board.crew_buttons.watchkeeper.text.contains("silent") and board.crew_buttons.watchkeeper.text.contains("last known"), tag + " Wes row")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if DisplayServer.get_name() == "headless":
		push_error("Native crew board capture requires a renderer")
		quit(1)
		return
	create_timer(300).timeout.connect(func(): push_error("Crew board capture watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	await resize(Vector2i(1440, 900))
	world = load("res://main.tscn").instantiate()
	world.stream_fixture_path = STREAM
	world.player_preferences_path = ""
	root.add_child(world)
	world.isolate_capture_input()
	await process_frame
	check(world.fixture_path.ends_with("crew-board-world.json") and not world.hud.board.fixture.is_empty(), "Offline fixtures only")
	check(world.event_stream.fixture_mode and world.event_stream.client == null, "No network stream")
	world.hud.close_panels()
	await settle(2.0)
	await replay()
	var board = world.hud.crew_board
	var talk = world.hud.crew_dialogue
	world.hud.toggle_crew_board()
	await settle(0.5)
	board_checks("1440")
	check(board.feed_title.text == "ACTIVITY · ALL CREW AND CORE · NEWEST FIRST", "Unfiltered feed")
	check(board.day_name.text == "Moss · lead · duty officer" and board.talk.text == "Talk to Moss [T]", "Duty officer by default")
	await picture("crew-board")
	board.select("repair")
	await settle(0.3)
	check(board.feed_title.text == "ACTIVITY · RIVET ONLY · NEWEST FIRST" and board.day_now.text.begins_with("[>] Running tests · mission 42, round 2"), "Rivet selected: " + board.day_now.text)
	check(board.feed_rows.filter(func(r): return r.row.visible).all(func(r): return r.who.text == "Rivet"), "Feed shows only Rivet")
	await picture("crew-board-filtered")
	board.request_talk("why_blocked")
	await settle(0.3)
	check(talk.visible and talk.speaker.text == "Rivet" and talk.line.text.begins_with("\"Core refused admission with active_mission."), "Rivet answers why we can't start")
	check(talk.options[4].get_global_rect().end.y <= talk.get_global_rect().end.y and talk.get_global_rect().end.y <= 900, "Questions visible inside the dialogue")
	check(talk.based_on.get_global_rect().end.y <= talk.options[0].get_global_rect().position.y, "Based on line visible above the questions")
	check(talk.based_on.text.begins_with("Based on: admission active_mission · mission sdlc-42 state implementing"), "Based on line: " + talk.based_on.text)
	await picture("crew-dialogue")
	talk.close()
	board.select("watchkeeper")
	board.request_talk("accounted")
	await settle(0.3)
	check(talk.speaker.text == "Moss" and talk.subtitle.text.contains("answering for Wes") and talk.subtitle.text.contains("last known"), "Moss answers for stale Wes: " + talk.subtitle.text)
	check(talk.line.text.begins_with("\"Not Wes.") and talk.based_on.text.begins_with("Based on: Wes record wes-workload-1336"), "Accounted answer: " + talk.line.text)
	await picture("crew-dialogue-stale")
	talk.close()
	board.select("")
	await resize(Vector2i(960, 700))
	world.hud.layout_hud()
	# Replay again so the compact frame is live rather than a stale stream.
	await replay()
	board_checks("960")
	var area: Rect2 = board.get_global_rect()
	check(area.end.x <= 960 and area.end.y <= 700, "Compact board inside the window: " + str(area))
	await picture("crew-board-compact")
	var path := ProjectSettings.globalize_path(output).path_join("captures.json")
	var existing = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	if not existing is Dictionary: existing = {}
	existing["crew_board"] = {"fixture":STREAM, "synthetic":true, "engine":Engine.get_version_info().string,
		"renderer":RenderingServer.get_current_rendering_driver_name(), "captures":notes}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(existing, "  "))
	file.close()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CREW_BOARD_CAPTURE_PASSED: board, filtered board, dialogue, stale dialogue and compact captures")
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
