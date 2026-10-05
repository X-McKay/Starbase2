extends SceneTree
## Captain's Log (page 4): events come only from records, distinct record states,
## collapsed quiet gaps, lanes, keyboard and click selection, the chronological
## list equivalent and the layout at wide, compact and large-text sizes.
const Model = preload("res://captains_log_model.gd")
const Activity = preload("res://live_activity.gd")
const Stream = preload("res://event_stream.gd")
const FIXTURE := "res://../../fixtures/world/transparency/"
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()

func load_json(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE + name))

## Replay the synthetic stream fully, as the world does, and return the inputs.
func story() -> Dictionary:
	var stream = Stream.new()
	root.add_child(stream)
	var log := Activity.new()
	stream.record_event.connect(func(evt): log.ingest(evt, stream.now_msec()))
	stream.activity.connect(func(evt): log.ingest(evt, stream.now_msec()))
	stream.start_fixture(FIXTURE + "stream.jsonl")
	stream.clock_offset_msec += 20000
	stream.advance_fixture()
	var offset: float = stream.fixture_time_offset
	var snapshot: Dictionary = Stream.rebase(load_json("v7-snapshot.json"), offset)
	var record: Dictionary = Stream.rebase(load_json("mission-sdlc-42.json"), offset)
	var data := {"stream":stream, "log":log, "snapshot":snapshot, "record":record, "offset":offset,
		"summary":Activity.mission_summary(snapshot, "sdlc-42"), "now":1790000000.0 + offset}
	return data

func titles(model: Dictionary) -> Array:
	return model.events.map(func(e): return str(e.lane) + " " + str(e.glyph) + " " + str(e.title))

func fixture_consistency(data: Dictionary) -> void:
	# The full record must agree with the summary it pairs with.
	var record: Dictionary = data.record
	var summary: Dictionary = data.summary
	check(record.events.size() == int(summary.event_count), "Record holds event_count events")
	var tail: Array = record.events.slice(record.events.size() - 3).map(func(e): return [e.key, e.at])
	check(tail == summary.recent_events.map(func(e): return [e.key, e.at]), "Record tail matches recent_events")
	check(record.created_at == summary.created_at and record.updated_at == summary.updated_at and record.revision_loops == summary.revision_count, "Record times and round match the summary")
	check(str(record._fixture).begins_with("SYNTHETIC FIXTURE"), "Full record is labelled synthetic")

func mission_42(data: Dictionary) -> void:
	var model := Model.build(data.record, data.summary, data.log.entries, {"now":data.now, "record_state":"fixture", "coordination":data.snapshot.coordination, "snapshot_known":true})
	var shown := titles(model)
	check(shown == [
		"core [/] Mission admitted",
		"core [/] Sources captured · 3 files",
		"lead [>] Plan handed to Rivet",
		"implementer [/] Patch round 1 · +6 −2",
		"core [=] Graded round 1 · improved",
		"reviewer [x] Changes requested · 2 findings",
		"implementer [/] Rivet applied a patch · ok",
		"implementer [x] Rivet ran tests · failed",
		"implementer [>] Rivet started running tests"], "Mission 42 timeline: " + str(shown))
	check(model.title == "Mission 42 · Fix cache eviction", "Title: " + model.title)
	check(model.meta.begins_with("X-McKay/algent · admitted ") and model.meta.contains("now implementing round 2") and model.meta.contains("19.3k tokens retained") and model.meta.ends_with("cost not recorded"), "Meta line: " + model.meta)
	var lanes: Array = model.lanes.map(func(l): return l.name + "|" + l.role + "|" + l.tokens_text)
	check(lanes == ["Moss|lead|6.1k tokens · 1 request", "Rivet|implementer|8.7k tokens · 1 request", "Prism|reviewer|4.5k tokens · 1 request", "Core|grader and gate|no model use · grades and gates"], "Lanes and retained tokens: " + str(lanes))
	for i in model.events.size():
		var e: Dictionary = model.events[i]
		check(int(e.n) == i + 1 and not str(e.source).is_empty(), "Event %d numbered and sourced" % i)
		if i > 0: check(float(e.at) >= float(model.events[i - 1].at), "Chronological order at %d" % i)
		check(float(e.f) >= 0.0 and float(e.f) <= 1.0, "Event %d placed on the axis" % i)
	var plan: Dictionary = model.events[2]
	check(plan.body == "Fix cache eviction so the least recently used entry leaves first" and plan.evidence.has("Decision · implement"), "Plan evidence from the record")
	check(plan.not_recorded.has(Model.NOT_RECORDED_REASONING), "Model reasoning is reported as not recorded")
	check(plan.source.begins_with("/v7/missions/sdlc-42 · events[1]"), "Plan cites its record entry: " + plan.source)
	var grade: Dictionary = model.events[4]
	check(grade.evidence.has("Cases · candidate 6/6 · baseline 4/6"), "Current-round cases come from retained stage evidence: " + str(grade.evidence))
	var patch: Dictionary = model.events[3]
	check(patch.not_recorded.has(Model.NOT_RECORDED_TOOL_ARGS), "Tool arguments are reported as not recorded")
	var review: Dictionary = model.events[5]
	check(review.evidence[0] == "Finding · algent/cache.py:41 · Size check uses > instead of >= · evidence: case_5 boundary", "Review findings: " + str(review.evidence))
	var note: Dictionary = model.events[7]
	check(note.kind == "observation" and note.source.contains("transient") and note.tone == "observed", "Stream notes are observations, not records")
	check(model.events[8].evidence.has("Outcome · in progress"), "An open note reads in progress")
	for e in model.events:
		check(e.kind in ["record", "observation"], "No provisional pins once the record holds every streamed key")
	# The live mission is not terminal: the now line is drawn.
	check(float(model.now_f) > 0.0 and not model.terminal, "Now line for an active mission")
	check(model.bands.map(func(b): return b.state) == ["queued", "investigating", "implementing", "testing", "reviewing"], "State bands from stage records: " + str(model.bands.map(func(b): return b.state)))
	var status: Array = model.status.map(func(s): return s.glyph + " " + s.text)
	check(status == ["[=] Synthetic fixture record · 4 retained events", "[-] Admission now · active mission (current Core state, not a timeline event)"], "Fixture status lines: " + str(status))
	var list: Array = model.events.map(func(e): return Model.list_line(e))
	check(list[0].begins_with("1. ") and list[0].contains(" UTC · Core · [/] Mission admitted"), "List line: " + list[0])
	check(list[7].ends_with("· observed, not retained"), "List marks observations: " + list[7])
	# Keyboard lane travel: from Rivet's patch, up is Moss and down is Prism (nearest in time).
	check(model.events[Model.neighbour_in_lane(model.events, 3, -1)].lane == "lead", "Up moves to the lead lane")
	check(model.events[Model.neighbour_in_lane(model.events, 3, 1)].lane == "reviewer", "Down moves to the reviewer lane")
	check(Model.neighbour_in_lane(model.events, 2, -1) == 2, "Up from the top lane stays put")

func states(data: Dictionary) -> void:
	var base := {"now":data.now, "coordination":{}, "snapshot_known":true}
	var lines := func(record: Dictionary, summary: Dictionary, state: String, extra: Dictionary = {}) -> Array:
		var options: Dictionary = base.duplicate()
		options.record_state = state
		options.merge(extra, true)
		return Model.build(record, summary, [], options).status.map(func(s): return s.glyph + " " + s.text)
	check(lines.call(data.record, data.summary, "live", {"record_age":2.0}) == ["[=] Full record · read 2.0 s ago · 4 retained events"], "Live record")
	check(lines.call(data.record, data.summary, "stale")[0].begins_with("[?] LAST KNOWN"), "Stale record is last known")
	check(lines.call(data.record, data.summary, "failed")[0] == "[x] Record read failed · showing last known record", "Failed reread keeps the last known record")
	check(lines.call({}, data.summary, "failed")[0] == "[x] Record read failed · showing the bounded summary", "Failed first read")
	check(lines.call({}, data.summary, "loading")[0] == "[-] Reading full record · showing the bounded summary", "Loading")
	check(lines.call({}, {}, "unknown", {"snapshot_known":false}) == ["[?] UNKNOWN · no /v7 snapshot received"], "Unknown: nothing received")
	check(lines.call({}, {}, "unknown") == ["[-] No V7 mission recorded · nothing to show"], "No mission is distinct from unknown")
	var behind: Dictionary = data.summary.duplicate(true)
	behind.event_count = 5
	check(lines.call(data.record, behind, "live").has("[?] Summary reports 5 events; record holds 4 · rereading"), "A record behind its summary says so")
	# Summary fallback: only the bounded recent events, marked as summary only.
	var fallback := Model.build({}, data.summary, [], {"now":data.now, "record_state":"loading"})
	check(fallback.events.size() == 4 and fallback.events.slice(1).all(func(e): return e.kind == "summary"), "Fallback uses recent_events only: " + str(titles(fallback)))
	check(fallback.lanes[0].tokens_text == "unknown · full record not read" and fallback.meta.contains("tokens unknown"), "Tokens unknown without the full record")
	# A stage streamed before the record is reread is provisional, never evidence.
	var older: Dictionary = data.record.duplicate(true)
	older.events = older.events.slice(0, 3)
	var provisional := Model.build(older, data.summary, data.log.entries, {"now":data.now, "record_state":"live"})
	var pending: Array = provisional.events.filter(func(e): return e.kind == "provisional")
	check(pending.size() == 1 and pending[0].lane == "reviewer" and pending[0].glyph == "[~]" and pending[0].evidence.is_empty() == false and pending[0].source.contains("awaiting"), "Streamed review awaits the record: " + str(titles(provisional)))

func mission_40() -> void:
	var record := load_json("mission-sdlc-40.json")
	var summary := {"id":"sdlc-40", "state":"awaiting_review", "objective":"Fix cache eviction", "created_at":record.created_at, "revision_count":1, "event_count":12, "stage_evidence":{}}
	var model := Model.build(record, summary, [], {"now":record.updated_at + 7200.0, "record_state":"live"})
	var shown := titles(model)
	check(shown.has("implementer [x] Patch round 1 rejected · not executed"), "Rejected patch")
	check(shown.has("core [x] Graded round 1 · ineligible"), "Failed grade")
	check(shown.has("core [x] Validator · revise · nothing ran") and shown.has("core [x] Patch returned · not executed"), "Validator records on the Core lane")
	check(shown.has("reviewer [=] Review accepted · 0 findings"), "Accepted review")
	check(shown.has("core [=] Gates passed · ready to publish") and shown.has("core [>] Publication authority claimed"), "Gate and claim")
	check(shown.has("core [/] PR opened #17") and shown.has("core [=] PR #17 submitted") and shown.has("core [/] PR #17 observed · open"), "PR opened and observed")
	check(shown[-2] == "core [-] Awaiting human review", "Awaiting review: " + str(shown))
	check(model.terminal and float(model.now_f) < 0.0, "Terminal missions draw no now line")
	var gaps: Array = model.ticks.filter(func(t): return t.gap)
	check(gaps.size() == 1 and str(gaps[0].label) == "≈ 3 h quiet", "The 3 h CI wait is collapsed: " + str(model.ticks.map(func(t): return t.label)))
	var submitted: Dictionary = model.events.filter(func(e): return e.key == "submitted")[0]
	var waiting: Dictionary = model.events.filter(func(e): return e.key == "awaiting-review")[0]
	check(float(waiting.f) - float(submitted.f) < 0.2, "A collapsed gap takes little width: %.3f" % (float(waiting.f) - float(submitted.f)))
	check(model.lanes[1].tokens_text == "≥2.4k tokens · 2 requests · 1 usage not recorded", "Unknown usage is not counted as zero: " + model.lanes[1].tokens_text)
	check(model.meta.contains("≥"), "Mission tokens marked as a lower bound")
	var claim: Dictionary = model.events.filter(func(e): return e.key == "publication-claim")[0]
	check(claim.evidence.has("Effect claims · branch, pr") and claim.body.contains("no merge"), "Claim evidence")
	check(submitted.body.contains("not a merge"), "PR submitted is not a merge")
	# No-change and refusal (blocked) records stay distinct.
	var empty: Dictionary = record.duplicate(true)
	empty.events[5].event.data.diff = "--- algent/cache.py\n+++ algent/cache.py\n"
	check(titles(Model.build(empty, summary, [], {"now":record.updated_at})).has("implementer [-] Patch round 2 · no change"), "Empty diff reads as no change")
	var blocked := {"id":"sdlc-39", "state":"blocked", "created_at":1.0e9, "events":[
		{"key":"lead-abstain", "at":1.0e9 + 30, "event":{"key":"lead-abstain", "stage":"blocked", "data":{"role":"lead", "output":{"decision":"abstain", "rationale":"No reproduced mismatch."}, "usage":{"input_tokens":10, "output_tokens":2}}}},
		{"key":"workflow-ended", "at":1.0e9 + 40, "event":{"key":"workflow-ended", "stage":"blocked", "data":{"reason":"A bounded activity failed", "external_effect_may_have_started":false}}},
		{"key":"reviewer-model-failed", "at":1.0e9 + 50, "event":{"key":"reviewer-model-failed", "stage":"blocked", "data":{"role":"reviewer", "error_type":"TimeoutError", "usage":null, "elapsed_ms":125000}}}]}
	var refused := titles(Model.build(blocked, {"id":"sdlc-39"}, [], {"now":1.0e9 + 60}))
	check(refused == ["core [/] Mission admitted", "lead [x] Lead abstained · mission blocked", "core [x] Blocked · bounded activity ended", "reviewer [x] Model request failed · TimeoutError"], "Refusals and blocks: " + str(refused))

func axis() -> void:
	var a := Model.build_axis([100.0, 160.0, 220.0, 5000.0], 100.0, 5060.0)
	check(a.segments.filter(func(s): return s.collapsed).size() == 1, "One long gap collapsed")
	check(Model.position(a, 100.0) > 0.0 and Model.position(a, 5060.0) < 1.0, "Padding keeps edge pins inside")
	check(Model.position(a, 160.0) < Model.position(a, 220.0) and Model.position(a, 220.0) < Model.position(a, 5000.0), "Monotonic placement")
	var even := Model.build_axis([10.0, 20.0, 30.0], 0.0, 40.0)
	check(even.segments.all(func(s): return not s.collapsed), "Regular spacing is not collapsed")
	check(Model.duration(10800) == "3 h" and Model.duration(150) == "3 m" and Model.duration(42) == "42 s", "Durations")

func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event

func overlaps(a: Rect2, b: Rect2) -> bool:
	return a.grow(-1).intersects(b.grow(-1))

func view(data: Dictionary) -> void:
	root.size = Vector2i(1440, 900)
	root.content_scale_size = root.size
	var hud = load("res://hud.gd").new()
	hud.board_fixture = "__empty_visual_fixture__"
	root.add_child(hud)
	await process_frame
	var log = hud.captains_log
	check(log != null and log.get_parent() == hud.root and not log.visible, "Captain's Log is a hidden HUD workspace")
	var controls := ""
	for label in hud.help.find_children("*", "Label", true, false): controls += label.text + "\n"
	check(controls.contains("G  ·  Captain's Log (mission timeline)"), "Controls help lists the G key")
	log.fixture_records = {"sdlc-42":FIXTURE + "mission-sdlc-42.json"}
	log.fixture_offset = data.offset
	hud.open_captains_log()
	check(log.visible and hud.is_open(), "Opening the log is an open workspace")
	check(hud.workspace_label.text == "CAPTAIN'S LOG", "Workspace label")
	var freshness := {"text":"[~] LIVE · last event 0.8 s ago · SYNTHETIC REPLAY", "live":true}
	log.update_from(data.snapshot, true, "sdlc-42", data.log.entries, freshness, data.now)
	await process_frame
	await process_frame
	var count: int = log.events().size()
	check(count == 9 and log.pins.size() == count and log.list_items.size() == count, "One pin and one list row per event")
	check(log.selected == 5 and log.detail_title.text == "[x] Changes requested · 2 findings", "Opens on the newest retained record: " + log.detail_title.text)
	check(log.detail_count.text == "EVENT 6 OF 9", "Detail count")
	check(log.status_box.get_child(0).text.begins_with("[~] LIVE"), "Freshness line in the header")
	# Keyboard: , . and arrows step in time; up/down change lane; Home/End.
	log._input(key(KEY_PERIOD))
	check(log.selected == 6, "Period steps forward")
	log._input(key(KEY_COMMA)); log._input(key(KEY_LEFT))
	check(log.selected == 4 and log.detail_title.text == "[=] Graded round 1 · improved", "Comma and Left step back")
	log._input(key(KEY_UP))
	check(log.events()[log.selected].lane == "reviewer", "Up moves to the lane above")
	log._input(key(KEY_HOME))
	check(log.selected == 0, "Home selects the first event")
	log._input(key(KEY_END))
	check(log.selected == 8, "End selects the last event")
	# Click.
	log.pins[2].pressed.emit()
	check(log.selected == 2 and log.detail_title.text == "[>] Plan handed to Rivet", "Clicking a pin selects it")
	var evidence: Array = log.detail_evidence.get_children().map(func(l): return l.text)
	check(evidence.has("› Decision · implement"), "Detail shows record evidence: " + str(evidence))
	check(log.detail_missing.get_child(0).text == "› " + Model.NOT_RECORDED_REASONING, "Detail says what is not recorded")
	check(log.detail_source.text.begins_with("/v7/missions/sdlc-42 · events[1]"), "Detail cites the record")
	# Tab order is chronological, and focusing a pin selects it.
	for i in log.pins.size():
		check(log.pins[i].get_node(log.pins[i].focus_next) == log.pins[(i + 1) % log.pins.size()], "Tab order follows time at pin %d" % i)
	await process_frame
	log.pins[3].grab_focus()
	await process_frame
	check(log.selected == 3, "Focus (Tab) selects the event")
	# Pins in each lane row and inside the canvas.
	for i in log.pins.size():
		var pin: Button = log.pins[i]
		var lane: int = Model.LANES.find(str(log.events()[i].lane))
		check(absf(pin.position.y - (log.lane_top(lane) + (float(log.geometry().lane_h) - log.PIN) * 0.5)) < 1.0, "Pin %d sits in its lane" % i)
		check(pin.position.x >= 0.0 and pin.position.x + pin.size.x <= log.canvas.size.x + 1.0, "Pin %d inside the timeline: %s" % [i, str(pin.position)])
	# Same-lane pins never overlap.
	for i in log.pins.size():
		for j in range(i + 1, log.pins.size()):
			if log.events()[i].lane == log.events()[j].lane:
				check(not overlaps(log.pins[i].get_global_rect(), log.pins[j].get_global_rect()), "Pins %d and %d do not overlap" % [i, j])
	# The chronological list is the same events with the same selection.
	log._input(key(KEY_L))
	await process_frame
	check(log.list_mode and log.list_scroll.visible and not log.canvas.visible, "L shows the chronological list")
	for i in count: check(log.list_items[i].text == Model.list_line(log.events()[i]), "List row %d matches the event" % i)
	check(log.list_items[3].button_pressed and log.selected == 3, "Selection carries into the list")
	log._input(key(KEY_DOWN))
	check(log.selected == 4 and log.list_items[4].button_pressed, "Down moves to the next row in the list")
	log.list_items[1].pressed.emit()
	check(log.selected == 1, "Clicking a row selects it")
	log._input(key(KEY_L))
	check(not log.list_mode and log.canvas.visible, "L returns to the timeline")
	# Layout at wide, compact and large text.
	for case in [[Vector2i(1440, 900), false], [Vector2i(1440, 900), true], [Vector2i(960, 700), false], [Vector2i(960, 700), true]]:
		var size: Vector2i = case[0]
		root.size = size
		root.content_scale_size = size
		hud.large_text = case[1]
		hud.scale_text()
		hud.sync_world_chrome()
		for _frame in 4: await process_frame
		var tag := "%s large=%s" % [str(size), str(case[1])]
		var panel: Rect2 = log.get_global_rect()
		check(panel.position.x >= 0 and panel.end.x <= size.x and panel.end.y <= size.y, "Log inside the window: %s %s" % [tag, str(panel)])
		var timeline: Rect2 = log.timeline_panel.get_global_rect()
		var detail: Rect2 = log.detail_panel.get_global_rect()
		check(not overlaps(timeline, detail) and detail.end.x <= panel.end.x + 1, "Timeline and detail side by side: %s t=%s d=%s" % [tag, str(timeline), str(detail)])
		if size.x >= 1100:
			check(log.tokens_box.visible and log.tokens_box.get_global_rect().end.y <= panel.end.y, "Token rows on screen: " + tag)
			check(log.canvas.get_global_rect().end.y <= log.tokens_box.get_global_rect().position.y + 1, "Canvas above the token rows: " + tag)
		else:
			var roles: Array = log.lane_labels.map(func(box): return box.get_child(1).text)
			check(not log.tokens_box.visible and roles[1] == "implementer · 8.7k tok", "Compact folds tokens into lane labels: " + str(roles))
		for pin in log.pins: check(timeline.encloses(pin.get_global_rect()), "Pin inside the timeline panel: " + tag)
		check(log.detail_title.get_theme_font_size("font_size") == (22 if case[1] else 19), "Larger text applies to the log: " + tag)
		check(log.close_button.get_global_rect().end.x <= panel.end.x, "Close button on screen: " + tag)
	root.size = Vector2i(1440, 900); root.content_scale_size = root.size
	hud.large_text = false; hud.scale_text()
	# Escape (and any other workspace) closes the log and restores the world.
	hud.close_panels()
	check(not log.visible and not hud.is_open(), "close_panels closes the log")
	hud.open_captains_log()
	hud.open_board()
	check(not log.visible, "Opening another workspace closes the log")
	hud.close_panels()
	# No mission and unknown states render without pins.
	hud.open_captains_log()
	log.update_from({}, false, "", [], {}, data.now)
	await process_frame
	check(log.pins.is_empty() and log.status_box.get_child(0).text == "[?] UNKNOWN · no /v7 snapshot received", "Unknown with no snapshot")
	check(log.detail_title.text == "No mission", "No mission selected")
	hud.queue_free()
	await process_frame

func run() -> void:
	var data := story()
	fixture_consistency(data)
	mission_42(data)
	states(data)
	mission_40()
	axis()
	await view(data)
	data.stream.queue_free()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CAPTAINS_LOG_PASSED: record-only events, distinct states, collapsed gaps, lanes, keyboard/click/Tab selection, list equivalent, layout")
	quit(0 if failures.is_empty() else 1)
