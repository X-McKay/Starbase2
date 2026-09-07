extends CanvasLayer
## Contextual controls; all commands have a non-spatial keyboard path.
## Layout and styling live here and in ui_theme.gd; every label's content
## comes from world.gd projections of authoritative records.
const CrewArt = preload("res://crew_art.gd")
const UI = preload("res://ui_theme.gd")
const CREW := {
	"repair":{"title":"MENDER / WORKSHOP","short":"Mender · workshop","appearance":"mender","suit":"COPPER EXOSUIT","key":"1","tint":Color.WHITE},
	"review":{"title":"SURVEYOR / COMMAND","short":"Surveyor · command","appearance":"surveyor","suit":"EVA EXPLORER","key":"2","tint":Color.WHITE},
	"gym":{"title":"TRAINER / TRIAL HALL","short":"Trainer · trial hall","appearance":"trainer","suit":"IVORY SENTINEL","key":"3","tint":Color.WHITE},
	"watchkeeper":{"title":"WATCHKEEPER / CLUSTER WATCH","short":"Watchkeeper · cluster watch","appearance":"trainer","suit":"AZURE SENTINEL","key":"4","tint":Color(0.5,0.82,1)},
	"reviewer":{"title":"PR REVIEWER / COMMAND","short":"PR Reviewer · command","appearance":"operator","suit":"VIOLET FIELD ANALYST","key":"5","tint":Color(0.85,0.65,1)},
}
var board: PanelContainer
var api := "http://127.0.0.1:8787"
var board_fixture := ""
var sound_enabled := false
var portrait: TextureRect
var suit_label: Label
signal place_selected(kind: String)
signal journal_requested
signal repair_requested(scenario: String, mode: String)
signal cancel_requested
signal selection_changed(id: String)
signal settings_changed
signal map_requested
signal room_requested(kind: String)
signal exit_requested
var room_exit: Button
var root := Control.new()
var scrim: ColorRect
var dock: PanelContainer
var directory: PanelContainer
var building_list: VBoxContainer
var building_search: LineEdit
var help: PanelContainer
var connection: Label
var connection_badge: HBoxContainer
var prompt: Label
var prompt_row: HBoxContainer
var roster: HFlowContainer
var heading: Label
var status: Label
var status_badge: HBoxContainer
var details: Label
var evidence: RichTextLabel
var evidence_toggle: Button
var list: OptionButton
var progression: Label
var progression_badge: HBoxContainer
var command_status: Label
var command_strip: PanelContainer
var repair_form: VBoxContainer
var scenario: OptionButton
var mode: OptionButton
var submit: Button
var stop: Button
var toast: PanelContainer
var toast_badge: HBoxContainer
var toast_timer := Timer.new()
var crew_badges: Dictionary = {}
var directory_first: Button
var help_first: Control
var reduced := false
var follow := true
var large_text := false
var records: Array = []
var selected_id := ""
var filter_kind := "repair"
var compact := false
var command_pending := false
var _prompt_signature := ""
var _roster_signature := ""
var margin := 24
var bar_height := 112

func _ready() -> void:
	layer = 2
	margin = 18 if compact else 24
	bar_height = 178 if compact else 116
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.build(large_text)
	_build_scrim()
	_build_masthead()
	_build_nav()
	_build_bottom_bar()
	_build_dock()
	_build_directory()
	_build_help()
	_build_toast()
	board=preload("res://command_board.gd").new()
	board.api=api; board.fixture=board_fixture
	root.add_child(board)
	board.offset_left=margin; board.offset_right=-margin
	board.offset_top=100 if compact else 104
	board.offset_bottom=-(bar_height+margin+10)
	board.closed.connect(close_panels)
	add_child(toast_timer)
	toast_timer.one_shot=true
	toast_timer.timeout.connect(func(): toast.hide())

func _build_scrim() -> void:
	scrim=ColorRect.new()
	scrim.color=UI.color("scrim")
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter=Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed: close_panels())
	scrim.hide()
	root.add_child(scrim)

func _build_masthead() -> void:
	var mast := VBoxContainer.new()
	mast.position = Vector2(margin+4,16)
	mast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mast.add_theme_constant_override("separation",2)
	root.add_child(mast)
	UI.eyebrow(mast,"Starbase 02   /   Aster Colony")
	var title := UI.label(mast,"A new world. A first foothold.","Display",false)
	title.add_theme_color_override("font_shadow_color",Color("0b1622cc"))
	title.add_theme_constant_override("shadow_offset_y",2)
	var pill := PanelContainer.new()
	pill.theme_type_variation="Chip"
	pill.mouse_filter=Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	mast.add_child(pill)
	connection_badge=UI.badge(pill,"unknown","Connecting to local core…")
	connection=connection_badge.get_node("Text")
	room_exit=UI.button(root,"Return to colony",func(): exit_requested.emit(),"NavButton","F")
	room_exit.custom_minimum_size=Vector2(232,42)
	room_exit.position=Vector2(margin+4,112)
	room_exit.hide()

func _build_nav() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation",8)
	root.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top.offset_top = 18
	top.offset_right = -margin
	var width := 132 if compact else 140
	for entry in [["Map","M",func(): map_requested.emit()],["Crew","Tab",toggle_directory],["Journal","J",func(): journal_requested.emit()]]:
		var b := UI.button(top,entry[0],entry[2],"NavButton",entry[1])
		b.custom_minimum_size=Vector2(width,42)
		b.size_flags_horizontal=Control.SIZE_SHRINK_END
	top.offset_left = -(width*3+16+margin)

func _build_bottom_bar() -> void:
	var bar := PanelContainer.new()
	bar.theme_type_variation="Bar"
	root.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left=margin; bar.offset_right=-margin
	bar.offset_top=-(bar_height+margin-6); bar.offset_bottom=-(margin-6)
	bar.grow_vertical=Control.GROW_DIRECTION_BEGIN
	bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.mouse_filter=Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation",8)
	bar.add_child(col)
	var top := HBoxContainer.new()
	top.mouse_filter=Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation",12)
	col.add_child(top)
	prompt_row=HBoxContainer.new()
	prompt_row.mouse_filter=Control.MOUSE_FILTER_IGNORE
	prompt_row.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	prompt_row.add_theme_constant_override("separation",10)
	top.add_child(prompt_row)
	prompt=UI.label(prompt_row,"WASD / arrows to walk · Click a path to travel","",false)
	prompt.add_theme_color_override("font_color",UI.color("accent"))
	prompt.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	prompt.clip_text=true
	prompt.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	# Compact viewports give the key legend its own wrapping row; wider ones keep
	# it beside the prompt (a shrink-aligned flow container would get no width).
	var hints: Container
	if compact:
		hints=HFlowContainer.new()
		hints.alignment=FlowContainer.ALIGNMENT_END
		hints.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		hints.add_theme_constant_override("h_separation",14)
		hints.add_theme_constant_override("v_separation",4)
		col.add_child(hints)
	else:
		hints=HBoxContainer.new()
		hints.size_flags_horizontal=Control.SIZE_SHRINK_END
		hints.add_theme_constant_override("separation",14)
		top.add_child(hints)
	hints.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hints.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	for pair in [["E","Interact"],["Tab","Crew"],["B","Command"],["J","Journal"],["M","Map"],["H","Settings"]]:
		UI.hint(hints,pair[0],pair[1])
	UI.divider(col).color=Color("2f4d6380")
	roster=HFlowContainer.new()
	roster.mouse_filter=Control.MOUSE_FILTER_IGNORE
	roster.add_theme_constant_override("h_separation",8)
	roster.add_theme_constant_override("v_separation",6)
	col.add_child(roster)
	set_roster([["Crew activity","waiting for authoritative records","unknown"]])

func _build_dock() -> void:
	dock = PanelContainer.new()
	root.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	dock.offset_left = -((344 if compact else 392)+margin)
	dock.offset_right = -margin
	dock.offset_top = 100 if compact else 104
	dock.offset_bottom = -(bar_height+margin+10)
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dock.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation",10)
	scroll.add_child(col)
	var row := HBoxContainer.new()
	col.add_child(row)
	heading = UI.label(row,"MENDER / WORKSHOP","Title")
	heading.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	UI.icon_button(row,"×",close_panels,"Close  [Esc]")
	var identity_card := UI.card(col,"Card",4)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation",14)
	identity_card.add_child(identity)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(72,100)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.texture = CrewArt.pose("mender")
	identity.add_child(portrait)
	var identity_text := VBoxContainer.new()
	identity_text.add_theme_constant_override("separation",3)
	identity_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.add_child(identity_text)
	UI.eyebrow(identity_text,"Loadout")
	suit_label = UI.label(identity_text,"COPPER EXOSUIT","Section")
	UI.label(identity_text,"Appearance is cosmetic. Levels grant no permissions.","Muted")
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation",8)
	col.add_child(actions)
	UI.button(actions,"Command board",open_board,"","B").clip_text=true
	UI.button(actions,"Visit this room",func(): room_requested.emit(filter_kind),"").clip_text=true
	UI.section(col,"Observed work · retained records")
	list = OptionButton.new()
	list.fit_to_longest_item = false
	list.custom_minimum_size = Vector2(0,40)
	list.clip_text = true
	list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	list.item_selected.connect(func(index: int):
		selected_id = str(list.get_item_metadata(index))
		selection_changed.emit(selected_id))
	col.add_child(list)
	var state_card := UI.card(col,"Inset",6)
	status_badge=UI.badge(state_card,"unknown","Unknown","Section")
	status=status_badge.get_node("Text")
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	details = UI.label(state_card,"No evidence received.","Secondary")
	evidence_toggle=UI.button(state_card,"Show evidence",func(): evidence.visible = not evidence.visible,"GhostButton","Enter")
	evidence = RichTextLabel.new()
	evidence.fit_content=true
	evidence.custom_minimum_size = Vector2(0,0)
	evidence.scroll_active=false
	evidence.add_theme_stylebox_override("normal",UI.panel_style("strip",12))
	evidence.visible = false
	evidence.visibility_changed.connect(func(): evidence_toggle.text="Hide evidence" if evidence.visible else "Show evidence")
	state_card.add_child(evidence)
	UI.section(col,"Progression · cosmetic")
	progression_badge=UI.badge(col,"idle","Progression unknown","Secondary")
	progression=progression_badge.get_node("Text")
	progression.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	progression.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	repair_form = VBoxContainer.new()
	repair_form.add_theme_constant_override("separation",8)
	col.add_child(repair_form)
	UI.section(repair_form,"Practice · isolated repair")
	UI.label(repair_form,"Synthetic task in an isolated VM. Nothing here touches a real repository.","Muted")
	scenario = OptionButton.new()
	scenario.fit_to_longest_item = false
	scenario.clip_text = true
	scenario.add_item("Clamp bounds · synthetic task")
	scenario.add_item("Stable dedupe · synthetic task")
	repair_form.add_child(scenario)
	mode = OptionButton.new()
	mode.fit_to_longest_item = false
	mode.clip_text = true
	mode.add_item("Known-good control · no inference / XP")
	mode.add_item("AI proposal · one model call")
	repair_form.add_child(mode)
	submit = UI.button(repair_form,"Launch isolated practice",func():
		repair_requested.emit("clamp-v1" if scenario.selected == 0 else "dedupe-v1", "control-good" if mode.selected == 0 else "inference"),"PrimaryButton")
	stop = UI.button(col,"Request cancellation",func(): cancel_requested.emit(),"DangerButton")
	command_strip=PanelContainer.new()
	command_strip.theme_type_variation="Strip"
	command_strip.hide()
	col.add_child(command_strip)
	command_status = UI.label(command_strip,"","Secondary")
	command_status.add_theme_color_override("font_color",UI.color("accent"))
	UI.divider(col)
	UI.button(col,"Full journal & independent stop controls",func(): journal_requested.emit(),"GhostButton","J")
	UI.label(col,"Poses and scenery are decorative. Levels grant no operational permissions.","Muted")
	# The dock has a fixed width; long captions trim rather than widen it.
	for b in dock.find_children("*","Button",true,false): b.clip_text=true
	dock.hide()

func _build_directory() -> void:
	directory = PanelContainer.new()
	root.add_child(directory)
	directory.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	directory.offset_left=margin
	directory.offset_right=margin+(330 if compact else 380)
	directory.offset_top=100 if compact else 104
	directory.offset_bottom=-(bar_height+margin+10)
	var directory_scroll := ScrollContainer.new()
	directory_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	directory_scroll.follow_focus=true
	directory.add_child(directory_scroll)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation",8)
	menu.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	directory_scroll.add_child(menu)
	var head := HBoxContainer.new()
	menu.add_child(head)
	var title_col := VBoxContainer.new()
	title_col.add_theme_constant_override("separation",2)
	title_col.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	head.add_child(title_col)
	UI.label(title_col,"STATION DIRECTORY","Title")
	UI.label(title_col,"Inspect or act from anywhere. No travel required.","Muted")
	UI.icon_button(head,"×",close_panels,"Close  [Esc]")
	directory_first=UI.button(menu,"Command board",open_board,"PrimaryButton","B")
	UI.section(menu,"Crew")
	for kind in CREW:
		var info: Dictionary=CREW[kind]
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation",2)
		menu.add_child(entry)
		UI.button(entry,info.short,func(): open_place(kind),"",info.key)
		var activity := HBoxContainer.new()
		entry.add_child(activity)
		var spacer := Control.new(); spacer.custom_minimum_size.x=12; activity.add_child(spacer)
		crew_badges[kind]=UI.badge(activity,"unknown","Waiting for records","Muted")
	UI.section(menu,"Visit a place")
	building_search=LineEdit.new()
	building_search.placeholder_text="Find a building…"
	building_search.clear_button_enabled=true
	building_search.text_changed.connect(filter_buildings)
	menu.add_child(building_search)
	building_list=VBoxContainer.new()
	building_list.add_theme_constant_override("separation",6)
	menu.add_child(building_list)
	UI.divider(menu)
	UI.button(menu,"Journal & all controls",func(): journal_requested.emit(),"GhostButton","J")
	UI.button(menu,"Return to outpost",close_panels,"GhostButton","Esc")
	directory.hide()

func _build_help() -> void:
	help = PanelContainer.new()
	root.add_child(help)
	help.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	help.offset_left=margin
	help.offset_right=margin+(400 if compact else 460)
	help.offset_top=100 if compact else 104
	help.offset_bottom=-(bar_height+margin+10)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	help.add_child(scroll)
	var hc := VBoxContainer.new()
	hc.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	hc.add_theme_constant_override("separation",10)
	scroll.add_child(hc)
	var head := HBoxContainer.new()
	hc.add_child(head)
	UI.label(head,"FIELD GUIDE & COMFORT","Title")
	UI.icon_button(head,"×",close_panels,"Close  [Esc]")
	UI.section(hc,"Keys")
	var grid := GridContainer.new()
	grid.columns=2
	grid.add_theme_constant_override("h_separation",14)
	grid.add_theme_constant_override("v_separation",6)
	hc.add_child(grid)
	for pair in [["WASD","Walk · arrows also work"],["Click","Choose a path on clear ground"],["E","Inspect nearby crew or console"],["F","Enter a nearby room · leave an interior"],["1–5","Inspect a crew member from anywhere"],["Tab","Station directory"],["B","Command board"],["J","Browser journal · every control, no renderer needed"],["M","Colony map"],["C","Follow camera · room camera"],["Wheel","Zoom"],["Enter","Activate the focused control · toggle evidence"],["Esc","Close panels"]]:
		var keys := HBoxContainer.new()
		keys.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
		grid.add_child(keys)
		UI.kbd(keys,pair[0])
		UI.label(grid,pair[1],"Secondary")
	UI.section(hc,"Comfort")
	var rm := CheckButton.new()
	help_first=rm
	rm.text = "Reduced motion · room cuts, still crew"
	rm.toggled.connect(func(value: bool): reduced=value; settings_changed.emit())
	hc.add_child(rm)
	var lt := CheckButton.new()
	lt.text = "Larger interface text"
	lt.toggled.connect(func(value: bool): large_text=value; scale_text(); settings_changed.emit())
	hc.add_child(lt)
	var sound := CheckButton.new()
	sound.text="Quiet footsteps & airlock sounds"
	sound.toggled.connect(func(value: bool): sound_enabled=value; settings_changed.emit())
	hc.add_child(sound)
	UI.label(hc,"Ambient poses are decorative. Live work never waits for a character to arrive. Habitat, shuttle and reserved sites are scenery. The browser journal works independently of Godot.","Muted")
	UI.button(hc,"Back to the outpost",close_panels,"GhostButton","Esc")
	help.hide()

func _build_toast() -> void:
	toast=PanelContainer.new()
	toast.theme_type_variation="Toast"
	toast.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.add_child(toast)
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toast.grow_horizontal=Control.GROW_DIRECTION_BOTH
	toast.grow_vertical=Control.GROW_DIRECTION_BEGIN
	toast.offset_bottom=-(bar_height+margin+12)
	toast_badge=UI.badge(toast,"verified","")
	toast.hide()

## Transient notice. Authoritative text is also retained in the dock/journal.
func notify(message: String, tone: String = "verified", seconds: float = 6.0) -> void:
	UI.set_badge(toast_badge,tone,message)
	UI.reveal(toast,reduced,Vector2(0,10))
	toast_timer.start(seconds)

func set_connection(text_value: String, tone: String) -> void:
	UI.set_badge(connection_badge,tone,text_value)

func set_status(text_value: String, tone: String) -> void:
	UI.set_badge(status_badge,tone,text_value)

func set_progression(text_value: String, tone: String) -> void:
	UI.set_badge(progression_badge,tone,text_value)

func set_command_status(message: String, pending: bool) -> void:
	command_status.text=message
	command_pending=pending
	command_strip.visible=not message.is_empty()

## parts: a plain String, or an Array of [key, text] pairs and separator strings.
func set_prompt(parts) -> void:
	var signature := JSON.stringify(parts)
	if signature==_prompt_signature: return
	_prompt_signature=signature
	for child in prompt_row.get_children():
		if child!=prompt: prompt_row.remove_child(child); child.queue_free()
	if parts is String:
		prompt.text=parts; prompt.show(); return
	prompt.text=""; prompt.hide()
	for part in parts:
		if part is Array:
			var h := UI.hint(prompt_row,str(part[0]),str(part[1]))
			h.get_child(1).theme_type_variation=""
			h.get_child(1).add_theme_color_override("font_color",UI.color("accent"))
		else:
			var sep := UI.label(prompt_row,str(part),"Muted" if str(part)=="·" else "",false)
			if str(part)!="·": sep.add_theme_color_override("font_color",UI.color("accent"))
			sep.size_flags_vertical=Control.SIZE_SHRINK_CENTER

## entries: [[name, activity, tone], ...] from StateView; chips are rebuilt on change.
func set_roster(entries: Array) -> void:
	var signature := JSON.stringify(entries)
	if signature==_roster_signature: return
	_roster_signature=signature
	for child in roster.get_children(): roster.remove_child(child); child.queue_free()
	for entry in entries:
		UI.chip(roster,str(entry[2]),str(entry[0]),str(entry[1]))
	for kind in crew_badges:
		for entry in entries:
			if str(entry[0]).to_lower()==str(CREW[kind].short.split(" ·")[0]).to_lower():
				UI.set_badge(crew_badges[kind],str(entry[2]),str(entry[1]))

func open_board() -> void:
	close_panels()
	scrim.show()
	board.open()
	UI.reveal(board,reduced)

func toggle_help() -> void:
	var was: bool = help.visible
	close_panels()
	if not was:
		scrim.show()
		UI.reveal(help,reduced,Vector2(-8,0))
		help_first.grab_focus()

func set_buildings(buildings: Array) -> void:
	for child in building_list.get_children():
		building_list.remove_child(child)
		child.queue_free()
	for building in buildings:
		if building.definition.interior_scene.is_empty(): continue
		var key := str(building.name)
		var entry := UI.button(building_list,building.definition.title,func(): room_requested.emit(key),"GhostButton")
		entry.alignment=HORIZONTAL_ALIGNMENT_LEFT
		entry.set_meta("building_key",key)
	filter_buildings(building_search.text)

func filter_buildings(query: String) -> void:
	for entry in building_list.get_children():
		entry.visible=query.strip_edges().is_empty() or entry.text.to_lower().contains(query.strip_edges().to_lower())

func scale_text() -> void:
	root.theme = UI.build(large_text)
	if board!=null: board.set_large_text(large_text)

func close_panels() -> void:
	if board!=null: board.hide()
	dock.hide()
	directory.hide()
	help.hide()
	scrim.hide()
	root.get_viewport().gui_release_focus()

func toggle_directory() -> void:
	var was := directory.visible
	close_panels()
	if not was:
		scrim.show()
		UI.reveal(directory,reduced,Vector2(-8,0))
		directory_first.grab_focus()

func open_place(kind: String) -> void:
	close_panels()
	filter_kind = kind
	var info: Dictionary = CREW.get(kind,{"title":"CREW","appearance":"operator","suit":"EXPEDITION CAPTAIN","tint":Color.WHITE})
	heading.text = info.title
	portrait.texture = CrewArt.pose(info.appearance)
	suit_label.text = info.suit
	portrait.modulate = info.tint
	repair_form.visible = kind == "repair"
	UI.reveal(dock,reduced,Vector2(8,0))
	place_selected.emit(kind)
	list.grab_focus()

func is_open() -> bool:
	return dock.visible or directory.visible or help.visible or (board!=null and board.visible)

func update_list(missions: Array) -> void:
	var shown: Array = missions.filter(func(m): return m["input"].get("kind", "review") == filter_kind)
	var ids: Array = shown.map(func(m): return m["input"]["id"])
	var old_ids: Array = []
	for i in range(list.item_count):
		old_ids.append(list.get_item_metadata(i))
	if ids != old_ids:
		list.clear()
		for id in ids:
			list.add_item(id)
			list.set_item_metadata(list.item_count-1,id)
	if selected_id not in ids:
		selected_id = str(ids[0]) if not ids.is_empty() else ""
	if selected_id != "":
		list.select(ids.find(selected_id))
	list.tooltip_text = selected_id
	list.disabled = ids.is_empty()
	if ids.is_empty():
		list.clear()
		list.add_item("No retained records for this crew")
