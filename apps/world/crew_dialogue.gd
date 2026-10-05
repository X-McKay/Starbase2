extends PanelContainer
## Page 6 (crew dialogue). The operator asks preset questions; every answer is a
## fixed template filled only from the crew board model, which is itself a
## projection of recorded state. No model text is generated or shown. Each
## answer cites the records it used in a "Based on:" line. A crew member whose
## records are stale, silent or unknown does not speak: Moss answers for them
## from their last known records.
const Model = preload("res://crew_board_model.gd")
const LiveView = preload("res://live_crew_view.gd")
const QUESTIONS := [
	{"id":"waiting", "label":"What is waiting on me?"},
	{"id":"why_blocked", "label":"Why can't we start another mission?"},
	{"id":"accounted", "label":"Is everyone accounted for?"},
	{"id":"finished", "label":"What finished in the last 24 h?"},
	{"id":"carry_on", "label":"Carry on. [Esc]"}]
const WORDS := ["Nothing", "One thing", "Two things", "Three things", "Four things", "Five things"]
signal closed
var model: Dictionary = {}
var target := "review"
var question := ""
var heading: Label
var summary: Label
var back: Button
var badge: Label
var speaker: Label
var subtitle: Label
var line: Label
var based_on: Label
var options: Array = []
var hud_ref: Node

static func names_list(names: Array) -> String:
	if names.size() <= 1: return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[-1]

## Who speaks for `kind`: the member themself when their records are current,
## otherwise Moss (the duty officer), otherwise the station record itself.
static func speaker_for(data: Dictionary, kind: String) -> Dictionary:
	var person := Model.person(data, kind)
	var moss := Model.person(data, "review")
	if not person.is_empty() and not person.last_known:
		return {"kind":kind, "name":person.name, "init":person.init, "for":"",
			"subtitle":person.role + " · speaking from recorded state"}
	if not moss.is_empty() and not moss.last_known:
		return {"kind":"review", "name":"Moss", "init":"Mo", "for":kind if kind != "review" else "",
			"subtitle":("lead · answering for %s (%s) from last known records" % [person.get("name", kind), person.get("state_text", "unknown")]) if kind != "review" else "lead · speaking from recorded state"}
	return {"kind":"core", "name":"Station record", "init":"SR", "for":kind,
		"subtitle":"no crew member has current records · last known only"}

static func tag(data: Dictionary, id: String) -> Dictionary:
	match id:
		"waiting": return {"text":"%d NEED YOU" % int(data.get("needs_known", 0)) if int(data.get("needs_known", 0)) > 0 else "NONE KNOWN", "tone":"need" if int(data.get("needs_known", 0)) > 0 else "muted"}
		"why_blocked":
			var gate: Dictionary = data.get("admission", {})
			if not gate.get("known", false): return {"text":"UNKNOWN", "tone":"muted"}
			return {"text":"BLOCKED", "tone":"failed"} if gate.get("blocked", false) else {"text":"READY", "tone":"passed"}
		"accounted":
			var stale := int(data.get("stale_count", 0))
			return {"text":"%d LAST KNOWN" % stale, "tone":"failed"} if stale > 0 else {"text":"ALL CURRENT", "tone":"passed"}
		"finished": return {"text":"LOG", "tone":"muted"}
	return {"text":"", "tone":"muted"}

## The answer for one preset question, filled only from `data` (the board model).
static func answer(data: Dictionary, id: String, kind: String) -> Dictionary:
	var who := speaker_for(data, kind)
	var lines: PackedStringArray = []
	var based: PackedStringArray = []
	var now := float(data.get("now", 0.0))
	var v7_note := ("/v7 snapshot %s ago" % Model.ago(float(data.get("v7_age", 0.0)))) if bool(data.get("v7_current", false)) else "/v7 snapshot not current · last known"
	match id:
		"waiting":
			var known: Array = data.get("needs", []).filter(func(n): return not n.get("unknown", false))
			var unknown: Array = data.get("needs", []).filter(func(n): return n.get("unknown", false))
			lines.append((WORDS[known.size()] if known.size() < WORDS.size() else "%d things" % known.size()) + (" in these records is waiting on you." if known.is_empty() else "."))
			for item in known: lines.append(str(item.say))
			for item in unknown: lines.append(str(item.say))
			for item in known + unknown: based.append(str(item.source))
			if not bool(data.get("v7_current", false)): lines.insert(0, "As of the last snapshot:")
		"why_blocked":
			var gate: Dictionary = data.get("admission", {})
			if not gate.get("known", false):
				lines.append("I don't know. There is no V7 admission state in these records.")
				based.append("no admission in /v7 snapshot")
			else:
				if not gate.current: lines.append("As of the last snapshot:")
				if not gate.blocked:
					lines.append("Nothing is blocking. Core reports admission ready, and Core still checks authority before every effect.")
				elif gate.code == "active_mission" and not str(gate.mission).is_empty():
					var holder := Model.name_of(Model.ROLE_KIND.get(preload("res://sdlc_crew.gd").ASSIGNED.get(str(gate.state), ""), "core"))
					lines.append("Core refused admission with active_mission.")
					lines.append("%s is still on mission %s, %s, round %d. When it finishes, the next one can start." % [holder, Model.short_id(str(gate.mission)), str(gate.state).replace("_", " "), int(gate.round)])
				else:
					lines.append("Core reports admission %s." % str(gate.code))
					if not str(gate.resolution).is_empty(): lines.append("Core's recorded resolution: \"%s\"" % str(gate.resolution))
				based.append("admission " + str(gate.code))
				if not str(gate.mission).is_empty(): based.append("mission %s state %s" % [gate.mission, gate.state])
			based.append(v7_note)
		"accounted":
			var missing: Array = data.get("crew", []).filter(func(p): return p.last_known)
			var current: Array = data.get("crew", []).filter(func(p): return not p.last_known)
			if bool(data.get("v2_disconnected", true)) and missing.size() == data.get("crew", []).size():
				lines.append("I can't confirm anyone. Core is disconnected, so everything here is last known.")
			for person in missing:
				if person.status == "silent":
					lines.append("Not %s. Nothing from the %s has changed in %s. %s. I am not treating that as healthy." % [person.name, person.role, Model.ago(float(person.silent_for)), str(person.now).replace("Last known:", "The last thing recorded is").replace(" (unconfirmed)", "")])
				elif person.status == "stale":
					lines.append("Not %s. Core marks the %s's record stale because the worker is unavailable. %s." % [person.name, person.role, str(person.now).replace(" (unconfirmed)", "")])
				elif not bool(data.get("v2_disconnected", true)) or missing.size() < data.get("crew", []).size():
					lines.append("I can't confirm %s: %s." % [person.name, str(person.now).to_lower()])
				for source in person.sources: based.append(str(person.name) + " " + str(source))
			if missing.is_empty(): lines.append("Yes. Every crew member has a current record.")
			if not current.is_empty():
				var parts: Array = current.map(func(p): return "%s %s" % [p.name, p.state_text])
				lines.append(("Everyone else is accounted for: " if not missing.is_empty() else "") + names_list(parts) + ".")
			based.append("/v2 snapshot " + ("disconnected · last known" if bool(data.get("v2_disconnected", true)) else "current"))
			based.append(v7_note)
		"finished":
			var scope: Array = data.get("crew", [])
			var solo: bool = kind != "review" and who.get("for", "") == ""
			if solo: scope = scope.filter(func(p): return p.kind == kind)
			var texts: Array = []
			for person in scope:
				for item in person.done:
					if not texts.has(item.text): texts.append(item.text)
			var subject := Model.name_of(kind) if solo else "The crew"
			if texts.is_empty(): lines.append("%s finished nothing in the last 24 h, as far as these records show." % subject)
			else:
				lines.append("%s finished %d thing%s in the last 24 h:" % [subject, texts.size(), "" if texts.size() == 1 else "s"])
				for text in texts.slice(0, 5): lines.append("· " + str(text) + ".")
				if texts.size() > 5: lines.append("· and %d more in the feed." % (texts.size() - 5))
			based.append("%d terminal record%s since %s UTC" % [texts.size(), "" if texts.size() == 1 else "s", Model.clock(now - Model.DAY_SECONDS)])
		"carry_on":
			lines.append("Understood. The board keeps updating from the records.")
		_:
			var count := int(data.get("needs_known", 0))
			if who.get("for", "") != "" and who.kind == "review":
				lines.append("%s is %s, so I'm answering from %s's last known records." % [Model.name_of(str(who["for"])), Model.person(data, str(who["for"])).get("state_text", "unknown"), Model.name_of(str(who["for"]))])
			lines.append(("%s %s your call. " % [WORDS[count] if count < WORDS.size() else "%d things" % count, "needs" if count == 1 else "need"]) if count > 0 else "Nothing in these records needs you right now. ")
			lines[-1] += "I only answer from recorded state."
	return {"speaker":who, "line":"\n".join(lines), "based_on":"Based on: " + " · ".join(based) if not based.is_empty() else ""}

func label(parent: Node, text: String, size: int, color: String) -> Label:
	var item := Label.new()
	item.text = text
	item.set_meta("base_font", size)
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", Color(color))
	parent.add_child(item)
	return item

func _ready() -> void:
	name = "CrewDialogue"
	# Opaque: the board behind is dimmed and must not read through the answer.
	var surface := LiveView.panel_style(20)
	surface.bg_color = Color("0b1626fa")
	surface.border_color = Color("7fdcff99")
	add_theme_stylebox_override("panel", surface)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	column.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	heading = label(titles, "SHIFT BRIEFING", 20, LiveView.TONES.title)
	summary = label(titles, "", 13, LiveView.MUTED)
	summary.clip_text = true
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	back = Button.new()
	back.name = "DialogueBack"
	back.text = "Back to crew board [Esc]"
	back.custom_minimum_size = Vector2(0, 38)
	back.pressed.connect(close)
	head.add_child(back)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 14)
	column.add_child(who)
	var badge_panel := PanelContainer.new()
	var badge_style := LiveView.panel_style(8)
	badge_style.bg_color = Color("ffc861")
	badge_panel.add_theme_stylebox_override("panel", badge_style)
	badge_panel.custom_minimum_size = Vector2(52, 52)
	who.add_child(badge_panel)
	badge = label(badge_panel, "Mo", 18, "0b141d")
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(names)
	speaker = label(names, "Moss", 18, LiveView.TONES.title)
	subtitle = label(names, "", 13, LiveView.MUTED)
	subtitle.clip_text = true
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# The answer scrolls when a short window or larger text leaves too little room.
	var answer_scroll := ScrollContainer.new()
	answer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	answer_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(answer_scroll)
	var answer_column := VBoxContainer.new()
	answer_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	answer_column.add_theme_constant_override("separation", 10)
	answer_scroll.add_child(answer_column)
	line = label(answer_column, "", 17, LiveView.TEXT)
	line.name = "DialogueLine"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	based_on = label(answer_column, "", 13, LiveView.MUTED)
	based_on.name = "DialogueBasedOn"
	based_on.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(HSeparator.new())
	for index in QUESTIONS.size():
		var option := Button.new()
		option.name = "Question%d" % (index + 1)
		option.alignment = HORIZONTAL_ALIGNMENT_LEFT
		option.custom_minimum_size = Vector2(0, 38)
		option.clip_text = true
		option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var id: String = QUESTIONS[index].id
		option.pressed.connect(func(): ask(id))
		column.add_child(option)
		options.append(option)
	hide()

func open_for(kind: String, data: Dictionary, first_question: String = "") -> void:
	target = kind
	question = ""
	show()
	set_model(data)
	if not first_question.is_empty(): ask(first_question)
	options[0 if first_question.is_empty() else maxi(0, QUESTIONS.map(func(q): return q.id).find(first_question))].grab_focus()

func close() -> void:
	if not visible: return
	hide()
	closed.emit()

func ask(id: String) -> void:
	if id == "carry_on":
		question = id
		render()
		close()
		return
	question = id
	render()

func set_model(data: Dictionary) -> void:
	model = data
	if visible: render()

func render() -> void:
	if line == null: return
	var stale := int(model.get("stale_count", 0))
	summary.text = "%d need you · %d blocked · %d last known · %s" % [int(model.get("needs_known", 0)), int(model.get("blocked_count", 0)), stale, str(model.get("freshness", ""))]
	var result := answer(model, question, target)
	var who: Dictionary = result.speaker
	speaker.text = str(who.name)
	subtitle.text = str(who.subtitle)
	subtitle.tooltip_text = subtitle.text
	summary.tooltip_text = summary.text
	badge.text = str(who.init)
	line.text = "\"" + str(result.line) + "\""
	based_on.text = str(result.based_on)
	based_on.visible = not based_on.text.is_empty()
	heading.text = "SHIFT BRIEFING · " + (("ASKING " + Model.name_of(target).to_upper()) if who.get("for", "") == "" else ("ABOUT " + Model.name_of(str(who["for"])).to_upper()))
	for index in options.size():
		var id: String = QUESTIONS[index].id
		var tag_info := tag(model, id)
		var option: Button = options[index]
		option.text = "%d   %s%s" % [index + 1, QUESTIONS[index].label, ("    [" + tag_info.text + "]") if not str(tag_info.text).is_empty() else ""]
		option.tooltip_text = option.text
		option.add_theme_color_override("font_color", Color(Model.TONES.get(tag_info.tone, LiveView.TEXT)) if id == question else Color(LiveView.TEXT))

## Keys while the dialogue is open: 1–5 ask, Esc closes back to the board, T is
## swallowed so it does not toggle the hidden live activity panel.
func handle_key(event: InputEventKey) -> bool:
	if not visible or not event.pressed or event.echo: return false
	if event.physical_keycode == KEY_ESCAPE:
		close()
		return true
	if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_5:
		var index: int = event.physical_keycode - KEY_1
		options[index].grab_focus()
		ask(QUESTIONS[index].id)
		return true
	return event.physical_keycode == KEY_T
