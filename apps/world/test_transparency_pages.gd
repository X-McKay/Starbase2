extends SceneTree
## Pages 2 and 3: the workstation console and the handoff dialogue. Covers the
## models (recorded vs not recorded, stale, failed, blocked, no-change, unknown),
## the layouts at wide, compact and large-text sizes, and the keyboard journey
## through the world with the synthetic round-2 stream fixture.
const Story = preload("res://mission_story.gd")
const Workstation = preload("res://workstation_screen.gd")
const Handoff = preload("res://handoff_dialogue.gd")
const Freshness = preload("res://freshness.gd")
const FIXTURE := "res://../../fixtures/world/transparency/"
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()

func load_json(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE + name))

func texts(lines: Array) -> Array:
	return lines.map(func(item): return str(item.text))

func base_ctx(record: Dictionary, summary: Dictionary, live: bool = true) -> Dictionary:
	return {"kind":"repair", "name":"Rivet", "role":"implementer", "mission":"sdlc-42", "summary":summary, "record":record,
		"record_status":"fixture" if not record.is_empty() else "unavailable", "record_age":1.0,
		"freshness":Freshness.evaluate("live" if live else "stale", 0.8 if live else 14.0, 5, true, 1.0, true),
		"snapshot_current":true, "stream_live":live, "note":{}, "note_fresh":false, "observed":{"requests":3, "tokens":9470},
		"fixture":true, "index":-1, "verdicts":{"testing-1":"improved", "testing-2":"improved"}}

func story_checks(record: Dictionary) -> void:
	var story := Story.parse(record)
	check(story.full and story.rounds.size() == 2, "Two rounds parsed: " + str(story.rounds.keys()))
	check(story.rounds[1].has("testing") and story.rounds[1].has("review") and story.rounds[2].has("revise") and story.rounds[2].has("testing"), "Round slots follow Core's reviewing -> implementing rule")
	check(str(story.lead.data.output.task).begins_with("Fix cache eviction"), "Lead plan from lead-handoff")
	check(story.max_rounds == 3, "Max rounds from coordination")
	var diff := Story.diff_rows("--- a\n+++ a\n@@ -1 +1 @@\n-x\n+y\n ctx\n")
	check(diff.files == ["a"] and diff.additions == 1 and diff.deletions == 1 and diff.rows.size() == 4 and diff.rows[0].kind == "hunk", "Unified diff rows: " + str(diff))
	check(Story.diff_rows("").rows.is_empty(), "Empty diff has no rows")
	check(Story.spend({"usage":{}}).input == null and Story.spend({}).is_empty(), "Unknown usage stays unknown, never zero")

func workstation_checks(record: Dictionary, summary: Dictionary) -> void:
	var model := Workstation.build(base_ctx(record, summary))
	check(model.title == "RIVET · IMPLEMENTER CONSOLE", "Title: " + model.title)
	check(model.subtitle == "mission sdlc-42 · X-McKay/algent · round 2 of 3 · testing · SYNTHETIC", "Subtitle: " + model.subtitle)
	check(model.live and model.badge.text.begins_with("[~] LIVE") and model.badge.text.ends_with("SYNTHETIC REPLAY"), "Live badge from the shared freshness rule")
	check(texts(model.banner) == ["[=] Full mission record · synthetic fixture"], "Banner: " + str(texts(model.banner)))
	var plan := texts(model.plan)
	check(plan[0] == "Fix cache eviction so the least recently used entry leaves first", "Plan task first: " + str(plan))
	check(plan.has("[=] diagnose · Moss") and plan.has("[=] implement r2 · Rivet") and plan.has("[>] review r2 · Prism · current step") and plan.has("[ ] publish · Core · Reality Gate"), "Plan step marker: " + str(plan))
	check(model.asks_title == "Prism asked for (round 1)", "Asks title: " + model.asks_title)
	var asks := texts(model.asks)
	check(asks[0] == "[!] Changes requested" and asks[1] == "1  cache.py:7  get() does not refresh access order" and asks[2] == "2  cache.py:10  Capacity 0 pops from an empty store", "Reviewer findings: " + str(asks))
	check(asks.has("[?] Missing evidence · No public test reads a key between two writes."), "Missing evidence is its own state")
	check(texts(model.why)[0] == "[?] Not recorded", "Model reasoning is shown as not recorded")
	check(str(model.diff.header).begins_with("algent/cache.py · +7 −2 · round 2 candidate · recorded "), "Diff header: " + str(model.diff.header))
	check(model.diff.rows.size() == 15 and model.diff.rows[0].kind == "hunk" and model.diff.rows.filter(func(r): return r.kind == "add").size() == 7, "Diff rows from the recorded diff")
	var tests := texts(model.tests.lines)
	check(tests[0] == "Core verdict · improved · round 2", "Verdict line: " + str(tests))
	check(tests.has("[x] Baseline failing · capacity_zero, get_refreshes") and tests.has("[=] Candidate · all 6 cases match"), "Case outcomes: " + str(tests))
	check(model.tests.rows[0].cells.size() == 6 and model.tests.rows[0].cells.filter(func(c): return not c.passed).size() == 2, "Baseline cells")
	var spend := texts(model.spend)
	check(spend.has("Recorded · round 2") and spend.has("Model requests  3") and spend.has("Tokens in / out  7.7k / 1.8k") and spend.has("Member time  58.7 s"), "Recorded spend: " + str(spend))
	check(spend.has("Observed this session (stream notes) · 3 requests · 9.5k tokens") and spend.has("Cost · not recorded"), "Observed spend and unknown cost: " + str(spend))
	var items: Array = model.receipts.items
	check(items.size() == 7 and model.receipts.title == "Tool receipts · round 2", "Seven recorded receipts: " + str(items.size()))
	check(items[2].tool == "run_public_tests" and items[2].glyph == "[x]" and items[2].detail == "failed · 22.0 s" and items[2].tone == "failed", "Failed receipt: " + str(items[2]))
	check(items[1].detail == "ok · 0.4 s" and items[1].glyph == "[=]", "Passed receipt")
	check(str(model.receipts.note).begins_with("Arguments not recorded · receipts keep an input digest only (e.g. 01aaaaaa)"), "Arguments not recorded: " + str(model.receipts.note))
	# Reviewer console: Prism's own receipts are not recorded yet for round 2.
	var prism := base_ctx(record, summary)
	prism.name = "Prism"; prism.role = "reviewer"
	prism.note = {"kind":"tool_started", "tool":"inspect_diff", "role":"reviewer"}; prism.note_fresh = true
	model = Workstation.build(prism)
	check(model.receipts.title == "Tool receipts · round 1" and model.receipts.items.size() == 3, "Reviewer falls back to the last recorded round, labelled: " + model.receipts.title)
	check(model.receipts.items[2].glyph == "[>]" and model.receipts.items[2].detail == "running · stream note, not a receipt", "In-flight note is labelled as a note")
	prism.stream_live = false
	check(Workstation.build(prism).receipts.items.size() == 2, "No in-flight item without a live stream")
	# Stale: last known, never live.
	model = Workstation.build(base_ctx(record, summary, false))
	check(not model.live and model.badge.tone == "stale" and model.badge.text.begins_with("[?] STALE"), "Stale badge")
	check(texts(model.banner)[0] == "[?] LAST KNOWN · stream not live · nothing below is current", "Stale banner: " + str(texts(model.banner)))
	var old := base_ctx(record, summary); old.snapshot_current = false
	check(texts(Workstation.build(old).banner)[0].contains("/v7 snapshot older than 15 s"), "An old snapshot is last known too")
	# Failed read: bounded summary only, every section says what is missing.
	model = Workstation.build(base_ctx({}, summary))
	check(texts(model.banner) == ["[x] Full record read failed · bounded summary only"], "Failed record read: " + str(texts(model.banner)))
	check(model.diff.state.text == "[?] Diff text needs the full mission record · stats from the summary" and model.diff.header == "1 file · +7 −2", "Diff falls back to stats")
	check(model.receipts.empty == "[?] Receipts need the full mission record" and texts(model.asks)[0] == "[?] Round 1 review needs the full record", "Receipts and asks unknown without the record")
	check(texts(model.tests.lines)[0] == "Core verdict · improved · round 2", "Tests still come from the summary")
	var missing := base_ctx({}, summary); missing.record_status = "missing"
	check(texts(Workstation.build(missing).banner) == ["[?] Full record not available · bounded summary only"], "Missing record is unknown, not failed")
	var loading := base_ctx({}, summary); loading.record_status = "loading"
	check(texts(Workstation.build(loading).banner)[0].begins_with("[-] Loading"), "Loading is distinct")
	# Round 3 in flight (the mock-up's moment): nothing graded or submitted yet.
	var later: Dictionary = summary.duplicate(true)
	later.state = "implementing"; later.revision_count = 2; later.stage_evidence.testing = null
	model = Workstation.build(base_ctx(record, later))
	check(texts(model.tests.lines)[0] == "[-] Round 3 not graded yet", "Ungraded round: " + str(texts(model.tests.lines)))
	check(str(model.diff.header).ends_with("round 2 (last retained; round 3 not submitted)"), "Previous diff is labelled: " + str(model.diff.header))
	check(texts(model.plan).has("[>] implement r3 · Rivet · current step"), "Plan marks implement r3")
	# No change, blocked, rejected patch.
	var empty_diff: Dictionary = record.duplicate(true)
	empty_diff.events[5].event.data.diff = ""
	check(Workstation.build(base_ctx(empty_diff, summary)).diff.state.text == "[-] No source change in this candidate", "No-change diff")
	var blocked: Dictionary = summary.duplicate(true)
	blocked.state = "blocked"
	model = Workstation.build(base_ctx(record, blocked))
	check(texts(model.banner).has("[||] Mission blocked · blocked") and texts(model.plan).has("[?] Current step unknown · state blocked"), "Blocked is distinct: " + str(texts(model.banner)))
	var failed: Dictionary = summary.duplicate(true); failed.state = "failed"
	check(texts(Workstation.build(base_ctx(record, failed)).banner).has("[x] Mission failed · failed"), "Failed is distinct from blocked")
	var rejected: Dictionary = record.duplicate(true)
	rejected.events[3].event.data = {"role":"patch-validator", "status":"revise", "validation_error":"Patch target is absent or ambiguous", "verdict":"invalid"}
	model = Workstation.build(base_ctx(rejected, summary))
	check(model.asks_title == "Patch validator (round 1)" and texts(model.asks)[0] == "[x] Rejected before execution · Patch target is absent or ambiguous", "Rejected patch: " + str(texts(model.asks)))
	# No role and no mission.
	var mae := base_ctx(record, summary); mae.role = ""; mae.name = "Mae"
	check(Workstation.build(mae).subtitle.begins_with("No V7 SDLC role"), "Non-SDLC crew")
	var none := base_ctx({}, {}); none.mission = ""
	check(texts(Workstation.build(none).banner)[0] == "[-] No V7 mission assigned to Rivet", "No mission")
	none.freshness = Freshness.evaluate("", -1.0, 5, false, -1.0)
	check(texts(Workstation.build(none).banner)[0].begins_with("[?] No mission record"), "Unknown with no data")

func handoff_checks(record: Dictionary, summary: Dictionary) -> void:
	var model := Handoff.build(base_ctx(record, summary))
	check(model.heading == "Prism returns the candidate to Rivet", "Heading: " + str(model.heading))
	check(model.detail == "reviewing → implementing · round 1 → 2", "Detail: " + str(model.detail))
	check(model.footer_title == "Mission sdlc-42 · Fix cache eviction" and model.footer_detail == "revision loops used 1 of 3 · fallback implementer: Moss · SYNTHETIC", "Footer: " + str(model.footer_detail))
	var reviewer: Dictionary = model.cards[0]
	check(reviewer.name == "Prism" and reviewer.status.text == "[!] changes requested" and reviewer.status.tone == "waiting", "Reviewer card status")
	check(str(reviewer.lines[0].text).begins_with("“Synthetic: the write path now evicts"), "Recorded review rationale quoted")
	check(texts(reviewer.list) == ["1  cache.py:7  get() does not refresh access order", "2  cache.py:10  Capacity 0 pops from an empty store", "?  Missing evidence: No public test reads a key between two writes."], "Findings: " + str(texts(reviewer.list)))
	check(str(reviewer.foot).ends_with("the reasoning behind it is not recorded"), "Reasoning not recorded")
	var reply: Dictionary = model.cards[1]
	check(reply.name == "Rivet" and reply.status.text == "[=] round 2 submitted" and str(reply.lines[0].text).begins_with("“Synthetic: taking both findings."), "Reply from the round 2 record")
	check(model.nav == "Review 1 of 1 · ← / →" and model.count == 1, "Navigation")
	var track: Array = model.track.map(func(item): return item.text + "|" + item.status)
	check(track == ["plan|done", "implement r1|done", "test r1 · improved|done", "review r1 · changes|changes", "↺ round 1 → 2|loop", "implement r2|done", "test r2 · improved|done", "review r2|current", "ready to publish|pending", "Reality Gate · branch + PR|pending", "awaiting human review|pending"], "Stage track: " + str(track))
	var no_stream := base_ctx(record, summary); no_stream.verdicts = {}
	check(Handoff.build(no_stream).track[2].text == "test r1 · verdict not retained" and Handoff.build(no_stream).track[2].status == "unknown", "Past verdict not retained is unknown")
	# Reply pending, stale, blocked.
	var pending: Dictionary = record.duplicate(true)
	pending.events.remove_at(5)
	var implementing: Dictionary = summary.duplicate(true)
	implementing.state = "implementing"; implementing.stage_evidence.testing = null
	model = Handoff.build(base_ctx(pending, implementing))
	check(model.cards[1].status.text == "[>] revising · reply not recorded yet", "Pending reply: " + str(model.cards[1].status.text))
	check(model.track[5].text == "implement r2" and model.track[5].status == "current" and model.track[6].status == "pending", "Implementing round 2 is current")
	model = Handoff.build(base_ctx(pending, implementing, false))
	check(model.cards[1].status.text == "[?] last known · reply not recorded" and not model.live, "Stale reply is last known")
	var blocked: Dictionary = implementing.duplicate(true); blocked.state = "blocked"
	var stopped: Dictionary = pending.duplicate(true)
	stopped.events.remove_at(4)
	model = Handoff.build(base_ctx(stopped, blocked))
	check(model.cards[1].status.text == "[||] no reply · mission blocked" and model.track[model.track.size() - 1].status == "blocked", "Blocked reply")
	# No review yet; summary only.
	var early: Dictionary = record.duplicate(true)
	early.events = early.events.slice(0, 3)
	var testing1: Dictionary = summary.duplicate(true); testing1.revision_count = 0
	model = Handoff.build(base_ctx(early, testing1))
	check(model.cards.is_empty() and model.empty.text == "[-] No review handoff recorded yet · Prism is reviewing round 1", "No handoff yet: " + str(model.empty))
	model = Handoff.build(base_ctx({}, summary))
	check(model.empty.text == "[?] Earlier reviews need the full mission record (unavailable)" and model.track[1].text == "rounds 1–1 · full record not loaded", "Summary-only handoff: " + str(model.empty) + " " + str(model.track))
	var none := base_ctx({}, {}); none.mission = ""
	check(Handoff.build(none).empty.text == "[-] No mission, so no handoff", "No mission")

func overlaps(a: Rect2, b: Rect2) -> bool:
	return a.grow(-1).intersects(b.grow(-1))

func inside(rect: Rect2, outer: Rect2) -> bool:
	return rect.position.x >= outer.position.x - 1 and rect.position.y >= outer.position.y - 1 and rect.end.x <= outer.end.x + 1 and rect.end.y <= outer.end.y + 1

func layout(record: Dictionary, summary: Dictionary) -> void:
	var hud = load("res://hud.gd").new()
	hud.board_fixture = "__empty_visual_fixture__"
	root.add_child(hud)
	await process_frame
	var screen = hud.workstation_screen
	var dialogue = hud.handoff_dialogue
	check(screen.get_parent() == hud.root and dialogue.get_parent() == hud.root, "Pages live in the HUD root")
	var controls := ""
	for label in hud.help.find_children("*", "Label", true, false): controls += label.text + "\n"
	check(controls.contains("N  ·  Workstation console") and controls.contains("U  ·  Handoff dialogue"), "Controls help lists N and U")
	var strip_buttons: Array = hud.crew_strip.find_children("*", "Button", true, false).map(func(b): return b.text)
	check(strip_buttons.has("Console [N]") and strip_buttons.has("Handoff [U]"), "Crew strip offers Console and Handoff: " + str(strip_buttons))
	var steps: Array = []
	screen.crew_step.connect(func(d): steps.append(d))
	for case in [[Vector2i(1440, 900), false], [Vector2i(1440, 900), true], [Vector2i(960, 700), false], [Vector2i(960, 700), true]]:
		var size: Vector2i = case[0]
		root.size = size; root.content_scale_size = size
		hud.large_text = case[1]; hud.scale_text()
		var tag := "%s large=%s" % [str(size), str(case[1])]
		hud.close_panels()
		screen.open(); hud.sync_world_chrome()
		screen.render(Workstation.build(base_ctx(record, summary)))
		for _frame in 4: await process_frame
		check(hud.is_open() and not hud.crew_strip.visible, "Console is a workspace: " + tag)
		var area := Rect2(Vector2.ZERO, Vector2(size))
		check(inside(screen.get_global_rect(), area), "Console inside the window: %s %s" % [tag, str(screen.get_global_rect())])
		check(screen.get_combined_minimum_size().x <= size.x, "Console has no horizontal overflow: %s %s" % [tag, str(screen.get_combined_minimum_size())])
		check(screen.title.get_theme_font_size("font_size") == (24 if case[1] else 21), "Larger text applies: " + tag)
		var panes: Array = ["plan", "asks", "why", "diff", "tests", "spend"].map(func(k): return screen.sections[k].panel.get_global_rect())
		for i in panes.size():
			for j in range(i + 1, panes.size()):
				check(not overlaps(panes[i], panes[j]), "Panes do not overlap: %s %d/%d" % [tag, i, j])
		check(screen.sections.receipts.body.find_children("*", "PanelContainer", true, false).size() == 7, "Seven receipt chips: " + tag)
		check(screen.columns.vertical == (size.x < 1200), "Compact console stacks its columns: " + tag)
		hud.close_panels()
		check(not screen.visible and not hud.is_open(), "Esc path closes the console: " + tag)
		dialogue.open(); hud.sync_world_chrome()
		dialogue.render(Handoff.build(base_ctx(record, summary)))
		for _frame in 4: await process_frame
		var cards: Array = dialogue.cards.map(func(c): return c.panel.get_global_rect())
		var footer: Rect2 = dialogue.footer.get_global_rect()
		var head: Rect2 = dialogue.heading_panel.get_global_rect()
		check(not overlaps(cards[0], cards[1]), "Speech cards do not overlap: " + tag)
		var scroll_rect: Rect2 = dialogue.dialogue_scroll.get_global_rect()
		check(inside(scroll_rect, area), "Dialogue scroll area on screen: " + tag)
		for rect in cards:
			# Stacked cards (compact, larger text) may scroll; they never leave the window sideways.
			check(rect.position.x >= 0 and rect.end.x <= size.x + 1 and (inside(rect, area) or dialogue.cards_row.vertical), "Card on screen: %s %s" % [tag, str(rect)])
			check(not overlaps(rect, head), "Card clears the heading: " + tag)
			check(not overlaps(rect, footer) or dialogue.get_node("Layout/DialogueScroll").get_global_rect().end.y <= footer.position.y + 1, "Card clears the stage track: " + tag)
		check(inside(footer, area) and inside(head, area), "Heading and track on screen: " + tag)
		check(dialogue.track.get_child_count() == 11, "Eleven stage chips: " + tag)
		for label in dialogue.track.find_children("*", "Label", true, false): check(label.get_global_rect().end.x <= footer.end.x + 1, "Stage chip text inside the track: " + tag)
		hud.close_panels()
		check(not dialogue.visible, "Close hides the dialogue: " + tag)
	# Keyboard inside the console.
	screen.open()
	var event := InputEventKey.new(); event.physical_keycode = KEY_RIGHT; event.pressed = true
	screen._input(event)
	check(steps == [1], "Right arrow steps the console crew")
	hud.close_panels()
	hud.queue_free()
	await process_frame

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code; event.keycode = code; event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func journey() -> void:
	root.size = Vector2i(1440, 900); root.content_scale_size = root.size
	var world = load("res://main.tscn").instantiate()
	world.stream_fixture_path = FIXTURE + "round2-stream.jsonl"
	root.add_child(world)
	await process_frame
	await process_frame
	world.hud.close_panels()
	var deadline := Time.get_ticks_msec() + 20000
	while not world.event_stream.fixture_done() and Time.get_ticks_msec() < deadline: await process_frame
	world.update_live_view(1.0)
	key(KEY_N)
	await process_frame
	var screen = world.hud.workstation_screen
	check(screen.visible and world.hud.is_open(), "N opens the workstation console")
	check(world.transparency.kind == "reviewer", "With no focus, the console opens on the crew the state assigns (Prism reviews)")
	key(KEY_LEFT)
	await process_frame
	world.update_live_view(1.0)
	check(world.transparency.kind == "repair" and screen.title.text == "RIVET · IMPLEMENTER CONSOLE", "Left arrow steps to Rivet: " + screen.title.text)
	check(world.transparency.record.status == "fixture" and screen.model.diff.rows.size() == 15, "Full record read from the synthetic fixture: " + world.transparency.record.status)
	check(screen.badge.text.begins_with("[~] LIVE"), "Console badge live: " + screen.badge.text)
	check(texts(screen.model.spend).has("Observed this session (stream notes) · 3 requests · 9.5k tokens"), "Observed spend from replayed notes: " + str(texts(screen.model.spend)))
	key(KEY_ESCAPE)
	await process_frame
	check(not screen.visible and not world.hud.is_open(), "Esc closes the console")
	key(KEY_U)
	await process_frame
	world.update_live_view(1.0)
	var dialogue = world.hud.handoff_dialogue
	check(dialogue.visible and dialogue.heading.text == "Prism returns the candidate to Rivet", "U opens the handoff dialogue: " + dialogue.heading.text)
	check(dialogue.model.track[2].text == "test r1 · improved", "Past verdict from the replayed stream record: " + str(dialogue.model.track[2]))
	key(KEY_U)
	await process_frame
	check(not dialogue.visible, "U toggles the dialogue closed")
	# Stale: the stream goes silent; the console says last known.
	world.event_stream.pause_fixture()
	world.event_stream.clock_offset_msec += 20000
	world.transparency.open_workstation("repair")
	world.update_live_view(1.0)
	check(screen.badge.text.begins_with("[?] STALE") and screen.model.banner[0].text.begins_with("[?] LAST KNOWN"), "Stale console: " + screen.badge.text)
	check(screen.sections.plan.head.text.ends_with("· LAST KNOWN"), "Section headings say last known")
	world.hud.close_panels()
	world.queue_free()
	await process_frame

func run() -> void:
	var record := load_json("round2-mission-sdlc-42.json")
	var summary: Dictionary = load_json("round2-v7-snapshot.json").missions[0]
	story_checks(record)
	workstation_checks(record, summary)
	handoff_checks(record, summary)
	await layout(record, summary)
	await journey()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("TRANSPARENCY_PAGES_PASSED: workstation and handoff models, stale/failed/blocked/no-change/unknown states, wide/compact/large-text layout, keyboard journey")
	quit(0 if failures.is_empty() else 1)
