extends PanelContainer
## Page 5 (crew board, design 5E-R3). Left: what needs the operator, alert chips
## and a newest-first feed of crew and Core events. Right: one line per crew
## member and the selected member's day. Rendering and navigation only: the
## world feeds a model from crew_board_model.gd, and the only actions wired are
## ones that already exist in the world (open a recorded PR link, open Field
## ops, inspect a mission, watch a crew member). Anything else says it is not
## available here. Every control is reachable with the keyboard.
const Model = preload("res://crew_board_model.gd")
const LiveView = preload("res://live_crew_view.gd")
const NEED_ROWS := 5
const CHIP_SLOTS := 4
signal talk_requested(kind: String, question: String)
var hud_ref: Node
## Replaced by tests so pressing "Open PR" never launches a browser.
var open_url: Callable = func(url: String): OS.shell_open(url)
var model: Dictionary = {}
var selected := ""
var title: Label
var freshness: Label
var places: Button
var close_button: Button
var needs_title: Label
var need_rows: Array = []
var action_status: Label
var chip_row: HFlowContainer
var chips: Array = []
var feed_title: Label
var show_all: Button
var feed_scroll: ScrollContainer
var feed_list: VBoxContainer
var feed_rows: Array = []
var crew_buttons: Dictionary = {}
var day_panel: PanelContainer
var day_name: Label
var day_state: Label
var day_counts: Label
var day_now: Label
var day_next: Label
var day_done_title: Label
var day_done: Label
var talk: Button
var watch: Button
var talk_hint: Label
var last_action := {}
var watch_armed := false
var columns: HBoxContainer

func label(parent: Node, text: String, size: int, color: String) -> Label:
	var item := Label.new()
	item.text = text
	item.set_meta("base_font", size)
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", Color(color))
	parent.add_child(item)
	return item

func heading(parent: Node, text: String) -> Label:
	return label(parent, text, 12, LiveView.MUTED)

func button(parent: Node, text: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = text
	item.tooltip_text = text
	item.custom_minimum_size = Vector2(0, 36)
	item.pressed.connect(action)
	parent.add_child(item)
	return item

static func box(color: String, border: String, pad: int = 10) -> StyleBoxFlat:
	var surface := LiveView.panel_style(pad)
	surface.bg_color = Color(color)
	surface.border_color = Color(border)
	return surface

func _ready() -> void:
	name = "CrewBoard"
	add_theme_stylebox_override("panel", LiveView.panel_style(16))
	var root_column := VBoxContainer.new()
	root_column.add_theme_constant_override("separation", 12)
	add_child(root_column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	root_column.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	title = label(titles, "COMMAND · CREW BOARD [Tab]", 20, LiveView.TONES.title)
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 12)
	titles.add_child(sub)
	var purpose := label(sub, "What happened, what needs you, and where everyone is", 13, LiveView.MUTED)
	freshness = label(sub, "[?] UNKNOWN", 13, LiveView.MUTED)
	for item in [title, purpose, freshness]:
		item.clip_text = true
		item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	places = button(head, "Crew & places [P]", func(): if hud_ref != null: hud_ref.toggle_directory())
	close_button = button(head, "Close [Esc]", func(): if hud_ref != null: hud_ref.close_panels())
	columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_column.add_child(columns)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.15
	columns.add_child(left)
	needs_title = label(left, "[!] NEEDS YOU", 13, Model.TONES.need)
	needs_title.clip_text = true
	for index in NEED_ROWS:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", box("0f1c28e6", "ffc86155", 8))
		left.add_child(row)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		row.add_child(line)
		var glyph := label(line, "[!]", 14, Model.TONES.need)
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_theme_constant_override("separation", 0)
		line.add_child(words)
		var main := label(words, "", 15, LiveView.TEXT)
		main.clip_text = true
		main.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var detail := label(words, "", 12, LiveView.MUTED)
		detail.clip_text = true
		detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var action := Button.new()
		action.name = "NeedAction%d" % index
		action.custom_minimum_size = Vector2(112, 36)
		action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(action)
		var slot := index
		action.pressed.connect(func(): run_need(slot))
		need_rows.append({"panel":row, "glyph":glyph, "title":main, "detail":detail, "action":action, "need":{}})
	action_status = label(left, "", 13, LiveView.TONES.waiting)
	action_status.name = "NeedActionStatus"
	action_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_status.hide()
	chip_row = HFlowContainer.new()
	chip_row.add_theme_constant_override("h_separation", 8)
	chip_row.add_theme_constant_override("v_separation", 6)
	left.add_child(chip_row)
	for index in CHIP_SLOTS:
		var chip := Button.new()
		chip.name = "AlertChip%d" % index
		chip.custom_minimum_size = Vector2(0, 32)
		chip.add_theme_stylebox_override("normal", box("2a1414e6", "ff8f7d99", 6))
		var slot := index
		chip.pressed.connect(func(): run_chip(slot))
		chip_row.add_child(chip)
		chips.append({"button":chip, "chip":{}})
	var feed_head := HBoxContainer.new()
	left.add_child(feed_head)
	feed_title = heading(feed_head, "ACTIVITY · ALL CREW AND CORE · NEWEST FIRST")
	feed_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed_title.clip_text = true
	show_all = button(feed_head, "Show all crew ×", func(): select(""))
	show_all.custom_minimum_size = Vector2(0, 30)
	show_all.hide()
	feed_scroll = ScrollContainer.new()
	feed_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	feed_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(feed_scroll)
	feed_list = VBoxContainer.new()
	feed_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed_list.add_theme_constant_override("separation", 3)
	feed_scroll.add_child(feed_list)
	for index in Model.FEED_LIMIT:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		feed_list.add_child(row)
		var time := label(row, "", 12, LiveView.MUTED)
		var who := label(row, "", 13, LiveView.TONES.title)
		who.custom_minimum_size.x = 48
		var glyph := label(row, "", 13, LiveView.MUTED)
		var text := label(row, "", 13, LiveView.TEXT)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.clip_text = true
		text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		feed_rows.append({"row":row, "time":time, "who":who, "glyph":glyph, "text":text})
		row.hide()
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	heading(right, "CREW · SELECT ONE TO SEE THEIR DAY")
	for item in Model.CREW:
		var entry := Button.new()
		entry.name = "Crew_" + str(item.kind)
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.clip_text = true
		entry.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		entry.custom_minimum_size = Vector2(0, 38)
		entry.toggle_mode = true
		var kind: String = item.kind
		entry.pressed.connect(func(): select("" if selected == kind else kind))
		right.add_child(entry)
		crew_buttons[kind] = entry
	day_panel = PanelContainer.new()
	day_panel.name = "CrewDay"
	day_panel.add_theme_stylebox_override("panel", box("0f1c28f0", "7fdcff55", 12))
	day_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(day_panel)
	# The day scrolls inside its panel on short windows and with larger text.
	var day_scroll := ScrollContainer.new()
	day_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	day_scroll.follow_focus = true
	day_panel.add_child(day_scroll)
	var day := VBoxContainer.new()
	day.add_theme_constant_override("separation", 5)
	day.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	day.size_flags_vertical = Control.SIZE_EXPAND_FILL
	day_scroll.add_child(day)
	day_name = label(day, "", 18, LiveView.TONES.title)
	day_state = label(day, "", 13, LiveView.MUTED)
	day_counts = label(day, "", 12, LiveView.MUTED)
	for item in [day_name, day_state, day_counts]: item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading(day, "DOING NOW")
	day_now = label(day, "", 15, LiveView.TEXT)
	day_now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading(day, "UP NEXT")
	day_next = label(day, "", 14, LiveView.TEXT)
	day_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	day_done_title = heading(day, "DONE · LAST 24 H")
	day_done = label(day, "", 13, LiveView.TEXT)
	day_done.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Talk and Watch stay outside the scroll so they are always on screen.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	right.add_child(actions)
	talk = button(actions, "Talk [T]", func(): request_talk(""))
	talk.clip_text = true
	talk.name = "CrewTalk"
	talk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	watch = button(actions, "Watch in the world [W]", watch_selected)
	watch.clip_text = true
	watch.name = "CrewWatch"
	watch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	talk_hint = label(right, "", 12, LiveView.MUTED)
	talk_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hide()

## Fit to the workspace rectangle the HUD gives every full panel.
var narrow_layout := false

func fit(area: Rect2, narrow: bool) -> void:
	narrow_layout = narrow
	position = area.position
	size = area.size
	custom_minimum_size = Vector2.ZERO
	columns.add_theme_constant_override("separation", 10 if narrow else 18)

func open() -> void:
	show()
	render()
	focus_default()

func focus_default() -> void:
	var target: Button = crew_buttons.get(selected, crew_buttons.review)
	target.grab_focus()

func focus_owner_inside() -> bool:
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return owner != null and is_ancestor_of(owner)

func set_model(data: Dictionary) -> void:
	model = data
	if visible: render()

func select(kind: String) -> void:
	selected = kind
	render()
	if not kind.is_empty() and crew_buttons.has(kind) and focus_owner_inside(): crew_buttons[kind].grab_focus()

func focus_kind() -> String:
	return selected if not selected.is_empty() else "review"

func render() -> void:
	if title == null or model.is_empty(): return
	freshness.text = str(model.get("freshness", ""))
	var needs: Array = model.get("needs", [])
	needs_title.text = "[!] NEEDS YOU · %d known%s · oldest first" % [int(model.get("needs_known", 0)), (" · %d unknown" % int(model.get("needs_unknown", 0))) if int(model.get("needs_unknown", 0)) > 0 else ""]
	if not bool(model.get("v7_current", false)): needs_title.text += " · LAST KNOWN"
	for index in need_rows.size():
		var row: Dictionary = need_rows[index]
		row.panel.visible = index < needs.size()
		if index >= needs.size(): row.need = {}; continue
		var need: Dictionary = needs[index]
		row.need = need
		row.glyph.text = str(need.glyph)
		row.glyph.add_theme_color_override("font_color", Color(Model.TONES.get(str(need.tone), LiveView.MUTED)))
		row.title.text = str(need.title)
		row.detail.text = str(need.detail)
		row.title.tooltip_text = str(need.title) + "\n" + str(need.detail) + "\nBased on: " + str(need.source)
		var action: Dictionary = need.action
		row.action.text = str(action.label)
		row.action.tooltip_text = str(action.get("reason", action.label)) if action.kind == "unavailable" else ("%s · %s" % [action.label, need.title])
		if action.kind == "unavailable": row.action.add_theme_color_override("font_color", Color(LiveView.MUTED))
		else: row.action.remove_theme_color_override("font_color")
	var chip_data: Array = model.get("chips", [])
	for index in chips.size():
		var slot: Dictionary = chips[index]
		slot.button.visible = index < chip_data.size()
		slot.chip = chip_data[index] if index < chip_data.size() else {}
		if index < chip_data.size():
			slot.button.text = str(chip_data[index].text)
			slot.button.tooltip_text = slot.button.text + " · ask the duty officer"
			slot.button.add_theme_color_override("font_color", Color(Model.TONES.get(str(chip_data[index].tone), LiveView.TEXT)))
	var feed := Model.filtered_feed(model, selected)
	feed_title.text = ("ACTIVITY · %s ONLY · NEWEST FIRST" % Model.name_of(selected).to_upper()) if not selected.is_empty() else "ACTIVITY · ALL CREW AND CORE · NEWEST FIRST"
	show_all.visible = not selected.is_empty()
	for index in feed_rows.size():
		var row: Dictionary = feed_rows[index]
		row.row.visible = index < feed.size()
		if index >= feed.size(): continue
		var item: Dictionary = feed[index]
		row.time.text = str(item.time)
		row.who.text = str(item.who)
		row.glyph.text = str(item.glyph)
		row.glyph.add_theme_color_override("font_color", Color(str(item.color)))
		row.text.text = str(item.text)
		row.text.tooltip_text = "%s UTC · %s %s · from %s" % [item.time, item.who, item.text, item.source]
	if feed.is_empty() and not feed_rows.is_empty():
		feed_rows[0].row.show()
		feed_rows[0].time.text = ""
		feed_rows[0].who.text = ""
		feed_rows[0].glyph.text = "[-]"
		feed_rows[0].text.text = "No recorded events" + (" for " + Model.name_of(selected) if not selected.is_empty() else "")
	for item in model.get("crew", []):
		var entry: Button = crew_buttons.get(item.kind)
		if entry == null: continue
		entry.text = "%s  %s   %s %s · %s" % [item.init, item.name, item.glyph, item.state_text, item.now]
		entry.tooltip_text = "%s · %s\n%s\nEnter selects · T talks · W watches" % [item.name, item.state_text, item.now]
		entry.set_pressed_no_signal(item.kind == selected)
		var on: bool = item.kind == selected
		var border := "7fdcff" if on else ("ff8f7d88" if item.last_known else "7fdcff33")
		entry.add_theme_stylebox_override("normal", box("7fdcff1f" if on else "0b1626e6", border, 8))
		entry.add_theme_stylebox_override("pressed", box("7fdcff2e", "7fdcff", 8))
		entry.add_theme_color_override("font_color", Color(str(item.color)) if item.last_known else Color(LiveView.TEXT))
		entry.add_theme_color_override("font_pressed_color", Color(LiveView.TONES.title))
	var person := Model.person(model, focus_kind())
	if person.is_empty(): return
	day_name.text = "%s · %s%s" % [person.name, person.role, "" if not selected.is_empty() else " · duty officer"]
	day_state.text = "%s %s · %s" % [person.glyph, person.state_text, person.where]
	day_state.add_theme_color_override("font_color", Color(str(person.color)))
	day_counts.text = "%d run%s in the last 24 h · %s" % [int(person.runs), "" if int(person.runs) == 1 else "s", person.tokens]
	day_now.text = str(person.now)
	day_next.text = str(person.next)
	day_done_title.text = "DONE · LAST 24 H · %d" % int(person.done_count)
	var done_lines: Array = person.done.slice(0, 3).map(func(item): return "[=] " + str(item.text) if not str(item.text).contains("failed") else "[x] " + str(item.text))
	day_done.text = "\n".join(done_lines) if not done_lines.is_empty() else "Nothing finished in these records"
	var speaker := preload("res://crew_dialogue.gd").speaker_for(model, focus_kind())
	if speaker.get("for", "") != "" and speaker.kind == "review": talk.text = "Ask Moss about %s [T]" % person.name
	elif speaker.kind == "core": talk.text = "Read %s's last records [T]" % person.name
	else: talk.text = "Talk to %s [T]" % person.name
	talk.tooltip_text = talk.text + (" · the duty officer" if selected.is_empty() else "")
	watch.text = ("Watch %s [W]" if narrow_layout else "Watch %s in the world [W]") % person.name
	watch.tooltip_text = watch.text
	talk_hint.text = ("Opens the dialogue with Moss, since %s is %s" % [person.name, person.state_text]) if speaker.get("for", "") != "" else ("Moss is the duty officer · select a crew member to filter the feed and talk to them" if selected.is_empty() else "Answers come only from recorded state")

func run_need(index: int) -> void:
	var need: Dictionary = need_rows[index].need
	if need.is_empty(): return
	var action: Dictionary = need.action
	last_action = action.duplicate()
	action_status.show()
	match str(action.kind):
		"open_url":
			action_status.text = "Opening %s in your browser · review and merge stay with you" % need.title.trim_prefix("Review ")
			open_url.call(str(action.url))
		"open_memory":
			action_status.text = "Opening Field ops → Memory"
			if hud_ref != null:
				hud_ref.open_board()
				hud_ref.board.tabs.current_tab = 2
		"inspect_mission":
			action_status.text = "Opening mission " + str(action.mission)
			if hud_ref != null:
				hud_ref.open_board()
				hud_ref.board.tabs.current_tab = 5
				hud_ref.board.sdlc_missions.selected = str(action.mission)
				hud_ref.board.sdlc_missions.signature = ""
				hud_ref.board.sdlc_missions.render()
		_:
			action_status.text = "%s · %s" % [action.label, str(action.get("reason", "Not available here"))]

func run_chip(index: int) -> void:
	var chip: Dictionary = chips[index].chip
	if chip.is_empty(): return
	request_talk(str(chip.get("question", "")), str(chip.get("kind", "")))

func request_talk(question: String, kind: String = "") -> void:
	talk_requested.emit(kind if not kind.is_empty() else focus_kind(), question)

func watch_selected() -> void:
	if hud_ref != null: hud_ref.watch_requested.emit(focus_kind())

## Board keys: T talks, W watches. W acts on release so the held key does not
## become a walk step once the board closes.
func handle_key(event: InputEventKey) -> bool:
	if not visible: return false
	if event.physical_keycode == KEY_W:
		if event.pressed and not event.echo: watch_armed = true
		elif not event.pressed and watch_armed:
			watch_armed = false
			watch_selected()
		return true
	if not event.pressed or event.echo: return false
	if event.physical_keycode == KEY_T:
		request_talk("")
		return true
	return false
