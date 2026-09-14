extends PanelContainer
## A native view of the existing core ledger, not a second source of agent state.
const ConnectionStatus = preload("res://connection_status.gd")
const ConsoleTheme = preload("res://console_theme.gd")
const Commands = preload("res://commands.gd")
var api := preload("res://transport.gd").default_origin()
var installation_snapshot: Dictionary = {}
var installation_offline := false
var policy: Label
var briefing: Label
var fixture := ""
var snapshot: Dictionary = {}
var fixture_details: Dictionary = {}
var online := false
var pending := false
var large_text := false
var is_docked := false
var signature := ""
var focus_context := ""
var selected := ""
var get_http = preload("res://transport.gd").create()
var detail_http = preload("res://transport.gd").create()
var commands: Node
var notice: Label
var reconcile: Button
var observation_availability: Label
var connection: Label
var targets: OptionButton
var launch: Button
var observation_inference: CheckButton
var duty_save: Button
var duty_identity: LineEdit
var duty_target: OptionButton
var duty_interval: SpinBox
var duty_inference: CheckButton
var duty_enabled: CheckButton
var duty_records: VBoxContainer
var duty_editor_status: Label
var editing_duty: Dictionary = {}
var watch_input: LineEdit
var interval: SpinBox
var watch_save: Button
var runs: VBoxContainer
var watches: VBoxContainer
var memories: VBoxContainer
var memory_status: Label
var detail: VBoxContainer
var tabs: TabContainer
var guidance: ScrollContainer
var guidance_toggle: Button
var timer := Timer.new()
signal closed

func label(parent: Node, value: String, size: int = 16) -> Label:
	var l := Label.new()
	l.text=value
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size",maxi(16,size)+(3 if large_text else 0))
	parent.add_child(l)
	return l

func button(parent: Node, title: String, action: Callable, mutation: bool = false) -> Button:
	var b := Button.new()
	b.text=title
	b.clip_text=false
	b.add_theme_font_size_override("font_size",19 if large_text else 16)
	b.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	b.tooltip_text=title
	b.set_meta("focus_key",focus_context+"/"+title)
	b.custom_minimum_size.y=40
	b.pressed.connect(func():
		if not mutation or (online and not pending and fixture.is_empty()): action.call())
	if mutation: b.set_meta("mutation",true)
	parent.add_child(b)
	var font:=b.get_theme_font("font")
	b.custom_minimum_size.x=ceilf(font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,b.get_theme_font_size("font_size")).x)+b.get_theme_stylebox("normal").get_minimum_size().x+8
	return b

func form_field(parent:Node,title:String,item:Control) -> void:
	var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",16); parent.add_child(row)
	var caption:=label(row,title); caption.custom_minimum_size.x=180; caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	item.size_flags_horizontal=Control.SIZE_EXPAND_FILL; item.size_flags_stretch_ratio=1.7
	item.custom_minimum_size.y=40; row.add_child(item)

func metadata(parent:Node,title:String,value:String) -> void:
	var row:=HBoxContainer.new(); parent.add_child(row)
	var key:=label(row,title,16); key.custom_minimum_size.x=165
	key.add_theme_color_override("font_color",ConsoleTheme.MUTED)
	var content:=label(row,value,16); content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.text=value

func page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name=title
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	tabs.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation",12)
	scroll.add_child(col)
	return col

func _ready() -> void:
	ConsoleTheme.apply(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout_workspace()
	get_viewport().size_changed.connect(layout_workspace)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation",8)
	add_child(col)
	var heading := HBoxContainer.new()
	col.add_child(heading)
	var title := label(heading,"FIELD COMMAND",22)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var dismiss := button(heading,"Close [Esc]",func(): hide(); closed.emit())
	dismiss.text="Close"
	dismiss.tooltip_text="Close Command · Esc"
	dismiss.custom_minimum_size.x=110
	dismiss.size_flags_horizontal=Control.SIZE_SHRINK_END
	guidance_toggle=button(heading,"Info",func():
		guidance.visible=not guidance.visible
		tabs.visible=not guidance.visible
		guidance_toggle.text="Back" if guidance.visible else "Info")
	connection=label(col,"Connecting to the core…",13)
	tabs=TabContainer.new()
	tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	col.add_child(tabs)
	guidance=ScrollContainer.new(); guidance.size_flags_vertical=Control.SIZE_EXPAND_FILL
	guidance.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; guidance.follow_focus=true
	col.add_child(guidance); guidance.hide()
	var policy_help:=VBoxContainer.new(); policy_help.size_flags_horizontal=Control.SIZE_EXPAND_FILL; guidance.add_child(policy_help)
	label(policy_help,"SNAPSHOT & COMMAND GUIDANCE",20)
	briefing=label(policy_help,"No observation window loaded",16)
	policy=label(policy_help,"Installation policy not reported",16)
	label(policy_help,"Choose a configured target and explicitly request an observation. AI advice requires a separate opt-in. Travel and inspection never start work.")
	var operations := page("Observations")
	label(operations,"NEW OBSERVATION",20)
	targets=OptionButton.new()
	targets.fit_to_longest_item=false
	targets.custom_minimum_size.y=40
	form_field(operations,"Configured target",targets)
	targets.item_selected.connect(func(_index: int): controls())
	observation_inference=CheckButton.new(); observation_inference.text="Request AI advice (uses target admission budget)"; observation_inference.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; operations.add_child(observation_inference)
	launch=button(operations,"Start observation",start_selected,true)
	ConsoleTheme.primary(launch)
	observation_availability=label(operations,"Waiting for configured target and policy")
	operations.add_child(HSeparator.new())
	label(operations,"OBSERVATION RECORDS",20)
	runs=VBoxContainer.new(); runs.add_theme_constant_override("separation",10); operations.add_child(runs)
	var repository_page := page("Repositories")
	label(repository_page,"Watched GitHub repositories",21)
	label(repository_page,"Checks up to 10 recently updated open PRs, with changed-Python analysis. Pausing or removing prevents future dispatch; stop active observations separately.",14)
	watch_input=LineEdit.new(); watch_input.placeholder_text="owner/repository"; watch_input.max_length=201
	form_field(repository_page,"Repository",watch_input)
	interval=SpinBox.new(); interval.min_value=30; interval.max_value=86400; interval.value=300; Commands.track_integer_spinbox(interval)
	form_field(repository_page,"Interval · seconds",interval)
	watch_save=button(repository_page,"Watch repository",save_watch,true)
	ConsoleTheme.primary(watch_save)
	repository_page.add_child(HSeparator.new())
	label(repository_page,"REPOSITORY WATCHES",18)
	watches=VBoxContainer.new(); repository_page.add_child(watches)
	var memory_page := page("Memory")
	label(memory_page,"Reviewed observations",21)
	label(memory_page,"Approve a sourced observation for future recall. Revocation prevents later recall; history is retained. Memory cannot grant permissions.",14)
	memory_status=label(memory_page,"Memory policy not reported")
	memories=VBoxContainer.new(); memory_page.add_child(memories)
	detail=page("Evidence")
	label(detail,"Select Findings or Source to load retained evidence.")
	var duties_page:=page("Duties")
	label(duties_page,"Configured field duties",21)
	label(duties_page,"Choose an existing Core target. Saving changes future observations; pausing does not cancel work already started. AI advice remains unverified and subject to target cooldown and daily admission.",14)
	duty_editor_status=label(duties_page,"New duty · generation 0",14)
	duty_identity=LineEdit.new(); duty_identity.max_length=40; form_field(duties_page,"Duty identity",duty_identity)
	duty_target=OptionButton.new(); duty_target.fit_to_longest_item=false; duty_target.custom_minimum_size.y=40; form_field(duties_page,"Configured target",duty_target)
	duty_target.item_selected.connect(func(_index: int): duty_target.set_meta("selection_missing",false); controls())
	duty_interval=SpinBox.new(); duty_interval.min_value=30; duty_interval.max_value=86400; duty_interval.value=300; Commands.track_integer_spinbox(duty_interval); form_field(duties_page,"Interval · seconds",duty_interval)
	duty_inference=CheckButton.new(); duty_inference.text="Request AI advice"; duties_page.add_child(duty_inference)
	duty_inference.toggled.connect(func(_value: bool): controls())
	duty_enabled=CheckButton.new(); duty_enabled.text="Enable future observations"; duty_enabled.button_pressed=true; duties_page.add_child(duty_enabled)
	duty_enabled.toggled.connect(func(_value:bool): controls())
	observation_inference.toggled.connect(func(_value:bool): controls())
	duty_save=button(duties_page,"Save field duty",save_field_duty,true)
	ConsoleTheme.primary(duty_save)
	button(duties_page,"New duty",new_field_duty)
	duties_page.add_child(HSeparator.new()); label(duties_page,"RETAINED FIELD DUTIES",18)
	duty_records=VBoxContainer.new(); duties_page.add_child(duty_records)
	# Feedback is below the workspace so accepting or rejecting a command cannot
	# move the form under the user's pointer or keyboard focus.
	notice=label(col,"",16); notice.hide()
	reconcile=button(col,"Reconcile uncertain request",func():
		if online and not pending and fixture.is_empty(): commands.submit("",{},""))
	reconcile.hide()
	commands=Commands.new(); commands.api=api; add_child(commands)
	commands.feedback.connect(func(message: String, busy: bool): notice.text=message; notice.visible=not message.is_empty(); pending=busy; controls())
	commands.accepted.connect(func(_id: String): signature=""; poll())
	for h in [get_http,detail_http]:
		add_child(h); h.timeout=4; h.max_redirects=0; h.body_size_limit=4194304
	get_http.request_completed.connect(received)
	detail_http.request_completed.connect(detail_received)
	timer.wait_time=3; timer.timeout.connect(poll); add_child(timer); timer.start()
	if not fixture.is_empty():
		if FileAccess.file_exists(fixture):
			var data=JSON.parse_string(FileAccess.get_file_as_string(fixture))
			if data is Dictionary:
				snapshot=data.get("snapshot",{}); fixture_details=data.get("details",{})
		render()
	hide()

func layout_workspace() -> void:
	var canvas:Vector2=get_viewport_rect().size
	is_docked=canvas.x>=1000
	offset_left=184 if is_docked else 22
	offset_right=(offset_left+minf(1060,canvas.x-206)-canvas.x) if is_docked else -22
	offset_top=92 if is_docked else 162
	offset_bottom=-32 if is_docked else -20

func workspace_rect() -> Rect2:
	return get_global_rect()

func open() -> void:
	layout_workspace()
	guidance.hide(); tabs.show(); guidance_toggle.text="Info"
	show(); poll(); tabs.get_tab_bar().grab_focus()

func set_installation(value: Dictionary, offline: bool) -> void:
	installation_snapshot=value.duplicate(true)
	installation_offline=offline
	if policy == null: return
	policy.text="Field: "+ConnectionStatus.reason(value,"field")+" · Memory: "+ConnectionStatus.reason(value,"memory")
	if offline: policy.text="Policy last-known · "+policy.text
	controls()

func set_api(value: String) -> void:
	if pending or (commands != null and (commands.uncertain or not commands.phase.is_empty())): return
	get_http.cancel_request(); detail_http.cancel_request()
	api=value; commands.api=value
	fixture=""; fixture_details.clear(); snapshot.clear(); selected=""; signature=""
	new_field_duty()
	online=false; installation_snapshot.clear(); installation_offline=true
	set_installation({},true)
	clear(detail); label(detail,"Select evidence from this installation.")
	connection.text="Connecting to selected Core…"
	render(); poll()

static func active_run(run: Dictionary) -> bool:
	return run.get("state","") not in ["completed","failed","cancelled"]

static func ordered_runs(records: Array) -> Array:
	var active: Array=[]
	var history: Array=[]
	var seen := {}
	for run in records:
		var id:=str(run.get("input",{}).get("id",""))
		if seen.has(id): continue
		seen[id]=true
		if active_run(run): active.append(run)
		else: history.append(run)
	var newest = func(a: Dictionary,b: Dictionary): return float(a.get("updated_at",0))>float(b.get("updated_at",0))
	active.sort_custom(newest); history.sort_custom(newest)
	return active+history.slice(0,30)

static func run_message(run: Dictionary) -> String:
	var message:=str(run.get("detail",""))
	return "Cancellation acknowledged. Last recorded message: "+message if run.get("state")=="cancelled" else message

static func source_time(run: Dictionary) -> float:
	var source=run.get("snapshot",{})
	return float(run.get("source_observed_at",0) if run.get("source_observed_at") != null else 0) if not source is Dictionary or not source.has("observed_at") else float(source.observed_at)

static func watch_status(watch: Dictionary, records: Array, now: float) -> Dictionary:
	var config: Dictionary=watch.config
	var latest: Dictionary={}
	var observed := 0.0
	var busy := false
	for run in records:
		if run.get("input",{}).get("target")!=watch.id: continue
		busy=busy or active_run(run)
		observed=maxf(observed,source_time(run))
		if latest.is_empty() or float(run.get("updated_at",0))>float(latest.get("updated_at",0)): latest=run
	var overdue: bool=not config.removed and config.enabled and observed>0 and now-observed>float(config.interval_seconds)*2+480
	var schedule: String="Removed" if config.removed else "Paused" if not config.enabled else "Busy · active observation" if busy else "Awaiting durable timer tick"
	var stamp: String="Source observation time unavailable" if observed<=0 else "Source observed "+Time.get_datetime_string_from_unix_time(int(observed))+" UTC"
	return {"latest":latest,"overdue":overdue,"text":("OVERDUE · " if overdue else "")+schedule+" · every "+str(int(config.interval_seconds))+"s · "+stamp}

static func briefing_text(data: Dictionary, now: float) -> String:
	var active:=0; var failed:=0; var completed:=0; var paused:=0; var overdue:=0
	for run in data.get("runs",[]):
		if active_run(run): active+=1
		elif run.state=="failed": failed+=1
		elif run.state=="completed": completed+=1
	for watch in data.get("repositories",[]):
		if not watch.config.enabled and not watch.config.removed: paused+=1
		if watch_status(watch,data.get("runs",[]),now).overdue: overdue+=1
	return "Snapshot window (%d runs): %d active · %d completed · %d failed · %d paused watches · %d overdue. List: all active + up to 30 recent." % [data.get("runs",[]).size(),active,completed,failed,paused,overdue]

func poll() -> void:
	if not visible or not fixture.is_empty() or get_http.get_http_client_status()!=HTTPClient.STATUS_DISCONNECTED: return
	if get_http.request(api+"/v4/snapshot")!=OK: received(1,0,[],PackedByteArray())

func received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var data=JSON.parse_string(body.get_string_from_utf8()) if result==0 and code==200 else null
	online=data is Dictionary and data.get("schema_version")==4
	if online:
		snapshot=data
		connection.text="CORE CONNECTED · observed "+Time.get_datetime_string_from_unix_time(int(snapshot.get("observed_at",0)))+" UTC"
		render()
	else:
		connection.text="OFFLINE · retained results are last-known; commands unavailable"
		signature=""
	controls()

func controls() -> void:
	var uncertain:bool=commands!=null and commands.uncertain
	reconcile.visible=uncertain
	reconcile.disabled=not online or pending or not fixture.is_empty()
	for b in find_children("*","Button",true,false):
		if b.has_meta("mutation"): b.disabled=not online or pending or uncertain or not fixture.is_empty()
	var field_policy:=ConnectionStatus.capability(installation_snapshot,"field")
	var dispatch_disabled: bool=installation_offline or (not field_policy.is_empty() and not field_policy.get("enabled",false))
	launch.disabled=launch.disabled or dispatch_disabled or not snapshot.get("enabled",false) or targets.item_count==0 or targets.selected<0
	launch.tooltip_text=("Choose a configured target." if targets.selected<0 else ConnectionStatus.reason(installation_snapshot,"field") if dispatch_disabled else "Start a read-only field observation.")
	watch_save.disabled=watch_save.disabled or dispatch_disabled or not snapshot.get("enabled",false)
	watch_save.tooltip_text=("Connect to an enabled Field policy before saving a watch." if dispatch_disabled or not online else "Save the repository watch with the typed interval.")
	observation_availability.text="Synthetic fixture · commands disabled" if not fixture.is_empty() else "Offline · retained records; commands unavailable" if not online else "Outcome unknown · reconcile the previous request" if uncertain else "Request pending · waiting for Core" if pending else "Field policy: "+ConnectionStatus.reason(installation_snapshot,"field")
	var inference_allowed:=ConnectionStatus.enabled(installation_snapshot,"inference") and not installation_offline
	var observation_target: Dictionary=targets.get_item_metadata(targets.selected) if targets.selected>=0 else {}
	var editor_target: Dictionary=duty_target.get_item_metadata(duty_target.selected) if duty_target.selected>=0 else {}
	observation_inference.disabled=not inference_allowed or not observation_target.get("allow_inference",false) or not online or pending or not fixture.is_empty()
	observation_inference.tooltip_text="Target and installation must both allow AI advice; target cooldown and daily admission apply. Cost is not reported by Core."
	observation_inference.text="Request AI advice · "+("On" if observation_inference.button_pressed else "Off")+" · target admission budget"
	duty_inference.text="Request AI advice · "+("On" if duty_inference.button_pressed else "Off")
	duty_inference.tooltip_text="Optional advice request; target cooldown and daily admission apply. Cost is not reported by Core."
	duty_enabled.text="Future observations · "+("On" if duty_enabled.button_pressed else "Off")
	duty_inference.disabled=not online or pending or not fixture.is_empty() or ((not inference_allowed or not editor_target.get("allow_inference",false)) and not duty_inference.button_pressed)
	if observation_inference.disabled: observation_inference.button_pressed=false
	duty_save.disabled=duty_save.disabled or dispatch_disabled or not ConnectionStatus.enabled(installation_snapshot,"field") or not snapshot.get("enabled",false) or duty_target.selected<0
	var memory_cap:=ConnectionStatus.capability(installation_snapshot,"memory")
	memory_status.text=("Last-known policy · " if installation_offline else "")+"Memory "+("UNKNOWN" if memory_cap.is_empty() else "ENABLED" if memory_cap.get("enabled",false) else "DISABLED")+" · "+ConnectionStatus.reason(installation_snapshot,"memory")
	for action in find_children("*","Button",true,false):
		if action.has_meta("memory_review"): action.disabled=action.disabled or installation_offline or not ConnectionStatus.enabled(installation_snapshot,"memory")
		if action.has_meta("field_resume"): action.disabled=action.disabled or dispatch_disabled or not ConnectionStatus.enabled(installation_snapshot,"field") or not snapshot.get("enabled",false)

func clear(parent: Node) -> void:
	for child in parent.get_children(): parent.remove_child(child); child.queue_free()

func render() -> void:
	if not fixture.is_empty(): connection.text="SYNTHETIC BOARD FIXTURE · commands disabled"
	var comparable=snapshot.duplicate(); comparable.erase("observed_at")
	comparable["freshness_minute"]=int(Time.get_unix_time_from_system()/60)
	var next=JSON.stringify(comparable)
	if next==signature: controls(); return
	signature=next
	var focused:=get_viewport().gui_get_focus_owner()
	var focus_key: String=str(focused.get_meta("focus_key","")) if focused!=null else ""
	var chosen: String=str(targets.get_item_metadata(targets.selected).get("id","")) if targets.selected>=0 else ""
	var duty_chosen: String=str(duty_target.get_item_metadata(duty_target.selected).get("id","")) if duty_target.selected>=0 else ""
	targets.clear(); duty_target.clear()
	var seen := {}
	for build in snapshot.get("builds",[]):
		var target: Dictionary=build.manifest.target.duplicate(true)
		target.agent=build.manifest.agent
		if seen.has(target.id): continue
		seen[target.id]=true
		if str(target.id).begins_with("repo-") and target.get("kind")=="github_repository" and not watch_enabled(target.id): continue
		targets.add_item(str(build.manifest.agent)+" · "+str(target.get("repository",target.id))+(" · SYNTHETIC" if target.kind=="fixture" else " · LIVE SOURCE"))
		targets.set_item_metadata(targets.item_count-1,target)
		if target.id==chosen: targets.select(targets.item_count-1)
		if not str(target.id).begins_with("repo-"):
			duty_target.add_item(str(target.agent)+" · "+str(target.get("repository",target.id)))
			duty_target.set_item_metadata(duty_target.item_count-1,target)
			if target.id==duty_chosen: duty_target.select(duty_target.item_count-1)
	if not chosen.is_empty():
		var found:=false
		for i in targets.item_count:
			if targets.get_item_metadata(i).id==chosen: found=true
		if not found: targets.select(-1)
	if not duty_chosen.is_empty():
		var found:=false
		for i in duty_target.item_count:
			if duty_target.get_item_metadata(i).id==duty_chosen: found=true
		if not found: duty_target.select(-1); duty_target.set_meta("selection_missing",true)
	elif duty_target.get_meta("selection_missing",false): duty_target.select(-1)
	clear(runs); clear(watches); clear(memories); clear(duty_records)
	briefing.text=briefing_text(snapshot,Time.get_unix_time_from_system())
	for run in ordered_runs(snapshot.get("runs",[])):
		focus_context=str(run.input.id)
		var summary: Dictionary=run.get("summary") if run.get("summary") is Dictionary else {}
		runs.add_child(HSeparator.new())
		label(runs,str(run.input.agent)+" · "+str(run.state).to_upper(),18)
		metadata(runs,"Target",str(run.input.target))
		metadata(runs,"Record",str(run.input.id))
		label(runs,advisory_description(run,false),14)
		label(runs,run_message(run)+(" · "+str(int(summary.get("finding_count",0)))+" findings" if not summary.is_empty() else ""),14)
		var row := HFlowContainer.new(); runs.add_child(row)
		button(row,"Findings",func(): inspect(str(run.input.id)))
		if run.state not in ["completed","failed","cancelled"]:
			button(row,"Stop observation",func(): commands.submit("/v4/runs/"+str(run.input.id)+"/cancel",{},str(run.input.id)),true)
	if runs.get_child_count()==0: label(runs,"No observations recorded. No activity inferred.")
	for watch in snapshot.get("repositories",[]):
		focus_context=str(watch.id)
		var c: Dictionary=watch.config
		watches.add_child(HSeparator.new())
		label(watches,str(c.repository)+" · "+("REMOVED" if c.removed else "WATCH ENABLED" if c.enabled else "PAUSED"),18)
		var status:=watch_status(watch,snapshot.get("runs",[]),Time.get_unix_time_from_system())
		var latest: Dictionary=status.latest
		label(watches,status.text,14)
		var row := HFlowContainer.new(); watches.add_child(row)
		button(row,"Restore" if c.removed else "Pause" if c.enabled else "Resume",func(): edit_watch(c,not c.enabled,false),true)
		if not c.removed: button(row,"Remove",func(): edit_watch(c,false,true),true)
		if not latest.is_empty(): button(row,"Latest findings",func(): inspect(str(latest.input.id)))
	for duty in snapshot.get("duties",[]):
		if str(duty.id).begins_with("repo-"): continue
		var target: Dictionary={}
		for build in snapshot.get("builds",[]):
			if build.manifest.target.id==duty.target: target=build.manifest.target
		duty_records.add_child(HSeparator.new())
		label(duty_records,str(duty.get("agent","Field"))+" duty · "+str(target.get("repository",duty.target)),18)
		label(duty_records,str(duty.id)+" · "+("enabled" if duty.enabled else "paused")+" · AI advice "+("requested" if duty.get("inference",false) else "off")+" · Observation interval "+str(int(duty.get("interval_seconds",0)))+" s",14)
		label(duty_records,"Target build unavailable · inference policy unknown" if target.is_empty() else "AI cooldown "+str(int(target.get("inference_min_interval_seconds",0)))+" s · Daily admission limit "+str(target.get("daily_inference_limit",24)),14)
		focus_context=str(duty.id)
		var duty_actions:=HFlowContainer.new(); duty_records.add_child(duty_actions)
		var toggle:=button(duty_actions,"Pause duty" if duty.enabled else "Resume duty",func(): edit_duty(duty,not duty.enabled),true)
		if not duty.enabled: toggle.set_meta("field_resume",true)
		button(duty_actions,"Edit duty",func(): load_field_duty(duty))
	if watches.get_child_count()==0: label(watches,"No repositories watched. Add one above.")
	for m in snapshot.get("memory",[]).slice(0,100):
		focus_context=str(m.id)
		memories.add_child(HSeparator.new())
		label(memories,str(m.finding.summary),18)
		label(memories,str(m.agent)+" · "+str(m.target)+" · "+str(m.decision)+" · revision "+str(m.revision),14)
		var row := HFlowContainer.new(); memories.add_child(row)
		button(row,"Source",func(): inspect(str(m.source_run)))
		for decision in (["revoke"] if m.decision=="approve" else ["approve","reject"]):
			var approval:=button(row,str(decision).capitalize(),func(): commands.submit("/v4/memory/review",{"id":m.id,"revision":m.revision,"decision":decision},str(m.id),"/v4/snapshot"),true)
			approval.set_meta("memory_review",true)
	if memories.get_child_count()==0: label(memories,"No memory proposals recorded.")
	controls()
	if not focus_key.is_empty():
		for b in find_children("*","Button",true,false):
			if b.get_meta("focus_key","")==focus_key: b.grab_focus(); break

func watch_enabled(id: String) -> bool:
	for w in snapshot.get("repositories",[]):
		if w.id==id: return w.config.enabled and not w.config.removed
	return false

func start_selected() -> void:
	if launch.disabled or not online or pending or not fixture.is_empty() or targets.selected<0: return
	var target: Dictionary=targets.get_item_metadata(targets.selected)
	var id:=Crypto.new().generate_random_bytes(16).hex_encode()
	commands.submit("/v4/runs",{"id":id,"agent":target.agent,"target":target.id,"inference":observation_inference.button_pressed and not observation_inference.disabled},id)

func save_watch() -> void:
	if not snapshot.get("enabled",false): return
	var repository:=watch_input.text.strip_edges().to_lower()
	if repository.is_empty():
		notice.text="Enter a repository before saving a watch."; notice.show(); return
	var interval_seconds:=Commands.commit_integer_spinbox(interval)
	if interval_seconds<0:
		notice.text="Enter an integer interval from 30 to 86400 seconds."; notice.show(); return
	var generation:=0
	for w in snapshot.get("repositories",[]):
		if w.config.repository==repository: generation=int(w.config.generation)+1
	commands.submit("/v4/repositories",{"repository":repository,"interval_seconds":interval_seconds,"enabled":true,"removed":false,"generation":generation},repository,"/v4/repositories")

func edit_watch(config: Dictionary, enabled: bool, removed: bool) -> void:
	var value:=config.duplicate()
	value.enabled=enabled; value.removed=removed; value.generation=int(value.generation)+1
	commands.submit("/v4/repositories",value,str(value.repository),"/v4/repositories")

func inspect(id: String) -> void:
	if detail_http.get_http_client_status()!=HTTPClient.STATUS_DISCONNECTED: return
	selected=id; guidance.hide(); tabs.show(); guidance_toggle.text="Info"; tabs.current_tab=3; clear(detail); label(detail,"Loading retained evidence…")
	if not fixture.is_empty(): show_detail(fixture_details.get(id,{})); return
	if detail_http.request(api+"/v4/runs/"+id.uri_encode())!=OK: show_detail({})

func detail_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var data=JSON.parse_string(body.get_string_from_utf8()) if result==0 and code==200 else null
	show_detail(data if data is Dictionary else {})

func show_detail(run: Dictionary) -> void:
	clear(detail)
	if run.is_empty(): label(detail,"Evidence unavailable. No successful outcome inferred."); return
	label(detail,"OBSERVATION / "+str(run.input.agent),22)
	metadata(detail,"Run ID",str(run.input.id))
	metadata(detail,"Latest retained state",str(run.state))
	metadata(detail,"Summary",run_message(run))
	detail.add_child(HSeparator.new())
	var source: Dictionary=run.get("snapshot",{}) if run.get("snapshot") is Dictionary else {}
	label(detail,("NO SOURCE CAPTURED · " if source.is_empty() else "SYNTHETIC · " if source.get("data",{}).get("simulation",false) else "RETAINED SOURCE · ")+(Time.get_datetime_string_from_unix_time(int(source_time(run)))+" UTC" if source_time(run)>0 else "capture time unavailable"),14)
	var report: Dictionary=run.report if run.get("report") is Dictionary else {}
	label(detail,"FINDINGS",18)
	if report.get("findings",[]).is_empty(): label(detail,"No findings recorded. Coverage and source remain below.")
	for f in report.get("findings",[]):
		label(detail,str(f.code)+" · "+str(f.subject)+":"+str(int(f.line)),18)
		metadata(detail,"Summary",str(f.summary))
		metadata(detail,"Recommendation",str(f.recommendation))
	detail.add_child(HSeparator.new())
	label(detail,"COVERAGE & QUALIFICATION",18)
	for c in report.get("coverage",[]): label(detail,"Coverage limit: "+str(c),14)
	label(detail,"Memory: "+str(report.get("memory",{}).get("status","not recorded")),14)
	label(detail,advisory_description(run),14)
	var raw := TextEdit.new()
	raw.text=JSON.stringify(run,"  "); raw.editable=false; raw.custom_minimum_size.y=260; raw.hide()
	button(detail,"Source, revisions & full record",func(): raw.visible=not raw.visible)
	detail.add_child(raw)

static func advisory_description(run: Dictionary, full: bool = true) -> String:
	var report: Dictionary=run.get("report",{}) if run.get("report") is Dictionary else {}
	var advisory=report.get("advisory")
	var summary: Dictionary=run.get("summary",{}) if run.get("summary") is Dictionary else {}
	if advisory==null and summary.get("advisory_status") is String:
		advisory={"status":summary.advisory_status,"reason":summary.get("advisory_reason","")}
	var budget: Dictionary=run.get("inference_budget",{}) if run.get("inference_budget") is Dictionary else {}
	var result: String=""
	if advisory is Dictionary:
		result="AI advice · "+str(advisory.get("status","unverified")).to_upper()+"\n"+str(advisory.get("reason",""))
		if full:
			for key in ["summary","recommendation","model","provider","usage","calls"]:
				if advisory.has(key): result+="\n"+key.capitalize()+": "+str(advisory[key])
			if advisory.get("advice") is Dictionary:
				for key in ["summary","recommendation"]:
					if advisory.advice.has(key): result+="\n"+str(advisory.advice[key])
	elif budget.get("status")=="skipped":
		result="AI advice · SKIPPED\n"+str(budget.get("reason","Admission limit reached"))
	elif not run.get("input",{}).get("inference",false):
		result="AI advice · NOT REQUESTED"
	elif run.get("state")=="failed":
		result="AI advice · NOT RETAINED · observation failed"
	else:
		result="AI advice · NOT RECORDED · no successful model result inferred"
	if full and not budget.is_empty():
		result+="\nAdmission: "+str(budget.get("status","unknown"))+" · "+str(budget.get("used","?"))+" / "+str(budget.get("limit","?"))+" · "+str(budget.get("reason",""))
	if full and float(budget.get("next_eligible_at",0))>0:
		result+="\nNext eligible: "+Time.get_datetime_string_from_unix_time(int(budget.next_eligible_at))+" UTC · subject to admission policy"
	return result

static func duty_change(duty: Dictionary, enabled: bool) -> Dictionary:
	return {"id":duty.id,"agent":duty.agent,"target":duty.target,"interval_seconds":int(duty.interval_seconds),"generation":int(duty.generation)+1,"enabled":enabled,"inference":duty.get("inference",false)}

func edit_duty(duty: Dictionary, enabled: bool) -> void:
	if not online or pending or not fixture.is_empty(): return
	if enabled and (installation_offline or not ConnectionStatus.enabled(installation_snapshot,"field") or not snapshot.get("enabled",false)): return
	commands.submit("/v4/duties",duty_change(duty,enabled),str(duty.id),"/v4/snapshot")

func new_field_duty() -> void:
	editing_duty={}; duty_identity.editable=true; duty_identity.text=""
	duty_target.set_meta("selection_missing",false)
	if duty_target.item_count>0: duty_target.select(0)
	duty_interval.value=300; duty_inference.button_pressed=false; duty_enabled.button_pressed=true
	duty_editor_status.text="New duty · generation 0"
	duty_identity.grab_focus()

func load_field_duty(duty: Dictionary) -> void:
	editing_duty=duty.duplicate(true); duty_identity.text=str(duty.id); duty_identity.editable=false
	duty_interval.value=int(duty.interval_seconds); duty_inference.button_pressed=duty.get("inference",false); duty_enabled.button_pressed=duty.enabled
	duty_target.select(-1); duty_target.set_meta("selection_missing",true)
	for i in duty_target.item_count:
		if duty_target.get_item_metadata(i).id==duty.target: duty_target.select(i); duty_target.set_meta("selection_missing",false); break
	duty_editor_status.text="Editing retained generation "+str(duty.generation)+" · save requires this generation to remain current"
	tabs.current_tab=4; duty_interval.get_line_edit().grab_focus(); controls()

func field_duty_request() -> Dictionary:
	var id:=duty_identity.text.strip_edges()
	var identity_pattern:=RegEx.new(); identity_pattern.compile("^[A-Za-z0-9-]{1,40}$")
	if identity_pattern.search(id)==null or id.begins_with("repo-") or duty_target.selected<0:
		duty_editor_status.text="Enter a non-reserved duty identity and choose an available configured target."; return {}
	var current: Dictionary={}
	for duty in snapshot.get("duties",[]):
		if duty.id==id: current=duty
	if editing_duty.is_empty() and not current.is_empty():
		duty_editor_status.text="This duty already exists. Choose Edit duty to load its retained configuration."; return {}
	if not editing_duty.is_empty() and (current.is_empty() or current.generation!=editing_duty.generation):
		duty_editor_status.text="Duty changed since editing began. Choose Edit duty again before saving."; return {}
	var interval_seconds:=Commands.commit_integer_spinbox(duty_interval)
	if interval_seconds<0:
		duty_editor_status.text="Enter an integer interval from 30 to 86400 seconds."; return {}
	var target: Dictionary=duty_target.get_item_metadata(duty_target.selected)
	if duty_inference.button_pressed and (not ConnectionStatus.enabled(installation_snapshot,"inference") or not target.get("allow_inference",false)):
		duty_editor_status.text="AI advice is unavailable in this installation. Turn it off or wait for policy to become available."; return {}
	return {"id":id,"agent":target.agent,"target":target.id,"interval_seconds":interval_seconds,"enabled":duty_enabled.button_pressed,"inference":duty_inference.button_pressed,"generation":0 if current.is_empty() else int(current.generation)+1}

func save_field_duty() -> void:
	if duty_save.disabled or not online or pending or not fixture.is_empty(): return
	var request:=field_duty_request()
	if request.is_empty(): return
	commands.submit("/v4/duties",request,str(request.id),"/v4/snapshot")
