extends PanelContainer
## Native V2 operator journeys; Core remains the owner of work and evidence.
const Status=preload("res://connection_status.gd")
const StateView=preload("res://state.gd")
const Commands=preload("res://commands.gd")
var api:="http://127.0.0.1:8787"
var fixture:=""
var snapshot:Dictionary={}
var offline:=true
var commands:Node
var history:VBoxContainer
var heading:Label
var notice:Label
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
signal accepted(id:String)

func label(parent:Node,value:String,size:int=16) -> Label:
	var item:=Label.new()
	item.text=value; item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_font_size_override("font_size",size)
	parent.add_child(item)
	return item

func button(parent:Node,value:String,action:Callable) -> Button:
	var item:=Button.new()
	item.text=value; item.custom_minimum_size.y=38
	item.pressed.connect(action); parent.add_child(item)
	return item

func choice(parent:Node,title:String) -> OptionButton:
	label(parent,title,14)
	var item:=OptionButton.new()
	item.fit_to_longest_item=false; item.clip_text=true
	item.custom_minimum_size.y=36; parent.add_child(item)
	return item

func page(title:String) -> VBoxContainer:
	var scroll:=ScrollContainer.new()
	scroll.name=title; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true; tabs.add_child(scroll)
	var column:=VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",10); scroll.add_child(column)
	return column

func _ready() -> void:
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
	notice=label(outer,"",14); notice.hide()
	reconcile_button=button(outer,"Reconcile uncertain request",func(): commands.submit("",{},""))
	reconcile_button.hide()
	tabs=TabContainer.new(); tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL; outer.add_child(tabs)
	var review:=page("Review")
	label(review,"Read-only checks of the selected local repository. This is separate from PR observation in Command.")
	target=choice(review,"Target reported by Core")
	profile=choice(review,"Registered build profile")
	inference=CheckButton.new(); inference.text="Explain synthetic results with one model call"; inference.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; review.add_child(inference)
	target.item_selected.connect(func(_i:int): refresh_controls())
	review_button=button(review,"Start review",func(): submit_run(false))
	var evaluation:=page("Compare")
	label(evaluation,"Compare two frozen builds on synthetic public cases. Results retain uncertainty and hard-gate failures.")
	baseline=choice(evaluation,"Baseline profile"); candidate=choice(evaluation,"Candidate profile")
	baseline.item_selected.connect(func(_i:int): refresh_controls())
	candidate.item_selected.connect(func(_i:int): refresh_controls())
	evaluation_button=button(evaluation,"Start comparison",func(): submit_run(true))
	var watch:=page("Duties")
	label(watch,"Recurring local reviews. The Review tab selects the target and build. Pause prevents future ticks; stop active work separately.")
	label(watch,"Duty identity",14); duty_id=LineEdit.new(); duty_id.text="repository-watch"; duty_id.max_length=100; watch.add_child(duty_id)
	label(watch,"Interval in seconds (30–86400)",14); interval=SpinBox.new(); interval.min_value=30; interval.max_value=86400; interval.value=300; watch.add_child(interval)
	duty_button=button(watch,"Save / enable recurring review",save_duty)
	duties=VBoxContainer.new(); duties.add_theme_constant_override("separation",12); watch.add_child(duties)
	var history_page:=page("History")
	history_page.size_flags_vertical=Control.SIZE_EXPAND_FILL
	history=preload("res://run_history.gd").new(); history.size_flags_vertical=Control.SIZE_EXPAND_FILL; history_page.add_child(history)
	history.configure(api,fixture)
	history.cancel_requested.connect(cancel_run)
	visits.load("user://starbase2-visits.cfg")
	hide()

func selected(item:OptionButton) -> String:
	return str(item.get_item_metadata(item.selected)) if item.selected>=0 else ""

func options(item:OptionButton,values:Dictionary) -> void:
	var old:=selected(item)
	var signature:=JSON.stringify(values)
	if item.get_meta("options","")==signature: return
	item.set_meta("options",signature); item.clear()
	for id in values:
		item.add_item(values[id]); item.set_item_metadata(item.item_count-1,id)
		if id==old: item.select(item.item_count-1)

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
	options(target,targets); options(profile,profiles); options(baseline,profiles); options(candidate,profiles)
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
	if not can_infer: inference.button_pressed=false
	review_button.disabled=not allowed("review") or selected(target).is_empty() or selected(profile).is_empty()
	review_button.tooltip_text=Status.reason(snapshot,"review")
	evaluation_button.disabled=not allowed("evaluation") or selected(baseline).is_empty() or selected(candidate).is_empty() or selected(baseline)==selected(candidate)
	duty_button.disabled=not allowed("review") or selected(target).is_empty() or selected(profile).is_empty()

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
	write_duty({"id":id,"target":selected(target),"profile":selected(profile),"interval_seconds":int(interval.value),"enabled":true,"generation":generation})

func write_duty(value:Dictionary) -> void:
	if offline or not fixture.is_empty() or other_pending or commands.phase!="": return
	if value.get("enabled",true) and not Status.enabled(snapshot,"review"): return
	commands.submit("/v2/duties",value,str(value.id),"/v2/snapshot")

func cancel_run(id:String) -> void:
	if offline or not fixture.is_empty() or other_pending or commands.phase!="": return
	commands.submit("/v2/runs/"+id.uri_encode()+"/cancel",{},id)

func render_duties() -> void:
	var records=rows(snapshot.get("duties",[]))
	var signature:=JSON.stringify([records,offline,fixture,other_pending,commands.phase,Status.enabled(snapshot,"review")])
	if signature==duty_signature: return
	duty_signature=signature
	for child in duties.get_children(): duties.remove_child(child); child.queue_free()
	for row in records:
		if not row is Dictionary or not row.get("id") is String: continue
		label(duties,"%s · %s · every %ss\n%s · configuration %s"%[row.id,row.get("target","unknown"),row.get("interval_seconds","?"),"Enabled · durable timer" if row.get("enabled",false) else "Paused",row.get("generation","?")],14)
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
	for run in projected:
		if run.get("state") not in ["completed","failed","cancelled"]: active+=1
		if run.get("stale",false) or (run.get("state")=="completed" and run.get("evidence")==null): unknown+=1
		if float(run.get("updated_at",0))<=prior_visit: continue
		if run.get("state")=="completed" and run.get("evidence")!=null: completed+=1
		if run.get("state")=="failed": failed+=1
	var since:="recent retained window" if prior_visit==0 else "since "+Time.get_datetime_string_from_unix_time(int(prior_visit)).replace("T"," ")+" UTC"
	briefing.text=("FIXTURE · " if not fixture.is_empty() else "LAST KNOWN · " if offline else "CORE OBSERVED · ")+"%d open · %d completed with evidence · %d failed · %d unknown\n%s; %d records in snapshot. Older work is in History; repository watches and memory review are in Command."%[active,completed,failed,unknown,since,projected.size()]

func configure(endpoint:String,visual_fixture:String="") -> bool:
	if unresolved() or not Commands.local_origin(endpoint): return false
	api=endpoint; fixture=visual_fixture; commands.api=endpoint
	snapshot={}; offline=true; duty_signature=""; prior_visit=0
	history.configure(endpoint,visual_fixture)
	update_snapshot({},true)
	return true
