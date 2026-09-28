extends VBoxContainer
## Static evidence-first sheet. This component cannot dispatch or qualify work.
signal evidence_requested
const SheetData=preload("res://crew_sheet_projection.gd")
const ThemeStyle=preload("res://console_theme.gd")
var fields:Dictionary={}
var stat_grid:GridContainer
var evidence_button:Button

func _ready() -> void:
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",16)
	label_field("freshness",14,ThemeStyle.MUTED)
	label_field("level",23,ThemeStyle.INK)
	label_field("class",16,ThemeStyle.MUTED)
	label_field("progression_note",14,ThemeStyle.MUTED)
	section("CURRENT CAPABILITY")
	label_field("current",16,ThemeStyle.INK)
	var note:=label_field("assessment_note",14,ThemeStyle.MUTED)
	note.text="Ratings use a 1–20 scale when supported by comparable evaluation evidence. No assessed ratings or comparable personal bests are reported yet."
	stat_grid=GridContainer.new()
	stat_grid.columns=2
	stat_grid.add_theme_constant_override("h_separation",10)
	stat_grid.add_theme_constant_override("v_separation",10)
	add_child(stat_grid)
	for stat in SheetData.STATS:
		var card:=PanelContainer.new()
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		card.focus_mode=Control.FOCUS_ALL
		card.add_theme_stylebox_override("panel",ThemeStyle.box(Color("191a1be0"),Color("777c8055"),12))
		card.focus_entered.connect(func():card.add_theme_stylebox_override("panel",ThemeStyle.box(Color("24201ee0"),ThemeStyle.ACCENT,12)))
		card.focus_exited.connect(func():card.add_theme_stylebox_override("panel",ThemeStyle.box(Color("191a1be0"),Color("777c8055"),12)))
		stat_grid.add_child(card)
		var content:=VBoxContainer.new()
		card.add_child(content)
		make_label(content,str(stat[0]),18,ThemeStyle.INK)
		make_label(content,"Unassessed",18,ThemeStyle.MUTED)
		make_label(content,"Best · unassessed",13,ThemeStyle.MUTED)
		make_label(content,str(stat[1]),14,ThemeStyle.MUTED)
	section("SKILLS")
	label_field("skills",16,ThemeStyle.INK)
	section("EQUIPMENT / BUILD REGISTRY")
	make_label(self,"Registered builds are available records, not proof of an active loadout. Equipped tools, procedures and Run book are not reported.",14,ThemeStyle.MUTED)
	label_field("equipment",15,ThemeStyle.INK,true)
	section("SERVICE RECORD / HISTORICAL QUALIFICATIONS")
	make_label(self,"These exact-build results remain historical. They do not qualify a replacement build or establish current stat ratings.",14,ThemeStyle.MUTED)
	label_field("history",15,ThemeStyle.INK,true)
	section("OPERATIONAL CLEARANCE")
	label_field("authority",15,ThemeStyle.INK)
	make_label(self,"XP, Level, Skills and equipment never grant operational permission.",14,ThemeStyle.MUTED)
	evidence_button=Button.new()
	evidence_button.text="View assignments & evidence"
	evidence_button.custom_minimum_size.y=40
	evidence_button.pressed.connect(func():evidence_requested.emit())
	add_child(evidence_button)
	resized.connect(fit)
	fit()

func make_label(parent:Node, value:String, font_size:int, color:Color, exact:bool=false) -> Label:
	var item:=Label.new()
	item.text=value
	item.autowrap_mode=TextServer.AUTOWRAP_ARBITRARY if exact else TextServer.AUTOWRAP_WORD_SMART
	item.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	item.add_theme_font_size_override("font_size",font_size)
	item.add_theme_color_override("font_color",color)
	parent.add_child(item)
	return item

func label_field(key:String, font_size:int, color:Color, exact:bool=false) -> Label:
	var item:=make_label(self,"",font_size,color,exact)
	fields[key]=item
	return item

func section(title:String) -> void:
	make_label(self,title,13,ThemeStyle.MUTED)

func fit() -> void:
	if stat_grid!=null: stat_grid.columns=1 if size.x<470 else 2

func update_snapshot(snapshot:Dictionary, role:String, offline:bool, fixture:bool) -> void:
	var projection:=SheetData.project(snapshot,role,offline,fixture)
	for key in projection:
		fields[key].text=str(projection[key])
