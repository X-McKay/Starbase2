extends Control
## Page 1 live crew view overlays inside the exploration HUD: the live activity
## panel, the Reality Gate and the follow-card. Rendering only; the world feeds
## projections from stream notes and the /v7 snapshot, and nothing here dispatches.
const NAVY := "0b1626de"
const BORDER := "4fd6e877"
const TEXT := "e3ecf2"
const MUTED := "aebccc"
const TONES := {"working":"6fe3f0", "waiting":"f3c26b", "passed":"8fdc8a", "failed":"ff8a70", "muted":"aebccc", "title":"f2f6f8"}
const ROWS := 6
var activity_panel: PanelContainer
var activity_title: Label
var activity_hint: Label
var activity_rows: Array = []
var activity_empty: Label
var activity_tab: Button
var gate_panel: PanelContainer
var gate_title: Label
var gate_summary: Label
var gate_mission: Label
var gate_policy: Label
var gate_budget: Label
var gate_checks: Array = []
var gate_note: Label
var card: PanelContainer
var card_lines: Array = []
var card_stem: ColorRect
var narrow := false
var large_text := false
var wide_open := true
var narrow_open := false
var activity_count := 0
var card_anchor := Vector2.ZERO
var card_wanted := false
var right_column_left := 0.0
var bottom_limit := 0.0

static func panel_style(pad: int = 12) -> StyleBoxFlat:
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color(NAVY)
	surface.border_color = Color(BORDER)
	surface.set_border_width_all(1)
	surface.set_corner_radius_all(3)
	surface.content_margin_left = pad
	surface.content_margin_right = pad
	surface.content_margin_top = pad - 3
	surface.content_margin_bottom = pad - 3
	return surface

func make_label(parent: Node, value: String, size: int, color: String) -> Label:
	var item := Label.new()
	item.text = value
	item.set_meta("base_font", size)
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", Color(color))
	item.add_theme_color_override("font_shadow_color", Color("000000cc"))
	item.add_theme_constant_override("shadow_offset_y", 1)
	item.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(item)
	return item

## Information panels must not swallow world clicks (walking, crew selection):
## backgrounds and layout containers ignore the mouse; labels keep tooltips and
## pass unhandled clicks on to the world.
func pass_through(node: Node) -> void:
	for child in [node] + node.find_children("*", "Container", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	name = "LiveCrewView"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gate_panel = PanelContainer.new()
	gate_panel.name = "RealityGate"
	gate_panel.add_theme_stylebox_override("panel", panel_style())
	add_child(gate_panel)
	# Wrapped text settles after layout; keep the activity column under the real gate.
	gate_panel.resized.connect(func(): if activity_panel != null: layout.call_deferred())
	var gate_column := VBoxContainer.new()
	gate_column.add_theme_constant_override("separation", 3)
	gate_panel.add_child(gate_column)
	var gate_head := HBoxContainer.new()
	gate_column.add_child(gate_head)
	gate_title = make_label(gate_head, "REALITY GATE", 13, TONES.title)
	gate_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	make_label(gate_head, "SDLC", 11, MUTED)
	gate_summary = make_label(gate_column, "[?] UNKNOWN", 13, TONES.waiting)
	gate_mission = make_label(gate_column, "No mission selected", 12, MUTED)
	gate_policy = make_label(gate_column, "Policy not reported", 13, TEXT)
	gate_budget = make_label(gate_column, "Missions used unknown", 12, MUTED)
	for index in 3:
		var row := make_label(gate_column, "[?] Check not evaluated", 13, TONES.waiting)
		# Gate checks wrap rather than truncate: the detail is the evidence.
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gate_checks.append(row)
	gate_note = make_label(gate_column, "", 11, MUTED)
	gate_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for item in [gate_mission, gate_policy, gate_budget]:
		item.clip_text = true
		item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	activity_panel = PanelContainer.new()
	activity_panel.name = "LiveActivity"
	activity_panel.add_theme_stylebox_override("panel", panel_style())
	add_child(activity_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	activity_panel.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	activity_title = make_label(head, "LIVE ACTIVITY", 13, TONES.title)
	activity_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	activity_hint = make_label(head, "UTC · hide [T]", 11, MUTED)
	activity_empty = make_label(column, "[-] No stream events yet", 13, MUTED)
	for index in ROWS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		column.add_child(row)
		var time := make_label(row, "", 12, MUTED)
		var glyph := make_label(row, "", 13, TONES.working)
		var text := make_label(row, "", 13, TEXT)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.clip_text = true
		text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		activity_rows.append({"row":row, "time":time, "glyph":glyph, "text":text})
		row.hide()
	activity_tab = Button.new()
	activity_tab.name = "LiveActivityTab"
	activity_tab.text = "[~] Activity [T]"
	activity_tab.add_theme_stylebox_override("normal", panel_style(8))
	activity_tab.add_theme_stylebox_override("hover", panel_style(8))
	activity_tab.add_theme_font_size_override("font_size", 13)
	activity_tab.tooltip_text = "Show the live activity panel · T"
	activity_tab.pressed.connect(toggle_activity)
	add_child(activity_tab)
	card_stem = ColorRect.new()
	card_stem.name = "FollowCardStem"
	card_stem.color = Color(BORDER)
	card_stem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card_stem)
	card_stem.hide()
	card = PanelContainer.new()
	card.name = "FollowCard"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", panel_style(10))
	add_child(card)
	var card_column := VBoxContainer.new()
	card_column.add_theme_constant_override("separation", 2)
	card.add_child(card_column)
	for index in 4:
		var line := make_label(card_column, "", 14 if index == 0 else 13, TEXT)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_lines.append(line)
	card.hide()
	pass_through(gate_panel)
	pass_through(activity_panel)
	pass_through(card)
	apply_fonts()

func toggle_activity() -> void:
	if narrow: narrow_open = not narrow_open
	else: wide_open = not wide_open
	layout()

func activity_visible() -> bool:
	return narrow_open if narrow else wide_open

func set_activity(lines: Array, live: bool) -> void:
	activity_count = lines.size()
	activity_empty.visible = lines.is_empty()
	activity_title.text = "LIVE ACTIVITY" if live else "ACTIVITY · LAST KNOWN"
	for index in ROWS:
		var row: Dictionary = activity_rows[index]
		if index >= lines.size():
			row.row.hide()
			continue
		var line: Dictionary = lines[index]
		row.row.show()
		row.time.text = str(line.get("time", ""))
		row.glyph.text = str(line.get("glyph", "[?]"))
		row.glyph.add_theme_color_override("font_color", Color(str(line.get("color", MUTED))))
		row.text.text = str(line.get("text", ""))
		row.text.tooltip_text = row.time.text + " UTC · " + row.glyph.text + " " + row.text.text
	activity_tab.text = "[~] Activity · %d [T]" % lines.size() if live else "[?] Activity · %d [T]" % lines.size()

func set_gate(model: Dictionary) -> void:
	var summary: Dictionary = model.get("summary", {})
	gate_summary.text = str(summary.get("glyph", "[?]")) + " " + str(summary.get("text", "UNKNOWN"))
	gate_summary.add_theme_color_override("font_color", Color(str(summary.get("color", TONES.waiting))))
	gate_mission.text = str(model.get("mission_line", "No mission selected"))
	gate_policy.text = str(model.get("policy_line", "Policy not reported"))
	gate_budget.text = str(model.get("budget_line", "Missions used unknown"))
	var checks: Array = model.get("checks", [])
	for index in gate_checks.size():
		var label: Label = gate_checks[index]
		if index >= checks.size():
			label.text = "[?] Check not evaluated"
			continue
		label.text = str(checks[index].text)
		label.tooltip_text = label.text
		label.add_theme_color_override("font_color", Color(str(checks[index].color)))
	gate_note.text = str(model.get("note", ""))
	for item in [gate_mission, gate_policy, gate_budget]: item.tooltip_text = item.text

func set_card(lines: Array, anchor: Vector2, wanted: bool) -> void:
	card_wanted = wanted and not lines.is_empty()
	card_anchor = anchor
	for index in card_lines.size():
		var label: Label = card_lines[index]
		label.visible = index < lines.size()
		if index >= lines.size(): continue
		label.text = str(lines[index].text)
		label.add_theme_color_override("font_color", Color(str(TONES.get(str(lines[index].tone), TEXT))))
	place_card()

func place_card() -> void:
	if card == null: return
	card.visible = card_wanted and visible
	card_stem.visible = card.visible
	if not card.visible: return
	card.reset_size()
	var size_now := card.get_combined_minimum_size()
	var limit_right := right_column_left - 12.0 if right_column_left > 0.0 else size.x - 12.0
	var x := clampf(card_anchor.x - size_now.x * 0.5, 12.0, maxf(12.0, limit_right - size_now.x))
	var y := clampf(card_anchor.y - size_now.y - 24.0, 120.0, maxf(120.0, bottom_limit - size_now.y))
	card.position = Vector2(x, y)
	# A thin stem ties the card to the actor it describes.
	var stem_x := clampf(card_anchor.x, x + 8.0, x + size_now.x - 8.0)
	var top := y + size_now.y
	card_stem.position = Vector2(stem_x - 1.0, top)
	card_stem.size = Vector2(2.0, maxf(0.0, card_anchor.y - top))

func apply_fonts() -> void:
	for label in find_children("*", "Label", true, false):
		label.add_theme_font_size_override("font_size", int(label.get_meta("base_font", 13)) + (3 if large_text else 0))
	activity_tab.add_theme_font_size_override("font_size", 16 if large_text else 13)

## top: below the masthead/navigation; bottom: above the prompt and crew strip.
func fit(viewport_size: Vector2, is_narrow: bool, large: bool, top: float, bottom: float, left_limit: float) -> void:
	narrow = is_narrow
	if large != large_text:
		large_text = large
		apply_fonts()
	var width := clampf(viewport_size.x * (0.42 if narrow else 0.29), 300.0, 470.0 if large_text else 430.0)
	width = minf(width, viewport_size.x - left_limit - 22.0)
	right_column_left = viewport_size.x - 22.0 - width
	bottom_limit = bottom
	gate_panel.position = Vector2(right_column_left, top)
	gate_panel.size = Vector2(width, 0)
	gate_panel.custom_minimum_size.x = width
	gate_budget.visible = not narrow or large_text == false
	gate_mission.visible = not narrow
	gate_note.custom_minimum_size.x = width - 24.0
	for row in gate_checks: row.custom_minimum_size.x = width - 24.0
	layout()

func layout() -> void:
	if gate_panel == null: return
	gate_panel.reset_size()
	var width := gate_panel.custom_minimum_size.x
	var below := gate_panel.position.y + maxf(gate_panel.size.y, gate_panel.get_combined_minimum_size().y) + 8.0
	var open := activity_visible()
	activity_panel.visible = open
	activity_tab.visible = not open
	activity_hint.text = ("UTC · close [T]" if narrow else "UTC · hide [T]")
	activity_panel.custom_minimum_size.x = width
	activity_panel.reset_size()
	activity_tab.reset_size()
	var panel_height := activity_panel.get_combined_minimum_size().y
	var tab_size := activity_tab.get_combined_minimum_size()
	activity_panel.position = Vector2(right_column_left, below)
	activity_tab.position = Vector2(right_column_left + width - tab_size.x, below)
	# Short windows: when there is no room under the gate, sit beside it instead
	# of covering the prompt or crew strip.
	if below + panel_height > bottom_limit:
		activity_panel.position = Vector2(maxf(12.0, right_column_left - width - 8.0), gate_panel.position.y)
	if below + tab_size.y > bottom_limit:
		activity_tab.position = Vector2(right_column_left - tab_size.x - 8.0, gate_panel.position.y)
	place_card()

func activity_rect() -> Rect2:
	return activity_panel.get_global_rect() if activity_panel.visible else activity_tab.get_global_rect()
