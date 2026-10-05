extends PanelContainer
## Page 2: one crew member's workstation console. Shows the mission plan and the
## step it is on, what the reviewer asked for, the recorded diff, Core-graded
## test cases, tool receipts and spend. Data comes only from the /v7 summary, the
## full mission record and /v8 activity notes; this screen never dispatches.
## Model reasoning and tool arguments are not recorded, and say so.
const Story = preload("res://mission_story.gd")
const Activity = preload("res://live_activity.gd")
signal crew_step(direction: int)
signal handoff_requested
signal close_requested
const TONES := {"title":"f2f6f8", "text":"e3ecf2", "muted":"aebccc", "working":"6fe3f0", "waiting":"f3c26b",
	"passed":"8fdc8a", "failed":"ff8a70", "unknown":"c6bdd6", "stale":"ff8a70", "blocked":"f3a0d8"}
const SDLC_KINDS := ["review", "repair", "reviewer"]
const STEP_FOR_STATE := {"queued":"diagnose", "investigating":"diagnose", "implementing":"implement", "testing":"review",
	"reviewing":"review", "ready_to_publish":"publish", "publishing":"publish", "submitted":"human review", "awaiting_review":"human review"}

var large_text := false
var compact := false
var title: Label
var subtitle: Label
var badge: Label
var banner: VBoxContainer
var scroll: ScrollContainer
var columns: BoxContainer
var column_left: VBoxContainer
var column_center: VBoxContainer
var column_right: VBoxContainer
var sections: Dictionary = {}
var close_button: Button
var model: Dictionary = {}
var signature := ""
var mono: SystemFont
var frame: PanelContainer
var main_column: VBoxContainer
var inner: VBoxContainer

# --- Model -----------------------------------------------------------------

static func line(text: String, tone: String = "text") -> Dictionary:
	return {"text":text, "tone":tone}

static func thousands(value: Variant) -> String:
	if not Story.is_number(value): return "?"
	return Activity.short_tokens(int(value))

static func clock(at: Variant) -> String:
	return Activity.clock(at) if Story.is_number(at) else "time not recorded"

static func seconds(value: Variant) -> String:
	if not Story.is_number(value): return "duration not recorded"
	return "%.1f s" % float(value) if float(value) < 60.0 else "%d s" % int(value)

## ctx keys: kind, name, role, mission (id), summary, record, record_status,
## record_age, freshness, snapshot_current, stream_live, note (latest activity
## payload or {}), note_fresh, observed ({requests, tokens}), fixture.
static func build(ctx: Dictionary) -> Dictionary:
	var name := str(ctx.get("name", "Crew"))
	var role := str(ctx.get("role", ""))
	var mission := str(ctx.get("mission", ""))
	var summary: Dictionary = Story.dict(ctx.get("summary"))
	var record: Dictionary = Story.dict(ctx.get("record"))
	var story := Story.parse(record)
	var freshness: Dictionary = Story.dict(ctx.get("freshness"))
	var live: bool = bool(freshness.get("live", false)) and bool(ctx.get("snapshot_current", false))
	var result := {"title":(name + " · " + (role if not role.is_empty() else "crew") + " console").to_upper(),
		"badge":line(str(freshness.get("text", "[?] UNKNOWN · nothing received from Core")), "passed" if live else "stale"),
		"live":live, "banner":[], "plan":[], "asks":[], "asks_title":"Reviewer asked for", "why":[], "diff":{}, "tests":{}, "spend":[], "receipts":{}}
	if role.is_empty():
		result.subtitle = "No V7 SDLC role · this console shows SDLC missions only"
		result.banner.append(line("[-] " + name + " holds no SDLC role. Use ← / → for Moss, Rivet or Prism.", "muted"))
		return result
	if mission.is_empty() or summary.is_empty():
		result.subtitle = "No V7 mission assigned"
		result.banner.append(line("[?] No mission record for " + name + " · nothing to show yet" if not live else "[-] No V7 mission assigned to " + name, "unknown" if not live else "muted"))
		return result
	var state := str(summary.get("state", story.state))
	var round := Story.current_round(story, summary)
	var max_rounds := int(story.max_rounds)
	var input: Dictionary = Story.dict(summary.get("input"))
	result.subtitle = "mission %s · %s · round %d%s · %s" % [mission, str(summary.get("repository", input.get("repository", "repository unknown"))), round, (" of %d" % max_rounds) if max_rounds > 0 else "", state.replace("_", " ")]
	if ctx.get("fixture", false): result.subtitle += " · SYNTHETIC"
	# Banner: freshness, record and mission state stay distinct.
	if not live: result.banner.append(line("[?] LAST KNOWN · " + ("stream not live" if not freshness.get("live", false) else "/v7 snapshot older than 15 s") + " · nothing below is current", "stale"))
	var status := str(ctx.get("record_status", "none"))
	match status:
		"live": result.banner.append(line("[=] Full mission record read %s ago" % preload("res://freshness.gd").age_text(maxf(0.0, float(ctx.get("record_age", 0.0)))), "passed"))
		"fixture": result.banner.append(line("[=] Full mission record · synthetic fixture", "passed"))
		"loading": result.banner.append(line("[-] Loading full mission record … summary shown meanwhile", "muted"))
		"unavailable": result.banner.append(line("[x] Full record read failed · " + ("showing last known record" if story.full else "bounded summary only"), "failed"))
		"missing": result.banner.append(line("[?] Full record not available · bounded summary only", "unknown"))
	if state in ["blocked", "failed", "cancelled"] or summary.get("cancel_requested", false):
		result.banner.append(line(("[_] Mission blocked" if state == "blocked" else ("[x] Mission failed" if state == "failed" else "[_] Mission stopped")) + " · " + (state.replace("_", " ") if not summary.get("cancel_requested", false) else "stop requested"), "blocked" if state != "failed" else "failed"))
	result.plan = plan_lines(story, summary, state, round)
	var asks := asks_lines(story, summary, round)
	result.asks = asks.lines
	result.asks_title = asks.title
	result.why = [line("[?] Not recorded", "unknown"),
		line("Model reasoning is not stored; ADR 0015 (proposed) would add bounded traces.", "muted")]
	result.diff = diff_model(story, summary, round)
	result.tests = tests_model(summary, round, state)
	result.spend = spend_lines(story, role, round, Story.dict(ctx.get("observed")))
	result.receipts = receipts_model(story, role, round, Story.dict(ctx.get("note")), bool(ctx.get("note_fresh", false)) and bool(ctx.get("stream_live", false)), name)
	return result

static func plan_lines(story: Dictionary, summary: Dictionary, state: String, round: int) -> Array:
	var lines: Array = []
	var plan: Dictionary = Story.dict(Story.dict(summary.get("stage_evidence")).get("plan"))
	if plan.is_empty() and not Story.dict(story.lead).is_empty(): plan = Story.dict(Story.dict(story.lead.data).get("output"))
	if plan.get("task") is String:
		lines.append(line(str(plan.task), "title"))
		if plan.get("rationale") is String: lines.append(line(str(plan.rationale), "muted"))
		if plan.get("decision") is String and plan.decision != "implement": lines.append(line("[_] Lead decision · " + str(plan.decision), "blocked"))
	else:
		lines.append(line("[?] Plan not recorded yet" if state in ["queued", "investigating"] else "[?] Plan not recorded", "unknown"))
	var current: String = STEP_FOR_STATE.get(state, "")
	var stopped := state in ["blocked", "failed", "cancelled"]
	var steps: Array = []
	for role in ["lead", "implementer", "reviewer"]:
		var task: Dictionary = Story.dict(Story.dict(story.assignments).get(role))
		var step := str(task.get("task", {"lead":"diagnose", "implementer":"implement", "reviewer":"review"}[role]))
		steps.append([step, Story.crew_name(Story.crew_for(story, summary, role))])
	steps.append(["publish", "Core · Reality Gate"])
	steps.append(["human review", "operator"])
	var reached := false
	for step in steps:
		var is_current: bool = step[0] == current
		var text := "%s · %s" % [step[0], step[1]]
		if step[0] in ["implement", "review"]: text = "%s r%d · %s" % [step[0], round, step[1]]
		if is_current:
			reached = true
			if stopped: lines.append(line("[_] " + text + " · stopped", "blocked"))
			elif state == "reviewing": lines.append(line("[?] " + text + " · recorded; Core decides next", "unknown"))
			else: lines.append(line("[>] " + text + " · current step", "working"))
		elif not reached and not current.is_empty(): lines.append(line("[=] " + text, "passed"))
		else: lines.append(line("[ ] " + text, "muted"))
	if current.is_empty(): lines.append(line("[?] Current step unknown · state " + state.replace("_", " "), "unknown"))
	return lines

static func asks_lines(story: Dictionary, summary: Dictionary, round: int) -> Dictionary:
	var reviewer := Story.crew_name(Story.crew_for(story, summary, "reviewer"))
	var review := Story.latest(story, "review", round)
	var lines: Array = []
	if review.is_empty():
		var current: Dictionary = Story.dict(Story.dict(summary.get("stage_evidence")).get("reviewing"))
		if current.is_empty():
			if not story.full and round > 1: lines.append(line("[?] Round %d review needs the full record" % (round - 1), "unknown"))
			else: lines.append(line("[-] No review recorded yet", "muted"))
			return {"title":reviewer + " asked for", "lines":lines}
		review = {"round":round, "data":current}
	var data: Dictionary = review.data
	var status := Story.review_status(review)
	var title := "%s asked for (round %d)" % [reviewer, int(review.round)]
	match status:
		"revise": lines.append(line("[!] Changes requested", "waiting"))
		"accept": lines.append(line("[=] Accepted", "passed"))
		"abstain": lines.append(line("[?] Abstained · evidence missing", "unknown"))
		"rejected":
			title = "Patch validator (round %d)" % int(review.round)
			lines.append(line("[x] Rejected before execution · " + str(data.get("validation_error", "reason not recorded")), "failed"))
		_: lines.append(line("[?] Review status not recorded", "unknown"))
	var listed: Variant = Story.findings(review)
	if listed == null: lines.append(line("[?] Findings not reported", "unknown"))
	elif listed.is_empty(): lines.append(line("[-] No findings reported", "muted"))
	else:
		var index := 0
		for finding in listed:
			index += 1
			var item: Dictionary = Story.dict(finding)
			var where := str(item.get("path", "")).get_file() if item.get("path") is String else "path not recorded"
			if Story.is_number(item.get("line")): where += ":" + str(int(item.line))
			lines.append(line("%d  %s  %s" % [index, where, str(item.get("problem", "problem not recorded"))], "text"))
	var missing: Variant = data.get("missing_evidence", Story.dict(data.get("output")).get("missing_evidence"))
	if missing is String and not missing.is_empty(): lines.append(line("[?] Missing evidence · " + missing, "unknown"))
	if status == "revise": lines.append(line("Addressed or not is for the next review to say.", "muted"))
	return {"title":title, "lines":lines}

static func diff_model(story: Dictionary, summary: Dictionary, round: int) -> Dictionary:
	var testing := Story.latest(story, "testing", round)
	var stats: Dictionary = Story.dict(Story.dict(Story.dict(summary.get("stage_evidence")).get("testing")).get("diff"))
	if testing.is_empty():
		if not stats.is_empty():
			return {"header":"%d file%s · +%d −%d" % [int(stats.get("files", 0)), "" if int(stats.get("files", 0)) == 1 else "s", int(stats.get("additions", 0)), int(stats.get("deletions", 0))],
				"state":line("[?] Diff text needs the full mission record · stats from the summary", "unknown"), "rows":[], "hidden":0}
		return {"header":"No candidate", "state":line("[-] No candidate recorded for round %d yet" % round if story.full or round == 1 else "[?] Candidate not known", "muted" if story.full else "unknown"), "rows":[], "hidden":0}
	var data: Dictionary = testing.data
	var label := "round %d candidate · recorded %s" % [int(testing.round), clock(testing.at)]
	if int(testing.round) < round: label = "round %d (last retained; round %d not submitted)" % [int(testing.round), round]
	var notes: Array = []
	if data.get("validation_error") is String: notes.append(line("[x] Rejected before execution · " + str(data.validation_error), "failed"))
	if not data.get("diff") is String:
		return {"header":label, "state":line("[?] Diff not recorded", "unknown"), "rows":[], "hidden":0, "notes":notes}
	var parsed := Story.diff_rows(str(data.diff))
	if parsed.rows.is_empty():
		return {"header":label, "state":line("[-] No source change in this candidate", "muted"), "rows":[], "hidden":0, "notes":notes}
	var files := ", ".join(parsed.files) if not parsed.files.is_empty() else "file not recorded"
	return {"header":"%s · +%d −%d · %s" % [files, parsed.additions, parsed.deletions, label], "state":{}, "rows":parsed.rows, "hidden":parsed.hidden, "notes":notes}

static func cells(cases: Variant) -> Variant:
	if not cases is Dictionary or not cases.get("passed") is Array or not cases.get("failed") is Array: return null
	var out: Array = []
	for id in cases.passed: out.append({"id":str(id), "passed":true})
	for id in cases.failed: out.append({"id":str(id), "passed":false})
	out.sort_custom(func(a, b): return a.id < b.id)
	return out

static func tests_model(summary: Dictionary, round: int, state: String) -> Dictionary:
	var testing: Dictionary = Story.dict(Story.dict(summary.get("stage_evidence")).get("testing"))
	if testing.is_empty():
		var why := "[-] Round %d not graded yet" % round if state in ["queued", "investigating", "implementing"] else "[?] Test evidence not recorded for round %d" % round
		return {"rows":[], "lines":[line(why, "muted" if why.begins_with("[-]") else "unknown"), line("Core keeps per-case grading for the current round only.", "muted")]}
	var rows: Array = []
	var lines: Array = []
	for pair in [["Baseline", testing.get("baseline_cases")], ["Candidate", testing.get("candidate_cases")]]:
		var row: Variant = cells(pair[1])
		rows.append({"label":pair[0], "cells":row})
		if row == null: lines.append(line("[?] %s not executed or not interpretable" % pair[0], "unknown"))
		else:
			var failed: Array = row.filter(func(c): return not c.passed).map(func(c): return c.id)
			if not failed.is_empty(): lines.append(line("[x] %s failing · %s" % [pair[0], ", ".join(failed)], "failed"))
			elif not row.is_empty(): lines.append(line("[=] %s · all %d cases match" % [pair[0], row.size()], "passed"))
			else: lines.append(line("[-] %s ran with no cases" % pair[0], "muted"))
	var verdict: Variant = testing.get("verdict")
	if testing.get("validation_error") is String: lines.append(line("[x] Rejected before execution · " + str(testing.validation_error), "failed"))
	lines.push_front(line("Core verdict · " + (str(verdict).replace("_", " ") if verdict is String else "not recorded") + " · round %d" % round, "passed" if verdict == "improved" else ("unknown" if not verdict is String else "failed")))
	lines.append(line("Expected values stay with Core's trusted oracle.", "muted"))
	return {"rows":rows, "lines":lines}

static func spend_lines(story: Dictionary, role: String, round: int, observed: Dictionary) -> Array:
	var lines: Array = []
	var shown_round := round
	var member := Story.member_entry(story, role, round)
	if member.is_empty() and role != "lead":
		for r in range(round - 1, 0, -1):
			member = Story.member_entry(story, role, r)
			if not member.is_empty(): shown_round = r; break
	var spent := Story.spend(Story.dict(member.get("data")))
	if spent.is_empty():
		lines.append(line("Recorded · " + ("[?] needs the full record" if not story.full else "[-] nothing recorded yet"), "unknown" if not story.full else "muted"))
	else:
		lines.append(line("Recorded · " + ("plan" if role == "lead" else "round %d" % shown_round), "muted"))
		lines.append(line("Model requests  " + (str(spent.requests) if spent.requests != null else "not recorded"), "text"))
		lines.append(line("Tokens in / out  %s / %s" % [thousands(spent.input), thousands(spent.output)], "text"))
		lines.append(line("Member time  " + (seconds(float(spent.elapsed_ms) / 1000.0) if spent.elapsed_ms != null else "not recorded"), "text"))
		if not spent.complete: lines.append(line("[?] Usage incomplete · some requests did not report tokens", "unknown"))
	var requests := int(observed.get("requests", 0))
	lines.append(line("Observed this session (stream notes) · " + ("%d request%s · %s tokens" % [requests, "" if requests == 1 else "s", Activity.short_tokens(int(observed.get("tokens", 0)))] if requests > 0 else "none"), "muted"))
	lines.append(line("Cost · not recorded", "unknown"))
	return lines

static func receipts_model(story: Dictionary, role: String, round: int, note: Dictionary, note_live: bool, name: String) -> Dictionary:
	var member := Story.member_entry(story, role, round)
	var shown_round := round
	if member.is_empty() and role != "lead":
		for r in range(round - 1, 0, -1):
			member = Story.member_entry(story, role, r)
			if not member.is_empty(): shown_round = r; break
	var items: Array = []
	for receipt in Story.receipts(Story.dict(member.get("data"))):
		var ok: Variant = receipt.ok
		var detail := ("ok" if ok == true else ("failed" if ok == false else "outcome not recorded")) + " · " + seconds(receipt.seconds)
		if receipt.cached: detail += " · cached"
		items.append({"tool":receipt.tool, "glyph":"[=]" if ok == true else ("[x]" if ok == false else "[?]"), "detail":detail, "tone":"passed" if ok == true else ("failed" if ok == false else "unknown")})
	var title := "Tool receipts · " + ("plan" if role == "lead" else "round %d" % shown_round)
	var empty := ""
	if member.is_empty(): empty = "[?] Receipts need the full mission record" if not story.full else "[-] No receipts recorded for %s yet" % name
	elif items.is_empty(): empty = "[-] No tools used in this recorded run"
	# A fresh tool_started note is the only in-flight receipt, and it is labelled as a note.
	if note_live and str(note.get("kind", "")) == "tool_started":
		items.append({"tool":str(note.get("tool", "tool")), "glyph":"[>]", "detail":"running · stream note, not a receipt", "tone":"working"})
	var digest := ""
	for receipt in Story.receipts(Story.dict(member.get("data"))):
		if not receipt.digest.is_empty(): digest = Story.short_digest(receipt.digest); break
	return {"title":title, "items":items, "empty":empty,
		"note":"Arguments not recorded · receipts keep an input digest only" + (" (e.g. " + digest + ")" if not digest.is_empty() else "") + " · outcome and duration from the retained record"}

# --- View ------------------------------------------------------------------

func make_label(parent: Node, text: String, size: int, tone: String = "text") -> Label:
	var item := Label.new()
	item.text = text
	item.set_meta("base_font", size)
	item.add_theme_font_size_override("font_size", size + (3 if large_text else 0))
	item.add_theme_color_override("font_color", Color(TONES.get(tone, tone)))
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(item)
	return item

static func surface(bg: String, border: String, radius: int = 6, pad: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(bg)
	style.border_color = Color(border)
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = pad; style.content_margin_right = pad
	style.content_margin_top = pad - 2; style.content_margin_bottom = pad - 2
	return style

func section(parent: Node, key: String, heading: String) -> void:
	var panel := PanelContainer.new()
	panel.name = key.capitalize().replace(" ", "") + "Pane"
	panel.add_theme_stylebox_override("panel", surface("0a283acc", "7fdcff47"))
	parent.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	panel.add_child(body)
	var head := make_label(body, heading.to_upper(), 11, "8fc4d8")
	head.autowrap_mode = TextServer.AUTOWRAP_OFF
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	body.add_child(content)
	sections[key] = {"panel":panel, "head":head, "body":content}

func _ready() -> void:
	name = "WorkstationScreen"
	mouse_filter = Control.MOUSE_FILTER_STOP
	# A dim backdrop over the whole window; the console frame sits inside it.
	add_theme_stylebox_override("panel", surface("02080ddb", "00000000", 0, 28))
	frame = PanelContainer.new()
	frame.name = "ConsoleFrame"
	frame.add_theme_stylebox_override("panel", surface("041a28f5", "7fdcff8c", 14, 20))
	add_child(frame)
	mono = SystemFont.new()
	mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Noto Sans Mono", "monospace"])
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	frame.add_child(column)
	main_column = column
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	column.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 2)
	head.add_child(titles)
	title = make_label(titles, "CONSOLE", 21, "title")
	subtitle = make_label(titles, "", 13, "muted")
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	head.add_child(controls)
	badge = make_label(controls, "", 12, "muted")
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 6)
	controls.add_child(buttons)
	for spec in [["← Crew", func(): crew_step.emit(-1), "Previous SDLC crew member · Left arrow"], ["Crew →", func(): crew_step.emit(1), "Next SDLC crew member · Right arrow"],
			["Handoff [U]", func(): handoff_requested.emit(), "Open the handoff dialogue for this mission"], ["Back to room [Esc]", func(): close_requested.emit(), "Close the console · Esc"]]:
		var control := Button.new()
		control.text = spec[0]
		control.tooltip_text = spec[2]
		control.add_theme_font_size_override("font_size", 13)
		control.pressed.connect(spec[1])
		buttons.add_child(control)
		close_button = control
	banner = VBoxContainer.new()
	banner.add_theme_constant_override("separation", 2)
	column.add_child(banner)
	scroll = ScrollContainer.new()
	scroll.name = "ConsoleScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	inner = VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 12)
	scroll.add_child(inner)
	columns = BoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	inner.add_child(columns)
	column_left = VBoxContainer.new(); column_center = VBoxContainer.new(); column_right = VBoxContainer.new()
	for item in [column_left, column_center, column_right]:
		item.add_theme_constant_override("separation", 12)
		columns.add_child(item)
	column_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section(column_left, "plan", "Plan")
	section(column_left, "asks", "Reviewer asked for")
	section(column_right, "why", "Why this step")
	section(column_center, "diff", "Live diff")
	section(column_right, "tests", "Test rig · Core-graded cases")
	section(column_right, "spend", "Spend")
	section(inner, "receipts", "Tool receipts")
	hide()

func open() -> void:
	show()
	scroll.scroll_vertical = 0
	close_button.grab_focus()

## _input, not _unhandled: a focused button would take arrows for focus moves.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed: return
	match event.physical_keycode:
		KEY_LEFT: crew_step.emit(-1); get_viewport().set_input_as_handled()
		KEY_RIGHT: crew_step.emit(1); get_viewport().set_input_as_handled()
		KEY_PAGEDOWN: scroll.scroll_vertical += int(scroll.size.y * 0.8); get_viewport().set_input_as_handled()
		KEY_PAGEUP: scroll.scroll_vertical -= int(scroll.size.y * 0.8); get_viewport().set_input_as_handled()

func fit(viewport_size: Vector2, large: bool) -> void:
	var was_large := large_text
	large_text = large
	compact = viewport_size.x < 1200
	var margin := 28.0 if viewport_size.x >= 1200 else 12.0
	position = Vector2.ZERO
	size = viewport_size
	var backdrop: StyleBoxFlat = get_theme_stylebox("panel")
	backdrop.content_margin_left = margin; backdrop.content_margin_right = margin
	backdrop.content_margin_top = margin; backdrop.content_margin_bottom = margin
	# Wide: receipts are a fixed strip under the panes, as in the approved layout.
	# Compact: they scroll with everything else.
	var receipts: Control = sections.receipts.panel
	var target: Node = inner if compact else main_column
	if receipts.get_parent() != target:
		receipts.get_parent().remove_child(receipts)
		target.add_child(receipts)
	columns.vertical = compact
	var side := 0.0 if compact else clampf(viewport_size.x * 0.23, 260.0, 340.0 if not large else 380.0)
	column_left.custom_minimum_size.x = side
	column_right.custom_minimum_size.x = side
	if was_large != large:
		for label in find_children("*", "Label", true, false):
			label.add_theme_font_size_override("font_size", int(label.get_meta("base_font", 13)) + (3 if large else 0))

func render(next: Dictionary) -> void:
	model = next
	title.text = str(next.get("title", "CONSOLE"))
	subtitle.text = str(next.get("subtitle", ""))
	var shown: Dictionary = next.get("badge", line("[?] UNKNOWN", "unknown"))
	badge.text = str(shown.text)
	badge.add_theme_color_override("font_color", Color(TONES.get(str(shown.tone), "aebccc")))
	# Only rebuild the panes when their content changed; ages tick in the badge.
	var content := JSON.stringify([next.get("banner"), next.get("plan"), next.get("asks"), next.get("asks_title"), next.get("why"), next.get("diff"), next.get("tests"), next.get("spend"), next.get("receipts"), large_text, compact])
	if content == signature: return
	signature = content
	clear(banner)
	for item in next.get("banner", []): make_label(banner, str(item.text), 13, str(item.tone))
	fill("plan", next.get("plan", []))
	sections.asks.head.text = str(next.get("asks_title", "Reviewer asked for")).to_upper()
	fill("asks", next.get("asks", []))
	fill("why", next.get("why", []))
	render_diff(Story.dict(next.get("diff")))
	render_tests(Story.dict(next.get("tests")))
	fill("spend", next.get("spend", []))
	render_receipts(Story.dict(next.get("receipts")))
	var stale: bool = not next.get("live", false)
	for key in sections:
		var head: Label = sections[key].head
		head.text = head.text.trim_suffix(" · LAST KNOWN") + (" · LAST KNOWN" if stale else "")

func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func fill(key: String, lines: Array) -> void:
	var body: VBoxContainer = sections[key].body
	clear(body)
	for item in lines: make_label(body, str(item.text), 13, str(item.tone))
	sections[key].panel.visible = not lines.is_empty()

func render_diff(diff: Dictionary) -> void:
	var body: VBoxContainer = sections.diff.body
	clear(body)
	sections.diff.head.text = "LIVE DIFF" + (" · " + str(diff.header) if diff.has("header") else "")
	sections.diff.head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for item in diff.get("notes", []): make_label(body, str(item.text), 13, str(item.tone))
	if diff.get("state") is Dictionary and not diff.state.is_empty(): make_label(body, str(diff.state.text), 13, str(diff.state.tone))
	for row in diff.get("rows", []):
		var kind := str(row.kind)
		var label := make_label(body, str(row.text) if not str(row.text).is_empty() else " ", 13, {"add":"b6f5cf", "delete":"ffc2b8", "hunk":"8fc4d8"}.get(kind, "e3ecf2"))
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_font_override("font", mono)
		if kind in ["add", "delete"]:
			label.add_theme_stylebox_override("normal", surface("6fe3a121" if kind == "add" else "ff8f7d24", "00000000", 0, 2))
		label.tooltip_text = str(row.text)
	if int(diff.get("hidden", 0)) > 0: make_label(body, "… %d more lines in the full record" % int(diff.hidden), 12, "muted")

func render_tests(tests: Dictionary) -> void:
	var body: VBoxContainer = sections.tests.body
	clear(body)
	var rows: Array = tests.get("rows", [])
	var lines: Array = tests.get("lines", [])
	if not lines.is_empty(): make_label(body, str(lines[0].text), 13, str(lines[0].tone))
	var count := 0
	for row in rows:
		if row.cells is Array: count = maxi(count, row.cells.size())
	if count > 0:
		var grid := GridContainer.new()
		grid.columns = count + 1
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		body.add_child(grid)
		for row in rows:
			make_label(grid, str(row.label), 12, "muted").autowrap_mode = TextServer.AUTOWRAP_OFF
			for index in count:
				var cell: Dictionary = row.cells[index] if row.cells is Array and index < row.cells.size() else {}
				var glyph := "?" if cell.is_empty() else ("=" if cell.passed else "x")
				var label := make_label(grid, glyph, 12, "text")
				label.autowrap_mode = TextServer.AUTOWRAP_OFF
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				label.add_theme_font_override("font", mono)
				label.add_theme_stylebox_override("normal", surface("c6bdd633" if cell.is_empty() else ("6fe3a159" if cell.passed else "ff8f7d6b"), "00000000", 3, 3))
				label.tooltip_text = (str(row.label) + " · " + str(cell.id) + " · " + ("passed" if cell.passed else "failed")) if not cell.is_empty() else str(row.label) + " · not executed"
	for item in lines.slice(1): make_label(body, str(item.text), 12, str(item.tone))

func render_receipts(receipts: Dictionary) -> void:
	var body: VBoxContainer = sections.receipts.body
	clear(body)
	sections.receipts.head.text = str(receipts.get("title", "Tool receipts")).to_upper()
	if not str(receipts.get("empty", "")).is_empty(): make_label(body, str(receipts.empty), 13, "unknown" if str(receipts.empty).begins_with("[?]") else "muted")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	body.add_child(flow)
	for item in receipts.get("items", []):
		var chip := PanelContainer.new()
		var tone := str(item.tone)
		chip.add_theme_stylebox_override("panel", surface({"passed":"6fe3a124", "failed":"ff8f7d2e", "working":"7fdcff1f"}.get(tone, "c6bdd61f"), "7fdcff99" if tone == "working" else "00000000", 6, 9))
		flow.add_child(chip)
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 1)
		chip.add_child(stack)
		var name_label := make_label(stack, str(item.glyph) + " " + str(item.tool), 13, "text")
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.add_theme_font_override("font", mono)
		var detail := make_label(stack, str(item.detail), 11, tone)
		detail.autowrap_mode = TextServer.AUTOWRAP_OFF
	make_label(body, str(receipts.get("note", "")), 11, "muted")
