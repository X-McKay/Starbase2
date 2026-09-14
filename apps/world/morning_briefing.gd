extends PanelContainer
## Historical, read-only projection. No replay, dispatch, memory or inferred absence.
const StateView = preload("res://state.gd")
const ConsoleTheme = preload("res://console_theme.gd")
const MAX_REPORTS := 5
const TERMINAL := ["completed", "failed", "cancelled"]
const OPEN := ["queued", "running", "cancel_requested", "executing", "analyzing", "evaluating", "verifying", "capturing", "reviewing"]
const CREW := {"review":"Moss Bombadil", "evaluation":"Mae Jin", "gym":"Mae Jin", "repair":"Rivet", "watchkeeper":"Wes Walker", "reviewer":"Prism"}
signal inspect_requested(run_id: String, context: String)
signal closed
var heading: Label
var freshness: Label
var summary: Label
var reports: VBoxContainer
var dismiss: Button
var large_text := false
var model: Dictionary = {}
var render_signature := ""
var search: LineEdit
var state_filter: OptionButton
var results_count: Label
var selected_key := ""
var workspace: BoxContainer
var detail_scroll: ScrollContainer
var detail_column: VBoxContainer
var detail_title: Label
var detail_metadata: Label
var detail_action: Button
var report_scroll: ScrollContainer

static func project(records: Array, disconnected: bool, observed_at: float, fixture: bool = false) -> Dictionary:
	var unique: Dictionary = {}
	for value in records:
		if not value is Dictionary or not value.get("input") is Dictionary: continue
		var id := str(value.input.get("id", ""))
		if id.is_empty(): continue
		var context := StateView.context(value)
		var key := context+":"+id
		var stamp := float(value.get("updated_at", 0)) if value.get("updated_at") is float or value.get("updated_at") is int else 0.0
		if unique.has(key) and stamp <= float(unique[key].get("stamp", 0)): continue
		unique[key] = {"record":value, "stamp":stamp, "id":id, "context":context}
	var retained: Array = []
	var active := 0
	var unknown := 0
	for entry in unique.values():
		var record: Dictionary = entry.record
		var state := str(record.get("state", "unknown"))
		if state not in TERMINAL:
			if state in OPEN: active += 1
			else: unknown += 1
			continue
		var evidence: Dictionary = record.get("evidence") if record.get("evidence") is Dictionary else {}
		var outcome: Dictionary = evidence.get("summary") if evidence.get("summary") is Dictionary else {}
		var label := state.capitalize()
		if state == "completed" and evidence.is_empty(): label = "Completion recorded · evidence missing"
		elif state == "completed":
			var result := str(outcome.get("outcome", ""))
			label = "Completed · "+result.replace("_", " ") if not result.is_empty() else "Completed · evidence retained"
		if record.get("stale", false): label = "Stale record · "+label
		retained.append({"id":entry.id, "context":entry.context, "crew":CREW.get(entry.context, "Crew"),
			"stamp":entry.stamp, "status":label, "target":str(record.input.get("target", record.input.get("scenario", "Target not reported"))),
			"advisory":outcome.get("source_kind", "") == "field" or entry.context in ["watchkeeper", "reviewer"],
			"state":state, "evidence_available":not evidence.is_empty()})
	retained.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.stamp == b.stamp: return (a.context+":"+a.id) < (b.context+":"+b.id)
		return a.stamp > b.stamp)
	return {"reports":retained.slice(0, MAX_REPORTS), "retained_count":retained.size(), "active_count":active, "unknown_count":unknown,
		"disconnected":disconnected, "observed_at":observed_at, "fixture":fixture}

func _ready() -> void:
	ConsoleTheme.apply(self)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	heading = make_label(column, "HABITAT / BRIEFING", 22)
	freshness = make_label(column, "Waiting for Core records", 16)
	summary = make_label(column, "Recent reports from the colony", 16)
	search = LineEdit.new()
	search.placeholder_text = "Search crew, target or record ID"
	search.tooltip_text = "Search the displayed snapshot window; does not fetch older records"
	search.clear_button_enabled = true
	search.custom_minimum_size.y = 40
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(_value: String): refresh())
	var filter_row := HBoxContainer.new()
	column.add_child(filter_row)
	filter_row.add_child(search)
	state_filter = OptionButton.new()
	for title in ["All states", "Open", "Completed", "Failed", "Cancelled", "Unknown"]: state_filter.add_item(title)
	state_filter.custom_minimum_size.y = 38
	filter_row.add_child(state_filter)
	state_filter.item_selected.connect(func(_index: int): refresh())
	results_count = make_label(filter_row, "", 16)
	results_count.hide()
	results_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace = HBoxContainer.new()
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(workspace)
	var scroll := ScrollContainer.new()
	report_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(scroll)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reports = VBoxContainer.new()
	reports.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reports.add_theme_constant_override("separation", 3)
	scroll.add_child(reports)
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.follow_focus = true
	workspace.add_child(detail_scroll)
	detail_column = VBoxContainer.new()
	detail_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(detail_column)
	detail_title = make_label(detail_column, "SELECTED RECORD", 18)
	detail_title.add_theme_color_override("font_color", ConsoleTheme.ACCENT)
	detail_action = Button.new()
	detail_action.text = "Inspect selected record →"
	ConsoleTheme.primary(detail_action)
	detail_action.custom_minimum_size.y = 40
	detail_column.add_child(detail_action)
	detail_action.pressed.connect(func():
		for entry in filtered_reports():
			if entry.context+":"+entry.id == selected_key: inspect_requested.emit(entry.id, entry.context))
	detail_metadata = make_label(detail_column, "Select a retained record to see its source identity.", 16)
	dismiss = Button.new()
	dismiss.text = "Back to colony · Esc"
	dismiss.custom_minimum_size.y = 40
	dismiss.pressed.connect(func(): hide(); closed.emit())
	column.add_child(dismiss)
	get_viewport().size_changed.connect(layout)
	minimum_size_changed.connect(layout.call_deferred)
	layout()
	hide()
	refresh()

func make_label(parent: Node, value: String, font_size: int) -> Label:
	var result := Label.new()
	result.text = value
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_size_override("font_size", font_size+(4 if large_text else 0))
	parent.add_child(result)
	return result

func layout() -> void:
	var viewport_size := get_viewport_rect().size
	position = Vector2(184, 92) if viewport_size.x >= 1000 else Vector2(22, 128)
	size = Vector2(minf(1000, viewport_size.x-position.x-22), maxf(220, viewport_size.y-position.y-20))
	if is_instance_valid(workspace):
		var compact := viewport_size.x < 1100
		detail_scroll.visible = not compact
		detail_scroll.custom_minimum_size.x = 280 if not compact else 0
		detail_scroll.size_flags_horizontal = Control.SIZE_FILL
		report_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		for label in reports.find_children("*", "Label", true, false):
			if label.has_meta("compact_detail"): label.visible = compact

func present() -> void:
	show()
	layout()
	dismiss.grab_focus()

func update_records(records: Array, disconnected: bool, observed_at: float, fixture: bool = false) -> void:
	model = project(records, disconnected, observed_at, fixture)
	refresh()
	if is_inside_tree(): layout.call_deferred()

func reset() -> void:
	model.clear()
	selected_key = ""
	if is_instance_valid(search): search.text = ""
	if is_instance_valid(state_filter): state_filter.select(0)
	render_signature = ""
	refresh()

func set_large_text(value: bool) -> void:
	if value==large_text and is_instance_valid(heading): return
	large_text = value
	if not is_instance_valid(heading): return
	heading.add_theme_font_size_override("font_size", 26 if value else 22)
	freshness.add_theme_font_size_override("font_size", 20 if value else 16)
	search.add_theme_font_size_override("font_size", 20 if value else 16)
	state_filter.add_theme_font_size_override("font_size", 20 if value else 16)
	results_count.add_theme_font_size_override("font_size", 20 if value else 16)
	summary.add_theme_font_size_override("font_size", 20 if value else 16)
	dismiss.add_theme_font_size_override("font_size", 20 if value else 16)
	render_signature = ""
	refresh()

func refresh() -> void:
	if not is_instance_valid(reports): return
	if model.is_empty():
		freshness.text = "UNKNOWN · Waiting for Core records"
		summary.text = "Recent reports from the colony"
	else:
		var stamp := float(model.observed_at)
		freshness.text = ("OFFLINE / STALE · last-known records" if model.disconnected else "CORE SNAPSHOT")
		freshness.text += " · "+Time.get_datetime_string_from_unix_time(int(stamp)).replace("T", " ")+" UTC" if stamp > 0 else " · observation time unavailable"
		if model.fixture: freshness.text = "FIXTURE · "+freshness.text
		summary.text = "HISTORICAL · snapshot window · %d terminal · %d open%s" % [model.retained_count, model.active_count, " (last known)" if model.disconnected else ""]
		if int(model.get("unknown_count", 0))>0: summary.text += " · %d unknown"%model.unknown_count
	var entries := filtered_reports()
	results_count.text = "%d / %d in window" % [entries.size(), model.get("reports", []).size()]
	summary.text += " · "+results_count.text
	var signature := JSON.stringify([entries, large_text])
	if signature == render_signature: return
	render_signature = signature
	var focused := ""
	var focus := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus) and reports.is_ancestor_of(focus): focused = str(focus.get_meta("record_key", ""))
	for child in reports.get_children():
		reports.remove_child(child)
		child.queue_free()
	if entries.is_empty():
		make_label(reports, "No matching records in this window." if not model.get("reports", []).is_empty() else "No terminal records in this snapshot.\nEarlier work may exist outside this window.", 16)
	if not entries.any(func(entry): return entry.context+":"+entry.id == selected_key):
		selected_key = entries[0].context+":"+entries[0].id if not entries.is_empty() else ""
	for entry in entries:
		var surface := PanelContainer.new()
		var style := ConsoleTheme.box(Color("10101055"), Color("77777733"), 9)
		style.border_width_left = 2
		style.border_width_top = 0
		style.border_width_right = 0
		surface.set_meta("record_key", entry.context+":"+entry.id)
		if selected_key == entry.context+":"+entry.id: style.border_color = ConsoleTheme.ACCENT
		surface.add_theme_stylebox_override("panel", style)
		reports.add_child(surface)
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 3)
		surface.add_child(card)
		var top := HBoxContainer.new()
		card.add_child(top)
		var identity := make_label(top, str(entry.crew)+" · "+("Stale · " if str(entry.status).to_lower().contains("stale") else "")+str(entry.state).replace("_", " ").capitalize(), 16)
		identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var inspect := Button.new()
		inspect.text = "Inspect →"
		inspect.toggle_mode = true
		inspect.button_pressed = selected_key == entry.context+":"+entry.id
		inspect.tooltip_text = "Run "+str(entry.id)+" · "+str(entry.context)
		inspect.custom_minimum_size.y = 40
		inspect.add_theme_font_size_override("font_size", 20 if large_text else 16)
		inspect.set_meta("record_key", entry.context+":"+entry.id)
		inspect.focus_entered.connect(func(): select_entry(entry))
		inspect.mouse_entered.connect(func(): select_entry(entry))
		inspect.pressed.connect(func():
			select_entry(entry)
			inspect_requested.emit(entry.id, entry.context))
		top.add_child(inspect)
		make_label(card, str(entry.target), 16)
		var time_label := Time.get_datetime_string_from_unix_time(int(entry.stamp)).replace("T", " ")+" UTC" if entry.stamp > 0 else "Update time unavailable"
		var qualifier := "Evidence retained" if entry.evidence_available else "Evidence unavailable"
		if entry.advisory: qualifier += " · advisory, not verified"
		var metadata := make_label(card, time_label+" · "+qualifier, 14)
		metadata.add_theme_color_override("font_color", ConsoleTheme.MUTED)
		# Compact layouts keep all identity and outcome information in the row.
		var compact_detail := make_label(card, str(entry.status)+" · ID "+str(entry.id), 14)
		compact_detail.add_theme_color_override("font_color", ConsoleTheme.MUTED)
		compact_detail.visible = get_viewport_rect().size.x < 1100
		compact_detail.set_meta("compact_detail", true)
		if inspect.get_meta("record_key") == focused: inspect.grab_focus()
	update_selected_detail()

	if not focused.is_empty() and get_viewport().gui_get_focus_owner() == null: dismiss.grab_focus()

func select_entry(entry: Dictionary) -> void:
	selected_key = entry.context+":"+entry.id
	for surface in reports.get_children():
		if surface is PanelContainer:
			var style: StyleBoxFlat = surface.get_theme_stylebox("panel")
			style.border_color = ConsoleTheme.ACCENT if surface.get_meta("record_key", "") == selected_key else Color("77777733")
	for button in reports.find_children("*", "Button", true, false):
		button.set_pressed_no_signal(button.get_meta("record_key", "") == selected_key)
	update_selected_detail()

func update_selected_detail() -> void:
	if not is_instance_valid(detail_metadata): return
	detail_action.disabled = true
	detail_title.text = "SELECTED RECORD"
	detail_metadata.text = "No record selected in this window."
	for entry in filtered_reports():
		if entry.context+":"+entry.id != selected_key: continue
		detail_title.text = str(entry.crew).to_upper()
		detail_action.disabled = false
		var stamp := Time.get_datetime_string_from_unix_time(int(entry.stamp)).replace("T", " ")+" UTC" if entry.stamp > 0 else "Not reported"
		detail_metadata.text = "LATEST KNOWN STATE\n"+str(entry.status)+"\n\nTARGET\n"+str(entry.target)+"\n\nRECORD ID\n"+str(entry.id)+"\n\nCONTEXT\n"+str(entry.context)+"\n\nUPDATED\n"+stamp+"\n\nEVIDENCE\n"+("Retained" if entry.evidence_available else "Unavailable")
		if entry.advisory: detail_metadata.text += " · advisory, not verified"
		detail_metadata.add_theme_font_size_override("font_size", 20 if large_text else 16)

func filtered_reports() -> Array:
	var output: Array = []
	var query := search.text.strip_edges().to_lower() if is_instance_valid(search) else ""
	var filter_index := state_filter.selected if is_instance_valid(state_filter) else 0
	for entry in model.get("reports", []):
		var state := str(entry.get("state", "unknown"))
		if filter_index == 1 and state not in OPEN: continue
		if filter_index in [2, 3, 4] and state != ["completed", "failed", "cancelled"][filter_index-2]: continue
		if filter_index == 5 and (state in OPEN or state in TERMINAL): continue
		var haystack := (str(entry.crew)+" "+str(entry.target)+" "+str(entry.id)+" "+str(entry.status)).to_lower()
		if not query.is_empty() and not haystack.contains(query): continue
		output.append(entry)
	return output
