extends VBoxContainer
## Local practice only: Core owns duty CAS, curriculum, trials and incumbent adoption.
const Commands=preload("res://learning_commands.gd")
const Transport=preload("res://transport.gd")
const ThemeStyle=preload("res://console_theme.gd")
const BUDGET:={"proposal_requests":1,"proposal_tokens":32768,"trial_requests":24,"trial_tokens":384000}
var api:=Transport.default_origin()
var fixture:=""
var snapshot:Dictionary={}
var builds:Array=[]
var online:=false
var unsupported:=false
var received_at:=0
var pending:=false
var epoch:=0
var callback:Callable
var build_callback:Callable
var http=Transport.create()
var build_http=Transport.create()
var duty_commands:Node
var stop_commands:Node
var cancel_commands:Node
var selected:=""
var stop_after_reconcile:=false
var timer:=Timer.new()
var notice:Label
var stop_button:Button
var cancel_button:Button
var reconcile_button:Button
var feedback:Label
var feedback_row:HBoxContainer
var picker:OptionButton
var baseline:OptionButton
var enable_button:Button
var rebase_button:Button
var baseline_heading:Label
var replacement_detail:Label
var duty_summary:Label
var baseline_detail:Label
var cycle_summary:Label
var trials:Label
var raw:TextEdit
var raw_toggle:Button
var scroll:ScrollContainer
var signature:=""
var build_signature:=""

func label(parent:Node,text:String,size:int=16,exact:bool=false) -> Label:
	var item:=Label.new();item.text=text;item.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	item.autowrap_mode=TextServer.AUTOWRAP_ARBITRARY if exact else TextServer.AUTOWRAP_WORD_SMART
	item.set_meta("base_font",size);item.add_theme_font_size_override("font_size",size+(3 if get_theme_default_font_size()>=19 else 0));parent.add_child(item);return item
func button(parent:Node,text:String,action:Callable) -> Button:
	var item:=Button.new();item.text=text;item.custom_minimum_size.y=40;item.pressed.connect(action);parent.add_child(item);return item
func _ready() -> void:
	size_flags_vertical=Control.SIZE_EXPAND_FILL;add_theme_constant_override("separation",10)
	for property in ["duty_commands","stop_commands","cancel_commands"]:
		var command:=Commands.new();command.api=api;add_child(command);set(property,command)
		command.feedback.connect(func(message:String,_pending:bool):feedback.text=message;refresh_controls())
		command.accepted.connect(func(_id:String):accepted(command))
	var top:=HBoxContainer.new();add_child(top)
	notice=label(top,"LOCAL PRACTICE · not observed",14)
	stop_button=button(top,"Stop practice duty",stop_future)
	stop_button.tooltip_text="Block further dispatch in active and future cycles. Already-started calls must still be reconciled and accounted."
	cancel_button=button(top,"Cancel cycle",cancel_cycle)
	var selection:=HBoxContainer.new();add_child(selection)
	picker=OptionButton.new();picker.fit_to_longest_item=false;picker.clip_text=true;picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL;picker.custom_minimum_size.y=40;selection.add_child(picker)
	picker.item_selected.connect(func(index:int):selected=str(picker.get_item_metadata(index));render_cycle();refresh_controls())
	button(selection,"Refresh",func():poll(true))
	scroll=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.follow_focus=true;scroll.focus_mode=Control.FOCUS_ALL;add_child(scroll)
	scroll.gui_input.connect(scroll_keys)
	var content:=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content.add_theme_constant_override("separation",14);scroll.add_child(content)
	duty_summary=label(content,"Practice duty not configured",21)
	label(content,"One Trainer proposal → eight public trials → independent Core decision. Practice adoption grants no operational qualification or XP.",16)
	baseline_heading=label(content,"Registered initial baseline",14)
	baseline=OptionButton.new();baseline.fit_to_longest_item=false;baseline.clip_text=true;baseline.custom_minimum_size.y=40;content.add_child(baseline)
	baseline.item_selected.connect(func(_index:int):refresh_controls())
	replacement_detail=label(content,"",14,true)
	rebase_button=button(content,"Change stopped baseline",rebase_duty)
	baseline_detail=label(content,"No initial baseline reported.",14,true)
	enable_button=button(content,"Enable practice duty",enable_duty);ThemeStyle.primary(enable_button)
	cycle_summary=label(content,"No learning cycle selected.",17,true)
	label(content,"PAIRED TRIALS / RETAINED OUTCOMES",14)
	trials=label(content,"No trial records reported.",15,true)
	raw_toggle=button(content,"Show exact practice records",func():raw.visible=not raw.visible;raw_toggle.text="Hide exact practice records" if raw.visible else "Show exact practice records")
	raw=TextEdit.new();raw.editable=false;raw.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;raw.custom_minimum_size.y=260;content.add_child(raw);raw.hide()
	feedback_row=HBoxContainer.new();add_child(feedback_row);feedback=label(feedback_row,"",14);feedback.max_lines_visible=2;feedback.clip_text=true;feedback.custom_minimum_size.y=42
	reconcile_button=button(feedback_row,"Reconcile",reconcile)
	for request in [http,build_http]:add_child(request);request.timeout=8;request.max_redirects=0;request.body_size_limit=2097152
	add_child(timer);timer.wait_time=3;timer.timeout.connect(func():refresh_controls();render_cycle();poll());timer.start()
	visibility_changed.connect(func():
		if is_visible_in_tree():poll())
	render()
func unresolved() -> bool:
	for command in [duty_commands,stop_commands,cancel_commands]:
		if command!=null and (command.phase!="" or command.uncertain):return true
	return false
func configure(endpoint:String,visual_fixture:String="") -> void:
	if unresolved():return
	epoch+=1;http.cancel_request();build_http.cancel_request();pending=false
	api=endpoint;fixture=visual_fixture;snapshot={};builds=[];selected="";signature="";build_signature="";received_at=0;online=false;unsupported=false
	for command in [duty_commands,stop_commands,cancel_commands]:command.api=endpoint
	render()
func poll(force:bool=false) -> void:
	if pending or not fixture.is_empty() or not is_visible_in_tree() or (unsupported and not force):return
	pending=true
	if callback.is_valid() and http.request_completed.is_connected(callback):http.request_completed.disconnect(callback)
	callback=received.bind(epoch);http.request_completed.connect(callback)
	if http.request(api+"/v6/snapshot")!=OK:received(1,0,[],PackedByteArray(),epoch)
func received(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray,request_epoch:int) -> void:
	if request_epoch!=epoch:return
	pending=false;online=false;unsupported=code==404
	var value=Commands.decode(body) if result==HTTPRequest.RESULT_SUCCESS and code==200 else null
	if valid_snapshot(value):snapshot=value;online=true;received_at=Time.get_ticks_msec()
	if online and (control().is_empty() or control().get("duty",{}).get("enabled")==false) and build_http.get_http_client_status()==HTTPClient.STATUS_DISCONNECTED:
		if build_callback.is_valid() and build_http.request_completed.is_connected(build_callback):build_http.request_completed.disconnect(build_callback)
		build_callback=received_builds.bind(epoch);build_http.request_completed.connect(build_callback)
		build_http.request(api+"/v5/snapshot")
	render()
func received_builds(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray,request_epoch:int) -> void:
	if request_epoch!=epoch:return
	var value=Commands.decode(body) if result==HTTPRequest.RESULT_SUCCESS and code==200 else null
	if value is Dictionary and value.get("builds") is Array:builds=value.builds;render()
static func valid_snapshot(value:Variant) -> bool:
	if not (value is Dictionary and value.get("schema_version")==6 and value.get("enabled") is bool and value.get("cycles") is Array and value.has("control")):return false
	var c=value.get("control")
	return c==null or (c is Dictionary and c.get("duty") is Dictionary and c.get("practice_incumbent") is Dictionary and c.practice_incumbent.get("build") is String)
func apply_fixture(value:Dictionary,registered:Array=[]) -> void:
	if fixture.is_empty():return
	if valid_snapshot(value):snapshot=value;builds=registered;online=true;received_at=Time.get_ticks_msec()
	render()
func control() -> Dictionary:return snapshot.get("control") if snapshot.get("control") is Dictionary else {}
func fresh() -> bool:return online and received_at>0 and Time.get_ticks_msec()-received_at<=30000
func cycles() -> Array:
	return snapshot.get("cycles",[]).filter(func(value):return value is Dictionary and value.get("id") is String and value.get("state") is String)
func current() -> Dictionary:
	for value in cycles():
		if value.id==selected:return value
	return {}
func chosen_baseline() -> String:
	var value:=control()
	if value.get("practice_incumbent") is Dictionary:return str(value.practice_incumbent.get("build",""))
	return selected_registered_build()
func selected_registered_build() -> String:
	return str(baseline.get_item_metadata(baseline.selected)) if baseline.selected>=0 and baseline.get_item_metadata(baseline.selected)!=null else ""
func render() -> void:
	if picker==null:return
	var rows:=cycles();var ids:Array=rows.map(func(value):return str(value.id));var next:=JSON.stringify(rows.map(func(value):return [value.id,value.state]))
	if next!=signature:
		signature=next;picker.clear()
		for value in rows:picker.add_item(str(value.state).capitalize()+" · "+str(value.id));picker.set_item_metadata(picker.item_count-1,value.id)
		if rows.is_empty():picker.add_item("No retained learning cycles");picker.set_item_disabled(0,true);picker.set_item_metadata(0,"")
	if selected not in ids:selected=str(ids[0]) if not ids.is_empty() else ""
	if not selected.is_empty():picker.select(ids.find(selected))
	picker.tooltip_text=selected
	var usable:Array=builds.filter(func(value):return value is Dictionary and value.get("digest") is String and value.get("manifest") is Dictionary and value.manifest.get("profile")=="joint-readiness-v1")
	next=JSON.stringify(usable)
	if next!=build_signature:
		build_signature=next;var previous:=chosen_baseline();baseline.clear()
		for value in usable:
			baseline.add_item(("Model inference" if value.manifest.get("inference")==true else "Scripted control")+" · "+str(value.digest).left(18));baseline.set_item_metadata(baseline.item_count-1,value.digest)
			if value.digest==previous:baseline.select(baseline.item_count-1)
		if usable.is_empty():baseline.add_item("No registered initial baseline");baseline.set_item_disabled(0,true);baseline.set_item_metadata(0,"")
	render_cycle();refresh_controls()
func refresh_controls() -> void:
	if feedback==null:return
	var c:=control();var duty:Dictionary=c.get("duty") if c.get("duty") is Dictionary else {}
	var local:=fixture.is_empty() and Commands.allowed_origin(api)
	notice.text="LOCAL PRACTICE · "+("preview fixture" if not fixture.is_empty() else "unavailable on this Core" if unsupported else "connected" if fresh() else "last-known / unknown")
	var omitted:int=snapshot.get("cycles",[]).size()-cycles().size()
	if omitted>0:notice.text+=" · incomplete cycle coverage"
	duty_summary.text="Practice duty not configured" if duty.is_empty() else "Practice duty "+("enabled" if duty.get("enabled")==true else "stopped")+" · %s / %s cycles admitted" % [str(c.get("admitted_cycles","?")),str(duty.get("max_cycles","?"))]
	var budget:Dictionary=duty.get("budget") if duty.get("budget") is Dictionary else BUDGET
	baseline_detail.text="Practice baseline  "+(chosen_baseline() if not chosen_baseline().is_empty() else "not reported")
	baseline_detail.text+="\nLimit  %s cycles · %ss cooldown\nPer cycle  1 proposal + 8 trials · up to %s reserved tokens" % [str(duty.get("max_cycles",2)),str(duty.get("cooldown_seconds",60)),str(int(budget.get("proposal_tokens",0))+8*int(budget.get("trial_tokens",0)))]
	if not c.is_empty():baseline_detail.text+="\nDuty generation  "+str(duty.get("generation","unknown"))+" · Practice incumbent generation  "+str(c.get("practice_incumbent",{}).get("generation","unknown"))
	var stopped:bool=not c.is_empty() and duty.get("enabled")==false
	baseline.visible=c.is_empty() or stopped;baseline.disabled=unresolved()
	baseline_heading.visible=baseline.visible;baseline_heading.text="Registered replacement baseline" if stopped else "Registered initial baseline"
	replacement_detail.visible=baseline.visible;replacement_detail.text="Selected build  "+selected_registered_build()
	if stopped:replacement_detail.text+="\nChanging the baseline keeps duty stopped. Existing cycle records remain unchanged."
	rebase_button.visible=stopped
	var active:bool=cycles().any(func(value):return value.state not in ["completed","failed","cancelled"])
	rebase_button.disabled=not stopped or not local or not fresh() or unresolved() or active or selected_registered_build().is_empty() or selected_registered_build()==chosen_baseline()
	if stopped and active:replacement_detail.text+="\nWait for active cycles to finish or cancel them before changing the baseline."
	enable_button.disabled=not local or not fresh() or snapshot.get("enabled")!=true or unresolved() or chosen_baseline().is_empty() or duty.get("enabled")==true
	stop_button.disabled=not local or not fresh() or stop_commands.phase!="" or stop_commands.uncertain or (duty.get("enabled")!=true and not duty_commands.uncertain and duty_commands.phase=="")
	var cycle:=current();cancel_button.disabled=not local or selected.is_empty() or cycle.get("state") in ["completed","failed","cancelled"] or cancel_commands.phase!="" or cancel_commands.uncertain
	reconcile_button.visible=duty_commands.uncertain or stop_commands.uncertain or cancel_commands.uncertain
	reconcile_button.disabled=duty_commands.phase!="" or stop_commands.phase!="" or cancel_commands.phase!=""
	feedback_row.visible=not feedback.text.is_empty() or unresolved();feedback.tooltip_text=feedback.text
func make_duty(enabled:bool) -> Dictionary:
	var c:=control();var old:Dictionary=c.get("duty") if c.get("duty") is Dictionary else {}
	if not old.is_empty() and not Commands.valid_duty_integer(old.get("generation")):return {}
	var allowance:Dictionary=old.get("budget",BUDGET)
	var normalized:Dictionary={}
	for key in BUDGET:
		if not Commands.valid_duty_integer(allowance.get(key)):return {}
		normalized[key]=int(allowance[key])
	for key in ["max_cycles","cooldown_seconds"]:
		if not Commands.valid_duty_integer(old.get(key,2 if key=="max_cycles" else 60)):return {}
	return {"id":"readiness-practice","generation":int(old.generation)+1 if not old.is_empty() else 0,"enabled":enabled,"baseline":chosen_baseline(),"max_cycles":int(old.get("max_cycles",2)),"cooldown_seconds":int(old.get("cooldown_seconds",60)),"budget":normalized}
func enable_duty() -> void:
	refresh_controls()
	if enable_button.disabled:return
	var request:=make_duty(true)
	if request.is_empty():feedback.text="Current duty generation is unknown. Refresh before changing it.";return
	duty_commands.intention="enable"
	duty_commands.receipt={};duty_commands.submit("/v6/duty",request,"readiness-practice","/v6/snapshot")
func rebase_duty() -> void:
	refresh_controls()
	if rebase_button.disabled:return
	var request:=make_duty(false)
	if request.is_empty():feedback.text="Current duty generation is unknown. Refresh before changing baseline.";return
	request.baseline=selected_registered_build()
	duty_commands.intention="rebase";duty_commands.receipt={};duty_commands.submit("/v6/duty",request,"readiness-practice","/v6/snapshot")
func stop_future() -> void:
	refresh_controls()
	if stop_button.disabled:return
	if control().is_empty() and (duty_commands.uncertain or duty_commands.phase!=""):
		stop_after_reconcile=true
		if duty_commands.uncertain:duty_commands.submit("",{},"")
		return
	var request:=make_duty(false)
	if request.is_empty():feedback.text="Current duty generation is unknown. Refresh before stopping.";return
	stop_commands.receipt={};stop_commands.submit("/v6/duty",request,"readiness-practice","/v6/snapshot")
func cancel_cycle() -> void:
	refresh_controls()
	if cancel_button.disabled:return
	cancel_commands.receipt={};cancel_commands.submit("/v6/cycles/"+selected.uri_encode()+"/cancel",{},selected)
func reconcile() -> void:
	for command in [duty_commands,stop_commands,cancel_commands]:
		if command.uncertain:command.submit("",{},"")
func accepted(command:Node) -> void:
	epoch+=1;http.cancel_request();build_http.cancel_request();pending=false
	var value:Dictionary=command.receipt
	if command in [duty_commands,stop_commands]:snapshot["control"]=value.get("control",value)
	else:
		for index in snapshot.get("cycles",[]).size():
			if snapshot.cycles[index].id==command.run_id:snapshot.cycles[index]=value;break
	render();poll(true)
	if stop_after_reconcile and command==duty_commands:stop_after_reconcile=false;stop_future.call_deferred()
func render_cycle() -> void:
	var value:=current()
	if value.is_empty():cycle_summary.text="No learning cycle selected.";trials.text="No trial records reported.";raw.text=JSON.stringify({"control":control(),"cycle":null},"  ");return
	var summary:Dictionary=value.get("summary") if value.get("summary") is Dictionary else {}
	var base:Dictionary=value.get("baseline") if value.get("baseline") is Dictionary else {}
	var candidate:Dictionary=value.get("candidate") if value.get("candidate") is Dictionary else {}
	var proposal:Dictionary=value.get("proposal") if value.get("proposal") is Dictionary else {}
	cycle_summary.text=("LAST KNOWN · " if not fresh() else "")+"Cycle "+str(value.state).capitalize()+"\n"+str(summary.get("outcome","No final practice decision recorded"))+"\nCycle  "+str(value.id)+"\nBaseline  "+str(base.get("digest","not reported"))+"\nCandidate  "+str(candidate.get("digest","not recorded"))+"\nTrainer proposal  "+str(proposal.get("state","not reported"))
	if summary.get("outcome")=="practice-adopted":cycle_summary.text+="\nAdopted for local practice only · no operational qualification or XP."
	if summary.get("reason")!=null:cycle_summary.text+="\n"+str(summary.reason)
	if summary.has("baseline_passes"):cycle_summary.text+="\nBaseline %s / %s · Candidate %s / %s · paired regression %s" % [str(summary.baseline_passes),str(summary.get("pairs","?")),str(summary.get("candidate_passes","?")),str(summary.get("pairs","?")),str(summary.get("paired_regression","unknown"))]
	if summary.has("hard_gates"):cycle_summary.text+="\nHard gates  "+JSON.stringify(summary.hard_gates)
	var lines:PackedStringArray=[]
	for trial in value.get("trials",[]):
		if not trial is Dictionary:continue
		var outcome:="Outcome not reported"
		for result in summary.get("trials",[]):
			if result is Dictionary and result.get("mission_id")==trial.get("mission_id"):outcome=str(result.get("outcome","unknown"))+" · "+str(result.get("tokens_accounted","unknown"))+" tokens accounted"
		lines.append("%s · %s · %s\nMission  %s\n%s" % [str(trial.get("slot","unknown slot")),str(trial.get("arm","unknown arm")),str(trial.get("scenario","unknown scenario")),str(trial.get("mission_id","not reported")),outcome])
	trials.text="\n\n".join(lines) if not lines.is_empty() else "No trial records reported."
	var text:=JSON.stringify({"control":control(),"cycle":value},"  ")
	if raw.text!=text:raw.text=text
func scroll_keys(event:InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:return
	match event.keycode:
		KEY_PAGEDOWN:scroll.scroll_vertical+=maxi(40,int(scroll.size.y)-32)
		KEY_PAGEUP:scroll.scroll_vertical-=maxi(40,int(scroll.size.y)-32)
		KEY_HOME:scroll.scroll_vertical=0
		KEY_END:scroll.scroll_vertical=int(scroll.get_v_scroll_bar().max_value)
		_:return
	scroll.accept_event()
