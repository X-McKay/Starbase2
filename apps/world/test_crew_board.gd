extends SceneTree
## Crew board (page 5) and crew dialogue (page 6): the projection from records,
## the templated answers with their "Based on:" sources, distinct unknown /
## stale / silent / idle / blocked states, keyboard access (Tab, traversal,
## Enter, T, W, 1–5, Esc), the action buttons, and layout at wide, compact and
## large-text sizes. Synthetic fixtures only; nothing connects or dispatches.
const Model = preload("res://crew_board_model.gd")
const Dialogue = preload("res://crew_dialogue.gd")
const Activity = preload("res://live_activity.gd")
const Stream = preload("res://event_stream.gd")
const StateView = preload("res://state.gd")
const FIXTURE := "res://../../fixtures/world/transparency/"
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()

func key(code: Key, pressed: bool = true, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.shift_pressed = shift
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(code: Key, shift: bool = false) -> void:
	key(code, true, shift)
	await process_frame
	key(code, false, shift)
	await process_frame

func overlaps(a: Rect2, b: Rect2) -> bool:
	return a.intersects(b) and a.intersection(b).get_area() > 1.0

## Replays the crew board stream fixture to its end and returns a context built
## exactly like the world builds it, from the paired synthetic snapshots.
func context() -> Dictionary:
	var stream = Stream.new()
	root.add_child(stream)
	var log := Activity.new()
	stream.record_event.connect(func(evt): log.ingest(evt, stream.now_msec()))
	stream.activity.connect(func(evt): log.ingest(evt, stream.now_msec()))
	stream.start_fixture(FIXTURE + "crew-board-stream.jsonl")
	stream.clock_offset_msec += 20000
	stream.advance_fixture()
	var offset: float = stream.fixture_time_offset
	var v7 = Stream.rebase(JSON.parse_string(FileAccess.get_file_as_string(FIXTURE + "crew-board-v7.json")), offset)
	var v2 = Stream.rebase(JSON.parse_string(FileAccess.get_file_as_string(FIXTURE + "crew-board-world.json")), offset)
	var ctx := {"now":float(v2.observed_at), "v7":v7, "v7_current":true, "v7_age":1.2, "v2_missions":StateView.project(v2),
		"v2_disconnected":false, "v2_observed_at":float(v2.observed_at), "activity":log, "stream_live":true,
		"now_msec":stream.now_msec(), "freshness":"[~] LIVE · last event 0.8 s ago · SYNTHETIC REPLAY", "stream":stream}
	return ctx

func model_checks(ctx: Dictionary) -> void:
	var model := Model.build(ctx)
	var needs: Array = model.needs
	check(needs.size() == 3 and model.needs_known == 2 and model.needs_unknown == 1, "Two known needs and one unknown: " + str(needs.map(func(n): return n.title)))
	check(needs[0].title == "Review PR #118 on algent" and needs[0].action.kind == "open_url" and needs[0].action.url == "https://github.com/X-McKay/algent/pull/118", "PR need first with the recorded link: " + str(needs[0]))
	check(str(needs[0].detail).begins_with("Mission 41 passed the gate · crew never merge · 4 h"), "PR need detail: " + str(needs[0].detail))
	check(needs[1].title == "Publish policy ends in 2d 14h" and needs[1].action.kind == "unavailable" and str(needs[1].action.reason).begins_with("Not available here"), "Policy need says Extend is not available here: " + str(needs[1]))
	check(needs[2].title == "Memory notes · not in these records" and needs[2].action.kind == "open_memory" and needs[2].get("unknown", false), "Memory queue is unknown, not zero")
	var chips: Array = model.chips.map(func(c): return c.text)
	check(chips == ["[x] Next mission blocked: active_mission", "[/] Wes silent 6 m"], "Alert chips: " + str(chips))
	var moss := Model.person(model, "review")
	var rivet := Model.person(model, "repair")
	var prism := Model.person(model, "reviewer")
	var wes := Model.person(model, "watchkeeper")
	var mae := Model.person(model, "gym")
	check(moss.status == "waiting" and moss.now == "Holding mission 42 while Rivet is implementing", "Moss waits: " + str(moss.now))
	check(moss.next == "Wait for mission 42 round 2 to finish", "Moss up next: " + str(moss.next))
	check(rivet.status == "working" and rivet.now == "[>] Running tests · mission 42, round 2", "Rivet's fresh verb: " + str(rivet.now))
	check(rivet.next == "Hand round 2 to Core for testing", "Rivet up next: " + str(rivet.next))
	check(rivet.tokens == "3.1k tokens observed this session", "Tokens are only those observed: " + str(rivet.tokens))
	check(prism.status == "waiting" and prism.next == "Review mission 42 round 2 after Core's tests", "Prism up next: " + str(prism.next))
	check(wes.status == "silent" and wes.last_known and wes.now == "Last known: workload check on training workload (unconfirmed)" and wes.state_text == "silent 6 m · last known", "Wes silent and last known: " + str(wes))
	check(wes.where == "Cluster watch · last known", "Wes location is last known")
	check(mae.status == "idle" and mae.now == "Nothing recorded right now" and mae.done_count == 0 and mae.runs == 0 and mae.tokens == "tokens not recorded", "Mae idle with nothing recorded: " + str(mae))
	check(moss.done.map(func(d): return d.text) == ["Mission 41 accepted · PR #118 opened for your review", "Repository review on X-McKay/Starbase2 · 2 findings"], "Moss done today: " + str(moss.done))
	check(wes.done_count == 2 and wes.runs == 3, "Wes done and runs in 24 h: %d %d" % [wes.done_count, wes.runs])
	var feed: Array = model.feed
	for index in range(1, feed.size()): check(feed[index - 1].at >= feed[index].at, "Feed is newest first")
	check(feed[0].who == "Rivet" and feed[0].text == "started running tests", "Newest feed item is Rivet's running tests: " + str(feed[0]))
	check(feed.any(func(f): return f.who == "Core" and f.text == "opened PR #118 for mission 41 · waiting for your review"), "Core PR event in the feed")
	check(feed.any(func(f): return f.who == "Wes" and f.text == "last record: workload check on training workload · running"), "Wes's last record in the feed")
	check(feed.filter(func(f): return f.who == "Prism" and f.text.begins_with("requested changes")).size() == 1, "A stream record is not repeated from recent_events")
	var only_wes := Model.filtered_feed(model, "watchkeeper")
	check(only_wes.size() == 3 and only_wes.all(func(f): return f.kind == "watchkeeper"), "Selecting Wes filters the feed: " + str(only_wes.size()))
	# Distinct states when the records are not current.
	var stale_ctx := ctx.duplicate(); stale_ctx.v7_current = false; stale_ctx.stream_live = false
	var stale := Model.build(stale_ctx)
	check(Model.person(stale, "repair").status == "unknown" and Model.person(stale, "repair").now == "Last known: mission 42 · implementing, round 2", "Rivet last known without a current /v7: " + str(Model.person(stale, "repair").now))
	check(stale.chips[0].text == "[x] Next mission blocked: active_mission · last known", "Blocked chip marked last known")
	var off_ctx := ctx.duplicate(); off_ctx.v2_disconnected = true; off_ctx.v7_current = false
	var off := Model.build(off_ctx)
	check(Model.person(off, "gym").status == "unknown" and Model.person(off, "gym").now == "Unknown · Core disconnected", "Disconnected Mae is unknown, not idle")
	check(Model.person(off, "watchkeeper").status == "silent", "A silent record stays silent while disconnected")
	check(off.chips.any(func(c): return c.text == "[x] Core disconnected · last known"), "Disconnected chip")
	var empty := Model.build({"now":1790000000.0, "v2_disconnected":false, "v7_current":false})
	check(empty.chips[0].text == "[?] Admission unknown" and empty.needs.size() == 1 and empty.needs_known == 0, "No V7 snapshot: admission unknown and nothing invented")
	var expired: Dictionary = ctx.duplicate(true)
	expired.v7.policy.expires_at = float(ctx.now) - 10.0
	expired.v7.missions[1].publication.pr_url = "https://example.com/pull/118"
	var expired_model := Model.build(expired)
	check(expired_model.needs.any(func(n): return n.title == "Publish policy gen 7 expired" and n.glyph == "[x]"), "Expired policy is a failure, not a warning")
	check(expired_model.needs[0].action.kind == "unavailable", "An unsafe PR link is never opened")
	dialogue_checks(model, stale, off)

func dialogue_checks(model: Dictionary, stale: Dictionary, off: Dictionary) -> void:
	var waiting := Dialogue.answer(model, "waiting", "review")
	check(waiting.speaker.name == "Moss" and waiting.speaker.get("for", "") == "", "Moss speaks for himself")
	check(waiting.line == "Two things.\nMission 41 opened PR #118 on algent and is waiting for your review.\nOur publish policy ends in 2d 14h.\nI can't see the memory review queue from these records; Field ops has it.", "Waiting answer: " + waiting.line)
	check(waiting.based_on == "Based on: mission sdlc-41 awaiting_review · PR #118 · policy gen 7 expires_at · memory review queue not read (/v4)", "Waiting sources: " + waiting.based_on)
	var blocked := Dialogue.answer(model, "why_blocked", "repair")
	check(blocked.speaker.name == "Rivet", "Rivet answers for himself")
	check(blocked.line == "Core refused admission with active_mission.\nRivet is still on mission 42, implementing, round 2. When it finishes, the next one can start.", "Blocked answer: " + blocked.line)
	check(blocked.based_on == "Based on: admission active_mission · mission sdlc-42 state implementing · /v7 snapshot 1 s ago", "Blocked sources: " + blocked.based_on)
	var about_wes := Dialogue.answer(model, "accounted", "watchkeeper")
	check(about_wes.speaker.name == "Moss" and about_wes.speaker["for"] == "watchkeeper" and str(about_wes.speaker.subtitle).contains("answering for Wes (silent 6 m · last known)"), "Moss answers for stale Wes: " + str(about_wes.speaker))
	check(about_wes.line.begins_with("Not Wes. Nothing from the watchkeeper has changed in 6 m. The last thing recorded is workload check on training workload. I am not treating that as healthy."), "Accounted answer: " + about_wes.line)
	check(about_wes.line.ends_with("Everyone else is accounted for: Moss waiting, Rivet working, Prism waiting and Mae idle."), "Others accounted: " + about_wes.line)
	check(about_wes.based_on.begins_with("Based on: Wes record wes-workload-1336 running · last update "), "Accounted sources: " + about_wes.based_on)
	var finished := Dialogue.answer(model, "finished", "repair")
	check(finished.line == "Rivet finished 2 things in the last 24 h:\n· Mission 41 accepted · PR #118 opened for your review.\n· Repair on clamp-v1 · inconclusive.", "Finished answer: " + finished.line)
	check(finished.based_on.begins_with("Based on: 2 terminal records since "), "Finished sources: " + finished.based_on)
	var crew_finished := Dialogue.answer(model, "finished", "review")
	check(crew_finished.line.begins_with("The crew finished 5 things in the last 24 h:"), "Duty officer answers for the crew: " + crew_finished.line)
	var greeting := Dialogue.answer(model, "", "watchkeeper")
	check(greeting.line.begins_with("Wes is silent 6 m · last known, so I'm answering from Wes's last known records."), "Greeting for a stale member: " + greeting.line)
	check(greeting.based_on.is_empty(), "A greeting cites nothing because it claims nothing")
	var last_known := Dialogue.answer(stale, "why_blocked", "review")
	check(last_known.line.begins_with("As of the last snapshot:\nCore refused admission"), "Last known answers say so: " + last_known.line)
	check(Dialogue.speaker_for(off, "repair").kind == "core", "With every crew member last known, the station record answers")
	check(Dialogue.answer(Model.build({"now":1.0, "v2_disconnected":false}), "why_blocked", "review").line == "I don't know. There is no V7 admission state in these records.", "Unknown admission answer")
	check(Dialogue.answer(model, "waiting", "review") == waiting, "Answers are deterministic templates")
	check(Dialogue.tag(model, "accounted").text == "1 LAST KNOWN" and Dialogue.tag(model, "why_blocked").text == "BLOCKED" and Dialogue.tag(model, "waiting").text == "2 NEED YOU", "Question tags")

func world_checks() -> void:
	root.size = Vector2i(1440, 900); root.content_scale_size = root.size
	var world = load("res://main.tscn").instantiate()
	world.stream_fixture_path = FIXTURE + "crew-board-stream.jsonl"
	world.player_preferences_path = ""
	root.add_child(world)
	for _frame in 3: await process_frame
	check(world.event_stream.fixture_mode and world.event_stream.client == null, "No network stream")
	world.event_stream.clock_offset_msec += 20000
	world.event_stream.advance_fixture()
	world.load_stream_fixture_snapshot()
	world.update_crew_presentation()
	var hud = world.hud
	var board = hud.crew_board
	var talk = hud.crew_dialogue
	opened_url = ""
	board.open_url = func(url: String): opened_url = url
	# Tab opens the board and focus lands inside it.
	key(KEY_TAB); await process_frame; key(KEY_TAB, false); await process_frame
	check(board.visible and board.focus_owner_inside(), "Tab opens the crew board with focus inside")
	check(hud.workspace_label.text == "CREW BOARD" and hud.active_navigation == "crew", "Masthead names the board")
	world.update_live_view(1.0)
	check(board.needs_title.text == "[!] NEEDS YOU · 2 known · 1 unknown · oldest first", "Needs heading: " + board.needs_title.text)
	check(board.crew_buttons.watchkeeper.text.contains("[/] silent 6 m · last known"), "Wes row: " + board.crew_buttons.watchkeeper.text)
	# Tab still traverses focus inside the open board (it does not close it).
	var first: Control = get_root().gui_get_focus_owner()
	await tap(KEY_TAB)
	var second: Control = get_root().gui_get_focus_owner()
	check(board.visible and second != first and board.focus_owner_inside(), "Tab moves focus within the board: %s -> %s" % [first, second])
	await tap(KEY_TAB, true)
	check(get_root().gui_get_focus_owner() == first and board.visible, "Shift+Tab moves focus back")
	# Every control in the board is focusable from the keyboard.
	for control in board.find_children("*", "BaseButton", true, false):
		check(control.focus_mode != Control.FOCUS_NONE, "Keyboard reachable: " + control.name)
	# Select Wes with the keyboard: focus his row, Enter.
	board.crew_buttons.watchkeeper.grab_focus()
	await tap(KEY_ENTER)
	check(board.selected == "watchkeeper", "Enter selects the focused crew member")
	check(board.feed_title.text == "ACTIVITY · WES ONLY · NEWEST FIRST" and board.show_all.visible, "Feed filtered to Wes")
	var shown: Array = board.feed_rows.filter(func(r): return r.row.visible).map(func(r): return r.who.text)
	check(shown.size() == 3 and shown.all(func(w): return w == "Wes"), "Only Wes's events: " + str(shown))
	check(board.day_now.text == "Last known: workload check on training workload (unconfirmed)" and board.talk.text == "Ask Moss about Wes [T]", "Wes's day and talk label: " + board.talk.text)
	# T opens the dialogue; Moss answers for Wes.
	await tap(KEY_T)
	check(talk.visible and talk.speaker.text == "Moss" and talk.subtitle.text.contains("answering for Wes"), "T opens the dialogue with Moss for Wes")
	check(hud.live_view.wide_open, "T in the board does not toggle the live activity panel")
	await tap(KEY_3)
	check(talk.line.text.begins_with("\"Not Wes.") and talk.based_on.text.begins_with("Based on: Wes record"), "3 asks whether everyone is accounted for: " + talk.line.text)
	check(not hud.dock.visible, "Number keys answer in the dialogue instead of opening a dossier")
	await tap(KEY_ESCAPE)
	check(not talk.visible and board.visible and board.talk.has_focus(), "Esc closes only the dialogue and returns to Talk")
	# Needs actions: Open PR uses the recorded link; Extend is not available here.
	board.need_rows[0].action.grab_focus()
	await tap(KEY_ENTER)
	check(opened_url == "https://github.com/X-McKay/algent/pull/118", "Open PR opens the recorded link: " + opened_url)
	board.need_rows[1].action.pressed.emit()
	check(board.action_status.visible and board.action_status.text.begins_with("Extend · Not available here"), "Extend says it is not available here: " + board.action_status.text)
	# A chip opens the dialogue on its question.
	board.chips[0].button.pressed.emit()
	check(talk.visible and talk.question == "why_blocked" and talk.line.text.contains("Core refused admission with active_mission."), "Blocked chip asks why")
	await tap(KEY_ESCAPE)
	# W watches the selected crew member (on release).
	board.select("repair")
	key(KEY_W); await process_frame
	check(board.visible, "W acts on release")
	key(KEY_W, false); await process_frame
	check(not board.visible and world.watched_crew == "repair", "W watches the selected crew member")
	world.stop_watching()
	# Memory action opens the existing Field ops memory page.
	hud.toggle_crew_board()
	board.need_rows[2].action.pressed.emit()
	check(hud.board.visible and hud.board.tabs.current_tab == 2, "Review in Field ops opens the memory page")
	hud.close_panels()
	# The navigation button opens the board; P keeps the directory.
	hud.nav_buttons.crew.pressed.emit()
	check(board.visible, "Crew navigation opens the board")
	await tap(KEY_ESCAPE)
	check(not board.visible and not hud.is_open(), "Esc closes the board")
	await tap(KEY_P)
	check(hud.directory.visible, "P opens Crew & places")
	await tap(KEY_ESCAPE)
	await tap(KEY_T)
	check(not hud.live_view.wide_open, "T outside the board still toggles live activity")
	hud.live_view.toggle_activity()
	await layout_checks(world)
	world.queue_free()
	await process_frame

var opened_url := ""

func layout_checks(world: Node) -> void:
	var hud = world.hud
	var board = hud.crew_board
	for case in [[Vector2i(1440, 900), false], [Vector2i(960, 700), false], [Vector2i(960, 700), true], [Vector2i(1440, 900), true]]:
		var size: Vector2i = case[0]
		root.size = size; root.content_scale_size = size
		hud.large_text = case[1]; hud.scale_text()
		hud.toggle_crew_board()
		world.update_live_view(1.0)
		for _frame in 4: await process_frame
		var tag := "%s large=%s" % [str(size), str(case[1])]
		var area: Rect2 = board.get_global_rect()
		check(area.position.x >= 0 and area.position.y >= hud.header_panel.get_global_rect().end.y - 1 and area.end.x <= size.x and area.end.y <= size.y, "Board inside the window below the masthead: %s %s" % [tag, str(area)])
		if size.x < 1000: check(area.position.y >= hud.navigation_bar.get_global_rect().end.y, "Board below compact navigation: " + tag)
		var nav: Rect2 = hud.navigation_bar.get_global_rect()
		check(not overlaps(area, nav), "Board clears the navigation: %s nav=%s" % [tag, str(nav)])
		var left: Rect2 = board.columns.get_child(0).get_global_rect()
		var right: Rect2 = board.columns.get_child(1).get_global_rect()
		check(not overlaps(left, right) and right.end.x <= area.end.x + 1 and left.end.y <= area.end.y + 1 and right.end.y <= area.end.y + 1, "Columns side by side inside the board: %s %s %s" % [tag, str(left), str(right)])
		check(board.talk.is_visible_in_tree() and board.talk.get_global_rect().end.y <= area.end.y and board.watch.get_global_rect().end.x <= area.end.x + 1, "Talk and Watch visible: " + tag)
		check(board.needs_title.get_theme_font_size("font_size") == (16 if case[1] else 13), "Larger text applies to the board: " + tag)
		board.request_talk("waiting")
		for _frame in 3: await process_frame
		var talk_rect: Rect2 = hud.crew_dialogue.get_global_rect()
		check(talk_rect.position.x >= area.position.x and talk_rect.end.x <= area.end.x + 1 and talk_rect.end.y <= size.y, "Dialogue inside the board: %s %s" % [tag, str(talk_rect)])
		var last_option: Rect2 = hud.crew_dialogue.options[4].get_global_rect()
		check(last_option.end.y <= talk_rect.end.y + 1, "All five questions visible: %s %s" % [tag, str(last_option)])
		if size.y >= 900: check(hud.crew_dialogue.based_on.get_global_rect().end.y <= hud.crew_dialogue.options[0].get_global_rect().position.y, "Based on visible without scrolling: " + tag)
		hud.close_panels()
	root.size = Vector2i(1440, 900); root.content_scale_size = root.size
	hud.large_text = false; hud.scale_text()

func run() -> void:
	var ctx := context()
	model_checks(ctx)
	ctx.stream.queue_free()
	await world_checks()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CREW_BOARD_PASSED: needs, alerts, feed, crew day, filtered feed, templated answers with sources, stale member via Moss, keyboard Tab/Enter/T/W/1-5/Esc, actions, layout")
	quit(0 if failures.is_empty() else 1)
