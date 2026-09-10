extends PanelContainer
const Status=preload("res://connection_status.gd")
const Commands=preload("res://commands.gd")
signal connect_requested(endpoint:String)
signal journal_requested
var endpoint:LineEdit
var summary:Label
var health:Label
var capabilities:Label
var feedback:Label
var reconnect:Button

func line(parent:Node,value:String,size:int=15) -> Label:
	var label:=Label.new()
	label.text=value
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",size)
	parent.add_child(label)
	return label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	offset_left=22; offset_right=430; offset_top=112; offset_bottom=-80
	var frame:=VBoxContainer.new()
	frame.add_theme_constant_override("separation",12)
	add_child(frame)
	line(frame,"COLONY CONNECTION",20)
	var scroll:=ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	frame.add_child(scroll)
	var column:=VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",12)
	scroll.add_child(column)
	summary=line(column,"No Core observed",17)
	health=line(column,"")
	line(column,"Local Core or private port-forward address",13)
	endpoint=LineEdit.new()
	endpoint.text="http://127.0.0.1:8787"
	endpoint.placeholder_text="http://127.0.0.1:8787"
	endpoint.max_length=80
	column.add_child(endpoint)
	reconnect=Button.new()
	reconnect.text="Connect to Core"
	reconnect.custom_minimum_size.y=38
	reconnect.pressed.connect(request_connection)
	endpoint.text_submitted.connect(func(_value:String): request_connection())
	column.add_child(reconnect)
	feedback=line(column,"")
	line(column,"Local development: start the backend with just dev. For a private installation, establish its authorized port-forward first. This screen does not start or deploy services.",13)
	capabilities=line(column,"Capabilities unknown",14)
	var journal:=Button.new()
	journal.text="Open operations & history"
	journal.custom_minimum_size.y=38
	journal.pressed.connect(func(): journal_requested.emit())
	column.add_child(journal)
	var close:=Button.new()
	close.text="Return to colony [Esc]"
	close.custom_minimum_size.y=38
	close.pressed.connect(hide)
	column.add_child(close)
	hide()

func request_connection() -> void:
	var value:=endpoint.text.strip_edges().trim_suffix("/")
	if not Commands.local_origin(value):
		feedback.text="Use http://127.0.0.1:<port>. Remote installations require a private local port-forward."
		return
	connect_requested.emit(value)

func worker_heartbeat(snapshot:Dictionary,offline:bool) -> String:
	var worker=snapshot.get("worker")
	var seen=worker.get("seen_at") if worker is Dictionary else null
	if not (seen is float or seen is int): return "not reported"
	if not is_finite(float(seen)) or float(seen)<=0: return "not reported"
	var timestamp:=Time.get_datetime_string_from_unix_time(int(seen),true)+" UTC"
	if offline or not Status.worker_available(snapshot): return timestamp+" · stale / last-known"
	return timestamp

func refresh(api:String,snapshot:Dictionary,offline:bool,fixture:bool,last_received:int,message:String,pending:bool) -> void:
	if not endpoint.has_focus(): endpoint.text=api
	summary.text=Status.headline(snapshot,offline,fixture)
	var info:=Status.installation(snapshot)
	var age:float=maxf(0,(Time.get_ticks_msec()-last_received)/1000.0)
	health.text="Environment: %s\nCore receipt: %s\nWorker: %s\nWorker heartbeat: %s\n%s" % [info.get("environment","unknown"),"none" if last_received==0 else "%.1fs ago"%age,"available" if Status.worker_available(snapshot) and not offline else "unavailable / last-known",worker_heartbeat(snapshot,offline),message]
	var lines:PackedStringArray=[]
	for key in ["review","evaluation","field","repair","memory","inference"]:
		var cap:=Status.capability(snapshot,key)
		lines.append("%s · %s\n%s" % [key.capitalize(),"unknown" if cap.is_empty() else "enabled" if cap.get("enabled",false) else "disabled",Status.reason(snapshot,key)])
	capabilities.text="CONFIGURED CAPABILITIES\n"+"\n\n".join(lines)+"\n\nEnabled policy does not establish worker or provider health. Stop and evidence remain separate."
	reconnect.disabled=pending
	if pending: feedback.text="Resolve the pending or uncertain command before switching installations."
