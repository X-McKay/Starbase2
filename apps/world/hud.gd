extends CanvasLayer
## Contextual controls; all commands have a non-spatial keyboard path.
const CrewArt = preload("res://crew_art.gd")
var board: PanelContainer
var room_details: PanelContainer
var room_detail_title: Label
var room_detail_body: Label
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
signal zoom_requested(direction: int)
signal map_requested
signal room_requested(kind: String)
signal exit_requested
var room_exit: Button
var root := Control.new()
var dock: PanelContainer
var directory: PanelContainer
var building_list: VBoxContainer
var building_search: LineEdit
var help: PanelContainer
var connection: Label
var prompt: Label
var roster: Label
var heading: Label
var status: Label
var details: Label
var evidence: RichTextLabel
var list: OptionButton
var progression: Label
var command_status: Label
var repair_form: VBoxContainer
var scenario: OptionButton
var mode: OptionButton
var submit: Button
var stop: Button
var reduced := false
var follow := true
var large_text := false
var records: Array = []
var selected_id := ""
var filter_kind := "repair"
var compact := false
var command_pending := false
var location: Label
var mast: VBoxContainer
var navigation_bar: HBoxContainer
var prompt_panel: PanelContainer
var crew_summary := false
var summary_toggles: Array[CheckButton] = []

func style(bg: String = "152b3fee", border: String = "526a78", pad: int = 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(bg)
	s.border_color = Color(border)
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s

func text(parent: Node, value: String, size: int = 16, color: String = "e3e7dc") -> Label:
	var l := Label.new()
	l.text = value
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(color))
	l.add_theme_color_override("font_shadow_color",Color("151c29dd"))
	l.add_theme_constant_override("shadow_offset_x",1)
	l.add_theme_constant_override("shadow_offset_y",2)
	parent.add_child(l)
	return l

func button(parent: Node, value: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = value
	b.custom_minimum_size = Vector2(100,38)
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.tooltip_text = value
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func panel_at(parent: Node, minimum: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = minimum
	p.add_theme_stylebox_override("panel", style())
	parent.add_child(p)
	return p

func _ready() -> void:
	layer = 2
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font_size = 16
	theme.set_stylebox("normal", "Button", style("294356", "557281", 9))
	theme.set_stylebox("hover", "Button", style("3a5a69", "a7c8bc", 9))
	theme.set_stylebox("pressed", "Button", style("456570", "e4c58f", 9))
	theme.set_stylebox("focus", "Button", style("00000000", "ffe0a0", 3))
	root.theme = theme
	mast = VBoxContainer.new()
	mast.name="ContextHeader"
	mast.position = Vector2(22,18)
	mast.add_theme_constant_override("separation",4)
	mast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mast)
	var brand := HBoxContainer.new()
	brand.mouse_filter=Control.MOUSE_FILTER_IGNORE
	brand.add_theme_constant_override("separation",12)
	mast.add_child(brand)
	text(brand,"STARBASE 02",13,"d9e6e2")
	location=text(brand,"ASTER OUTPOST",12,"aac1bd")
	location.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	location.clip_text=true
	location.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	connection = text(mast,"Connecting to local core…",12,"c0cdd0")
	connection.clip_text=true
	connection.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	connection.mouse_filter=Control.MOUSE_FILTER_PASS
	connection.mouse_entered.connect(func(): connection.tooltip_text=connection.text)
	var top := HBoxContainer.new()
	navigation_bar=top
	top.name="NavigationBar"
	top.add_theme_constant_override("separation",4)
	root.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top.offset_left = -418
	top.offset_right = -22
	top.offset_top = 16
	button(top,"Map [M]",func(): map_requested.emit())
	button(top,"Crew [Tab]",toggle_directory)
	button(top,"Journal [J]",func(): journal_requested.emit())
	var zoom_in := button(top,"+",func(): zoom_requested.emit(-1))
	zoom_in.name="ZoomIn"
	zoom_in.tooltip_text="Zoom in · + or mouse wheel up"
	var zoom_out := button(top,"−",func(): zoom_requested.emit(1))
	zoom_out.name="ZoomOut"
	zoom_out.tooltip_text="Zoom out · - or mouse wheel down"
	var guide := button(top,"H",func():
		var was:=help.visible
		close_panels()
		help.visible=not was)
	guide.tooltip_text="Field guide & comfort · H"
	for item in top.get_children():
		item.custom_minimum_size=Vector2(82 if item.get_index()<3 else 36,36)
		item.add_theme_font_size_override("font_size",13)
		item.add_theme_stylebox_override("normal",style("10232cdd","38505b88",6))
	room_exit=button(root,"Exit room [F]",func(): exit_requested.emit())
	room_exit.custom_minimum_size=Vector2(146,34)
	room_exit.add_theme_font_size_override("font_size",13)
	room_exit.position=Vector2(22,74)
	room_exit.hide()
	var bottom_panel := PanelContainer.new()
	prompt_panel=bottom_panel
	bottom_panel.name="ContextPrompt"
	bottom_panel.add_theme_stylebox_override("panel",style("0d202bdc","4b626b77",10))
	root.add_child(bottom_panel)
	bottom_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.offset_left=26; bottom_panel.offset_right=-26
	bottom_panel.offset_top=-62; bottom_panel.offset_bottom=-18
	bottom_panel.grow_vertical=Control.GROW_DIRECTION_BEGIN
	bottom_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var bottom := VBoxContainer.new()
	bottom.mouse_filter=Control.MOUSE_FILTER_IGNORE
	bottom_panel.add_child(bottom)
	prompt = text(bottom,"WASD / arrows to walk · Click a path to travel",14,"eadbc1")
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	dock = panel_at(root, Vector2(388,0))
	dock.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	dock.offset_left = -414
	dock.offset_right = -24
	dock.offset_top = 115
	dock.offset_bottom = -140
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
	heading = text(row,"MENDER / WORKSHOP",18,"efd29d")
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var close := button(row,"×",close_panels)
	close.custom_minimum_size.x = 32
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation",16)
	col.add_child(identity)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(80,110)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = CrewArt.pose("mender")
	identity.add_child(portrait)
	var identity_text := VBoxContainer.new()
	identity_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(identity_text)
	suit_label = text(identity_text,"COPPER EXOSUIT",14,"efd29d")
	suit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cosmetic := text(identity_text,"Crew appearance\nEquipment is cosmetic.",12,"a6c9be")
	cosmetic.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button(col,"Command board [B]",open_board)
	button(col,"Visit this room",func(): room_requested.emit(filter_kind))
	text(col,"OBSERVED WORK · retained records",12,"a6c9be")
	list = OptionButton.new()
	list.fit_to_longest_item = false
	list.custom_minimum_size = Vector2(0,36)
	list.clip_text = true
	list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	list.item_selected.connect(func(index: int):
		selected_id = str(list.get_item_metadata(index))
		selection_changed.emit(selected_id))
	col.add_child(list)
	status = text(col,"Unknown",20,"efd29d")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details = text(col,"No evidence received.",15)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button(col,"Inspect evidence",func(): evidence.visible = not evidence.visible)
	evidence = RichTextLabel.new()
	evidence.custom_minimum_size = Vector2(0,160)
	evidence.add_theme_font_size_override("normal_font_size",14)
	evidence.visible = false
	col.add_child(evidence)
	progression = text(col,"Progression unknown",14,"bcd8c4")
	progression.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	repair_form = VBoxContainer.new()
	repair_form.add_theme_constant_override("separation",8)
	col.add_child(repair_form)
	text(repair_form,"PRACTICE / ISOLATED REPAIR",12,"a6c9be")
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
	submit = button(repair_form,"Launch isolated practice",func():
		repair_requested.emit("clamp-v1" if scenario.selected == 0 else "dedupe-v1", "control-good" if mode.selected == 0 else "inference"))
	stop = button(col,"Request cancellation",func(): cancel_requested.emit())
	command_status = text(col,"",13,"f0cea0")
	command_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button(col,"Full journal & independent stop controls ↗",func(): journal_requested.emit())
	var truth := text(col,"Poses and scenery are decorative.\nLevels grant no operational permissions.",12,"a8babf")
	truth.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.hide()
	directory = panel_at(root,Vector2(330,0))
	directory.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	directory.offset_left=28
	directory.offset_right=414
	directory.offset_top=120
	directory.offset_bottom=-140
	var directory_scroll := ScrollContainer.new()
	directory_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	directory_scroll.follow_focus=true
	directory.add_child(directory_scroll)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation",10)
	menu.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	directory_scroll.add_child(menu)
	text(menu,"STATION DIRECTORY",18,"efd29d")
	text(menu,"Inspect or act from anywhere.",14)
	button(menu,"Command board [B]",open_board)
	button(menu,"1   Mender / workshop",func(): open_place("repair"))
	button(menu,"2   Surveyor / command",func(): open_place("review"))
	button(menu,"3   Trainer / trial hall",func(): open_place("gym"))
	button(menu,"4   Watchkeeper / cluster watch",func(): open_place("watchkeeper"))
	button(menu,"5   PR Reviewer / command",func(): open_place("reviewer"))
	add_summary_toggle(menu)
	roster=text(menu,"Crew activity unknown · waiting for authoritative records",14,"c5d4cc")
	roster.name="CrewSummary"
	roster.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	roster.hide()
	text(menu,"VISIT A PLACE",16,"efd29d")
	building_search=LineEdit.new()
	building_search.placeholder_text="Find a building…"
	building_search.text_changed.connect(filter_buildings)
	menu.add_child(building_search)
	building_list=VBoxContainer.new()
	menu.add_child(building_list)
	button(menu,"Journal & all controls ↗",func(): journal_requested.emit())
	button(menu,"Return to outpost [Esc]",close_panels)
	directory.hide()
	help = panel_at(root,Vector2(410,0))
	help.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	var help_scroll := ScrollContainer.new()
	help_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	help_scroll.follow_focus=true
	help.add_child(help_scroll)
	var hc := VBoxContainer.new()
	hc.add_theme_constant_override("separation",12)
	hc.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	help_scroll.add_child(hc)
	text(hc,"FIELD GUIDE & COMFORT",18,"efd29d")
	text(hc,"WASD / arrows: move · Click: choose path\nE: inspect crew or console · F: enter or exit\n1–5: inspect crew · Tab: station directory\nEnter: focused control · Esc: close\nC: follow / room camera · M: colony map\n+ / − or wheel: zoom · B: command board\nJ: independent journal · H: this guide\nHabitat, Botanical and reserved sites are scenery.",15).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	add_summary_toggle(hc)
	var rm := CheckButton.new()
	rm.text = "Reduced motion (room cuts, still crew)"
	rm.clip_text=true
	rm.tooltip_text=rm.text
	rm.toggled.connect(func(value: bool): reduced=value; settings_changed.emit())
	hc.add_child(rm)
	var lt := CheckButton.new()
	lt.text = "Larger interface text"
	lt.toggled.connect(func(value: bool): large_text=value; scale_text(); settings_changed.emit())
	hc.add_child(lt)
	text(hc,"Ambient poses are decorative. Sound is optional.\nLive work never waits for a character to arrive.\nThe browser journal works independently of Godot.",14,"b3c6c5").autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var sound := CheckButton.new()
	sound.text="Enable quiet footsteps & airlock sounds"
	sound.clip_text=true
	sound.tooltip_text=sound.text
	sound.toggled.connect(func(value: bool): sound_enabled=value; settings_changed.emit())
	hc.add_child(sound)
	button(hc,"Back to the outpost",close_panels)
	help.hide()
	board=preload("res://command_board.gd").new()
	board.api=api; board.fixture=board_fixture
	board.add_theme_stylebox_override("panel",style("102535fa","759496",18))
	root.add_child(board)
	room_details=panel_at(root,Vector2(386,0))
	room_details.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	var room_scroll:=ScrollContainer.new()
	room_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	room_scroll.follow_focus=true
	room_details.add_child(room_scroll)
	var room_column:=VBoxContainer.new()
	room_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	room_column.add_theme_constant_override("separation",16)
	room_scroll.add_child(room_column)
	room_detail_title=text(room_column,"ROOM GUIDE",19,"efd29d")
	room_detail_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	room_detail_body=text(room_column,"",16)
	room_detail_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	button(room_column,"Back to exploring [Esc]",close_panels)
	room_details.hide()
	root.resized.connect(layout_hud)
	layout_hud.call_deferred()

func set_location(value:String) -> void:
	location.text=value
	location.tooltip_text=value

func add_summary_toggle(parent:Node) -> void:
	var toggle:=CheckButton.new()
	toggle.text="Crew summary"
	toggle.tooltip_text="Show authoritative crew activity in the station directory"
	toggle.toggled.connect(set_crew_summary)
	parent.add_child(toggle)
	summary_toggles.append(toggle)

func set_crew_summary(value:bool) -> void:
	crew_summary=value
	if roster!=null: roster.visible=value
	for toggle in summary_toggles: toggle.set_pressed_no_signal(value)

func layout_hud() -> void:
	if dock==null or help==null or navigation_bar==null: return
	var viewport_size:Vector2=root.size
	var narrow:=viewport_size.x<900
	navigation_bar.get_child(1).text="Crew" if large_text else "Crew [Tab]"
	navigation_bar.get_child(2).text="Journal" if large_text else "Journal [J]"
	navigation_bar.offset_top=70 if narrow else 16
	navigation_bar.offset_left=-minf(530 if large_text else 440,viewport_size.x-44)-22
	mast.size.x=maxf(180,viewport_size.x-44 if narrow else viewport_size.x-460)
	room_exit.position=Vector2(22,112 if narrow else 70)
	var top_edge:=154.0 if narrow else 112.0
	var panel_width:=minf(410 if large_text else 386,viewport_size.x-44)
	for panel in [dock,directory,help,room_details]:
		panel.custom_minimum_size.x=panel_width
		panel.offset_top=top_edge
		panel.offset_bottom=-80
	dock.offset_left=-panel_width-22
	dock.offset_right=-22
	room_details.offset_left=-panel_width-22
	room_details.offset_right=-22
	for panel in [directory,help]:
		panel.offset_left=22
		panel.offset_right=22+panel_width
	var prompt_width:=minf(820,viewport_size.x-44)
	prompt_panel.offset_left=(viewport_size.x-prompt_width)*0.5
	prompt_panel.offset_right=-(viewport_size.x-prompt_width)*0.5
	prompt_panel.offset_top=-68 if large_text else -62

func open_board() -> void:
	close_panels()
	board.open()

func open_room_details(title:String,description:String) -> void:
	close_panels()
	room_detail_title.text=title
	room_detail_body.text=description
	room_details.show()
	room_details.find_children("*","Button",true,false)[0].grab_focus()

func set_structures(buildings: Array) -> void:
	for child in building_list.get_children():
		building_list.remove_child(child)
		child.queue_free()
	for building in buildings:
		if building.definition.interior_scene.is_empty(): continue
		var key := str(building.name)
		var entry := button(building_list,building.definition.title,func(): room_requested.emit(key))
		entry.set_meta("building_key",key)
	filter_buildings(building_search.text)

func filter_buildings(query: String) -> void:
	for entry in building_list.get_children():
		entry.visible=query.strip_edges().is_empty() or entry.text.to_lower().contains(query.strip_edges().to_lower())

func scale_text() -> void:
	if board!=null: board.large_text=large_text
	for node in root.find_children("*", "Label", true, false):
		if not node.has_meta("base_font"):
			node.set_meta("base_font", node.get_theme_font_size("font_size"))
		node.add_theme_font_size_override("font_size", int(node.get_meta("base_font")) + (3 if large_text else 0))
	root.theme.default_font_size = 19 if large_text else 16
	for item in navigation_bar.get_children(): item.add_theme_font_size_override("font_size",16 if large_text else 13)
	room_exit.add_theme_font_size_override("font_size",16 if large_text else 13)
	layout_hud()

func close_panels() -> void:
	if board!=null: board.hide()
	dock.hide()
	directory.hide()
	help.hide()
	if room_details!=null: room_details.hide()
	root.get_viewport().gui_release_focus()

func toggle_directory() -> void:
	var was := directory.visible
	close_panels()
	directory.visible = not was
	if directory.visible:
		directory.find_children("*","Button",true,false)[0].grab_focus()

func open_place(kind: String) -> void:
	close_panels()
	filter_kind = kind
	dock.show()
	heading.text = {"repair":"MENDER / WORKSHOP","review":"SURVEYOR / COMMAND","gym":"TRAINER / TRIAL HALL","watchkeeper":"WATCHKEEPER / CLUSTER WATCH","reviewer":"PR REVIEWER / COMMAND"}.get(kind,"CREW")
	portrait.texture = CrewArt.pose({"repair":"mender","review":"surveyor","gym":"trainer","watchkeeper":"trainer","reviewer":"operator"}.get(kind,"operator"))
	suit_label.text = {"repair":"COPPER EXOSUIT","review":"EVA EXPLORER","gym":"IVORY SENTINEL","watchkeeper":"AZURE SENTINEL","reviewer":"VIOLET FIELD ANALYST"}.get(kind,"EXPEDITION CAPTAIN")
	portrait.modulate={"watchkeeper":Color(0.5,0.82,1),"reviewer":Color(0.85,0.65,1)}.get(kind,Color.WHITE)
	repair_form.visible = kind == "repair"
	place_selected.emit(kind)
	list.grab_focus()

func is_open() -> bool:
	return dock.visible or directory.visible or help.visible or (board!=null and board.visible) or (room_details!=null and room_details.visible)

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
