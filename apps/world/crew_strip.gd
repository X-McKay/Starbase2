extends PanelContainer
## A quiet, non-spatial way into the living crew. Records and local activity stay distinct.
signal inspect_requested(kind:String)
signal home_requested
signal briefing_requested
signal observe_requested
const NAMES := {"repair":"Rivet","review":"Moss Bombadil","gym":"Mae Jin","watchkeeper":"Wes Walker","reviewer":"Prism"}
var entries:Dictionary={}
var rows:HBoxContainer
var watching:Label

func _ready() -> void:
	preload("res://console_theme.gd").apply(self)
	var column:=VBoxContainer.new(); column.add_theme_constant_override("separation",8); add_child(column)
	var head:=HBoxContainer.new(); column.add_child(head)
	watching=Label.new(); watching.text="THE CREW  /  ASTER COLONY"
	watching.add_theme_font_size_override("font_size",13)
	watching.add_theme_color_override("font_color",Color("c9c5c1"))
	watching.size_flags_horizontal=Control.SIZE_EXPAND_FILL; head.add_child(watching)
	for action in [["Briefing [K]",briefing_requested],["Observe [V]",observe_requested]]:
		var control:=Button.new(); control.text=action[0]; control.flat=false
		control.add_theme_font_size_override("font_size",14); head.add_child(control)
		control.pressed.connect(func():action[1].emit())
	var home:=Button.new(); home.text="Habitat  [L]"; home.flat=false
	home.add_theme_font_size_override("font_size",14)
	home.tooltip_text="Visit the crew's home · L"; head.add_child(home)
	home.pressed.connect(func():home_requested.emit())
	rows=HBoxContainer.new(); rows.add_theme_constant_override("separation",6); column.add_child(rows)
	for kind in NAMES:
		var entry:=Button.new(); entry.custom_minimum_size=Vector2(0,55)
		entry.size_flags_horizontal=Control.SIZE_EXPAND_FILL; rows.add_child(entry)
		entry.alignment=HORIZONTAL_ALIGNMENT_LEFT; entry.clip_text=true
		entry.add_theme_font_size_override("font_size",14)
		# Idle and unknown states stay quiet; attention is added per projection below.
		entry.add_theme_color_override("font_color",Color("c9c5c1"))
		entry.add_theme_color_override("font_hover_color",Color("e9e5df"))
		entry.add_theme_stylebox_override("normal",_entry_style("11111166","77777733"))
		entry.add_theme_stylebox_override("hover",_entry_style("ffffff0d","77777755"))
		entry.add_theme_stylebox_override("pressed",_entry_style("ff653f19","ff653f"))
		entry.pressed.connect(func():inspect_requested.emit(kind))
		entries[kind]=entry
		entry.text=NAMES[kind]+"\nConnecting…"

func project(kind:String,intent:Dictionary,activity:String="",blocked:bool=false) -> void:
	if not entries.has(kind): return
	var label:=str(intent.get("label","Unknown"))
	if bool(intent.get("unknown",true)):
		label="Last known · offline" if not intent.get("run_id","").is_empty() else "Awaiting live state"
	elif int(intent.get("active_count",0))>0:
		label="Queued" if intent.get("backend_state")=="queued" else "Working"
		if intent.get("backend_state")=="cancel_requested": label="Cancel pending"
	elif intent.get("evidence_ready",false): label="Report ready"
	elif intent.get("backend_state")=="failed": label="Needs attention"
	elif intent.get("backend_state")=="cancelled": label="Cancelled"
	elif not activity.is_empty(): label=activity
	else: label="Between assignments"
	if blocked and not bool(intent.get("unknown",true)): label+=" · route blocked"
	entries[kind].text=NAMES[kind]+"\n"+label
	var attention:=label in ["Working","Queued","Cancel pending","Needs attention"] or label.ends_with("· route blocked")
	entries[kind].add_theme_color_override("font_color",Color("ffb39c") if attention else Color("c9c5c1"))
	entries[kind].tooltip_text="%s · %s\n%s\nInspect crew and retained work" % [NAMES[kind],str(intent.get("label","Unknown")),str(intent.get("duty_label",""))]

func set_watching(kind:String) -> void:
	watching.text="WATCHING  /  "+NAMES.get(kind,"").to_upper() if NAMES.has(kind) else "THE CREW  /  ASTER COLONY"

func fit(width:float,large:bool) -> void:
	for kind in entries:
		entries[kind].add_theme_font_size_override("font_size",15 if large else (12 if width<900 else 14))

func _entry_style(background:String,border:String) -> StyleBoxFlat:
	var surface:=StyleBoxFlat.new()
	surface.bg_color=Color(background)
	surface.border_color=Color(border)
	surface.set_border_width_all(1)
	surface.set_corner_radius_all(4)
	surface.content_margin_left=8
	surface.content_margin_right=8
	surface.content_margin_top=5
	surface.content_margin_bottom=5
	return surface
