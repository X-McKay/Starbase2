extends SceneTree
## Live crew view: activity panel text, follow-card text, Reality Gate checks
## (missing vs failed vs passed) and the HUD layout at wide/compact/large text.
const Activity = preload("res://live_activity.gd")
const Gate = preload("res://reality_gate.gd")
const Stream = preload("res://event_stream.gd")
const FIXTURE := "res://../../fixtures/world/transparency/"
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()

func story() -> Dictionary:
	var stream = Stream.new()
	root.add_child(stream)
	var log := Activity.new()
	stream.record_event.connect(func(evt): log.ingest(evt, stream.now_msec()))
	stream.activity.connect(func(evt): log.ingest(evt, stream.now_msec()))
	stream.start_fixture(FIXTURE + "stream.jsonl")
	stream.clock_offset_msec += 20000
	stream.advance_fixture()
	var snapshot = Stream.rebase(JSON.parse_string(FileAccess.get_file_as_string(FIXTURE + "v7-snapshot.json")), stream.fixture_time_offset)
	var result := {"stream":stream, "log":log, "snapshot":snapshot}
	return result

func activity_text(data: Dictionary) -> void:
	var log: Activity = data.log
	var lines: Array = log.visible_entries(data.snapshot, 6)
	var texts: Array = lines.map(func(line): return line.glyph + " " + line.text)
	check(lines.size() == 6, "Last six entries shown")
	check(texts == [
		"[=] Core graded round 1 · improved (6/6 vs 4/6)",
		"[x] Prism requested changes · 2 findings",
		"[/] Rivet model request 3 · 3.1k tokens · 4.1 s",
		"[/] Rivet applied a patch · ok",
		"[x] Rivet ran tests · failed",
		"[>] Rivet started running tests"], "Story reads as human activity: " + str(texts))
	for line in lines:
		check(str(line.time).length() == 8 and str(line.time).count(":") == 2, "Timestamped HH:MM:SS: " + str(line.time))
		check(not str(line.color).is_empty(), "Each line has a tone colour in addition to its glyph")
	check(log.entries.size() == 7 and log.entries[0].evt.payload.role == "lead", "Started notes were replaced by their finished notes")
	check(log.visible_entries(data.snapshot, 7)[0].text == "Moss handed the plan to Rivet", "Lead handoff text")
	# Without the snapshot the log still reads, just without retained detail.
	check(log.visible_entries({}, 6)[1].text == "Prism requested changes", "Finding count only from retained evidence")
	check(log.visible_entries({}, 6)[0].text == "Core graded round 1 · improved", "Case counts only from retained evidence")
	log.note_reset("buffer_exceeded", 1790000000.0, data.stream.now_msec())
	check(log.visible_entries(data.snapshot, 1)[0].text == "Stream reset · buffer exceeded · records refetched", "Reset is visible in the log")
	var failed := Activity.describe_note({"kind":"model_request_finished", "role":"reviewer", "request":2, "ok":false, "error":"TimeoutError"})
	check(failed.text == "Prism model request 2 failed · TimeoutError" and failed.glyph == "[x]", "Failed model request")
	check(Activity.describe_note({"kind":"sandbox_finished", "role":"implementer", "ok":true, "elapsed_ms":61000}).text == "Rivet sandbox run finished · 61 s", "Sandbox note")
	check(Activity.describe_note({"kind":"tool_started", "role":"implementer", "verification_id":"v1", "tool":"inspect_diff"}).text == "Verifier rivet started inspecting the diff", "Verifier notes are labelled")
	var log2 := Activity.new()
	log2.ingest({"type":"mission.activity", "retained":false, "record_id":"m", "at":1.0, "payload":{"kind":"model_request_finished", "role":"implementer", "request":1, "ok":true, "input_tokens":10, "output_tokens":5}}, 0)
	log2.ingest({"type":"mission.activity", "retained":false, "record_id":"m", "at":2.0, "payload":{"kind":"model_request_finished", "role":"implementer", "request":1, "ok":true, "input_tokens":10, "output_tokens":5}}, 0)
	check(log2.usage_for("m", "implementer") == {"requests":1, "tokens":15}, "A duplicated note is not double-counted")

func follow_card(data: Dictionary) -> void:
	var log: Activity = data.log
	var now: int = data.stream.now_msec()
	var act := log.current("sdlc-42", "implementer", now, true)
	check(act.fresh and act.glyph == "[>]" and act.text == "Running tests", "Current verb from the latest note: " + str(act))
	var intent := {"sdlc_mission_id":"sdlc-42", "unknown":false, "label":"SDLC implementer · implementing"}
	var summary := Activity.mission_summary(data.snapshot, "sdlc-42")
	var card: Array = Activity.follow_card("Rivet", "implementer", intent, summary, act, log.usage_for("sdlc-42", "implementer")).lines
	var texts: Array = card.map(func(line): return line.text)
	check(texts == ["RIVET · IMPLEMENTER", "Mission sdlc-42 · round 2", "[>] Running tests", "1 model request · 3.1k tokens · observed"], "Follow-card text: " + str(texts))
	var stale := log.current("sdlc-42", "implementer", now, false)
	check(not stale.fresh and stale.text.contains("stream not live") and stale.glyph == "[?]", "Stale stream makes activity unknown")
	check(not log.current("sdlc-42", "implementer", now + 121000, true).fresh, "An old note is not a current verb")
	check(log.current("sdlc-42", "reviewer", now, true).text == "No activity observed yet", "No note is distinct from unknown")
	check(not log.current("other-mission", "implementer", now, true).fresh, "Notes from another mission do not apply")
	intent.unknown = true
	texts = Activity.follow_card("Rivet", "implementer", intent, summary, act, {}).lines.map(func(line): return line.text)
	check(texts[2].begins_with("[?] Last known") and texts[3] == "Model requests · none observed", "Unknown assignment overrides the verb")
	texts = Activity.follow_card("Mae", "trainer", {"label":"Between assignments"}, {}, {}, {}).lines.map(func(line): return line.text)
	check(texts.size() == 2 and texts[1].begins_with("No V7 mission assigned"), "Crew without a mission")

func gate(data: Dictionary) -> void:
	var now := Time.get_unix_time_from_system()
	var snapshot: Dictionary = data.snapshot
	var mission := Activity.mission_summary(snapshot, "sdlc-42")
	var model := Gate.evaluate(snapshot, mission, now, true)
	check(model.policy_line == "Policy gen 7 · expires in 2d 14h", "Policy line: " + model.policy_line)
	check(model.budget_line == "1 / 3 missions used · admission active mission", "Budget line: " + model.budget_line)
	var texts: Array = model.checks.map(func(c): return c.text)
	check(texts == ["[=] Policy enabled + publish · allowed", "[=] Test verdict · improved · 6/6 vs 4/6 · +6 −2", "[x] Reviewer · changes requested · 2 findings"], "Gate checks: " + str(texts))
	check(model.summary.text == "CLOSED · 1 failing" and model.summary.glyph == "[x]", "One failing check closes the gate")
	check(model.note == "Opens only for: create branch and pull request. Never merges.", "Authority note")
	# Missing evidence is [?], never passed.
	var bare: Dictionary = mission.duplicate(true)
	bare.stage_evidence = {"plan":null, "testing":null, "reviewing":null}
	var missing := Gate.evaluate(snapshot, bare, now, true)
	check(missing.checks[1].status == "missing" and missing.checks[1].glyph == "[?]" and missing.checks[1].detail == "not recorded", "Missing test evidence")
	check(missing.checks[2].status == "missing" and missing.checks[2].detail == "not recorded", "Missing review evidence")
	check(missing.summary.text == "CLOSED · evidence missing", "Missing evidence keeps the gate closed")
	bare.stage_evidence = {"testing":{"verdict":null}, "reviewing":{"status":"abstain", "findings":[], "findings_truncated":false}}
	missing = Gate.evaluate(snapshot, bare, now, true)
	check(missing.checks[1].detail == "verdict not recorded" and missing.checks[2].status == "missing" and missing.checks[2].detail.begins_with("abstain"), "Unknown verdict and abstention are missing, not failed")
	# Failed vs passed.
	var failed: Dictionary = mission.duplicate(true)
	failed.stage_evidence.testing.verdict = "ineligible"
	failed.stage_evidence.reviewing.status = "accept"
	failed.stage_evidence.reviewing.findings = []
	var result := Gate.evaluate(snapshot, failed, now, true)
	check(result.checks[1].status == "failed" and result.checks[1].text.begins_with("[x] Test verdict · ineligible"), "Failed verdict")
	check(result.checks[2].status == "passed" and result.checks[2].detail == "accepted · 0 findings", "Accepted review")
	failed.stage_evidence.testing.verdict = "improved"
	result = Gate.evaluate(snapshot, failed, now, true)
	check(result.summary.text == "CONDITIONS MET" and result.summary.glyph == "[=]", "All evidence passed")
	check(Gate.evaluate(snapshot, failed, now, false).summary.text == "LAST KNOWN", "A stale snapshot never reads as conditions met")
	# Policy cases.
	var policy: Dictionary = snapshot.duplicate(true)
	policy.policy.expires_at = now - 5
	check(Gate.evaluate(policy, mission, now, true).checks[0].detail == "policy expired" and Gate.evaluate(policy, mission, now, true).policy_line.ends_with("expired"), "Expired policy fails")
	policy.policy.expires_at = now + 600
	policy.policy.publish = false
	check(Gate.evaluate(policy, mission, now, true).checks[0].detail == "publish not authorized", "Publish not authorized")
	policy.erase("policy")
	var unknown := Gate.evaluate(policy, mission, now, true)
	check(unknown.checks[0].status == "missing" and unknown.policy_line == "Policy gen unknown · expiry not reported" and unknown.budget_line.begins_with("missions used unknown"), "Missing policy is unknown")
	var paged: Dictionary = snapshot.duplicate(true)
	paged.page.total = 9
	check(Gate.evaluate(paged, mission, now, true).budget_line.begins_with("≥1 / 3"), "A partial page is a lower bound")
	var empty := Gate.evaluate(snapshot, {}, now, true)
	check(empty.checks[1].detail == "no mission selected" and empty.mission_line == "No mission selected", "No mission")
	check(Gate.duration(59) == "59s" and Gate.duration(3600 * 5 + 120) == "5h 2m" and Gate.duration(86400 * 2 + 3600 * 14 + 1800) == "2d 14h", "Countdown format")

func overlaps(a: Rect2, b: Rect2) -> bool:
	return a.grow(-1).intersects(b.grow(-1))

func layout() -> void:
	var hud = load("res://hud.gd").new()
	hud.board_fixture = "__empty_visual_fixture__"
	root.add_child(hud)
	await process_frame
	var view = hud.live_view
	check(view != null and view.get_parent() == hud.root, "Live view is part of the existing HUD")
	# Regression: the information panels swallowed world clicks on crew under them.
	for panel in [view, view.gate_panel, view.activity_panel, view.card]:
		check(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Live panel lets world clicks through: " + panel.name)
	for container in view.find_children("*", "Container", true, false):
		check(container.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Live layout container lets clicks through: " + container.name)
	var lines: Array = []
	for index in 6: lines.append({"time":"14:0%d:00" % index, "glyph":"[>]", "text":"Rivet started running tests with a long description %d" % index, "color":"6fe3f0"})
	view.set_activity(lines, true)
	view.set_gate(Gate.evaluate({}, {}, 0, true))
	view.set_card([{"text":"RIVET · IMPLEMENTER", "tone":"title"}, {"text":"Mission sdlc-42 · round 2", "tone":"muted"}], Vector2(500, 400), true)
	hud.set_freshness(preload("res://freshness.gd").evaluate("live", 0.8, 5, true, 1.0))
	check(hud.freshness_badge.text == "[~] LIVE · last event 0.8 s ago", "Masthead badge text")
	for case in [[Vector2i(1440, 900), false], [Vector2i(1440, 900), true], [Vector2i(960, 700), false], [Vector2i(960, 700), true], [Vector2i(800, 640), true]]:
		var size: Vector2i = case[0]
		root.size = size
		root.content_scale_size = size
		hud.large_text = case[1]
		hud.scale_text()
		hud.sync_world_chrome()
		for _frame in 4: await process_frame
		var tag := "%s large=%s" % [str(size), str(case[1])]
		var narrow := size.x < 1000
		check(view.activity_panel.visible == (not narrow) and view.activity_tab.visible == narrow, "Activity panel collapses only on narrow windows: " + tag)
		var gate_rect: Rect2 = view.gate_panel.get_global_rect()
		var strip: Rect2 = hud.crew_strip.get_global_rect()
		var prompt: Rect2 = hud.prompt_panel.get_global_rect()
		check(gate_rect.end.x <= size.x - 10 and gate_rect.position.y >= hud.header_panel.get_global_rect().end.y, "Gate panel below the masthead and inside the window: %s gate=%s header=%s" % [tag, str(gate_rect), str(hud.header_panel.get_global_rect())])
		if narrow: check(gate_rect.position.y >= hud.navigation_bar.get_global_rect().end.y, "Gate below compact navigation: " + tag)
		var activity: Rect2 = view.activity_rect()
		check(not overlaps(activity, gate_rect), "Activity does not cover the gate: " + tag)
		for rect in [gate_rect, activity]:
			check(not overlaps(rect, strip) and not overlaps(rect, prompt), "Live panels clear the crew strip and prompt: %s %s strip=%s prompt=%s" % [tag, str(rect), str(strip), str(prompt)])
			check(rect.end.y <= size.y - 10, "Live panels on screen: " + tag)
		for label in view.gate_checks + [view.gate_policy, view.gate_note]:
			if label.is_visible_in_tree(): check(label.get_global_rect().end.x <= gate_rect.end.x + 1, "Gate text inside its panel: " + tag)
		check(view.gate_checks[0].get_theme_font_size("font_size") == (16 if case[1] else 13), "Larger text applies to the live view: " + tag)
		var card_rect: Rect2 = view.card.get_global_rect()
		check(view.card.visible and card_rect.end.x <= view.right_column_left and card_rect.position.x >= 0, "Follow-card stays left of the right column: " + tag)
		if narrow:
			view.toggle_activity()
			await process_frame
			check(view.activity_panel.visible and not view.activity_tab.visible, "T expands the collapsed activity on narrow windows: " + tag)
			check(not overlaps(view.activity_rect(), view.gate_panel.get_global_rect()), "Expanded activity stays below the gate: " + tag)
			view.toggle_activity()
	root.size = Vector2i(1440, 900); root.content_scale_size = root.size
	hud.large_text = false; hud.scale_text(); hud.sync_world_chrome()
	await process_frame
	view.toggle_activity()
	check(not view.activity_panel.visible and view.activity_tab.visible, "T hides the activity panel on wide windows")
	view.toggle_activity()
	hud.open_operations()
	await process_frame
	check(not view.visible, "Live overlays yield to an open workspace")
	hud.close_panels()
	check(view.visible, "Live overlays return with the exploration HUD")
	hud.toggle_exploration_hud()
	check(not view.visible, "F1 hides the live overlays with the HUD")
	hud.toggle_exploration_hud()
	var controls := ""
	for label in hud.help.find_children("*", "Label", true, false): controls += label.text + "\n"
	check(controls.contains("T  ·  Live activity panel"), "Controls help lists the activity key")
	hud.queue_free()
	await process_frame

func run() -> void:
	var data := story()
	activity_text(data)
	follow_card(data)
	gate(data)
	data.stream.queue_free()
	await layout()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("LIVE_CREW_VIEW_PASSED: activity text, follow-card text, gate missing/failed/passed, freshness badge, wide/compact/large-text layout, T toggle")
	quit(0 if failures.is_empty() else 1)
