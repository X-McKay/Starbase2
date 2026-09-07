extends CanvasLayer
## Contextual controls; all commands have a non-spatial keyboard path.
const CrewArt = preload("res://crew_art.gd")
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

func style(bg: String = "152b3fee", border: String = "526a78", pad: int = 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(bg)
	s.border_color = Color(border)
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
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
	var mast := VBoxContainer.new()
	mast.position = Vector2(28,22)
	mast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mast)
	text(mast,"STARBASE 02     /     ASTER COLONY",14,"b6d7cd")
	text(mast,"A new world. A first foothold.",26,"f1e5cc")
	connection = text(mast,"Connecting to local core…",13,"c0cdd0")
	var top := HBoxContainer.new()
	root.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top.offset_left = -408
	top.offset_right = -26
	top.offset_top = 24
	button(top,"Map  [M]",func(): map_requested.emit())
	button(top,"Crew  [Tab]",toggle_directory)
	button(top,"Journal  [J]",func(): journal_requested.emit())
	var zoom_controls := HBoxContainer.new()
	root.add_child(zoom_controls)
	zoom_controls.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	zoom_controls.grow_horizontal=Control.GROW_DIRECTION_BEGIN
	zoom_controls.offset_left=-310
	zoom_controls.offset_right=-26
	zoom_controls.offset_top=76
	var zoom_in := button(zoom_controls,"Zoom in  [+]",func(): zoom_requested.emit(-1))
	zoom_in.name="ZoomIn"
	zoom_in.tooltip_text="Zoom in · + or mouse wheel up"
	var zoom_out := button(zoom_controls,"Zoom out  [−]",func(): zoom_requested.emit(1))
	zoom_out.name="ZoomOut"
	zoom_out.tooltip_text="Zoom out · - or mouse wheel down"
	room_exit=button(root,"Return to colony  [F]",func(): exit_requested.emit())
	room_exit.custom_minimum_size=Vector2(240,40)
	room_exit.position=Vector2(28,112)
	room_exit.hide()
	var bottom_panel := PanelContainer.new()
	bottom_panel.add_theme_stylebox_override("panel",style("102535e8","294653",10))
	root.add_child(bottom_panel)
	bottom_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.offset_left=26; bottom_panel.offset_right=-26
	bottom_panel.offset_top=-126; bottom_panel.offset_bottom=-18
	bottom_panel.grow_vertical=Control.GROW_DIRECTION_BEGIN
	bottom_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var bottom := VBoxContainer.new()
	bottom.mouse_filter=Control.MOUSE_FILTER_IGNORE
	bottom_panel.add_child(bottom)
	prompt = text(bottom,"WASD / arrows to walk · Click a path to travel",16,"f5dfb4")
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roster = text(bottom,"Crew activity unknown · waiting for authoritative records",13,"c5d4cc")
	roster.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var controls := text(bottom,"E  INTERACT     ·     TAB  CREW     ·     B  COMMAND     ·     J  JOURNAL     ·     M  MAP     ·     H  SETTINGS",12,"a6bbbf")
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	list.custom_minimum_size = Vector2(325,36)
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
	evidence.custom_minimum_size = Vector2(320,160)
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
	help.position = Vector2(28,120)
	var hc := VBoxContainer.new()
	hc.add_theme_constant_override("separation",12)
	help.add_child(hc)
	text(hc,"FIELD GUIDE & COMFORT",18,"efd29d")
	text(hc,"WASD / arrows: move    Mouse: choose path\nE: crew / console    F: enter nearby room / leave interior\n1–5: inspect crew    Visit this room: travel directly\nTab: directory    Enter: focused control    Esc: close\nC: follow / room camera    M: colony map\n+ / - or wheel: zoom    B: command board    J: journal\nHabitat, shuttle and reserved sites are decorative.",15)
	var rm := CheckButton.new()
	rm.text = "Reduced motion (room cuts, still crew)"
	rm.toggled.connect(func(value: bool): reduced=value; settings_changed.emit())
	hc.add_child(rm)
	var lt := CheckButton.new()
	lt.text = "Larger interface text"
	lt.toggled.connect(func(value: bool): large_text=value; scale_text(); settings_changed.emit())
	hc.add_child(lt)
	text(hc,"Ambient poses are decorative. Sound is optional.\nLive work never waits for a character to arrive.\nThe browser journal works independently of Godot.",14,"b3c6c5")
	var sound := CheckButton.new()
	sound.text="Enable quiet footsteps & airlock sounds"
	sound.toggled.connect(func(value: bool): sound_enabled=value; settings_changed.emit())
	hc.add_child(sound)
	button(hc,"Back to the outpost",close_panels)
	help.hide()
	board=preload("res://command_board.gd").new()
	board.api=api; board.fixture=board_fixture
	board.add_theme_stylebox_override("panel",style("102535fa","759496",18))
	root.add_child(board)

func open_board() -> void:
	close_panels()
	board.open()

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

func close_panels() -> void:
	if board!=null: board.hide()
	dock.hide()
	directory.hide()
	help.hide()
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
