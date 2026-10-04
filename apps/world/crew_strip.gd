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
var status_detail:Label
var full_status:Dictionary={}
var shown_status:Dictionary={}
var detail_kind:=""
var compact_labels:=false

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
		entry.focus_entered.connect(func():show_status(kind))
		entry.mouse_entered.connect(func():show_status(kind))
		entries[kind]=entry
		entry.text=NAMES[kind]+"\nConnecting…"
	status_detail=Label.new();status_detail.text="Focus a crew member for full status"
	status_detail.add_theme_font_size_override("font_size",12);status_detail.add_theme_color_override("font_color",Color("bcb9b6"))
	status_detail.clip_text=true;status_detail.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(status_detail)

func project(kind:String,intent:Dictionary,_activity:String="",blocked:bool=false) -> void:
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
	else: label="Between assignments"
	if intent.has("sdlc_label"): label=str(intent.sdlc_label)
	# A fresh activity note supplies the verb; the record label stays in full status.
	var verb:=str(intent.get("activity_verb",""))
	var detail:=label
	if not verb.is_empty() and not bool(intent.get("unknown",true)):
		detail=verb+" · "+label
		label=verb
	if blocked and not bool(intent.get("unknown",true)):
		label+=" · route blocked"
		detail+=" · route blocked"
	full_status[kind]=detail
	shown_status[kind]=label
	entries[kind].text=NAMES[kind]+"\n"+display_status(label)
	if detail_kind==kind:show_status(kind)
	var attention:=label in ["Working","Queued","Cancel pending","Needs attention"] or label.ends_with("· route blocked") or not verb.is_empty()
	entries[kind].add_theme_color_override("font_color",Color("ffb39c") if attention else Color("c9c5c1"))
	entries[kind].tooltip_text="%s · %s\n%s\nInspect crew and retained work" % [NAMES[kind],detail,str(intent.get("duty_label",""))]

func set_watching(kind:String) -> void:
	watching.text="WATCHING  /  "+NAMES.get(kind,"").to_upper() if NAMES.has(kind) else "THE CREW  /  ASTER COLONY"

func fit(width:float,large:bool) -> void:
	compact_labels=width<1200
	for kind in entries:
		entries[kind].add_theme_font_size_override("font_size",15 if large else (12 if width<900 else 14))
		if shown_status.has(kind):entries[kind].text=NAMES[kind]+"\n"+display_status(shown_status[kind])
	if status_detail!=null:status_detail.add_theme_font_size_override("font_size",14 if large else 12)

func display_status(value:String) -> String:
	if not compact_labels:return value
	if value.ends_with("· route blocked"):return "Route blocked"
	return {"Between assignments":"Between tasks","Last known · offline":"Last known","Awaiting live state":"State unknown"}.get(value,value)

func show_status(kind:String) -> void:
	detail_kind=kind
	if status_detail!=null:
		status_detail.text=NAMES.get(kind,kind)+" · "+str(full_status.get(kind,"Connecting…"))
		status_detail.tooltip_text=status_detail.text

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
