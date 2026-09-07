extends PanelContainer
## A native view of the existing core ledger, not a second source of agent state.
const Commands = preload("res://commands.gd")
const UI = preload("res://ui_theme.gd")
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
var notice_strip: PanelContainer
var connection: Label
var connection_badge: HBoxContainer
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

const TERMINAL := ["completed","failed","cancelled"]

static func run_tone(state: String) -> String:
	match state:
		"completed": return "verified"
		"failed": return "failed"
		"cancelled": return "idle"
		_: return "pending"

func button(parent: Node, title: String, action: Callable, mutation: bool = false, variation: String = "") -> Button:
	var b := UI.button(parent,title,func():
		if not mutation or (online and not pending and fixture.is_empty()): action.call(),variation)
	b.set_meta("focus_key",focus_context+"/"+title)
	b.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	b.custom_minimum_size=Vector2(0,40)
	if mutation: b.set_meta("mutation",true)
	return b

func page(title: String, intro: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name=title
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	tabs.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation",10)
	scroll.add_child(col)
	if not intro.is_empty(): UI.label(col,intro,"Muted")
	return col

func empty(parent: Node, text: String) -> void:
	var l := UI.label(parent,text,"Muted")
	l.add_theme_stylebox_override("normal",UI.panel_style("strip",14))

func _ready() -> void:
	theme=UI.build(large_text)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left=28; offset_right=-28; offset_top=112; offset_bottom=-135
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation",10)
	add_child(col)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation",12)
	col.add_child(heading)
	var title_col := VBoxContainer.new()
	title_col.add_theme_constant_override("separation",4)
	title_col.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading.add_child(title_col)
	UI.eyebrow(title_col,"Command · field operations")
	UI.label(title_col,"COMMAND BOARD","Title")
	var pill := PanelContainer.new()
	pill.theme_type_variation="Chip"
	pill.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	heading.add_child(pill)
	connection_badge=UI.badge(pill,"unknown","Connecting to the core…")
	connection=connection_badge.get_node("Text")
	var close := UI.button(heading,"Close",func(): hide(); closed.emit(),"GhostButton","Esc")
	close.size_flags_horizontal=Control.SIZE_SHRINK_END
	close.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size=Vector2(124,40)
	notice_strip=PanelContainer.new()
	notice_strip.theme_type_variation="Strip"
	col.add_child(notice_strip)
	var notice_row := UI.badge(notice_strip,"idle","")
	notice=notice_row.get_node("Text")
	notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	notice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	set_notice("Observations and local drafts only. Scenery and travel do not start work.","idle")
	tabs=TabContainer.new()
	tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	col.add_child(tabs)
	var operations := page("Observations","Choose a target, then explicitly request an observation. AI advice is off.")
	var launch_row := HBoxContainer.new()
	launch_row.add_theme_constant_override("separation",10)
	operations.add_child(launch_row)
	targets=OptionButton.new()
	targets.fit_to_longest_item=false
	targets.clip_text=true
	targets.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	targets.custom_minimum_size.y=40
	targets.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	launch_row.add_child(targets)
	launch=button(launch_row,"Start observation",start_selected,true,"PrimaryButton")
	launch.custom_minimum_size=Vector2(190,40)
	UI.section(operations,"Recent observations")
	runs=VBoxContainer.new(); runs.add_theme_constant_override("separation",8); operations.add_child(runs)
	var repository_page := page("Repositories","Checks up to 10 recently updated open PRs, with changed-Python analysis. Pausing or removing prevents future dispatch; stop active observations separately.")
	var form := UI.card(repository_page,"Card",8)
	UI.eyebrow(form,"Watch a GitHub repository")
	var form_row := HBoxContainer.new()
	form_row.add_theme_constant_override("separation",10)
	form.add_child(form_row)
	watch_input=LineEdit.new(); watch_input.placeholder_text="owner/repository"; watch_input.max_length=201
	watch_input.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	watch_input.custom_minimum_size.y=40
	form_row.add_child(watch_input)
	var interval_col := VBoxContainer.new()
	interval_col.add_theme_constant_override("separation",2)
	form_row.add_child(interval_col)
	interval=SpinBox.new(); interval.min_value=30; interval.max_value=86400; interval.value=300; interval.suffix="s"
	interval.custom_minimum_size=Vector2(130,40)
	interval.tooltip_text="Check interval in seconds"
	interval_col.add_child(interval)
	watch_save=button(form_row,"Watch repository",save_watch,true,"PrimaryButton")
	watch_save.custom_minimum_size=Vector2(180,40)
	UI.label(form,"Interval in seconds · minimum 30.","Muted")
	UI.section(repository_page,"Watched repositories")
	watches=VBoxContainer.new(); watches.add_theme_constant_override("separation",8); repository_page.add_child(watches)
	var memory_page := page("Memory","Approve a sourced observation for future recall. Revocation prevents later recall; history is retained. Memory cannot grant permissions.")
	UI.section(memory_page,"Reviewed observations")
	memories=VBoxContainer.new(); memories.add_theme_constant_override("separation",8); memory_page.add_child(memories)
	detail=page("Evidence","")
	empty(detail,"Select Findings or Source to load retained evidence.")
	commands=Commands.new(); commands.api=api; add_child(commands)
	commands.feedback.connect(func(message: String, busy: bool): set_notice(message,"pending" if busy else "failed" if message.begins_with("Request rejected") or message.begins_with("Could not") else "unknown" if message.begins_with("Outcome unknown") else "verified"); pending=busy; controls())
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

func set_large_text(value: bool) -> void:
	large_text=value
	theme=UI.build(large_text)
	signature=""
	render()

func set_notice(message: String, tone: String) -> void:
	UI.set_badge(notice.get_parent(),tone,message)

func set_connection(message: String, tone: String) -> void:
	UI.set_badge(connection_badge,tone,message)

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
		set_connection("Core connected · observed "+Time.get_datetime_string_from_unix_time(int(snapshot.get("observed_at",0))).replace("T"," ")+" UTC","live")
		render()
	else:
		set_connection("Offline · retained results are last-known; commands unavailable","offline")
		signature=""
	controls()

func controls() -> void:
	for b in find_children("*","Button",true,false):
		if b.has_meta("mutation"): b.disabled=not online or pending or not fixture.is_empty()
	launch.disabled=launch.disabled or not snapshot.get("enabled",false) or targets.disabled or targets.item_count==0
	watch_save.disabled=watch_save.disabled or not snapshot.get("enabled",false)

func clear(parent: Node) -> void:
	for child in parent.get_children(): parent.remove_child(child); child.queue_free()

func record_card(parent: Node, tone: String, state_text: String, title: String, subtitle: String) -> HBoxContainer:
	var card := UI.card(parent,"Card",6)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation",12)
	card.add_child(head)
	var t := UI.label(head,title,"Section")
	t.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	var badge := UI.badge(head,tone,state_text,"Secondary")
	badge.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	if not subtitle.is_empty(): UI.label(card,subtitle,"Secondary")
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",8)
	card.add_child(actions)
	return actions

func render() -> void:
	if not fixture.is_empty(): set_connection("Synthetic board fixture · commands disabled","fixture")
	var comparable=snapshot.duplicate(); comparable.erase("observed_at")
	comparable["freshness_minute"]=int(Time.get_unix_time_from_system()/60)
	var next=JSON.stringify(comparable)
	if next==signature: controls(); return
	signature=next
	var focused:=get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focus_key: String=str(focused.get_meta("focus_key","")) if focused!=null else ""
	var chosen_meta = targets.get_item_metadata(targets.selected) if targets.selected>=0 else null
	var chosen: String=str(chosen_meta.get("id","")) if chosen_meta is Dictionary else ""
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
	if targets.item_count==0:
		targets.add_item("No observation targets registered")
	targets.disabled=seen.is_empty()
	clear(runs); clear(watches); clear(memories)
	for run in snapshot.get("runs",[]).slice(0,30):
		focus_context=str(run.input.id)
		var summary: Dictionary=run.get("summary") if run.get("summary") is Dictionary else {}
		var actions := record_card(runs,run_tone(str(run.state)),str(run.state).capitalize(),str(run.input.agent)+" / "+str(run.input.target),str(run.detail)+(" · "+str(summary.get("finding_count",0))+" findings" if not summary.is_empty() else ""))
		button(actions,"Findings",func(): inspect(str(run.input.id)),false,"OutlineButton")
		if run.state not in TERMINAL:
			button(actions,"Stop observation",func(): commands.submit("/v4/runs/"+str(run.input.id)+"/cancel",{},str(run.input.id)),true,"DangerButton")
	if runs.get_child_count()==0: empty(runs,"No observations recorded. No activity inferred.")
	for watch in snapshot.get("repositories",[]):
		focus_context=str(watch.id)
		var c: Dictionary=watch.config
		var latest: Dictionary={}
		for run in snapshot.get("runs",[]):
			if run.input.target==watch.id: latest=run; break
		var last_text := "Not yet observed"
		var tone := "idle"
		if not latest.is_empty():
			last_text=str(latest.state).capitalize()+" · "+Time.get_datetime_string_from_unix_time(int(latest.updated_at)).replace("T"," ")+" UTC"
			tone=run_tone(str(latest.state))
			if Time.get_unix_time_from_system()-float(latest.updated_at)>float(c.interval_seconds)*2+480:
				last_text="STALE · "+last_text; tone="stale"
		var state_text := "REMOVED" if c.removed else "WATCH ENABLED" if c.enabled else "PAUSED"
		var state_tone := "idle" if c.removed else "live" if c.enabled else "paused"
		var actions := record_card(watches,state_tone,state_text,str(c.repository),"Every "+str(int(c.interval_seconds))+"s")
		var last := UI.badge(actions.get_parent(),tone,last_text,"Secondary")
		actions.get_parent().move_child(last,actions.get_index())
		button(actions,"Restore" if c.removed else "Pause" if c.enabled else "Resume",func(): edit_watch(c,not c.enabled,false),true)
		if not c.removed: button(actions,"Remove",func(): edit_watch(c,false,true),true,"DangerButton")
		if not latest.is_empty(): button(actions,"Latest findings",func(): inspect(str(latest.input.id)),false,"OutlineButton")
	for duty in snapshot.get("duties",[]):
		if str(duty.id).begins_with("repo-"): continue
		for b in snapshot.get("builds",[]):
			var t: Dictionary=b.manifest.target
			if t.id==duty.target and t.kind=="github":
				var actions := record_card(watches,"live" if duty.enabled else "paused","enabled" if duty.enabled else "paused","Individual PR duty · "+str(t.repository)+" #"+str(int(t.pull)),str(duty.id)+" · Manage this separate configured duty in the browser journal.")
				actions.queue_free()
	if watches.get_child_count()==0: empty(watches,"No repositories watched. Add one above.")
	for m in snapshot.get("memory",[]).slice(0,100):
		focus_context=str(m.id)
		var decision := str(m.decision)
		var actions := record_card(memories,{"approve":"verified","reject":"failed","revoke":"idle"}.get(decision,"pending"),decision.capitalize(),str(m.finding.summary),str(m.agent)+" · "+str(m.target)+" · revision "+str(m.revision))
		button(actions,"Source",func(): inspect(str(m.source_run)),false,"OutlineButton")
		for choice in (["revoke"] if m.decision=="approve" else ["approve","reject"]):
			button(actions,str(choice).capitalize(),func(): commands.submit("/v4/memory/review",{"id":m.id,"revision":m.revision,"decision":choice},str(m.id),"/v4/snapshot"),true,"PrimaryButton" if choice=="approve" else "DangerButton" if choice=="reject" else "")
	if memories.get_child_count()==0: empty(memories,"No memory proposals recorded.")
	controls()
	if not focus_key.is_empty():
		for b in find_children("*","Button",true,false):
			if b.get_meta("focus_key","")==focus_key: b.grab_focus(); break

func watch_enabled(id: String) -> bool:
	for w in snapshot.get("repositories",[]):
		if w.id==id: return w.config.enabled and not w.config.removed
	return false

func start_selected() -> void:
	if not snapshot.get("enabled",false) or targets.selected<0 or targets.disabled: return
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
	selected=id; tabs.current_tab=3; clear(detail); empty(detail,"Loading retained evidence…")
	if not fixture.is_empty(): show_detail(fixture_details.get(id,{})); return
	if detail_http.request(api+"/v4/runs/"+id.uri_encode())!=OK: show_detail({})

func detail_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var data=JSON.parse_string(body.get_string_from_utf8()) if result==0 and code==200 else null
	show_detail(data if data is Dictionary else {})

func show_detail(run: Dictionary) -> void:
	clear(detail)
	if run.is_empty():
		var l := UI.badge(detail,"unknown","Evidence unavailable. No successful outcome inferred.","Secondary")
		l.get_node("Text").autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		l.get_node("Text").size_flags_horizontal=Control.SIZE_EXPAND_FILL
		return
	var head := UI.card(detail,"Card",6)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation",12)
	head.add_child(head_row)
	UI.label(head_row,str(run.input.agent)+" / "+str(run.input.target),"Title")
	UI.badge(head_row,run_tone(str(run.state)),str(run.state).capitalize(),"Secondary").size_flags_vertical=Control.SIZE_SHRINK_CENTER
	UI.label(head,str(run.detail),"Secondary")
	var source: Dictionary=run.get("snapshot",{}) if run.get("snapshot") is Dictionary else {}
	var stamp := Time.get_datetime_string_from_unix_time(int(run.updated_at)).replace("T"," ")+" UTC"
	if source.is_empty(): UI.badge(head,"unknown","NO SOURCE CAPTURED · "+stamp,"Muted")
	elif source.get("data",{}).get("simulation",false): UI.badge(head,"fixture","SYNTHETIC · "+stamp,"Muted")
	else: UI.badge(head,"verified","RETAINED SOURCE · "+stamp,"Muted")
	var report: Dictionary=run.report if run.get("report") is Dictionary else {}
	var findings: Array=report.get("findings",[])
	UI.section(detail,"%d finding%s" % [findings.size(),"" if findings.size()==1 else "s"])
	if findings.is_empty(): empty(detail,"No findings retained for this run.")
	for f in findings:
		var card := UI.card(detail,"Inset",6)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",10)
		card.add_child(row)
		var code := PanelContainer.new()
		code.theme_type_variation="Kbd"
		code.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		row.add_child(code)
		UI.label(code,str(f.code),"Secondary",false).add_theme_color_override("font_color",UI.color("accent"))
		var subject := UI.label(row,str(f.subject)+":"+str(int(f.line)),"Section")
		subject.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		UI.label(card,str(f.summary),"")
		UI.label(card,str(f.recommendation),"Secondary")
	var coverage: Array=report.get("coverage",[])
	if not coverage.is_empty():
		UI.section(detail,"Coverage limits")
		for c in coverage:
			var b := UI.badge(detail,"stale","Coverage limit: "+str(c),"Secondary")
			b.get_node("Text").autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			b.get_node("Text").size_flags_horizontal=Control.SIZE_EXPAND_FILL
	UI.badge(detail,"idle","Memory: "+str(report.get("memory",{}).get("status","not recorded")),"Secondary")
	if report.get("advisory") is Dictionary:
		var advice := UI.card(detail,"Inset",4)
		UI.badge(advice,"unknown","AI advice · UNVERIFIED","Secondary")
		UI.label(advice,JSON.stringify(report.advisory),"Muted")
	var raw := TextEdit.new()
	raw.text=JSON.stringify(run,"  "); raw.editable=false; raw.custom_minimum_size.y=260; raw.hide()
	button(detail,"Source, revisions & full record",func(): raw.visible=not raw.visible,false,"OutlineButton")
	detail.add_child(raw)
