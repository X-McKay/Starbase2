extends PanelContainer
## A native view of the existing core ledger, not a second source of agent state.
const ConnectionStatus = preload("res://connection_status.gd")
const Commands = preload("res://commands.gd")
var api := "http://127.0.0.1:8787"
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
var get_http := HTTPRequest.new()
var detail_http := HTTPRequest.new()
var commands: Node
var notice: Label
var connection: Label
var targets: OptionButton
var launch: Button
var watch_input: LineEdit
var interval: SpinBox
var watch_save: Button
var runs: VBoxContainer
var watches: VBoxContainer
var memories: VBoxContainer
var detail: VBoxContainer
var tabs: TabContainer
var timer := Timer.new()
signal closed

func label(parent: Node, value: String, size: int = 16) -> Label:
	var l := Label.new()
	l.text=value
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size",size+(3 if large_text else 0))
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
	b.custom_minimum_size.y=38
	b.pressed.connect(func():
		if not mutation or (online and not pending and fixture.is_empty()): action.call())
	if mutation: b.set_meta("mutation",true)
	parent.add_child(b)
	var font:=b.get_theme_font("font")
	b.custom_minimum_size.x=ceilf(font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,b.get_theme_font_size("font_size")).x)+b.get_theme_stylebox("normal").get_minimum_size().x+8
	return b

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
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout_workspace()
	get_viewport().size_changed.connect(layout_workspace)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation",8)
	add_child(col)
	var heading := HBoxContainer.new()
	col.add_child(heading)
	var title := label(heading,"COMMAND / FIELD OPERATIONS",22)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var dismiss := button(heading,"Close [Esc]",func(): hide(); closed.emit())
	dismiss.text="Close"
	dismiss.tooltip_text="Close Command · Esc"
	dismiss.custom_minimum_size.x=110
	dismiss.size_flags_horizontal=Control.SIZE_SHRINK_END
	connection=label(col,"Connecting to the core…",13)
	policy=label(col,"Installation policy not reported",13)
	briefing=label(col,"No observation window loaded",13)
	notice=label(col,"Observations and local drafts only. Scenery and travel do not start work.",14)
	tabs=TabContainer.new()
	tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	col.add_child(tabs)
	var operations := page("Observations")
	label(operations,"Choose a target, then explicitly request an observation. AI advice is off.",14)
	targets=OptionButton.new()
	targets.fit_to_longest_item=false
	targets.custom_minimum_size.y=38
	operations.add_child(targets)
	launch=button(operations,"Start observation",start_selected,true)
	runs=VBoxContainer.new(); operations.add_child(runs)
	var repository_page := page("Repositories")
	label(repository_page,"Watched GitHub repositories",21)
	label(repository_page,"Checks up to 10 recently updated open PRs, with changed-Python analysis. Pausing or removing prevents future dispatch; stop active observations separately.",14)
	watch_input=LineEdit.new(); watch_input.placeholder_text="owner/repository"; watch_input.max_length=201
	repository_page.add_child(watch_input)
	label(repository_page,"Check interval (seconds)",14)
	interval=SpinBox.new(); interval.min_value=30; interval.max_value=86400; interval.value=300
	repository_page.add_child(interval)
	watch_save=button(repository_page,"Watch repository",save_watch,true)
	watches=VBoxContainer.new(); repository_page.add_child(watches)
	var memory_page := page("Memory")
	label(memory_page,"Reviewed observations",21)
	label(memory_page,"Approve a sourced observation for future recall. Revocation prevents later recall; history is retained. Memory cannot grant permissions.",14)
	memories=VBoxContainer.new(); memory_page.add_child(memories)
	detail=page("Evidence")
	label(detail,"Select Findings or Source to load retained evidence.")
	commands=Commands.new(); commands.api=api; add_child(commands)
	commands.feedback.connect(func(message: String, busy: bool): notice.text=message; pending=busy; controls())
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
	is_docked=canvas.x>=1100
	offset_left=canvas.x-672 if is_docked else 22
	offset_right=-22
	offset_top=80 if canvas.x>=900 else 124
	offset_bottom=-80

func workspace_rect() -> Rect2:
	return get_global_rect()

func open() -> void:
	layout_workspace()
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
	for b in find_children("*","Button",true,false):
		if b.has_meta("mutation"): b.disabled=not online or pending or not fixture.is_empty()
	var field_policy:=ConnectionStatus.capability(installation_snapshot,"field")
	var dispatch_disabled: bool=installation_offline or (not field_policy.is_empty() and not field_policy.get("enabled",false))
	launch.disabled=launch.disabled or dispatch_disabled or not snapshot.get("enabled",false) or targets.item_count==0
	watch_save.disabled=watch_save.disabled or dispatch_disabled or not snapshot.get("enabled",false)

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
	targets.clear()
	var seen := {}
	for build in snapshot.get("builds",[]):
		var target: Dictionary=build.manifest.target
		if seen.has(target.id): continue
		seen[target.id]=true
		if target.get("kind")=="github_repository" and not watch_enabled(target.id): continue
		targets.add_item(str(build.manifest.agent)+" · "+str(target.get("repository",target.id))+(" · SYNTHETIC" if target.kind=="fixture" else " · LIVE SOURCE"))
		targets.set_item_metadata(targets.item_count-1,target)
		if target.id==chosen: targets.select(targets.item_count-1)
	clear(runs); clear(watches); clear(memories)
	briefing.text=briefing_text(snapshot,Time.get_unix_time_from_system())
	for run in ordered_runs(snapshot.get("runs",[])):
		focus_context=str(run.input.id)
		var summary: Dictionary=run.get("summary") if run.get("summary") is Dictionary else {}
		label(runs,str(run.input.agent)+" / "+str(run.input.target)+" · "+str(run.state),18)
		label(runs,run_message(run)+(" · "+str(int(summary.get("finding_count",0)))+" findings" if not summary.is_empty() else ""),14)
		var row := HFlowContainer.new(); runs.add_child(row)
		button(row,"Findings",func(): inspect(str(run.input.id)))
		if run.state not in ["completed","failed","cancelled"]:
			button(row,"Stop observation",func(): commands.submit("/v4/runs/"+str(run.input.id)+"/cancel",{},str(run.input.id)),true)
	if runs.get_child_count()==0: label(runs,"No observations recorded. No activity inferred.")
	for watch in snapshot.get("repositories",[]):
		focus_context=str(watch.id)
		var c: Dictionary=watch.config
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
		for b in snapshot.get("builds",[]):
			var t: Dictionary=b.manifest.target
			if t.id==duty.target and t.kind=="github":
				label(watches,"Individual PR duty · "+str(t.repository)+" #"+str(int(t.pull)),18)
				label(watches,str(duty.id)+" · "+("enabled" if duty.enabled else "paused")+" · Manage this separate configured duty in the browser journal.",14)
	if watches.get_child_count()==0: label(watches,"No repositories watched. Add one above.")
	for m in snapshot.get("memory",[]).slice(0,100):
		focus_context=str(m.id)
		label(memories,str(m.finding.summary),18)
		label(memories,str(m.agent)+" · "+str(m.target)+" · "+str(m.decision)+" · revision "+str(m.revision),14)
		var row := HFlowContainer.new(); memories.add_child(row)
		button(row,"Source",func(): inspect(str(m.source_run)))
		for decision in (["revoke"] if m.decision=="approve" else ["approve","reject"]):
			button(row,str(decision).capitalize(),func(): commands.submit("/v4/memory/review",{"id":m.id,"revision":m.revision,"decision":decision},str(m.id),"/v4/snapshot"),true)
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
	if not snapshot.get("enabled",false) or targets.selected<0: return
	var target: Dictionary=targets.get_item_metadata(targets.selected)
	var id:=Crypto.new().generate_random_bytes(16).hex_encode()
	commands.submit("/v4/runs",{"id":id,"agent":target.agent,"target":target.id,"inference":false},id)

func save_watch() -> void:
	if not snapshot.get("enabled",false): return
	var repository:=watch_input.text.strip_edges().to_lower()
	var generation:=0
	for w in snapshot.get("repositories",[]):
		if w.config.repository==repository: generation=int(w.config.generation)+1
	commands.submit("/v4/repositories",{"repository":repository,"interval_seconds":int(interval.value),"enabled":true,"removed":false,"generation":generation},repository,"/v4/repositories")

func edit_watch(config: Dictionary, enabled: bool, removed: bool) -> void:
	var value:=config.duplicate()
	value.enabled=enabled; value.removed=removed; value.generation=int(value.generation)+1
	commands.submit("/v4/repositories",value,str(value.repository),"/v4/repositories")

func inspect(id: String) -> void:
	if detail_http.get_http_client_status()!=HTTPClient.STATUS_DISCONNECTED: return
	selected=id; tabs.current_tab=3; clear(detail); label(detail,"Loading retained evidence…")
	if not fixture.is_empty(): show_detail(fixture_details.get(id,{})); return
	if detail_http.request(api+"/v4/runs/"+id.uri_encode())!=OK: show_detail({})

func detail_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var data=JSON.parse_string(body.get_string_from_utf8()) if result==0 and code==200 else null
	show_detail(data if data is Dictionary else {})

func show_detail(run: Dictionary) -> void:
	clear(detail)
	if run.is_empty(): label(detail,"Evidence unavailable. No successful outcome inferred."); return
	label(detail,str(run.input.agent)+" / "+str(run.state),22)
	label(detail,run_message(run))
	var source: Dictionary=run.get("snapshot",{}) if run.get("snapshot") is Dictionary else {}
	label(detail,("NO SOURCE CAPTURED · " if source.is_empty() else "SYNTHETIC · " if source.get("data",{}).get("simulation",false) else "RETAINED SOURCE · ")+(Time.get_datetime_string_from_unix_time(int(source_time(run)))+" UTC" if source_time(run)>0 else "capture time unavailable"),14)
	var report: Dictionary=run.report if run.get("report") is Dictionary else {}
	for f in report.get("findings",[]):
		label(detail,str(f.code)+" · "+str(f.subject)+":"+str(int(f.line)),18)
		label(detail,str(f.summary)+"\n"+str(f.recommendation))
	for c in report.get("coverage",[]): label(detail,"Coverage limit: "+str(c),14)
	label(detail,"Memory: "+str(report.get("memory",{}).get("status","not recorded")),14)
	if report.get("advisory") is Dictionary: label(detail,"AI advice · UNVERIFIED\n"+JSON.stringify(report.advisory),14)
	var raw := TextEdit.new()
	raw.text=JSON.stringify(run,"  "); raw.editable=false; raw.custom_minimum_size.y=260; raw.hide()
	button(detail,"Source, revisions & full record",func(): raw.visible=not raw.visible)
	detail.add_child(raw)
