extends PanelContainer
## Native V2 operator journeys; Core remains the owner of work and evidence.
const ConsoleTheme=preload("res://console_theme.gd")
const Status=preload("res://connection_status.gd")
const StateView=preload("res://state.gd")
const Commands=preload("res://commands.gd")
var api:=preload("res://transport.gd").default_origin()
var fixture:=""
var snapshot:Dictionary={}
var offline:=true
var commands:Node
var history:VBoxContainer
var heading:Label
var notice:Label
var notice_slot:Control
var briefing:Label
var tabs:TabContainer
var target:OptionButton
var profile:OptionButton
var baseline:OptionButton
var candidate:OptionButton
var inference:CheckButton
var review_button:Button
var evaluation_button:Button
var duty_button:Button
var duty_id:LineEdit
var interval:SpinBox
var duties:VBoxContainer
var duty_signature:=""
var prior_visit:=0.0
var visits:=ConfigFile.new()
var other_pending:=false
var reconcile_button:Button
var briefing_toggle:Button
var briefing_scroll:ScrollContainer
var review_status:Label
var comparison_status:Label
var duty_context:Label
signal accepted(id:String)

func label(parent:Node,value:String,size:int=16) -> Label:
	var item:=Label.new()
	item.text=value; item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_font_size_override("font_size",maxi(16,size)+(3 if theme.default_font_size>=19 else 0))
	parent.add_child(item)
	return item

func button(parent:Node,value:String,action:Callable) -> Button:
	var item:=Button.new()
	item.text=value; item.custom_minimum_size.y=40
	item.pressed.connect(action); parent.add_child(item)
	return item

func form_field(parent:Node,title:String,item:Control) -> void:
	var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",16); parent.add_child(row)
	var caption:=label(row,title); caption.custom_minimum_size.x=180
	caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	item.size_flags_horizontal=Control.SIZE_EXPAND_FILL; item.size_flags_stretch_ratio=1.7
	item.custom_minimum_size.y=40; row.add_child(item)

func choice(parent:Node,title:String) -> OptionButton:
	var item:=OptionButton.new()
	item.fit_to_longest_item=false; item.clip_text=true
	form_field(parent,title,item)
	return item

func section(parent:Node,title:String) -> void:
	parent.add_child(HSeparator.new()); label(parent,title,18)

func page(title:String) -> VBoxContainer:
	var scroll:=ScrollContainer.new()
	scroll.name=title; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true; tabs.add_child(scroll)
	var column:=VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",10); scroll.add_child(column)
	return column

func _ready() -> void:
	ConsoleTheme.apply(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	commands=Commands.new(); commands.api=api; add_child(commands)
	commands.feedback.connect(func(message:String,_pending:bool): notice.text=message; notice.visible=not message.is_empty(); refresh_controls())
	commands.accepted.connect(func(id:String):
		accepted.emit(id)
		if commands.path=="/v2/runs":
			tabs.current_tab=3; history.load_latest(); history.inspect_run(id))
	var outer:=VBoxContainer.new(); outer.add_theme_constant_override("separation",10); add_child(outer)
	var header:=HBoxContainer.new(); outer.add_child(header)
	heading=label(header,"OPERATIONS",21); heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button(header,"Close [Esc]",hide)
	briefing_toggle=button(outer,"Show return briefing & help",func():
		briefing_scroll.visible=not briefing_scroll.visible
		briefing_toggle.text="Hide return briefing & help" if briefing_scroll.visible else "Show return briefing & help")
	briefing_scroll=ScrollContainer.new(); briefing_scroll.custom_minimum_size.y=110
	briefing_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	briefing_scroll.follow_focus=true; outer.add_child(briefing_scroll)
	var briefing_content:=VBoxContainer.new(); briefing_content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	briefing_scroll.add_child(briefing_content)
	briefing=label(briefing_content,"Waiting for retained Core records",14)
	label(briefing_content,"Commands require an explicit request. Travel and inspection do not start work.",14)
	briefing_scroll.hide()
	tabs=TabContainer.new(); tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL; outer.add_child(tabs)
	var review:=page("Review")
	section(review,"LOCAL REPOSITORY REVIEW")
	label(review,"Read-only checks of the selected local repository. This is separate from PR observation in Command.")
	target=choice(review,"Target reported by Core")
	profile=choice(review,"Registered build profile")
	inference=CheckButton.new(); inference.text="Explain synthetic results with one model call"; inference.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; review.add_child(inference)
	target.item_selected.connect(func(_i:int): refresh_controls())
	profile.item_selected.connect(func(_i:int): refresh_controls())
	inference.toggled.connect(func(_value:bool): refresh_controls())
	review_button=button(review,"Start review",func(): submit_run(false))
	ConsoleTheme.primary(review_button)
	section(review,"RESULTS & AVAILABILITY")
	review_status=label(review,"Waiting for Core records")
	button(review,"Inspect review history",func(): tabs.current_tab=3)
	var evaluation:=page("Compare")
	section(evaluation,"FROZEN BUILD COMPARISON")
	label(evaluation,"Compare two frozen builds on synthetic public cases. Results retain uncertainty and hard-gate failures.")
	baseline=choice(evaluation,"Baseline profile"); candidate=choice(evaluation,"Candidate profile")
	baseline.item_selected.connect(func(_i:int): refresh_controls())
	candidate.item_selected.connect(func(_i:int): refresh_controls())
	evaluation_button=button(evaluation,"Start comparison",func(): submit_run(true))
	ConsoleTheme.primary(evaluation_button)
	section(evaluation,"SYNTHETIC PUBLIC CASES")
	comparison_status=label(evaluation,"Waiting for Core records")
	button(evaluation,"Inspect comparison history",func(): tabs.current_tab=3)
	var watch:=page("Duties")
	section(watch,"RECURRING LOCAL REVIEWS")
	label(watch,"Recurring local reviews. The Review tab selects the target and build. Pause prevents future ticks; stop active work separately.")
	duty_id=LineEdit.new(); duty_id.text="repository-watch"; duty_id.max_length=100; form_field(watch,"Duty identity",duty_id)
	interval=SpinBox.new(); interval.min_value=30; interval.max_value=86400; interval.value=300; Commands.track_integer_spinbox(interval); form_field(watch,"Interval · seconds",interval)
	duty_context=label(watch,"Target and build not reported")
	duty_button=button(watch,"Save / enable recurring review",save_duty)
	ConsoleTheme.primary(duty_button)
	section(watch,"RETAINED DUTIES")
	duties=VBoxContainer.new(); duties.add_theme_constant_override("separation",12); watch.add_child(duties)
	var history_page:=page("History")
	history_page.size_flags_vertical=Control.SIZE_EXPAND_FILL
	history=preload("res://run_history.gd").new(); history.size_flags_vertical=Control.SIZE_EXPAND_FILL; history_page.add_child(history)
	history.configure(api,fixture)
	history.cancel_requested.connect(cancel_run)
	# Keep transient command feedback below the workspace so it can never move a
	# form control after a submission. The slot is always in the layout; the
	# label remains hidden until there is a message to show.
	notice_slot=VBoxContainer.new(); notice_slot.add_theme_constant_override("separation",4); outer.add_child(notice_slot)
	notice=label(notice_slot,"",14); notice.hide()
	reconcile_button=button(notice_slot,"Reconcile uncertain request",func(): commands.submit("",{},""))
	reconcile_button.hide()
	visits.load("user://starbase2-visits.cfg")
	hide()

func selected(item:OptionButton) -> String:
	return str(item.get_item_metadata(item.selected)) if item.selected>=0 else ""

func options(item:OptionButton,values:Dictionary,empty_text:String="No options available") -> void:
	var old:=selected(item)
	var signature:=JSON.stringify([values,empty_text])
	if item.get_meta("options","")==signature: return
	item.set_meta("options",signature); item.clear()
	if values.is_empty():
		item.add_item(empty_text)
		item.set_item_metadata(0,"")
		item.set_item_disabled(0,true)
		item.select(0)
		item.tooltip_text=empty_text
		return
	for id in values:
		item.add_item(values[id]); item.set_item_metadata(item.item_count-1,id)
		if id==old: item.select(item.item_count-1)
	item.tooltip_text="Choose a retained option"

static func rows(value:Variant) -> Array:
	return value if value is Array else []

func update_snapshot(data:Dictionary,disconnected:bool,blocked:bool=false) -> void:
	snapshot=data; offline=disconnected; other_pending=blocked
	var targets:Dictionary={}; var profiles:Dictionary={}
	for row in rows(data.get("targets",[])):
		if row is Dictionary and row.get("id") is String:
			targets[row.id]=str(row.get("label",row.id))+(" · synthetic" if row.get("simulation",false) else " · local repository")
	for build in rows(data.get("builds",[])):
		if build is Dictionary and build.get("manifest") is Dictionary and build.manifest.get("profile") is String:
			profiles[build.manifest.profile]=build.manifest.profile
	options(target,targets,"No targets available")
	options(profile,profiles,"No registered builds available")
	options(baseline,profiles,"No registered builds available")
	options(candidate,profiles,"No registered builds available")
	history.update_snapshot(data,disconnected)
	refresh_briefing(); refresh_controls(); render_duties()

func unresolved() -> bool:
	return commands.phase!="" or commands.uncertain

func allowed(capability:String) -> bool:
	return not offline and fixture.is_empty() and not other_pending and commands.phase.is_empty() and Status.enabled(snapshot,capability)

func refresh_controls() -> void:
	if review_button==null: return
	reconcile_button.visible=commands.uncertain
	reconcile_button.disabled=offline or not fixture.is_empty() or other_pending or commands.phase!=""
	var can_infer:=selected(target)=="sample" and Status.enabled(snapshot,"inference")
	inference.disabled=not can_infer
	inference.tooltip_text="Optional synthetic explanation · one model call. Cost is not reported by Core. Submit the review explicitly to request it."
	if not can_infer: inference.button_pressed=false
	review_button.disabled=not allowed("review") or selected(target).is_empty() or selected(profile).is_empty()
	review_button.tooltip_text=Status.reason(snapshot,"review")
	evaluation_button.disabled=not allowed("evaluation") or selected(baseline).is_empty() or selected(candidate).is_empty() or selected(baseline)==selected(candidate)
	evaluation_button.tooltip_text=("Choose two different registered profiles." if selected(baseline)==selected(candidate) else "Choose two registered profiles." if selected(baseline).is_empty() or selected(candidate).is_empty() else Status.reason(snapshot,"evaluation"))
	duty_button.disabled=not allowed("review") or selected(target).is_empty() or selected(profile).is_empty()
	var counts:Dictionary={"review":0,"evaluation":0}
	for record in StateView.operation_records(snapshot):
		var request:Dictionary=record.get("input",{}).get("request",record.get("input",{}))
		var kind:=str(request.get("kind","review"))
		if counts.has(kind): counts[kind]+=1
	var availability:="Synthetic fixture · commands disabled" if not fixture.is_empty() else "Disconnected · retained snapshot" if offline else "Pending request · wait for resolution" if other_pending or unresolved() else "Core connected"
	var target_hint:="" if not targets_empty() else "\nNo targets available. Connect to Core or retain a target before starting work."
	var profile_hint:="" if not profiles_empty() else "\nNo registered builds available. Register a build before starting work."
	review_status.text=availability+"\n"+Status.reason(snapshot,"review")+target_hint+profile_hint+"\n"+str(counts.review)+" review records in this snapshot. Inspect History for retained detail."
	comparison_status.text=availability+"\n"+Status.reason(snapshot,"evaluation")+profile_hint+"\n"+str(counts.evaluation)+" comparison records in this snapshot. No automatic promotion or certification."
	duty_context.text="Target: "+(selected(target) if not selected(target).is_empty() else "No targets available")+" · Build: "+(selected(profile) if not selected(profile).is_empty() else "No registered builds available")+"\nInterval range: 30–86400 seconds. Selection comes from Review."
	inference.text="Explain synthetic results · "+("On" if inference.button_pressed else "Off")+" · one model call"

func targets_empty() -> bool:
	return target.item_count == 0 or selected(target).is_empty()

func profiles_empty() -> bool:
	return profile.item_count == 0 or selected(profile).is_empty()

func submit_run(compare:bool) -> void:
	if (evaluation_button.disabled if compare else review_button.disabled): return
	var id:="starbase2-"+("comparison-" if compare else "review-")+Crypto.new().generate_random_bytes(12).hex_encode()
	commands.submit("/v2/runs",{"id":id,"kind":"evaluation" if compare else "review","target":"sample" if compare else selected(target),"profile":selected(baseline) if compare else selected(profile),"candidate":selected(candidate) if compare else null,"inference":false if compare else inference.button_pressed},id)

func save_duty() -> void:
	if duty_button.disabled: return
	var id:=duty_id.text.strip_edges()
	if id.is_empty(): notice.text="Enter a duty identity."; notice.show(); return
	var generation:=0
	for duty in rows(snapshot.get("duties",[])):
		if duty is Dictionary and duty.get("id")==id: generation=int(duty.get("generation",0))
	var interval_seconds:=Commands.commit_integer_spinbox(interval)
	if interval_seconds<0:
		notice.text="Enter an integer interval from 30 to 86400 seconds."; notice.show(); return
	write_duty({"id":id,"target":selected(target),"profile":selected(profile),"interval_seconds":interval_seconds,"enabled":true,"generation":generation})

func write_duty(value:Dictionary) -> void:
	if offline or not fixture.is_empty() or other_pending or commands.phase!="": return
	if value.get("enabled",true) and not Status.enabled(snapshot,"review"): return
	var request:Dictionary={
		"id":value.get("id",""),
		"target":value.get("target",""),
		"profile":value.get("profile",""),
		"interval_seconds":value.get("interval_seconds",-1),
		"enabled":value.get("enabled",false),
		"generation":value.get("generation",-1),
	}
	for key in ["id","target","profile"]:
		if not request[key] is String or str(request[key]).is_empty():
			notice.text="Duty request is missing "+key+"."; notice.show(); return
	for key in ["interval_seconds","generation"]:
		if not Commands.valid_duty_integer(request[key]):
			notice.text="Duty "+key.replace("_"," ")+" must be an integer."; notice.show(); return
	request.interval_seconds=int(request.interval_seconds)
	request.generation=int(request.generation)
	if not request.enabled is bool:
		notice.text="Duty enabled state is invalid."; notice.show(); return
	commands.submit("/v2/duties",request,str(request.id),"/v2/snapshot")

func cancel_run(id:String) -> void:
	if offline or not fixture.is_empty() or other_pending or commands.phase!="": return
	commands.submit("/v2/runs/"+id.uri_encode()+"/cancel",{},id)

func render_duties() -> void:
	var records=rows(snapshot.get("duties",[]))
	var signature:=JSON.stringify([records,offline,fixture,other_pending,commands.phase,Status.enabled(snapshot,"review")])
	if signature==duty_signature: return
	duty_signature=signature
	for child in duties.get_children(): duties.remove_child(child); child.queue_free()
	if records.is_empty(): label(duties,"No recurring local reviews recorded.")
	for row in records:
		if not row is Dictionary or not row.get("id") is String: continue
		label(duties,"%s · %s · every %ss\n%s · configuration %s"%[row.id,row.get("target","unknown"),str(int(row.interval_seconds)) if row.has("interval_seconds") else "?","Enabled · durable timer" if row.get("enabled",false) else "Paused",str(int(row.generation)) if row.has("generation") else "?"],14)
		var value:Dictionary=row.duplicate(true); value.enabled=not row.get("enabled",false)
		var toggle:=button(duties,"Resume" if value.enabled else "Pause future reviews",func(): write_duty(value))
		toggle.disabled=offline or not fixture.is_empty() or other_pending or commands.phase!="" or (value.enabled and not Status.enabled(snapshot,"review"))

func visit_key() -> String:
	return (api+"/"+str(Status.installation(snapshot).get("id","unknown"))).sha256_text()

func open() -> void:
	prior_visit=float(visits.get_value("last_opened",visit_key(),0.0))
	if not offline and fixture.is_empty() and snapshot.get("observed_at",0)>0:
		visits.set_value("last_opened",visit_key(),snapshot.observed_at)
		visits.save("user://starbase2-visits.cfg")
	refresh_briefing(); show(); review_button.grab_focus()

func refresh_briefing() -> void:
	var projected:=StateView.project(snapshot)
	var completed:=0; var failed:=0; var active:=0; var unknown:=0
	var review_records:=0; var observations:=0; var repairs:=0
	for run in projected:
		match StateView.kind(run):
			"review", "evaluation": review_records+=1
			"repair": repairs+=1
			_: observations+=1
		if run.get("state") not in ["completed","failed","cancelled"]: active+=1
		if run.get("stale",false) or (run.get("state")=="completed" and run.get("evidence")==null): unknown+=1
		if float(run.get("updated_at",0))<=prior_visit: continue
		if run.get("state")=="completed" and run.get("evidence")!=null: completed+=1
		if run.get("state")=="failed": failed+=1
	var since:="recent retained window" if prior_visit==0 else "since "+Time.get_datetime_string_from_unix_time(int(prior_visit)).replace("T"," ")+" UTC"
	var record_label:=str(projected.size())+" "+("record" if projected.size()==1 else "records")+" (all work)"
	heading.tooltip_text="Snapshot observed "+Time.get_datetime_string_from_unix_time(int(snapshot.get("observed_at",0)))+" UTC" if snapshot.get("observed_at",0)>0 else "Snapshot time unavailable"
	heading.text="WORK · "+("FIXTURE" if not fixture.is_empty() else "LAST KNOWN" if offline else "CONNECTED")
	briefing_toggle.text=("Hide" if briefing_scroll.visible else "Show")+" briefing · %d open · %s"%[active,record_label]
	briefing.text=("FIXTURE · " if not fixture.is_empty() else "LAST KNOWN · " if offline else "CORE OBSERVED · ")+"%d open · %d completed with evidence · %d failed · %d unknown\n%s; %d all retained work records (%d review/comparison · %d observations · %d repairs). Review History shows review/comparison records; repository watches and memory review are in Command."%[active,completed,failed,unknown,since,projected.size(),review_records,observations,repairs]

func configure(endpoint:String,visual_fixture:String="") -> bool:
	if unresolved() or not Commands.allowed_origin(endpoint): return false
	api=endpoint; fixture=visual_fixture; commands.api=endpoint
	snapshot={}; offline=true; duty_signature=""; prior_visit=0
	history.configure(endpoint,visual_fixture)
	update_snapshot({},true)
	return true
