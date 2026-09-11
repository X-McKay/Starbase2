extends PanelContainer
## A quiet, non-spatial way into the living crew. Records and local activity stay distinct.
signal inspect_requested(kind:String)
signal home_requested
const NAMES := {"repair":"Mender","review":"Surveyor","gym":"Trainer","watchkeeper":"Watchkeeper","reviewer":"Reviewer"}
const COLORS := {"repair":"d7a16f","review":"a9c4ba","gym":"d8cdb2","watchkeeper":"86c8dd","reviewer":"b8a6cf"}
var entries:Dictionary={}
var rows:HBoxContainer
var watching:Label

func _ready() -> void:
	var skin:=StyleBoxFlat.new()
	skin.bg_color=Color("101e24f2"); skin.border_color=Color("a899704d")
	skin.set_border_width_all(1); skin.set_corner_radius_all(14)
	skin.content_margin_left=14; skin.content_margin_right=14
	skin.content_margin_top=10; skin.content_margin_bottom=10
	add_theme_stylebox_override("panel",skin)
	var column:=VBoxContainer.new(); column.add_theme_constant_override("separation",8); add_child(column)
	var head:=HBoxContainer.new(); column.add_child(head)
	watching=Label.new(); watching.text="THE CREW  /  ASTER COLONY"
	watching.add_theme_font_size_override("font_size",11)
	watching.add_theme_color_override("font_color",Color("bdc9c3"))
	watching.size_flags_horizontal=Control.SIZE_EXPAND_FILL; head.add_child(watching)
	var home:=Button.new(); home.text="Habitat  [L]"; home.flat=true
	home.add_theme_font_size_override("font_size",12)
	home.tooltip_text="Visit the crew's home · L"; head.add_child(home)
	home.pressed.connect(func():home_requested.emit())
	rows=HBoxContainer.new(); rows.add_theme_constant_override("separation",6); column.add_child(rows)
	for kind in NAMES:
		var entry:=Button.new(); entry.custom_minimum_size=Vector2(0,55)
		entry.size_flags_horizontal=Control.SIZE_EXPAND_FILL; rows.add_child(entry)
		entry.alignment=HORIZONTAL_ALIGNMENT_LEFT; entry.clip_text=true
		entry.add_theme_font_size_override("font_size",14)
		entry.add_theme_color_override("font_color",Color(COLORS[kind]))
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
	entries[kind].tooltip_text="%s · %s\n%s\nInspect crew and retained work" % [NAMES[kind],str(intent.get("label","Unknown")),str(intent.get("duty_label",""))]

func set_watching(kind:String) -> void:
	watching.text="WATCHING  /  "+NAMES.get(kind,"").to_upper() if NAMES.has(kind) else "THE CREW  /  ASTER COLONY"

func fit(width:float,large:bool) -> void:
	for kind in entries:
		entries[kind].add_theme_font_size_override("font_size",15 if large else (12 if width<900 else 14))
