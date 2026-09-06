extends PanelContainer
## A native view of the existing core ledger, not a second source of agent state.
const Commands = preload("res://commands.gd")
var api := "http://127.0.0.1:8787"
var fixture := ""
var snapshot: Dictionary = {}
var fixture_details: Dictionary = {}
var online := false
var pending := false
var large_text := false
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
	b.set_meta("focus_key",focus_context+"/"+title)
	b.custom_minimum_size.y=38
	b.pressed.connect(func():
		if not mutation or (online and not pending and fixture.is_empty()): action.call())
	if mutation: b.set_meta("mutation",true)
	parent.add_child(b)
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
	offset_left=28; offset_right=-28; offset_top=112; offset_bottom=-135
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation",8)
	add_child(col)
	var heading := HBoxContainer.new()
	col.add_child(heading)
	var title := label(heading,"COMMAND / FIELD OPERATIONS",22)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button(heading,"Close [Esc]",func(): hide(); closed.emit())
	connection=label(col,"Connecting to the core…",13)
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

func open() -> void:
	show(); poll(); tabs.get_tab_bar().grab_focus()

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
	launch.disabled=launch.disabled or not snapshot.get("enabled",false) or targets.item_count==0
	watch_save.disabled=watch_save.disabled or not snapshot.get("enabled",false)

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
	for run in snapshot.get("runs",[]).slice(0,30):
		focus_context=str(run.input.id)
		var summary: Dictionary=run.get("summary") if run.get("summary") is Dictionary else {}
		label(runs,str(run.input.agent)+" / "+str(run.input.target)+" · "+str(run.state),18)
		label(runs,str(run.detail)+(" · "+str(summary.get("finding_count",0))+" findings" if not summary.is_empty() else ""),14)
		var row := HBoxContainer.new(); runs.add_child(row)
		button(row,"Findings",func(): inspect(str(run.input.id)))
		if run.state not in ["completed","failed","cancelled"]:
			button(row,"Stop observation",func(): commands.submit("/v4/runs/"+str(run.input.id)+"/cancel",{},str(run.input.id)),true)
	if runs.get_child_count()==0: label(runs,"No observations recorded. No activity inferred.")
	for watch in snapshot.get("repositories",[]):
		focus_context=str(watch.id)
		var c: Dictionary=watch.config
		label(watches,str(c.repository)+" · "+("REMOVED" if c.removed else "WATCH ENABLED" if c.enabled else "PAUSED"),18)
		var latest: Dictionary={}
		for run in snapshot.get("runs",[]):
			if run.input.target==watch.id: latest=run; break
		var last_text := "Not yet observed"
		if not latest.is_empty():
			last_text=str(latest.state)+" · "+Time.get_datetime_string_from_unix_time(int(latest.updated_at))+" UTC"
			if Time.get_unix_time_from_system()-float(latest.updated_at)>float(c.interval_seconds)*2+480: last_text="STALE · "+last_text
		label(watches,"Every "+str(int(c.interval_seconds))+"s · "+last_text,14)
		var row := HBoxContainer.new(); watches.add_child(row)
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
		var row := HBoxContainer.new(); memories.add_child(row)
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
	label(detail,str(run.detail))
	var source: Dictionary=run.get("snapshot",{}) if run.get("snapshot") is Dictionary else {}
	label(detail,("NO SOURCE CAPTURED · " if source.is_empty() else "SYNTHETIC · " if source.get("data",{}).get("simulation",false) else "RETAINED SOURCE · ")+Time.get_datetime_string_from_unix_time(int(run.updated_at))+" UTC",14)
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
