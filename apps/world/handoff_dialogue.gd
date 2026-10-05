extends Control
## Page 3: the review handoff as dialogue. The reviewer's recorded findings and
## the implementer's recorded reply (the rationale retained with the next round's
## candidate) appear as speech cards, above a mission stage track:
## plan -> implement -> test -> review -> revise loop -> accept / PR.
## Text comes only from the retained mission record and /v7 summary; a reply that
## has not been recorded is shown as not recorded, never written for the crew.
const Story = preload("res://mission_story.gd")
const Activity = preload("res://live_activity.gd")
signal review_step(direction: int)
signal workstation_requested
signal close_requested
const TONES := {"title":"f2f6f8", "text":"eef3f6", "muted":"9fb3c1", "working":"7fdcff", "waiting":"ffc861",
	"passed":"6fe3a1", "failed":"ff8a70", "unknown":"c6bdd6", "stale":"ff8a70", "blocked":"f3a0d8"}
const STAGE_STYLE := {"done":["6fe3a11f", "c9d6de", "[=]"], "current":["7fdcff2e", "d8f4ff", "[>]"], "changes":["ffc8612e", "ffe2a6", "[!]"],
	"failed":["ff8a702e", "ffc2b8", "[x]"], "blocked":["f3a0d82e", "f8d0ec", "[_]"], "unknown":["c6bdd61f", "c6bdd6", "[?]"],
	"pending":["ffffff0f", "8195a3", "[ ]"], "loop":["00000000", "ffc861", ""]}

var large_text := false
var compact := false
var heading_panel: PanelContainer
var heading: Label
var heading_detail: Label
var heading_badge: Label
var cards_row: BoxContainer
var cards: Array = []  # [{panel, name, status, quote, list, foot, tail}]
var empty_card: PanelContainer
var empty_label: Label
var footer: PanelContainer
var footer_title: Label
var footer_detail: Label
var track: HFlowContainer
var nav_label: Label
var close_button: Button
var dialogue_scroll: ScrollContainer
var signature := ""
var model: Dictionary = {}

## A speech-card tail: a triangle under the card pointing at its speaker.
static func make_tail(left: bool) -> Control:
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(0, 16)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shape := Polygon2D.new()
	shape.color = Color("0d1621eb")
	tail.add_child(shape)
	tail.resized.connect(func():
		var x := 40.0 if left else tail.size.x - 40.0
		shape.polygon = PackedVector2Array([Vector2(x - 14, 0), Vector2(x + 14, 0), Vector2(x, tail.size.y)]))
	return tail

static func line(text: String, tone: String = "text") -> Dictionary:
	return {"text":text, "tone":tone}

## Reviews that can be shown, oldest first: [{round, review}].
static func reviews(story: Dictionary) -> Array:
	var out: Array = []
	var keys: Array = Story.dict(story.get("rounds")).keys()
	keys.sort()
	for round in keys:
		var slot: Dictionary = story.rounds[round]
		if slot.has("review"): out.append({"round":int(round), "review":slot.review})
	return out

## ctx: mission, summary, record, record_status, freshness, snapshot_current,
## index (review index, -1 for latest), verdicts, fixture.
static func build(ctx: Dictionary) -> Dictionary:
	var summary: Dictionary = Story.dict(ctx.get("summary"))
	var record: Dictionary = Story.dict(ctx.get("record"))
	var story := Story.parse(record)
	var freshness: Dictionary = Story.dict(ctx.get("freshness"))
	var live: bool = bool(freshness.get("live", false)) and bool(ctx.get("snapshot_current", false))
	var mission := str(ctx.get("mission", ""))
	var result := {"live":live, "badge":line(str(freshness.get("text", "[?] UNKNOWN")), "passed" if live else "stale"), "cards":[], "empty":{}, "track":[], "nav":""}
	if mission.is_empty() or summary.is_empty():
		result.heading = "Handoff · no V7 mission"
		result.detail = "No mission summary received" if not live else "No SDLC mission is retained"
		result.empty = line("[?] Nothing to show · no mission record" if not live else "[-] No mission, so no handoff", "unknown" if not live else "muted")
		result.footer_title = "No mission"
		result.footer_detail = ""
		return result
	var state := str(summary.get("state", story.state))
	var round := Story.current_round(story, summary)
	var lead := Story.crew_name(Story.crew_for(story, summary, "lead"))
	var implementer := Story.crew_name(Story.crew_for(story, summary, "implementer"))
	var reviewer := Story.crew_name(Story.crew_for(story, summary, "reviewer"))
	result.footer_title = "Mission %s · %s" % [mission, str(summary.get("objective", "objective not recorded")) if summary.get("objective") is String else "objective not recorded"]
	var loops := int(summary.get("revision_count", story.revision_loops)) if Story.is_number(summary.get("revision_count")) else int(story.revision_loops)
	var detail := "revision loops used %d%s" % [loops, (" of %d" % int(story.max_rounds)) if int(story.max_rounds) > 0 else ""]
	var task: Dictionary = Story.dict(Story.dict(story.assignments).get("implementer"))
	if task.get("fallback_crews") is Array and not task.fallback_crews.is_empty(): detail += " · fallback implementer: " + Story.crew_name(str(task.fallback_crews[0]))
	for change in story.reassignments:
		if change is Dictionary: detail += " · reassigned %s → %s (round %s)" % [Story.crew_name(str(change.get("from", "?"))), Story.crew_name(str(change.get("to", "?"))), str(change.get("round", "?"))]
	if ctx.get("fixture", false): detail += " · SYNTHETIC"
	result.footer_detail = detail
	result.track = Story.track(story, summary, Story.dict(ctx.get("verdicts")))
	var listed := reviews(story)
	if listed.is_empty():
		result.heading = "Handoff · " + state.replace("_", " ")
		var current: Dictionary = Story.dict(Story.dict(summary.get("stage_evidence")).get("reviewing"))
		if not story.full and not current.is_empty():
			var count: Variant = current.get("findings")
			result.detail = "Review recorded · " + str(current.get("status", "status not recorded"))
			result.empty = line("[?] Review text needs the full mission record · summary reports %s%s" % [str(current.get("status", "a review")), (" with %d finding%s" % [count.size(), "" if count.size() == 1 else "s"]) if count is Array else ""], "unknown")
		elif not story.full and round > 1:
			result.detail = "Round %d · earlier reviews not loaded" % round
			result.empty = line("[?] Earlier reviews need the full mission record (%s)" % str(ctx.get("record_status", "not loaded")), "unknown")
		else:
			result.detail = "%s → %s → %s" % [lead, implementer, reviewer]
			result.empty = line("[-] No review handoff recorded yet · %s" % stage_phrase(state, implementer, reviewer, round), "muted")
		if not live: result.empty.text = "LAST KNOWN · " + result.empty.text
		return result
	var index := int(ctx.get("index", -1))
	if index < 0 or index >= listed.size(): index = listed.size() - 1
	result.index = index
	result.count = listed.size()
	result.nav = "Review %d of %d · ← / →" % [index + 1, listed.size()]
	var chosen: Dictionary = listed[index]
	var review: Dictionary = chosen.review
	var r := int(chosen.round)
	var status := Story.review_status(review)
	var data: Dictionary = review.data
	var reviewer_card := {"side":"left", "name":reviewer, "role":"reviewer", "lines":[], "list":[], "foot":""}
	match status:
		"revise":
			result.heading = "%s returns the candidate to %s" % [reviewer, implementer]
			reviewer_card.status = line("[!] changes requested", "waiting")
		"accept":
			result.heading = "%s accepts %s's round %d" % [reviewer, implementer, r]
			reviewer_card.status = line("[=] accepted", "passed")
		"abstain":
			result.heading = "%s abstains on round %d" % [reviewer, r]
			reviewer_card.status = line("[?] abstained", "unknown")
		"rejected":
			result.heading = "Patch rejected before execution · back to %s" % implementer
			reviewer_card.name = "Core"
			reviewer_card.role = "patch validator"
			reviewer_card.status = line("[x] not executed", "failed")
		_:
			result.heading = "%s reviewed round %d" % [reviewer, r]
			reviewer_card.status = line("[?] status not recorded", "unknown")
	var next_slot: Dictionary = Story.dict(Story.dict(story.rounds).get(r + 1))
	var moved := not next_slot.is_empty()
	result.detail = ("reviewing → implementing · round %d → %d" % [r, r + 1]) if moved else ("reviewing · round %d · %s" % [r, stage_phrase(state, implementer, reviewer, round)])
	var rationale: Variant = data.get("rationale", Story.dict(data.get("output")).get("rationale"))
	if status == "rejected": reviewer_card.lines.append(line(str(data.get("validation_error", "Validation reason not recorded")), "text"))
	elif rationale is String and not rationale.is_empty(): reviewer_card.lines.append(line("“" + rationale + "”", "text"))
	else: reviewer_card.lines.append(line("[?] Review rationale not recorded", "unknown"))
	var found: Variant = Story.findings(review)
	if found == null: reviewer_card.list.append(line("[?] Findings not reported", "unknown"))
	elif found.is_empty(): reviewer_card.list.append(line("[-] No findings", "muted"))
	else:
		var n := 0
		for item in found:
			n += 1
			var finding: Dictionary = Story.dict(item)
			var where := str(finding.get("path", "")).get_file() if finding.get("path") is String else "path not recorded"
			if Story.is_number(finding.get("line")): where += ":" + str(int(finding.line))
			reviewer_card.list.append(line("%d  %s  %s" % [n, where, str(finding.get("problem", "problem not recorded"))], "text"))
	var missing: Variant = data.get("missing_evidence", Story.dict(data.get("output")).get("missing_evidence"))
	if missing is String and not missing.is_empty(): reviewer_card.list.append(line("?  Missing evidence: " + missing, "unknown"))
	reviewer_card.foot = "Recorded review output, %s · the reasoning behind it is not recorded" % Activity.clock(review.at)
	result.cards.append(reviewer_card)
	var reply := {"side":"right", "name":implementer, "role":"implementer", "lines":[], "list":[], "foot":""}
	var reply_testing: Dictionary = Story.dict(next_slot.get("testing"))
	if status == "accept":
		reply.status = line("[-] no reply needed", "muted")
		reply.lines.append(line("The review accepted this round; Core checks the gates next.", "muted"))
	elif not reply_testing.is_empty():
		var patch: Dictionary = Story.dict(Story.dict(reply_testing.data).get("patch"))
		var said: Variant = Story.dict(patch.get("output")).get("rationale")
		reply.status = line("[=] round %d submitted" % (r + 1), "passed")
		reply.lines.append(line("“" + str(said) + "”", "text") if said is String and not said.is_empty() else line("[?] Reply rationale not recorded", "unknown"))
		reply.foot = "Reply is the rationale %s recorded with the round %d candidate, %s" % [implementer, r + 1, Activity.clock(reply_testing.at)]
		var crew_now := Story.crew_name(str(Story.dict(Story.dict(patch.get("assignment"))).get("crew", "")))
		if patch.get("assignment") is Dictionary and crew_now != implementer: reply.name = crew_now
	elif state in ["blocked", "failed", "cancelled"] or summary.get("cancel_requested", false):
		reply.status = line("[_] no reply · mission " + (state.replace("_", " ") if not summary.get("cancel_requested", false) else "stop requested"), "blocked" if state != "failed" else "failed")
		reply.lines.append(line("No round %d candidate was recorded." % (r + 1), "muted"))
	elif moved or (state == "implementing" and round == r + 1):
		reply.status = line("[>] revising · reply not recorded yet" if live else "[?] last known · reply not recorded", "working" if live else "stale")
		reply.lines.append(line("%s's reply is the rationale recorded with the round %d candidate. It appears when Core retains that candidate." % [implementer, r + 1], "muted"))
	else:
		reply.status = line("[?] reply not recorded", "unknown")
		reply.lines.append(line("No later round is recorded for this review.", "muted"))
	result.cards.append(reply)
	return result

static func stage_phrase(state: String, implementer: String, reviewer: String, round: int) -> String:
	match state:
		"queued", "investigating": return "lead is planning"
		"implementing": return "%s is implementing round %d" % [implementer, round]
		"testing": return "%s is reviewing round %d" % [reviewer, round]
		"reviewing": return "review recorded · Core decides next"
		"ready_to_publish", "publishing": return "publishing through the Reality Gate"
		"submitted", "awaiting_review": return "PR awaiting human review"
	return state.replace("_", " ")

# --- View ------------------------------------------------------------------

static func surface(bg: String, border: String, radius: int = 10, pad: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(bg)
	style.border_color = Color(border)
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = pad; style.content_margin_right = pad
	style.content_margin_top = pad - 4; style.content_margin_bottom = pad - 4
	return style

func make_label(parent: Node, text: String, size: int, tone: String = "text") -> Label:
	var item := Label.new()
	item.text = text
	item.set_meta("base_font", size)
	item.add_theme_font_size_override("font_size", size + (3 if large_text else 0))
	item.add_theme_color_override("font_color", Color(TONES.get(tone, tone)))
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(item)
	return item

func _ready() -> void:
	name = "HandoffDialogue"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color("02060a59")
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var column := VBoxContainer.new()
	column.name = "Layout"
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	var top := CenterContainer.new()
	column.add_child(top)
	heading_panel = PanelContainer.new()
	heading_panel.add_theme_stylebox_override("panel", surface("0d1621eb", "7fdcff38", 10, 14))
	top.add_child(heading_panel)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	heading_panel.add_child(head)
	var titles := VBoxContainer.new()
	head.add_child(titles)
	make_label(titles, "HANDOFF · REVIEW DIALOGUE", 11, "muted").autowrap_mode = TextServer.AUTOWRAP_OFF
	heading = make_label(titles, "", 15, "title")
	heading_detail = make_label(titles, "", 12, "waiting")
	var side := VBoxContainer.new()
	head.add_child(side)
	heading_badge = make_label(side, "", 12, "muted")
	nav_label = make_label(side, "", 11, "muted")
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	side.add_child(buttons)
	for spec in [["← Review", func(): review_step.emit(-1), "Earlier review · Left arrow"], ["Review →", func(): review_step.emit(1), "Later review · Right arrow"],
			["Console [N]", func(): workstation_requested.emit(), "Open the workstation console"], ["Close [Esc]", func(): close_requested.emit(), "Close the dialogue · Esc"]]:
		var control := Button.new()
		control.text = spec[0]
		control.tooltip_text = spec[2]
		control.add_theme_font_size_override("font_size", 13)
		control.pressed.connect(spec[1])
		buttons.add_child(control)
		close_button = control
	var middle := ScrollContainer.new()
	dialogue_scroll = middle
	middle.name = "DialogueScroll"
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(middle)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(center)
	cards_row = BoxContainer.new()
	cards_row.add_theme_constant_override("separation", 48)
	center.add_child(cards_row)
	for side_name in ["left", "right"]:
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 0)
		cards_row.add_child(stack)
		var panel := PanelContainer.new()
		panel.name = "ReviewerCard" if side_name == "left" else "ReplyCard"
		stack.add_child(panel)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 8)
		panel.add_child(body)
		var top_row := HBoxContainer.new()
		top_row.add_theme_constant_override("separation", 10)
		body.add_child(top_row)
		var who := make_label(top_row, "", 15, "title")
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var state := make_label(top_row, "", 12, "muted")
		state.autowrap_mode = TextServer.AUTOWRAP_OFF
		var quote := VBoxContainer.new()
		quote.add_theme_constant_override("separation", 4)
		body.add_child(quote)
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 4)
		body.add_child(list)
		var foot := make_label(body, "", 11, "muted")
		var tail := make_tail(side_name == "right")
		stack.add_child(tail)
		cards.append({"stack":stack, "panel":panel, "name":who, "status":state, "quote":quote, "list":list, "foot":foot, "tail":tail})
	empty_card = PanelContainer.new()
	empty_card.name = "NoHandoffCard"
	empty_card.add_theme_stylebox_override("panel", surface("0d1621eb", "7fdcff38"))
	cards_row.add_child(empty_card)
	empty_label = make_label(empty_card, "", 14, "muted")
	footer = PanelContainer.new()
	footer.name = "StageTrack"
	footer.add_theme_stylebox_override("panel", surface("0d1621eb", "7fdcff38", 10, 14))
	column.add_child(footer)
	var foot_column := VBoxContainer.new()
	foot_column.add_theme_constant_override("separation", 8)
	footer.add_child(foot_column)
	var foot_head := HBoxContainer.new()
	foot_head.add_theme_constant_override("separation", 12)
	foot_column.add_child(foot_head)
	footer_title = make_label(foot_head, "", 11, "muted")
	footer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_detail = make_label(foot_head, "", 12, "muted")
	footer_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track = HFlowContainer.new()
	track.name = "Stages"
	track.add_theme_constant_override("h_separation", 6)
	track.add_theme_constant_override("v_separation", 6)
	foot_column.add_child(track)
	hide()

func open() -> void:
	show()
	close_button.grab_focus()

## _input, not _unhandled: a focused button would take arrows for focus moves.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed: return
	match event.physical_keycode:
		KEY_LEFT: review_step.emit(-1); get_viewport().set_input_as_handled()
		KEY_RIGHT: review_step.emit(1); get_viewport().set_input_as_handled()
		KEY_PAGEDOWN: dialogue_scroll.scroll_vertical += int(dialogue_scroll.size.y * 0.8); get_viewport().set_input_as_handled()
		KEY_PAGEUP: dialogue_scroll.scroll_vertical -= int(dialogue_scroll.size.y * 0.8); get_viewport().set_input_as_handled()

## inset: the left and top edges kept clear for the HUD's navigation and masthead.
func fit(viewport_size: Vector2, large: bool, inset: Vector2 = Vector2.ZERO) -> void:
	var changed := large != large_text
	large_text = large
	compact = viewport_size.x < 1100
	var margin := 24.0 if not compact else 12.0
	position = Vector2.ZERO
	size = viewport_size
	var layout: Control = get_node("Layout")
	layout.offset_left = inset.x + margin; layout.offset_right = -margin
	layout.offset_top = inset.y + (12.0 if not compact else 6.0); layout.offset_bottom = -(20.0 if not compact else 10.0)
	cards_row.vertical = compact and large
	var available := viewport_size.x - inset.x - margin * 2.0 - 48.0
	var widths := [minf(470.0, available * 0.54), minf(400.0, available * 0.46)] if not cards_row.vertical else [minf(640.0, viewport_size.x - margin * 2.0), minf(640.0, viewport_size.x - margin * 2.0)]
	for index in cards.size():
		cards[index].panel.custom_minimum_size.x = widths[index]
		for label in cards[index].panel.find_children("*", "Label", true, false):
			if label.autowrap_mode != TextServer.AUTOWRAP_OFF and label != cards[index].name: label.custom_minimum_size.x = widths[index] - 36.0
	empty_label.custom_minimum_size.x = minf(560.0, viewport_size.x - margin * 2.0 - 40.0)
	heading.custom_minimum_size.x = minf(560.0, viewport_size.x * 0.45)
	if changed:
		for label in find_children("*", "Label", true, false):
			label.add_theme_font_size_override("font_size", int(label.get_meta("base_font", 13)) + (3 if large else 0))
		signature = ""
		if not model.is_empty(): render(model)

func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func render(next: Dictionary) -> void:
	model = next
	heading.text = str(next.get("heading", "Handoff"))
	heading_detail.text = str(next.get("detail", ""))
	var shown: Dictionary = next.get("badge", line("[?] UNKNOWN", "unknown"))
	heading_badge.text = str(shown.text) if next.get("live", false) else "LAST KNOWN · " + str(shown.text)
	heading_badge.add_theme_color_override("font_color", Color(TONES.get(str(shown.tone), "9fb3c1")))
	nav_label.text = str(next.get("nav", ""))
	footer_title.text = str(next.get("footer_title", "")).to_upper()
	footer_detail.text = str(next.get("footer_detail", ""))
	var content := JSON.stringify([next.get("cards"), next.get("empty"), next.get("track"), next.get("live"), large_text, compact])
	if content == signature: return
	signature = content
	var listed: Array = next.get("cards", [])
	for index in cards.size():
		var card: Dictionary = cards[index]
		card.stack.visible = index < listed.size()
		if index >= listed.size(): continue
		var data: Dictionary = listed[index]
		var status: Dictionary = data.get("status", line("[?]", "unknown"))
		card.panel.add_theme_stylebox_override("panel", surface("0d1621eb", TONES.get(str(status.tone), "7fdcff") + "80"))
		card.name.text = "%s · %s" % [str(data.name), str(data.role)]
		card.status.text = str(status.text)
		card.status.add_theme_color_override("font_color", Color(TONES.get(str(status.tone), "9fb3c1")))
		clear(card.quote)
		clear(card.list)
		for item in data.get("lines", []): make_label(card.quote, str(item.text), 14, str(item.tone)).custom_minimum_size.x = card.panel.custom_minimum_size.x - 36.0
		if not data.get("list", []).is_empty():
			make_label(card.list, "FINDINGS", 11, "muted")
			for item in data.list: make_label(card.list, str(item.text), 13, str(item.tone)).custom_minimum_size.x = card.panel.custom_minimum_size.x - 36.0
		card.foot.text = str(data.get("foot", ""))
		card.foot.visible = not card.foot.text.is_empty()
		card.tail.visible = not cards_row.vertical
	var empty: Dictionary = next.get("empty", {})
	empty_card.visible = listed.is_empty()
	empty_label.text = str(empty.get("text", ""))
	empty_label.add_theme_color_override("font_color", Color(TONES.get(str(empty.get("tone", "muted")), "9fb3c1")))
	clear(track)
	for item in next.get("track", []):
		var style: Array = STAGE_STYLE.get(str(item.status), STAGE_STYLE.unknown)
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", surface(style[0], "7fdcff99" if item.status == "current" else "00000000", 6, 11))
		track.add_child(chip)
		var text := str(item.text) if str(item.status) == "loop" else str(style[2]) + " " + str(item.text)
		var label := make_label(chip, text, 12, style[1])
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.tooltip_text = str(item.text) + " · " + str(item.status)
