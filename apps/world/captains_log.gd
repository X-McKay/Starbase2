extends PanelContainer
## Page 4 · Captain's Log. A mission timeline with one lane per crew role plus
## Core, built only from authoritative records (see captains_log_model.gd). The
## chronological list is the structured non-spatial equivalent: the same events,
## the same selection and the same detail panel. Read-only; nothing dispatches.
const Model = preload("res://captains_log_model.gd")
const EventStream = preload("res://event_stream.gd")
const NAVY := "0b1626fc"
const BORDER := "4fd6e866"
const TEXT := "e3ecf2"
const MUTED := "aebccc"
const INK := "0d1621"
const PIN := 28.0
const LEGEND := "Pins are recorded events, numbered in time order: click one, or step with , and . (arrows, Tab). Hollow pins are live stream observations Core does not retain; ~ pins await the record. Shaded breaks are collapsed quiet gaps. The dashed line is now."
const LEGEND_COMPACT := "Pins: recorded events in time order (, . arrows Tab). Hollow: live observation, not retained. Shaded: quiet gap. Dashed: now."
var api := preload("res://transport.gd").default_origin()
var http: Node
var large_text := false
var compact := false
var list_mode := false
## Fixture mode: mission id -> full record path, plus the stream's time offset.
var fixture_records: Dictionary = {}
var fixture_offset := 0.0
var model: Dictionary = {}
var selected := -1
var selected_key := ""
var mission_id := ""
var summary: Dictionary = {}
var record: Dictionary = {}
var record_received_msec := 0
var record_state := "unknown"
var fetch_pending := ""
var fetch_signature := ""
var events_signature := ""
var snapshot_known := false
var title_label: Label
var meta_label: Label
var status_box: VBoxContainer
var prev_button: Button
var next_button: Button
var list_button: Button
var close_button: Button
var timeline_panel: PanelContainer
var canvas: Control
var legend: Label
var tokens_box: VBoxContainer
var spacer: Control
var list_scroll: ScrollContainer
var list_box: VBoxContainer
var detail_panel: PanelContainer
var detail_count: Label
var detail_time: Label
var detail_title: Label
var detail_who: Label
var detail_body: Label
var detail_evidence: VBoxContainer
var detail_missing: VBoxContainer
var detail_source: Label
var lane_labels: Array = []
var pins: Array = []
var list_items: Array = []

static func surface(bg: String, border: String, radius: int = 6, pad: int = 14, width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(bg)
	s.border_color = Color(border)
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad; s.content_margin_right = pad
	s.content_margin_top = pad; s.content_margin_bottom = pad
	return s

func make_label(parent: Node, value: String, size: int, color: String = TEXT, wrap: bool = false) -> Label:
	var item := Label.new()
	item.text = value
	item.set_meta("base_font", size)
	item.add_theme_font_size_override("font_size", size + (3 if large_text else 0))
	item.add_theme_color_override("font_color", Color(color))
	if wrap: item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(item)
	return item

func make_button(parent: Node, value: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = value
	item.custom_minimum_size.y = 40
	item.set_meta("base_font", 14)
	item.add_theme_font_size_override("font_size", 14)
	item.pressed.connect(action)
	parent.add_child(item)
	return item

func _ready() -> void:
	name = "CaptainsLog"
	hide()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel", surface(NAVY, BORDER, 10, 18))
	# Full-window workspace: the world and masthead must not read through it.
	http = preload("res://transport.gd").create()
	add_child(http)
	http.timeout = 8; http.max_redirects = 0; http.body_size_limit = 16777216
	http.request_completed.connect(received)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	column.add_child(titles)
	# First row: page name and actions; the mission text below gets the full width.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	titles.add_child(head)
	var page := make_label(head, "CAPTAIN'S LOG · MISSION TIMELINE", 12, MUTED)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_SHRINK_END
	title_label = make_label(titles, "No mission", 24, "f2f6f8")
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	meta_label = make_label(titles, "", 13, MUTED)
	meta_label.clip_text = true
	meta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_box = VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 0)
	titles.add_child(status_box)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	head.add_child(actions)
	prev_button = make_button(actions, "Previous [,]", func(): step(-1))
	next_button = make_button(actions, "Next [.]", func(): step(1))
	list_button = make_button(actions, "List view [L]", toggle_list)
	list_button.tooltip_text = "Chronological list with the same events · L"
	close_button = make_button(actions, "Close [Esc]", func(): hide())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	column.add_child(body)
	timeline_panel = PanelContainer.new()
	timeline_panel.name = "Timeline"
	timeline_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_panel.add_theme_stylebox_override("panel", surface("0d1621e6", "7fdcff38", 8, 14))
	body.add_child(timeline_panel)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	timeline_panel.add_child(left)
	canvas = Control.new()
	canvas.name = "TimelineCanvas"
	canvas.custom_minimum_size = Vector2(0, 270)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.clip_contents = true
	canvas.draw.connect(draw_canvas)
	canvas.resized.connect(place_pins)
	left.add_child(canvas)
	list_scroll = ScrollContainer.new()
	list_scroll.name = "ChronologicalList"
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.follow_focus = true
	left.add_child(list_scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 4)
	list_scroll.add_child(list_box)
	list_scroll.hide()
	legend = make_label(left, LEGEND, 12, MUTED, true)
	spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	tokens_box = VBoxContainer.new()
	tokens_box.add_theme_constant_override("separation", 4)
	left.add_child(tokens_box)
	detail_panel = PanelContainer.new()
	detail_panel.name = "EventDetail"
	detail_panel.custom_minimum_size.x = 380
	detail_panel.add_theme_stylebox_override("panel", surface("0d1621f0", "7fdcff5a", 8, 16))
	body.add_child(detail_panel)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_panel.add_child(detail_scroll)
	var detail_margin := MarginContainer.new()
	detail_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_margin.add_theme_constant_override("margin_right", 12)
	detail_scroll.add_child(detail_margin)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 8)
	detail_margin.add_child(detail)
	var detail_head := HBoxContainer.new()
	detail.add_child(detail_head)
	detail_count = make_label(detail_head, "NO EVENT SELECTED", 12, MUTED)
	detail_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_count.clip_text = true
	detail_time = make_label(detail_head, "", 12, MUTED)
	detail_title = make_label(detail, "", 19, "f2f6f8", true)
	detail_who = make_label(detail, "", 13, MUTED, true)
	detail_body = make_label(detail, "", 14, "dce7ed", true)
	make_label(detail, "EVIDENCE FROM THE RECORD", 12, MUTED)
	detail_evidence = VBoxContainer.new()
	detail_evidence.add_theme_constant_override("separation", 4)
	detail.add_child(detail_evidence)
	make_label(detail, "NOT RECORDED", 12, MUTED)
	detail_missing = VBoxContainer.new()
	detail.add_child(detail_missing)
	make_label(detail, "SOURCE", 12, MUTED)
	detail_source = make_label(detail, "", 12, MUTED, true)
	render()

func open() -> void:
	show()
	render()
	focus_selected()

func toggle_list() -> void:
	list_mode = not list_mode
	render_mode()
	focus_selected()

func render_mode() -> void:
	canvas.visible = not list_mode
	legend.visible = not list_mode
	list_scroll.visible = list_mode
	spacer.visible = not list_mode
	list_button.text = "Timeline view [L]" if list_mode else "List view [L]"

## Called by the world while the log is visible. `entries` are the live
## activity entries already received from /v8 (records and notes).
func update_from(v7_snapshot: Dictionary, snapshot_current: bool, id: String, entries: Array, freshness: Dictionary, now: float) -> void:
	snapshot_known = v7_snapshot.get("schema_version") == 7
	var next_summary: Dictionary = {}
	for mission in v7_snapshot.get("missions", []):
		if mission is Dictionary and str(mission.get("id", "")) == id: next_summary = mission
	if id != mission_id:
		mission_id = id
		record = {}; record_received_msec = 0; fetch_signature = ""; selected_key = ""; selected = -1; record_state = "unknown"
	summary = next_summary
	maybe_fetch()
	if not fixture_records.is_empty(): pass
	elif has_record():
		# A failed reread keeps the last known record and says so until a read succeeds.
		if record_state != "failed": record_state = "live" if snapshot_current else "stale"
	elif record_state != "failed":
		record_state = "loading" if not summary.is_empty() else "unknown"
	var options := {"now":now, "record_state":record_state, "freshness_text":str(freshness.get("text", "")),
		"freshness_tone":"passed" if freshness.get("live", false) else "waiting", "coordination":v7_snapshot.get("coordination"),
		"snapshot_known":snapshot_known, "record_age":(Time.get_ticks_msec() - record_received_msec) / 1000.0 if record_received_msec > 0 else -1.0}
	model = Model.build(record if has_record() else {}, summary, entries, options)
	render()

func has_record() -> bool:
	return not record.is_empty() and str(record.get("id", "")) == mission_id

## Read the full record when the summary changes (stream events speed up the
## summary refresh). One request at a time; the latest change wins.
func maybe_fetch() -> void:
	if mission_id.is_empty() or summary.is_empty(): return
	var next := mission_id + JSON.stringify([summary.get("updated_at"), summary.get("event_count"), summary.get("state"), summary.get("publication")])
	if next == fetch_signature or not fetch_pending.is_empty(): return
	if not fixture_records.is_empty():
		fetch_signature = next
		var path := str(fixture_records.get(mission_id, ""))
		var data = JSON.parse_string(FileAccess.get_file_as_string(path)) if not path.is_empty() else null
		if data is Dictionary:
			record = EventStream.rebase(data, fixture_offset)
			record_received_msec = Time.get_ticks_msec()
			record_state = "fixture"
		else:
			record = {}
			record_state = "failed"
		return
	fetch_pending = next
	var result: int = http.request(api + "/v7/missions/" + mission_id.uri_encode())
	if result != OK: received(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())

func received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var requested := fetch_pending
	fetch_pending = ""
	if requested.is_empty(): return
	var data = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	if data is Dictionary and requested.begins_with(str(data.get("id", "")) + "[") and str(data.get("id", "")) == mission_id:
		record = data
		record_received_msec = Time.get_ticks_msec()
		record_state = "live"
		fetch_signature = requested
	else:
		# Keep the last known record and say so; retry on the next summary change.
		record_state = "failed"
		fetch_signature = requested

func events() -> Array:
	return model.get("events", [])

func render() -> void:
	if title_label == null: return
	render_mode()
	title_label.text = str(model.get("title", "No mission"))
	meta_label.text = str(model.get("meta", "Open with G from the world. Records come from /v7 and the /v8 stream."))
	meta_label.tooltip_text = meta_label.text
	for child in status_box.get_children(): status_box.remove_child(child); child.queue_free()
	for line in model.get("status", []):
		var tone := str(line.get("tone", "muted"))
		var item := make_label(status_box, (str(line.glyph) + " " if not str(line.get("glyph", "")).is_empty() else "") + str(line.text), 13, str(Model.TONES.get(tone, MUTED)))
		item.clip_text = true
		item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		item.tooltip_text = item.text
	var signature := JSON.stringify(events().map(func(e): return [e.key, e.kind, e.title, e.n, e.glyph]))
	var changed := signature != events_signature
	if changed:
		events_signature = signature
		rebuild_pins()
		rebuild_list()
	if selected_key.is_empty() and not events().is_empty():
		# Open on the newest retained record, not on a transient observation.
		var index := events().size() - 1
		for i in range(events().size() - 1, -1, -1):
			if events()[i].kind == "record":
				index = i
				break
		selected = index
		selected_key = str(events()[index].key)
	else:
		selected = -1
		for i in events().size():
			if str(events()[i].key) == selected_key: selected = i
		if selected < 0 and not events().is_empty():
			selected = events().size() - 1
			selected_key = str(events()[selected].key)
	render_tokens()
	show_detail()
	place_pins()
	canvas.queue_redraw()
	if changed and visible and get_viewport() != null and get_viewport().gui_get_focus_owner() == null: focus_selected()

func rebuild_pins() -> void:
	for pin in pins: canvas.remove_child(pin); pin.queue_free()
	for label in lane_labels: canvas.remove_child(label); label.queue_free()
	pins.clear(); lane_labels.clear()
	for lane in model.get("lanes", []):
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.add_child(box)
		make_label(box, str(lane.name), 15, "f2f6f8")
		# Compact windows fold the token rows into the lane labels.
		var role := str(lane.role)
		if compact and int(lane.tokens) > 0: role = str(lane.id) + " · " + preload("res://live_activity.gd").short_tokens(int(lane.tokens)) + " tok"
		make_label(box, role, 11, MUTED)
		lane_labels.append(box)
	var all := events()
	for i in all.size():
		var e: Dictionary = all[i]
		var pin := Button.new()
		pin.name = "Pin%d" % int(e.n)
		pin.text = str(int(e.n)) if e.kind != "provisional" else "~"
		pin.custom_minimum_size = Vector2(PIN, PIN)
		pin.size = Vector2(PIN, PIN)
		pin.focus_mode = Control.FOCUS_ALL
		pin.tooltip_text = "Event %d · %s UTC · %s %s" % [int(e.n), Model.clock(e.at), str(e.glyph), str(e.title)]
		pin.add_theme_font_size_override("font_size", 11)
		pin.set_meta("index", i)
		var index := i
		pin.pressed.connect(func(): select(index, false))
		pin.focus_entered.connect(func():
			if selected != index: select(index, false))
		canvas.add_child(pin)
		pins.append(pin)
	# Tab follows time order, not tree or screen order.
	for i in pins.size():
		pins[i].focus_next = pins[(i + 1) % pins.size()].get_path()
		pins[i].focus_previous = pins[(i - 1 + pins.size()) % pins.size()].get_path()
	style_pins()

func style_pins() -> void:
	var all := events()
	for i in pins.size():
		if i >= all.size(): break
		var e: Dictionary = all[i]
		var color := Color(str(Model.TONES.get(str(e.tone), MUTED)))
		var hollow: bool = e.kind in ["observation", "provisional"]
		var chosen := i == selected
		var look := surface("0d1621" if hollow else color.to_html(false), "ffffff" if chosen else (color.to_html(false) if hollow else INK), int(PIN / 2), 0, 3 if chosen or hollow else 2)
		for state in ["normal", "hover", "pressed", "disabled"]: pins[i].add_theme_stylebox_override(state, look)
		var focus := surface("00000000", "ffffff", int(PIN / 2) + 3, 0, 3)
		focus.expand_margin_left = 3; focus.expand_margin_right = 3; focus.expand_margin_top = 3; focus.expand_margin_bottom = 3
		pins[i].add_theme_stylebox_override("focus", focus)
		var ink := color if hollow else Color(INK)
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: pins[i].add_theme_color_override(key, ink)

func geometry() -> Dictionary:
	var label_w := 96.0 if compact else 120.0
	var x0 := label_w + 12.0
	var width := maxf(40.0, canvas.size.x - x0 - PIN * 0.5 - 4.0)
	var lane_h := 44.0 if compact else 52.0
	return {"x0":x0, "width":width, "tick_y":0.0, "band_y":24.0, "lane_y":56.0, "lane_h":lane_h, "lane_gap":8.0}

func lane_top(index: int) -> float:
	var g := geometry()
	return g.lane_y + index * (g.lane_h + g.lane_gap)

func place_pins() -> void:
	if canvas == null: return
	var g := geometry()
	for i in lane_labels.size():
		lane_labels[i].position = Vector2(0, lane_top(i) + 2)
		lane_labels[i].size = Vector2(g.x0 - 12.0, g.lane_h)
	var all := events()
	# Events close in time share a lane: spread them so each pin stays legible
	# and clickable, first rightwards, then back inside the right edge.
	var xs: Array = []
	var last_x := {}
	for i in mini(pins.size(), all.size()):
		var lane := Model.LANES.find(str(all[i].lane))
		var x: float = g.x0 + float(all[i].f) * g.width - PIN * 0.5
		if last_x.has(lane): x = maxf(x, float(last_x[lane]) + PIN + 2.0)
		last_x[lane] = x
		xs.append(x)
	var limit := {}
	for i in range(xs.size() - 1, -1, -1):
		var lane := Model.LANES.find(str(all[i].lane))
		var right: float = float(limit.get(lane, g.x0 + g.width))
		xs[i] = maxf(g.x0 - PIN * 0.5, minf(float(xs[i]), right))
		limit[lane] = float(xs[i]) - PIN - 2.0
	for i in xs.size():
		var lane := Model.LANES.find(str(all[i].lane))
		pins[i].position = Vector2(xs[i], lane_top(lane) + (g.lane_h - PIN) * 0.5)
		pins[i].set_meta("center_x", float(xs[i]) + PIN * 0.5)
	canvas.queue_redraw()

func draw_canvas() -> void:
	var g := geometry()
	var font := get_theme_default_font()
	var font_size := 11 + (2 if large_text else 0)
	var bottom: float = lane_top(Model.LANES.size()) - g.lane_gap
	for lane in Model.LANES.size():
		canvas.draw_rect(Rect2(g.x0, lane_top(lane), g.width + PIN * 0.5, g.lane_h), Color(1, 1, 1, 0.04))
	canvas.draw_string(font, Vector2(0, g.band_y + 12), "Mission state", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(MUTED))
	# Collapsed-gap labels take priority; time labels fill the remaining space.
	var taken: Array = []
	for pass_gaps in [true, false]:
		for tick in model.get("ticks", []):
			var gap: bool = tick.get("gap", false)
			if gap != pass_gaps: continue
			var x: float = g.x0 + float(tick.f) * g.width
			var label_x: float = (g.x0 + float(tick.f0) * g.width) if gap else x - 16.0
			var span := Vector2(label_x - 4.0, label_x + font.get_string_size(str(tick.label), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 4.0)
			var fits := true
			for other in taken:
				if span.x < other.y and other.x < span.y: fits = false
			if fits:
				taken.append(span)
				canvas.draw_string(font, Vector2(label_x, g.tick_y + 13), str(tick.label), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(MUTED))
			if gap:
				var x0: float = g.x0 + float(tick.f0) * g.width
				var x1: float = g.x0 + float(tick.f1) * g.width
				canvas.draw_rect(Rect2(x0, g.band_y, maxf(2.0, x1 - x0), bottom - g.band_y), Color(1, 1, 1, 0.07))
				for y in range(int(g.band_y), int(bottom), 10):
					canvas.draw_line(Vector2(x0, y), Vector2(minf(x1, x0 + 8.0), y + 8), Color(1, 1, 1, 0.18), 1.0)
			else:
				canvas.draw_line(Vector2(x, g.tick_y + 17), Vector2(x, bottom), Color(1, 1, 1, 0.08), 1.0)
	for band in model.get("bands", []):
		var x0: float = g.x0 + float(band.f0) * g.width
		var x1: float = g.x0 + float(band.f1) * g.width
		var state := str(band.state)
		var tone := "passed" if state in ["ready_to_publish", "submitted", "awaiting_review"] else ("failed" if state in ["blocked", "failed", "cancelled"] else ("waiting" if state in ["reviewing", "queued"] else "working"))
		canvas.draw_rect(Rect2(x0, g.band_y, maxf(1.0, x1 - x0 - 1.0), 16), Color(Color(str(Model.TONES[tone])), 0.55))
		if x1 - x0 > 60.0: canvas.draw_string(font, Vector2(x0 + 4, g.band_y + 12), state.replace("_", " "), HORIZONTAL_ALIGNMENT_LEFT, x1 - x0 - 6.0, font_size, Color(INK))
	var now_f := float(model.get("now_f", -1.0))
	if now_f >= 0.0:
		var x: float = g.x0 + now_f * g.width
		canvas.draw_dashed_line(Vector2(x, g.band_y), Vector2(x, bottom), Color("6fe3a1"), 2.0, 6.0)
		canvas.draw_string(font, Vector2(x - 12, bottom + 14), "now", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("6fe3a1"))
	if selected >= 0 and selected < pins.size():
		var cx: float = float(pins[selected].get_meta("center_x", 0.0))
		canvas.draw_line(Vector2(cx, g.band_y), Vector2(cx, bottom), Color(1, 1, 1, 0.75), 2.0)
	if events().is_empty():
		canvas.draw_string(font, Vector2(g.x0, lane_top(1) + 28), "No recorded events to place.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(MUTED))

func rebuild_list() -> void:
	for item in list_items: list_box.remove_child(item); item.queue_free()
	list_items.clear()
	var all := events()
	if all.is_empty():
		var empty := Label.new(); empty.text = "No recorded events."
		list_box.add_child(empty); list_items.append(empty)
		return
	for i in all.size():
		var item := Button.new()
		item.name = "ListEvent%d" % int(all[i].n)
		item.text = Model.list_line(all[i])
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item.clip_text = true
		item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		item.tooltip_text = item.text
		item.custom_minimum_size.y = 34
		item.toggle_mode = true
		item.add_theme_font_size_override("font_size", 14 + (3 if large_text else 0))
		item.add_theme_color_override("font_color", Color(str(Model.TONES.get(str(all[i].tone), TEXT))).lerp(Color(TEXT), 0.4))
		var index := i
		item.pressed.connect(func(): select(index, false))
		item.focus_entered.connect(func():
			if selected != index: select(index, false))
		list_box.add_child(item)
		list_items.append(item)

func render_tokens() -> void:
	var next := JSON.stringify([model.get("lanes", []), compact, large_text])
	if next == str(tokens_box.get_meta("signature", "")): return
	tokens_box.set_meta("signature", next)
	for child in tokens_box.get_children(): tokens_box.remove_child(child); child.queue_free()
	make_label(tokens_box, "TOKENS PER CREW · retained in the record", 12, MUTED)
	for lane in model.get("lanes", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		tokens_box.add_child(row)
		var name_label := make_label(row, str(lane.name), 13)
		name_label.custom_minimum_size.x = 96.0 if compact else 120.0
		var track := Control.new()
		track.custom_minimum_size = Vector2(0, 10)
		track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fraction := float(lane.fraction)
		track.draw.connect(func():
			track.draw_rect(Rect2(Vector2.ZERO, track.size), Color(1, 1, 1, 0.06))
			if fraction > 0.0: track.draw_rect(Rect2(Vector2.ZERO, Vector2(track.size.x * fraction, track.size.y)), Color("7fdcff")))
		row.add_child(track)
		var value := make_label(row, str(lane.tokens_text), 12, MUTED)
		value.custom_minimum_size.x = 210.0 if compact else 280.0
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.clip_text = true
		value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		value.tooltip_text = value.text

func show_detail() -> void:
	for box in [detail_evidence, detail_missing]:
		for child in box.get_children(): box.remove_child(child); child.queue_free()
	var all := events()
	if selected < 0 or selected >= all.size():
		detail_count.text = "NO EVENT SELECTED"
		detail_time.text = ""
		detail_title.text = "Nothing recorded yet" if not str(model.get("mission_id", "")).is_empty() else "No mission"
		detail_who.text = ""
		detail_body.text = "The timeline places only events Core has recorded or the live stream has announced."
		detail_source.text = "—"
		return
	var e: Dictionary = all[selected]
	detail_count.text = "EVENT %d OF %d" % [int(e.n), all.size()]
	detail_time.text = Model.clock(e.at) + " UTC"
	detail_time.tooltip_text = Model.stamp(e.at)
	detail_title.text = str(e.glyph) + " " + str(e.title)
	detail_title.add_theme_color_override("font_color", Color(str(Model.TONES.get(str(e.tone), TEXT))).lerp(Color("f2f6f8"), 0.35))
	var kind: String = {"observation":" · live observation, not retained", "provisional":" · streamed, awaiting record", "summary":" · bounded summary"}.get(str(e.kind), "")
	detail_who.text = str(e.who) + " · stage " + str(e.stage).replace("_", " ") + kind
	detail_body.text = str(e.body)
	for line in e.evidence: make_label(detail_evidence, "› " + str(line), 13, TEXT, true)
	if e.evidence.is_empty(): make_label(detail_evidence, "› No further fields in this record", 13, MUTED, true)
	for line in e.not_recorded: make_label(detail_missing, "› " + str(line), 13, MUTED, true)
	if e.not_recorded.is_empty(): make_label(detail_missing, "› Nothing further claimed for this event", 13, MUTED, true)
	detail_source.text = str(e.source)
	style_pins()
	for i in list_items.size():
		if list_items[i] is Button: list_items[i].set_pressed_no_signal(i == selected)
	prev_button.disabled = selected <= 0
	next_button.disabled = selected >= all.size() - 1

func select(index: int, focus: bool = true) -> void:
	var all := events()
	if all.is_empty(): return
	selected = clampi(index, 0, all.size() - 1)
	selected_key = str(all[selected].key)
	show_detail()
	canvas.queue_redraw()
	if focus: focus_selected()

func step(direction: int) -> void:
	select(selected + direction)

func focus_selected() -> void:
	if not visible or selected < 0: return
	var targets: Array = list_items if list_mode else pins
	if selected < targets.size(): focus_now.call_deferred(selected, list_mode)

## Deferred so a rebuilt pin or row is in the tree; skipped if the target changed.
func focus_now(index: int, in_list: bool) -> void:
	var targets: Array = list_items if in_list else pins
	if not visible or in_list != list_mode or index != selected or index >= targets.size(): return
	var target = targets[index]
	if target is Control and is_instance_valid(target) and target.is_visible_in_tree(): target.grab_focus()

## Keys while the log is open. Arrows and , . move in time; up and down move
## between lanes on the timeline (and between rows in the list).
func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed: return
	var handled := true
	match event.physical_keycode:
		KEY_LEFT, KEY_COMMA: step(-1)
		KEY_RIGHT, KEY_PERIOD: step(1)
		KEY_HOME: select(0)
		KEY_END: select(events().size() - 1)
		KEY_UP: select(selected - 1 if list_mode else Model.neighbour_in_lane(events(), selected, -1))
		KEY_DOWN: select(selected + 1 if list_mode else Model.neighbour_in_lane(events(), selected, 1))
		KEY_L:
			if event.echo: return
			toggle_list()
		_: handled = false
	if handled: get_viewport().set_input_as_handled()

func apply_fonts() -> void:
	for label in find_children("*", "Label", true, false):
		if label.has_meta("base_font"): label.add_theme_font_size_override("font_size", int(label.get_meta("base_font")) + (3 if large_text else 0))
	for button in [prev_button, next_button, list_button, close_button]: button.add_theme_font_size_override("font_size", 14 + (3 if large_text else 0))

## viewport: the HUD root size. Below 1100 px the detail column narrows.
func fit(viewport_size: Vector2, large: bool) -> void:
	var was_compact := compact
	compact = viewport_size.x < 1100.0
	if large != large_text:
		large_text = large
		apply_fonts()
		events_signature = ""
	offset_left = 24 if not compact else 12
	offset_top = 24 if not compact else 12
	offset_right = -offset_left
	offset_bottom = -offset_top
	if detail_panel != null:
		detail_panel.custom_minimum_size.x = 300.0 if compact else 380.0
		tokens_box.visible = not compact
		legend.text = LEGEND_COMPACT if compact else LEGEND
		canvas.custom_minimum_size.y = lane_top(Model.LANES.size()) + 14.0
	if was_compact != compact: events_signature = ""
	render()
