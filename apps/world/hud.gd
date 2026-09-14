extends CanvasLayer
## Contextual controls; all commands have a non-spatial keyboard path.
const StateView = preload("res://state.gd")
const ConsoleTheme = preload("res://console_theme.gd")
var connection_panel: PanelContainer
signal connect_requested(endpoint:String)
var operations: PanelContainer
var board: PanelContainer
var room_details: PanelContainer
var room_detail_title: Label
var room_detail_body: Label
var api := preload("res://transport.gd").default_origin()
var board_fixture := ""
var sound_enabled := false
var portrait: Control
var suit_label: Label
signal place_selected(kind: String)
signal repair_requested(scenario: String, mode: String)
signal cancel_requested
signal selection_changed(id: String)
signal player_character_selected(character_id:String)
signal settings_changed
signal zoom_requested(direction: int)
signal map_requested
signal room_requested(kind: String)
signal exit_requested
signal watch_requested(kind:String)
var crew_strip:PanelContainer
var briefing:PanelContainer
var station_records:PanelContainer
signal stations_requested
var observing := false
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
var header_panel: PanelContainer
var navigation_bar: BoxContainer
var prompt_panel: PanelContainer
var crew_summary := false
var summary_toggles: Array[CheckButton] = []
var dossier_scroll: ScrollContainer
var record_metadata: Label
var player_character_buttons:Dictionary={}
var player_character_status:Label
var selected_player_character:="operator"
var settings_tabs: TabContainer
var settings_nav: VBoxContainer
var settings_buttons: Array[Button]=[]
var large_toggle: CheckButton
var room_available := false
var workspace_label: Label
var nav_buttons: Dictionary = {}
var dossier_tabs: TabContainer
var identity_column: VBoxContainer
var dossier_body: HBoxContainer
var practice_page: ScrollContainer
var progression_heading: Label
var compact_watch: Button
var navigation_background: PanelContainer
var navigation_icons: Dictionary={}
var active_navigation:=""
var directory_tabs:TabContainer
var crew_record_labels:Dictionary={}
var directory_records:Array=[]
var exploration_hud_collapsed := false
var chrome_toggle: Button
var crew_purpose: Label
var crew_workflows: Label
var crew_limits: Label
var crew_availability: Label
var crew_action: Button
var crew_route := ""

func style(bg: String = "0a0a0ad6", border: String = "77777766", pad: int = 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(bg)
	s.border_color = Color(border)
	s.set_border_width_all(1)
	s.set_corner_radius_all(1)
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
	l.add_theme_color_override("font_shadow_color",Color("000000dd"))
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
	ConsoleTheme.smoke(p)
	parent.add_child(p)
	return p

func _ready() -> void:
	layer = 2
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ConsoleTheme.apply(root)
	mast = VBoxContainer.new()
	mast.name="ContextHeader"
	mast.position = Vector2.ZERO
	mast.add_theme_constant_override("separation",2)
	mast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_panel=panel_at(root,Vector2.ZERO)
	header_panel.position=Vector2(18,14)
	header_panel.add_theme_stylebox_override("panel",style("0a0a0acc","77777755",8))
	header_panel.add_child(mast)
	var brand := HBoxContainer.new()
	brand.mouse_filter=Control.MOUSE_FILTER_IGNORE
	brand.add_theme_constant_override("separation",12)
	mast.add_child(brand)
	text(brand,"STARBASE2",16,"e9e5df")
	location=text(brand,"ASTER OUTPOST",12,"b5b6b5")
	location.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	location.clip_text=true
	location.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	workspace_label=text(brand,"WORLD",12,"c9c5c1")
	chrome_toggle=button(brand,"HUD [F1]",toggle_exploration_hud)
	chrome_toggle.custom_minimum_size=Vector2(132,30)
	chrome_toggle.size_flags_horizontal=Control.SIZE_SHRINK_END
	chrome_toggle.add_theme_font_size_override("font_size",11)
	connection = text(mast,"Connecting to local core…",12,"bcb9b6")
	connection.clip_text=true
	connection.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	connection.mouse_filter=Control.MOUSE_FILTER_PASS
	connection.mouse_entered.connect(func(): connection.tooltip_text=connection.text+" · Connection [O]")
	connection.gui_input.connect(func(event:InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			open_connection()
			root.get_viewport().set_input_as_handled())
	navigation_background=PanelContainer.new()
	navigation_background.name="NavigationRail"
	navigation_background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var rail_style:=style("0c0c0cc9","77777744",0)
	rail_style.set_border_width_all(0)
	rail_style.border_width_right=1
	navigation_background.add_theme_stylebox_override("panel",rail_style)
	ConsoleTheme.smoke(navigation_background)
	root.add_child(navigation_background)
	for key in ["map","crew","work","stations","field","settings","connection"]:
		navigation_icons[key]=load("res://assets/ui/ember-icons/"+key+".svg")
	var top := BoxContainer.new()
	navigation_bar=top
	top.name="NavigationBar"
	top.add_theme_constant_override("separation",4)
	root.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top.offset_left = -418
	top.offset_right = -22
	top.offset_top = 16
	nav_buttons.map=button(top,"Map [M]",func(): map_requested.emit())
	nav_buttons.crew=button(top,"Crew [Tab]",toggle_directory)
	nav_buttons.work=button(top,"Work [J]",open_operations)
	nav_buttons.stations=button(top,"Stations [I]",func(): stations_requested.emit())
	nav_buttons.field=button(top,"Field ops [B]",open_board)
	nav_buttons.settings=button(top,"Settings [H]",toggle_settings)
	nav_buttons.connection=button(top,"Connection [O]",open_connection)
	var zoom_in := button(top,"+",func(): zoom_requested.emit(-1))
	zoom_in.name="ZoomIn"
	zoom_in.tooltip_text="Zoom in · + or mouse wheel up"
	var zoom_out := button(top,"−",func(): zoom_requested.emit(1))
	zoom_out.name="ZoomOut"
	zoom_out.tooltip_text="Zoom out · - or mouse wheel down"
	for item in top.get_children():
		item.custom_minimum_size=Vector2(0,38)
		item.add_theme_font_size_override("font_size",14)
		item.add_theme_stylebox_override("normal",style("111111c9","77777766",7))
	room_exit=button(root,"Exit room [F]",func(): exit_requested.emit())
	room_exit.custom_minimum_size=Vector2(146,34)
	room_exit.add_theme_font_size_override("font_size",13)
	room_exit.position=Vector2(22,74)
	room_exit.hide()
	var bottom_panel := PanelContainer.new()
	prompt_panel=bottom_panel
	bottom_panel.name="ContextPrompt"
	bottom_panel.add_theme_stylebox_override("panel",style("0a0a0ace","77777766",10))
	root.add_child(bottom_panel)
	bottom_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.offset_left=26; bottom_panel.offset_right=-26
	bottom_panel.offset_top=-62; bottom_panel.offset_bottom=-18
	bottom_panel.grow_vertical=Control.GROW_DIRECTION_BEGIN
	bottom_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var bottom := VBoxContainer.new()
	bottom.mouse_filter=Control.MOUSE_FILTER_IGNORE
	bottom_panel.add_child(bottom)
	prompt = text(bottom,"WASD / arrows to walk · Click a path to travel",14,"e9e5df")
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	dock = panel_at(root, Vector2(388,0))
	dock.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	dock.offset_left = -414
	dock.offset_right = -24
	dock.offset_top = 115
	dock.offset_bottom = -140
	var dossier_column:=VBoxContainer.new()
	dock.add_child(dossier_column)
	var row := HBoxContainer.new()
	dossier_column.add_child(row)
	heading = text(row,"RIVET / WORKSHOP",22,"e9e5df")
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var close := button(row,"Close",close_panels)
	close.tooltip_text="Close workspace · Esc"
	close.custom_minimum_size.x = 110
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	dossier_body=HBoxContainer.new()
	dossier_body.add_theme_constant_override("separation",24)
	dossier_body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	dossier_column.add_child(dossier_body)
	identity_column=VBoxContainer.new()
	identity_column.add_theme_constant_override("separation",12)
	dossier_body.add_child(identity_column)
	portrait=preload("res://crew_portrait.gd").new()
	portrait.custom_minimum_size=Vector2(230,220)
	portrait.size_flags_vertical=Control.SIZE_EXPAND_FILL
	identity_column.add_child(portrait)
	suit_label=text(identity_column,"COPPER EXOSUIT",17,"e9e5df")
	suit_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	text(identity_column,"ASTER FIELD CREW",13,"b5b6b5")
	button(identity_column,"Watch this crew member",func(): watch_requested.emit(filter_kind))
	button(identity_column,"Field operations [B]",open_board)
	button(identity_column,"Work & history [J]",open_operations)
	dossier_tabs=TabContainer.new()
	dossier_tabs.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	dossier_tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	dossier_body.add_child(dossier_tabs)
	var col:=dossier_page("Overview")
	dossier_scroll=col.get_parent()
	compact_watch=button(col,"Watch this crew member",func(): watch_requested.emit(filter_kind))
	crew_purpose=text(col,"",22,"e9e5df")
	crew_purpose.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	crew_action=button(col,"Open workspace",open_crew_workflow)
	ConsoleTheme.primary(crew_action)
	crew_action.tooltip_text="Open the setup form. Work starts only when you explicitly submit it."
	crew_availability=text(col,"",15,"bcb9b6")
	crew_availability.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	text(col,"SKILLS & WORKFLOWS",13,"bcb9b6")
	crew_workflows=text(col,"",17)
	crew_workflows.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	text(col,"SCOPE",13,"bcb9b6")
	crew_limits=text(col,"",15,"bcb9b6")
	crew_limits.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	button(col,"View assignments & results",func(): dossier_tabs.current_tab=1)
	var evidence_column:=dossier_page("Evidence")
	col=evidence_column
	text(col,"ASSIGNMENT / RETAINED RECORDS",13,"bcb9b6")
	list=OptionButton.new()
	list.fit_to_longest_item=false
	list.custom_minimum_size=Vector2(0,40)
	list.clip_text=true
	list.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	list.item_selected.connect(func(index:int):
		selected_id=str(list.get_item_metadata(index))
		selection_changed.emit(selected_id))
	col.add_child(list)
	status=text(col,"Unknown",24,"ff7755")
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	details=text(col,"No evidence received.",17)
	details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	record_metadata=text(col,"No retained assignment selected.",15,"bcb9b6")
	record_metadata.autowrap_mode=TextServer.AUTOWRAP_ARBITRARY
	stop=button(col,"Request cancellation",func():cancel_requested.emit())
	stop.tooltip_text="Cancellation is available only for active retained work."
	command_status=text(dossier_column,"",15,"ff997f")
	command_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	text(col,"Latest known state comes from Core records. Crew location does not change work authority.",14,"bcb9b6").autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	text(evidence_column,"SELECTED RECORD / EVIDENCE",13,"bcb9b6")
	evidence=RichTextLabel.new()
	evidence.custom_minimum_size=Vector2(0,220)
	evidence.fit_content=true
	evidence.add_theme_font_size_override("normal_font_size",16)
	evidence_column.add_child(evidence)
	progression_heading=text(evidence_column,"VERIFIED PROGRESSION / RIVET",13,"bcb9b6")
	progression=text(evidence_column,"Progression unknown",16,"c9c5c1")
	progression.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	repair_form=dossier_page("Practice")
	practice_page=repair_form.get_parent()
	text(repair_form,"ISOLATED REPAIR PRACTICE",18,"e9e5df")
	text(repair_form,"Synthetic tasks in an isolated environment. Operational permissions never depend on practice or XP.",16,"bcb9b6").autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	text(repair_form,"Task",15)
	scenario=OptionButton.new()
	scenario.fit_to_longest_item=false
	scenario.clip_text=true
	scenario.add_item("Clamp bounds · synthetic task")
	scenario.add_item("Stable dedupe · synthetic task")
	repair_form.add_child(scenario)
	text(repair_form,"Practice mode",15)
	mode=OptionButton.new()
	mode.fit_to_longest_item=false
	mode.clip_text=true
	mode.add_item("Known-good control · no inference / XP")
	mode.add_item("AI proposal · one model call")
	repair_form.add_child(mode)
	submit=button(repair_form,"Launch isolated practice",func():
		repair_requested.emit("clamp-v1" if scenario.selected==0 else "dedupe-v1","control-good" if mode.selected==0 else "inference"))
	ConsoleTheme.primary(submit)
	text(repair_form,"Submission feedback remains visible below. Request cancellation is available in Evidence.",15,"bcb9b6").autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	dock.hide()
	directory = panel_at(root,Vector2(330,0))
	directory.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	directory.offset_left=28
	directory.offset_right=414
	directory.offset_top=120
	directory.offset_bottom=-140
	var directory_column:=VBoxContainer.new()
	directory_column.add_theme_constant_override("separation",12)
	directory.add_child(directory_column)
	var directory_head:=HBoxContainer.new()
	directory_column.add_child(directory_head)
	var directory_title:=text(directory_head,"CREW & PLACES",22,"e9e5df")
	directory_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var directory_close:=button(directory_head,"Close [Esc]",close_panels)
	directory_close.custom_minimum_size.x=112
	directory_close.size_flags_horizontal=Control.SIZE_SHRINK_END
	building_search=LineEdit.new()
	building_search.placeholder_text="Find a building… · search opens Places"
	building_search.text_changed.connect(filter_buildings)
	directory_column.add_child(building_search)
	directory_tabs=TabContainer.new()
	directory_tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	directory_column.add_child(directory_tabs)
	var crew_scroll:=ScrollContainer.new()
	crew_scroll.name="Crew"
	crew_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	crew_scroll.follow_focus=true
	directory_tabs.add_child(crew_scroll)
	var menu:=VBoxContainer.new()
	menu.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	menu.add_theme_constant_override("separation",4)
	crew_scroll.add_child(menu)
	var crew_columns:=HBoxContainer.new()
	crew_columns.add_theme_constant_override("separation",18)
	menu.add_child(crew_columns)
	text(crew_columns,"Crew & home station",14,"bcb9b6").custom_minimum_size.x=180
	var assignment_heading:=text(crew_columns,"Latest retained assignment",14,"bcb9b6")
	assignment_heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	assignment_heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for entry in [["repair","1  Rivet","Workshop"],["review","2  Moss Bombadil","Command"],["gym","3  Mae Jin","Trial Hall"],["watchkeeper","4  Wes Walker","Cluster watch"],["reviewer","5  Prism","Command"]]:
		var crew_row:=HBoxContainer.new()
		crew_row.add_theme_constant_override("separation",18)
		menu.add_child(crew_row)
		var identity:=VBoxContainer.new()
		identity.custom_minimum_size.x=180
		crew_row.add_child(identity)
		var inspect:=button(identity,entry[1],func():open_place(entry[0]))
		inspect.alignment=HORIZONTAL_ALIGNMENT_LEFT
		inspect.custom_minimum_size.y=34
		inspect.add_theme_stylebox_override("normal",style("00000000","00000000",4))
		inspect.add_theme_stylebox_override("hover",style("ffffff0d","77777755",4))
		inspect.add_theme_stylebox_override("pressed",style("ff653f19","ff653f",4))
		text(identity,"Home · "+entry[2],14,"bcb9b6")
		var assignment:=text(crew_row,"No retained assignment",15,"c9c5c1")
		assignment.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		assignment.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		crew_record_labels[entry[0]]=assignment
		menu.add_child(HSeparator.new())
	add_summary_toggle(menu)
	roster=text(menu,"Crew activity unknown · waiting for authoritative records",14,"c9c5c1")
	roster.name="CrewSummary"
	roster.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	roster.hide()
	var places_scroll:=ScrollContainer.new()
	places_scroll.name="Places"
	places_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	places_scroll.follow_focus=true
	directory_tabs.add_child(places_scroll)
	building_list=VBoxContainer.new()
	building_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	building_list.add_theme_constant_override("separation",8)
	places_scroll.add_child(building_list)
	var directory_links:=HBoxContainer.new()
	directory_column.add_child(directory_links)
	button(directory_links,"Field ops [B]",open_board)
	button(directory_links,"Work [J]",open_operations)
	button(directory_links,"Connection [O]",open_connection)
	directory.hide()
	help = panel_at(root,Vector2(410,0))
	help.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	var settings_column := VBoxContainer.new()
	help.add_child(settings_column)
	var settings_head:=HBoxContainer.new()
	settings_column.add_child(settings_head)
	var settings_title:=text(settings_head,"SETTINGS & CONTROLS",18,"c9c5c1")
	settings_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	settings_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var settings_close:=button(settings_head,"Close",close_panels)
	settings_close.size_flags_horizontal=Control.SIZE_SHRINK_END
	settings_close.custom_minimum_size.x=80
	var settings_body:=HBoxContainer.new()
	settings_body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	settings_body.add_theme_constant_override("separation",22)
	settings_column.add_child(settings_body)
	settings_nav=VBoxContainer.new()
	settings_nav.custom_minimum_size.x=160
	settings_nav.add_theme_constant_override("separation",8)
	settings_body.add_child(settings_nav)
	settings_tabs=TabContainer.new()
	settings_tabs.tabs_visible=false
	settings_tabs.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	settings_tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	settings_body.add_child(settings_tabs)
	settings_tabs.tab_changed.connect(func(_index:int): update_settings_selection())
	for index in range(4):
		var tab_button:=button(settings_nav,["Display","Audio","Controls","Character"][index],func(): select_settings(index))
		tab_button.custom_minimum_size.y=48
		settings_buttons.append(tab_button)
	var comfort:=settings_page("Display")
	text(comfort,"Display",26,"e9e5df")
	text(comfort,"Adjust the native interface and camera to suit you.",15).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var rm := CheckButton.new()
	rm.text = "Reduced motion · Off"
	rm.toggled.connect(func(value: bool): reduced=value; rm.text="Reduced motion · "+("On" if value else "Off"); settings_changed.emit())
	comfort.add_child(rm)
	text(comfort,"Uses immediate camera cuts and still ambient effects. Work continues normally.",14,"b5b6b5").autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var lt := CheckButton.new()
	large_toggle=lt
	lt.text = "Larger interface text · Off"
	lt.toggled.connect(func(value: bool): large_text=value; lt.text="Larger interface text · "+("On" if value else "Off"); scale_text(); settings_changed.emit())
	comfort.add_child(lt)
	add_summary_toggle(comfort)
	var audio:=settings_page("Audio")
	text(audio,"Audio",26,"e9e5df")
	var sound := CheckButton.new()
	sound.text="Ambient sounds · Off"
	sound.toggled.connect(func(value: bool): sound_enabled=value; sound.text="Ambient sounds · "+("On" if value else "Off"); settings_changed.emit())
	audio.add_child(sound)
	text(audio,"Quiet footsteps, airlocks and room ambience. Off by default. All operational status remains available visually.",15).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var guide:=settings_page("Controls")
	text(guide,"Controls",26,"e9e5df")
	for section in [
		["EXPLORE", "WASD / arrows  ·  Walk\nClick a path  ·  Travel\nE  ·  Inspect nearby crew or console\nF  ·  Enter / exit a room\nL  ·  Visit Habitat\nM  ·  Colony map"],
		["WORKSPACES", "Tab  ·  Crew & places\n1–5  ·  Crew dossier\nB  ·  Field operations\nJ  ·  Work & history\nI  ·  Station records\nK  ·  Habitat briefing\nO  ·  Connection"],
		["CAMERA & NAVIGATION", "V  ·  Observe crew\nC  ·  Follow / room camera\n+ / − or wheel  ·  Zoom\nEnter  ·  Activate focused control\nEsc  ·  Close workspace\nH  ·  Settings & controls"]]:
		text(guide,section[0],13,"c9c5c1")
		text(guide,section[1],15).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	button(guide,"Connection settings [O]",open_connection)
	var character_page:=settings_page("Character")
	text(character_page,"Your character",26,"e9e5df")
	text(character_page,"Choose who you explore the colony as.",15).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var character_group:=ButtonGroup.new()
	for choice in [["operator","Sho Junko"],["cybercat","Cybercat"]]:
		var character_id:String=choice[0]
		var pick:=button(character_page,choice[1],func():player_character_selected.emit(character_id))
		pick.toggle_mode=true;pick.button_group=character_group
		pick.custom_minimum_size.y=56
		player_character_buttons[character_id]=pick
	player_character_status=text(character_page,"Playing as Sho Junko",15,"c9c5c1")
	text(character_page,"Your choice is remembered on this device.",14,"b5b6b5").autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	set_player_character_selection(selected_player_character)

	help.hide()
	board=preload("res://command_board.gd").new()
	board.api=api; board.fixture=board_fixture
	board.add_theme_stylebox_override("panel",style("0a0a0ad6","77777766",18))
	root.add_child(board)
	operations=preload("res://operations_panel.gd").new()
	operations.api=api; operations.fixture=board_fixture
	operations.add_theme_stylebox_override("panel",style("0a0a0ad6","77777766",18))
	root.add_child(operations)
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
	room_detail_title=text(room_column,"ROOM GUIDE",19,"ff7755")
	room_detail_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	room_detail_body=text(room_column,"",16)
	room_detail_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	button(room_column,"Back to exploring [Esc]",close_panels)
	room_details.hide()
	connection_panel=preload("res://connection_panel.gd").new()
	connection_panel.add_theme_stylebox_override("panel",style())
	ConsoleTheme.smoke(connection_panel)
	root.add_child(connection_panel)
	connection_panel.connect_requested.connect(func(value:String): connect_requested.emit(value))
	connection_panel.journal_requested.connect(open_operations)
	crew_strip=preload("res://crew_strip.gd").new()
	root.add_child(crew_strip)
	crew_strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	crew_strip.inspect_requested.connect(open_place)
	crew_strip.home_requested.connect(func():room_requested.emit("habitat"))
	for workspace in [dock,directory,help,room_details,connection_panel]:
		workspace.visibility_changed.connect(sync_world_chrome)
	board.visibility_changed.connect(sync_world_chrome)
	operations.visibility_changed.connect(sync_world_chrome)
	root.resized.connect(layout_hud)
	layout_hud.call_deferred()

func set_location(value:String) -> void:
	location.text=value
	location.tooltip_text=value

func _unhandled_key_input(event:InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_F1:
		toggle_exploration_hud()
		get_viewport().set_input_as_handled()

func sync_world_chrome() -> void:
	# Dense evidence workspaces get their full scroll area; closing restores the
	# world without making a second action necessary.
	if crew_strip==null: return
	var expanded:bool=is_open()
	room_exit.visible=room_available and not expanded
	var active:="crew" if dock.visible or directory.visible else ("work" if operations.visible else ("field" if board.visible else ("settings" if help.visible else ("stations" if station_records!=null and station_records.visible else ("connection" if connection_panel.visible else "")))))
	if briefing!=null and briefing.visible: active="stations"
	if room_details!=null and room_details.visible: active="stations"
	workspace_label.text={"crew":"CREW DOSSIER" if dock.visible else "CREW & PLACES","work":"WORK","field":"FIELD OPERATIONS","settings":"SETTINGS","stations":"STATION RECORDS","connection":"CONNECTION"}.get(active,"WORLD")
	if briefing!=null and briefing.visible: workspace_label.text="HABITAT BRIEFING"
	if room_details!=null and room_details.visible: workspace_label.text="ROOM GUIDE · "+room_detail_title.text
	active_navigation=active
	update_navigation_style()
	var show_exploration:=not expanded and not exploration_hud_collapsed
	crew_strip.visible=show_exploration
	crew_strip.rows.visible=show_exploration and not observing
	prompt_panel.visible=show_exploration
	navigation_bar.visible=show_exploration or expanded
	navigation_background.visible=navigation_bar.visible and navigation_bar.vertical
	chrome_toggle.text="Show HUD [F1]" if exploration_hud_collapsed else "Hide HUD [F1]"
	chrome_toggle.visible=not expanded
	layout_hud()

func toggle_exploration_hud() -> void:
	exploration_hud_collapsed=not exploration_hud_collapsed
	sync_world_chrome()

func add_summary_toggle(parent:Node) -> void:
	var toggle:=CheckButton.new()
	toggle.text="Crew summary · Off"
	toggle.tooltip_text="Show authoritative crew activity in the station directory"
	toggle.toggled.connect(set_crew_summary)
	parent.add_child(toggle)
	summary_toggles.append(toggle)

func set_crew_summary(value:bool) -> void:
	crew_summary=value
	if roster!=null: roster.visible=value
	for toggle in summary_toggles:
		toggle.set_pressed_no_signal(value)
		toggle.text="Crew summary · "+("On" if value else "Off")

func layout_hud() -> void:
	if dock==null or help==null or navigation_bar==null: return
	var viewport_size:Vector2=root.size
	var narrow:=viewport_size.x<1000
	var labels:={"map":"Map [M]","crew":"Crew [Tab]","work":"Work [J]","stations":"Stations [I]","field":"Field ops [B]","settings":"Settings [H]","connection":"Connection [O]"}
	var short_labels:={"map":"Map","crew":"Crew","work":"Work","stations":"Stations","field":"Field","settings":"Settings","connection":"Connect"}
	for key in nav_buttons:
		nav_buttons[key].text=short_labels[key] if narrow else {"map":"Map","crew":"Crew","work":"Work","stations":"Stations","field":"Field ops","settings":"Settings","connection":"Connection"}[key]
		nav_buttons[key].tooltip_text=labels[key]
	navigation_bar.offset_top=72
	navigation_bar.offset_left=-minf(980,viewport_size.x-44)-22
	navigation_bar.offset_right=-22
	header_panel.size.x=viewport_size.x-36
	room_exit.position=Vector2(22,116)
	var top_edge:=128.0
	var panel_width:=minf(520 if large_text else 490,viewport_size.x-44)
	for panel in [dock,directory,help,room_details,connection_panel]:
		panel.custom_minimum_size.x=panel_width
		panel.offset_top=top_edge
		panel.offset_bottom=-24
	dock.offset_left=-panel_width-22
	dock.offset_right=-22
	room_details.offset_left=-panel_width-22
	room_details.offset_right=-22
	for panel in [directory,help,connection_panel]:
		panel.offset_left=22
		panel.offset_right=22+panel_width
	if operations!=null:
		var operations_width:=minf(930,viewport_size.x-44)
		operations.offset_left=viewport_size.x-operations_width-22
		operations.offset_right=-22
		operations.offset_top=top_edge
		operations.offset_bottom=-24
	var wide:=viewport_size.x>=1000
	room_exit.position=Vector2(184,92) if wide else Vector2(22,116)
	navigation_bar.vertical=wide
	navigation_background.visible=wide and navigation_bar.visible
	navigation_background.position=Vector2(18,92)
	navigation_background.size=Vector2(150,maxf(0,viewport_size.y-116))
	for key in nav_buttons:
		nav_buttons[key].icon=navigation_icons[key] if wide else null
		nav_buttons[key].icon_alignment=HORIZONTAL_ALIGNMENT_LEFT
		nav_buttons[key].alignment=HORIZONTAL_ALIGNMENT_LEFT if wide else HORIZONTAL_ALIGNMENT_CENTER
		nav_buttons[key].add_theme_constant_override("h_separation",10)
		nav_buttons[key].add_theme_constant_override("icon_max_width",20)
	update_navigation_style()
	identity_column.visible=wide
	compact_watch.visible=not wide
	if wide:
		navigation_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		navigation_bar.position=Vector2(18,92)
		navigation_bar.size=Vector2(150,0)
		for item in navigation_bar.get_children():
			item.custom_minimum_size=Vector2(150,48)
		dock.offset_left=184-viewport_size.x
		dock.offset_right=-22
		dock.offset_top=92
		settings_nav.custom_minimum_size.x=160
		identity_column.custom_minimum_size.x=clampf((viewport_size.x-250)*0.28,230,340)
		for panel in [directory,help,connection_panel]:
			panel.offset_left=184
			panel.offset_right=viewport_size.x-22
			panel.offset_top=92
		if operations!=null:
			operations.offset_left=184
			operations.offset_top=92
	else:
		navigation_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		navigation_bar.offset_top=72
		navigation_bar.offset_left=-viewport_size.x+22
		navigation_bar.offset_right=-22
		for item in navigation_bar.get_children(): item.custom_minimum_size=Vector2(0,38)
		dock.offset_left=22-viewport_size.x
		dock.offset_right=-22
		help.offset_right=viewport_size.x-22
		settings_nav.custom_minimum_size.x=120 if large_text else 110
	var prompt_width:=minf(820,viewport_size.x-44)
	prompt_panel.offset_left=(viewport_size.x-prompt_width)*0.5
	prompt_panel.offset_right=-(viewport_size.x-prompt_width)*0.5
	prompt_panel.offset_top=-138 if observing else -210
	prompt_panel.offset_bottom=-108 if observing else -174
	if crew_strip!=null:
		var strip_width:=minf(1000,viewport_size.x-44)
		var strip_left:float=(viewport_size.x-strip_width)*0.5
		# Keep the persistent roster inside the world safe area beside the wide rail.
		if wide:
			strip_left=maxf(184.0,strip_left)
			strip_width=minf(strip_width,viewport_size.x-strip_left-22.0)
		crew_strip.offset_left=strip_left
		crew_strip.offset_right=-(viewport_size.x-(strip_left+strip_width))
		crew_strip.offset_top=-108 if observing else -174; crew_strip.offset_bottom=-16
		crew_strip.fit(viewport_size.x,large_text)

func settings_page(title:String) -> VBoxContainer:
	var scroll:=ScrollContainer.new()
	scroll.name=title
	scroll.follow_focus=true
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	settings_tabs.add_child(scroll)
	var column:=VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",16)
	scroll.add_child(column)
	return column

func toggle_settings() -> void:
	var was:=help.visible
	close_panels()
	help.visible=not was
	if help.visible:
		select_settings(settings_tabs.current_tab)
		settings_buttons[settings_tabs.current_tab].grab_focus()

func open_connection() -> void:
	close_panels()
	connection_panel.show()
	connection_panel.endpoint.grab_focus()

func open_operations() -> void:
	close_panels()
	operations.open()

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
		entry.alignment=HORIZONTAL_ALIGNMENT_LEFT
		entry.tooltip_text="Visit "+building.definition.title+" · Enter to travel"
		entry.set_meta("building_key",key)
	filter_buildings(building_search.text)

func filter_buildings(query: String) -> void:
	if directory_tabs!=null and not query.strip_edges().is_empty(): directory_tabs.current_tab=1
	for entry in building_list.get_children():
		entry.visible=query.strip_edges().is_empty() or entry.text.to_lower().contains(query.strip_edges().to_lower())

func scale_text() -> void:
	if large_toggle!=null:
		large_toggle.set_pressed_no_signal(large_text)
		large_toggle.text="Larger interface text · "+("On" if large_text else "Off")
	if board!=null: board.large_text=large_text
	for node in root.find_children("*", "Label", true, false):
		if not node.has_meta("base_font"):
			node.set_meta("base_font", node.get_theme_font_size("font_size"))
		node.add_theme_font_size_override("font_size", int(node.get_meta("base_font")) + (3 if large_text else 0))
	for surface in [root,board,operations,crew_strip]:
		if surface==null or surface.theme==null: continue
		surface.theme.default_font_size = 19 if large_text else 16
		for kind in ["Button","OptionButton","CheckButton","CheckBox","LineEdit","RichTextLabel","TabBar","TabContainer"]:
			surface.theme.set_font_size("font_size",kind,19 if large_text else 16)
	for control in root.find_children("*","Button",true,false):
		control.add_theme_font_size_override("font_size",19 if large_text else 16)
	evidence.add_theme_font_size_override("normal_font_size",18 if large_text else 16)
	for item in navigation_bar.get_children(): item.add_theme_font_size_override("font_size",16 if large_text else 13)
	room_exit.add_theme_font_size_override("font_size",16 if large_text else 13)
	layout_hud()

func close_panels() -> void:
	if station_records!=null: station_records.hide()
	if briefing!=null: briefing.hide()
	if operations!=null: operations.hide()
	if board!=null: board.hide()
	if connection_panel!=null: connection_panel.hide()
	dock.hide()
	directory.hide()
	help.hide()
	if room_details!=null: room_details.hide()
	root.get_viewport().gui_release_focus()
	sync_world_chrome()

func toggle_directory() -> void:
	var was := directory.visible
	close_panels()
	directory.visible = not was
	if directory.visible:
		update_directory_records()
		directory.find_children("*","Button",true,false)[0].grab_focus()

func open_place(kind: String) -> void:
	close_panels()
	filter_kind = kind
	dock.show()
	heading.text = {"repair":"RIVET / WORKSHOP","review":"MOSS BOMBADIL / COMMAND","gym":"MAE JIN / TRIAL HALL","watchkeeper":"WES WALKER / CLUSTER WATCH","reviewer":"PRISM / COMMAND"}.get(kind,"CREW")
	if portrait.has_method("set_crew"): portrait.set_crew(kind)
	suit_label.text={"repair":"RIVET · MENDER","review":"MOSS BOMBADIL · SURVEYOR","gym":"MAE JIN · TRAINER","watchkeeper":"WES WALKER · WATCHKEEPER","reviewer":"PRISM · REVIEWER"}.get(kind,"FIELD CREW")
	dossier_tabs.current_tab=0
	dossier_tabs.set_tab_hidden(2,kind!="repair")
	progression.visible=kind=="repair"
	progression_heading.visible=kind=="repair"
	repair_form.visible = kind == "repair"
	update_crew_guide()
	place_selected.emit(kind)
	dossier_scroll.scroll_vertical=0
	dock.find_children("*","Button",true,false)[0].grab_focus()

func is_open() -> bool:
	return (station_records!=null and station_records.visible) or (briefing!=null and briefing.visible) or (operations!=null and operations.visible) or (connection_panel!=null and connection_panel.visible) or dock.visible or directory.visible or help.visible or (board!=null and board.visible) or (room_details!=null and room_details.visible)

func update_list(missions: Array) -> void:
	directory_records=missions
	update_directory_records()
	var shown: Array = missions.filter(func(m): return StateView.context(m) == filter_kind)
	var ids: Array = shown.map(func(m): return m["input"]["id"])
	var old_ids: Array = []
	for i in range(list.item_count):
		old_ids.append(list.get_item_metadata(i))
	if ids != old_ids or (ids.is_empty() and list.item_count == 0):
		list.clear()
		for id in ids:
			list.add_item(id)
			list.set_item_metadata(list.item_count-1,id)
		if ids.is_empty():
			list.add_item("No retained assignments")
			list.set_item_disabled(0,true)
	if selected_id not in ids:
		selected_id = str(ids[0]) if not ids.is_empty() else ""
	if selected_id != "":
		list.select(ids.find(selected_id))
	list.tooltip_text = "No retained assignments are available in this snapshot." if selected_id.is_empty() else selected_id
	var current:Dictionary={}
	for record in shown:
		if str(record.input.id)==selected_id: current=record; break
	var input:Dictionary=current.get("input",{})
	var build=current.get("build")
	var build_label:="Not reported"
	if build is String: build_label=build
	elif build is Dictionary: build_label=str(build.get("id",build.get("build_id","Not reported")))
	var updated:=float(current.get("updated_at",0))
	record_metadata.text="Record  %s\nTarget  %s\nBuild  %s\nUpdated  %s" % [selected_id if not selected_id.is_empty() else "None retained",str(input.get("target",input.get("scenario","Not reported"))),build_label,Time.get_datetime_string_from_unix_time(int(updated)).replace("T"," ")+" UTC" if updated>0 else "Not reported"]
	stop.visible=not selected_id.is_empty()
	record_metadata.visible=not selected_id.is_empty()
	if selected_id.is_empty():
		status.text="No retained assignment"
		status.add_theme_color_override("font_color",Color("c9c5c1"))
		details.text="No retained assignment is available for this crew member. Open Work & history [J] to review other retained records."
		stop.disabled=true
		stop.text="Cancellation unavailable"
		stop.tooltip_text="There is no active retained work to cancel."
	else:
		status.add_theme_color_override("font_color",Color("ff7755"))
		stop.text="Request cancellation"
		stop.tooltip_text="Cancellation is available only for active retained work."

func dossier_page(title:String) -> VBoxContainer:
	var scroll:=ScrollContainer.new()
	scroll.name=title
	scroll.follow_focus=true
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	dossier_tabs.add_child(scroll)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",16)
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",16)
	scroll.add_child(column)
	return column

func select_settings(index:int) -> void:
	settings_tabs.current_tab=index
	update_settings_selection()

func update_settings_selection() -> void:
	var index:=settings_tabs.current_tab
	for item in range(settings_buttons.size()):
		settings_buttons[item].add_theme_stylebox_override("normal",style("42251ec9" if item==index else "11111199","ff653f" if item==index else "77777755",12))

func navigation_style(selected:bool=false,hovered:bool=false) -> StyleBoxFlat:
	var surface:=style("ff653f19" if selected else ("ffffff0d" if hovered else "00000000"),"ff653f" if selected else "00000000",10 if navigation_bar.vertical else 6)
	surface.set_border_width_all(0)
	surface.border_width_left=2 if selected else 0
	surface.content_margin_left=14 if navigation_bar.vertical else 6
	return surface

func update_navigation_style() -> void:
	if navigation_bar==null: return
	for item in navigation_bar.get_children():
		item.add_theme_stylebox_override("normal",navigation_style())
		item.add_theme_stylebox_override("hover",navigation_style(false,true))
		item.add_theme_stylebox_override("pressed",navigation_style(true))
	for key in nav_buttons:
		var selected:bool=key==active_navigation
		nav_buttons[key].add_theme_stylebox_override("normal",navigation_style(selected))
		nav_buttons[key].add_theme_color_override("icon_normal_color",Color("ff7755") if selected else Color.WHITE)

func set_room_available(value:bool) -> void:
	room_available=value
	sync_world_chrome()

func update_directory_records() -> void:
	for kind in crew_record_labels:
		var matching:Array=directory_records.filter(func(record):return StateView.context(record)==kind)
		matching.sort_custom(func(a,b):return float(a.get("updated_at",0))>float(b.get("updated_at",0)))
		var label:Label=crew_record_labels[kind]
		if matching.is_empty():
			label.text="No assignment in retained snapshot"
			label.tooltip_text="No record is retained here. This does not establish whether older work exists."
			continue
		var record:Dictionary=matching[0]
		var input:Dictionary=record.get("input",{})
		var target:=str(input.get("target",input.get("scenario","Target not reported")))
		var state:=str(record.get("state","unknown")).capitalize().replace("_"," ")
		if record.get("stale",true): state="Stale · last known "+state
		var evidence_note:="Evidence retained" if record.get("evidence")!=null else "No completion evidence retained"
		label.text="%s · %s\n%s" % [state,target,evidence_note]
		label.tooltip_text="Record %s\n%d records in this snapshot\n%s" % [str(input.get("id","Not reported")),matching.size(),str(record.get("detail","Detail not reported"))]

func set_player_character_selection(character_id:String) -> void:
	selected_player_character=character_id
	for choice in player_character_buttons:
		player_character_buttons[choice].set_pressed_no_signal(choice==character_id)
	if player_character_status!=null:
		player_character_status.text="Playing as "+("Cybercat" if character_id=="cybercat" else "Sho Junko")

func update_crew_guide() -> void:
	if crew_purpose==null: return
	var role:String={"repair":"mender","review":"surveyor","gym":"trainer"}.get(filter_kind,filter_kind)
	var guide:Dictionary=preload("res://crew_guide.gd").profile(operations.snapshot,role,operations.offline)
	crew_purpose.text=str(guide.get("purpose","Crew profile unavailable."))
	var actions:Array=guide.get("actions",[])
	crew_action.visible=not actions.is_empty()
	if not actions.is_empty():
		crew_action.text=str(actions[0].label)
		crew_route=str(actions[0].route)
	var lines:PackedStringArray=[]
	for skill in guide.get("skills",[]):
		lines.append(str(skill.label)+"\n"+str(skill.explanation))
	crew_workflows.text="\n\n".join(lines)
	crew_limits.text="\n".join(guide.get("limits",[]))
	var key:String={"repair":"repair","review":"review","gym":"evaluation"}.get(filter_kind,"field")
	var policy:Dictionary=preload("res://connection_status.gd").capability(operations.snapshot,key)
	crew_availability.text="Preview fixture · work cannot be submitted here." if not operations.fixture.is_empty() else "Disconnected · availability cannot be confirmed." if operations.offline else "Availability not reported by Core." if policy.is_empty() else "Configured workflow · choose a target in the workspace." if policy.get("enabled",false) else "Unavailable · "+str(policy.get("reason","Disabled by installation policy."))
	if not operations.offline and operations.fixture.is_empty() and not preload("res://connection_status.gd").worker_available(operations.snapshot):
		crew_availability.text+=" Worker unavailable."

func open_crew_workflow() -> void:
	match crew_route:
		"work.repair":
			dossier_tabs.current_tab=2
			scenario.grab_focus()
		"work.review", "work.evaluation":
			open_operations()
			operations.tabs.current_tab=0 if crew_route=="work.review" else 1
			(operations.target if crew_route=="work.review" else operations.baseline).grab_focus()
		"field.watchkeeper", "field.reviewer":
			open_board()
			board.tabs.current_tab=0
			board.targets.select(-1)
			var agent_role:="watchkeeper" if crew_route=="field.watchkeeper" else "reviewer"
			for index in board.targets.item_count:
				var target_data=board.targets.get_item_metadata(index)
				if target_data is Dictionary and target_data.get("agent","")==agent_role:
					board.targets.select(index)
					break
			board.controls()
			board.targets.grab_focus()
