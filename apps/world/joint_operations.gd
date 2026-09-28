extends VBoxContainer
## V5 mission bridge. Core owns lifecycle; local commands reconcile exact intent.
const View=preload("res://joint_state.gd")
const Transport=preload("res://transport.gd")
const JointCommands=preload("res://joint_commands.gd")
const ConsoleTheme=preload("res://console_theme.gd")
const SCENARIOS:=["route-mismatch","healthy","persistent-dependency","listening-but-broken"]
var launch_commands:Node
var cancel_commands:Node
var stop_button:Button
var reconcile_button:Button
var action_notice:Label
var launch_content:VBoxContainer
var build_picker:OptionButton
var scenario_picker:OptionButton
var requests:SpinBox
var tokens:SpinBox
var launch_button:Button
var launch_context:Label
var launch_mode:=false
var draft_id:=""
var build_signature:=""
var mission_banner:Label
var budget_strip:Label
var handoff_cards:VBoxContainer
var handoff_signature:=""
var ledger_toggle:CheckButton
var command_detail:Label
var budget_heading:Label
var feedback_row:HBoxContainer
var api:=Transport.default_origin()
var fixture:=""
var snapshot:Dictionary={}
var selected:=""
var connection_state:="unknown"
var pending:=false
var epoch:=0
var callback:Callable
var http=Transport.create()
var timer:=Timer.new()
var notice:Label
var choose:OptionButton
var view_choice:OptionButton
var review_mode:=false
var review_selected:=""
var mission_content:VBoxContainer
var review_content:VBoxContainer
var review_note:Label
var review_summary:Label
var review_sources:Label
var review_investigation:Label
var refresh_button:Button
var summary:Label
var budget:Label
var members:RichTextLabel
var decision:Label
var source:TextEdit
var source_toggle:Button
var scroll:ScrollContainer
var row_signature:=""
var invalid_rows:=0

func label(parent:Node,value:String,size:int=16) -> Label:
	var item:=Label.new();item.text=value
	item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	item.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	item.set_meta("base_font",size)
	item.add_theme_font_size_override("font_size",size+(3 if get_theme_default_font_size()>=19 else 0))
	parent.add_child(item)
	return item

func _ready() -> void:
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",10)
	launch_commands=JointCommands.new();launch_commands.api=api;add_child(launch_commands)
	cancel_commands=JointCommands.new();cancel_commands.api=api;add_child(cancel_commands)
	for command in [launch_commands,cancel_commands]:
		command.feedback.connect(func(message:String,_pending:bool):
			if action_notice!=null:action_notice.text=message;refresh_actions())
		command.accepted.connect(func(id:String):accept_record(command,id))
	var status_row:=HBoxContainer.new();add_child(status_row)
	notice=label(status_row,"Joint operations have not been observed.",14)
	stop_button=Button.new();stop_button.text="Cancel selected";stop_button.custom_minimum_size.y=40
	stop_button.pressed.connect(cancel_selected);status_row.add_child(stop_button)
	var row:=HBoxContainer.new();add_child(row)
	view_choice=OptionButton.new();view_choice.add_item("Missions");view_choice.add_item("Trainer reviews");view_choice.add_item("Launch mission")
	view_choice.custom_minimum_size=Vector2(160,40);view_choice.fit_to_longest_item=false
	view_choice.item_selected.connect(select_view)
	row.add_child(view_choice)
	choose=OptionButton.new();choose.fit_to_longest_item=false;choose.clip_text=true
	choose.size_flags_horizontal=Control.SIZE_EXPAND_FILL;choose.custom_minimum_size.y=40
	choose.item_selected.connect(func(index:int):
		if review_mode:review_selected=str(choose.get_item_metadata(index))
		else:selected=str(choose.get_item_metadata(index))
		render_detail())
	row.add_child(choose)
	refresh_button=Button.new();refresh_button.text="Refresh";refresh_button.custom_minimum_size.y=40
	refresh_button.pressed.connect(func():poll(true));row.add_child(refresh_button)
	scroll=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.follow_focus=true;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroll)
	scroll.focus_mode=Control.FOCUS_ALL
	scroll.tooltip_text="Keyboard details: Page Up / Page Down, Home / End"
	scroll.gui_input.connect(scroll_keys)
	var content:=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content.add_theme_constant_override("separation",16);scroll.add_child(content)
	mission_content=VBoxContainer.new();mission_content.add_theme_constant_override("separation",16);content.add_child(mission_content)
	var banner:=PanelContainer.new();banner.add_theme_stylebox_override("panel",ConsoleTheme.box(Color("24201ee0"),Color("ff653f88"),10));mission_content.add_child(banner)
	mission_banner=label(banner,"MISSION · UNKNOWN",20)
	budget_strip=label(mission_content,"",16)
	command_detail=label(content,"",14);command_detail.autowrap_mode=TextServer.AUTOWRAP_ARBITRARY;command_detail.hide()
	summary=label(mission_content,"No mission selected.",17);summary.autowrap_mode=TextServer.AUTOWRAP_ARBITRARY
	budget_heading=label(mission_content,"DETAILED ACCOUNTING",14);budget_heading.hide()
	budget=label(mission_content,"Budget not reported.");budget.hide();summary.hide()
	label(mission_content,"CREW HANDOFFS",14)
	ledger_toggle=CheckButton.new();ledger_toggle.text="Technical handoff ledger";mission_content.add_child(ledger_toggle)
	handoff_cards=VBoxContainer.new();handoff_cards.add_theme_constant_override("separation",12);mission_content.add_child(handoff_cards)
	ledger_toggle.toggled.connect(func(value:bool):
		handoff_cards.visible=not value;members.visible=value
		summary.visible=value;budget.visible=value;budget_heading.visible=value)
	members=RichTextLabel.new();members.bbcode_enabled=false;members.selection_enabled=true
	members.fit_content=true;members.scroll_active=false;members.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	members.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	members.add_theme_constant_override("line_separation",5)
	members.focus_mode=Control.FOCUS_ALL;mission_content.add_child(members);members.hide()
	label(mission_content,"RECORDED DECISION",14)
	decision=label(mission_content,"No decision recorded.");decision.autowrap_mode=TextServer.AUTOWRAP_ARBITRARY
	review_content=VBoxContainer.new();review_content.add_theme_constant_override("separation",16);content.add_child(review_content)
	review_note=label(review_content,"Trainer opportunities are not reported.",14)
	review_summary=label(review_content,"No proposed review selected.",17);review_summary.autowrap_mode=TextServer.AUTOWRAP_ARBITRARY
	label(review_content,"PROPOSED INVESTIGATION",14)
	review_investigation=label(review_content,"Not reported.")
	label(review_content,"GROUPED SOURCE EVIDENCE",14)
	review_sources=label(review_content,"No source details reported.");review_sources.autowrap_mode=TextServer.AUTOWRAP_ARBITRARY
	launch_content=VBoxContainer.new();launch_content.add_theme_constant_override("separation",14);content.add_child(launch_content)
	label(launch_content,"Launch a readiness investigation",23)
	label(launch_content,"Public simulation · lead + workload and service specialists. No cluster changes, XP or qualification.",16)
	label(launch_content,"Registered immutable build",14)
	build_picker=OptionButton.new();build_picker.fit_to_longest_item=false;build_picker.clip_text=true;build_picker.custom_minimum_size.y=42;launch_content.add_child(build_picker)
	build_picker.item_selected.connect(func(_index:int):refresh_actions())
	label(launch_content,"Public scenario",14)
	scenario_picker=OptionButton.new();scenario_picker.custom_minimum_size.y=42;launch_content.add_child(scenario_picker)
	for scenario in SCENARIOS:scenario_picker.add_item(scenario.capitalize().replace("-"," "))
	label(launch_content,"Shared mission budget · requests / tokens",14)
	var allowance:=HBoxContainer.new();launch_content.add_child(allowance)
	requests=SpinBox.new();requests.min_value=1;requests.max_value=24;requests.value=12;requests.size_flags_horizontal=Control.SIZE_EXPAND_FILL;allowance.add_child(requests);JointCommands.track_integer_spinbox(requests)
	tokens=SpinBox.new();tokens.min_value=1;tokens.max_value=384000;tokens.value=384000;tokens.size_flags_horizontal=Control.SIZE_EXPAND_FILL;allowance.add_child(tokens);JointCommands.track_integer_spinbox(tokens)
	launch_context=label(launch_content,"No registered build selected.",14);launch_context.autowrap_mode=TextServer.AUTOWRAP_ARBITRARY
	launch_button=Button.new();launch_button.text="Launch public simulation";ConsoleTheme.primary(launch_button);launch_button.pressed.connect(launch_mission);launch_content.add_child(launch_button)
	label(launch_content,"Core reserves each member's grant before dispatch and enforces a ten-minute mission deadline. A quick diagnostic pass is not service recovery.",14)
	source_toggle=Button.new();source_toggle.text="Show exact retained record";source_toggle.custom_minimum_size.y=40
	source_toggle.pressed.connect(func():source.visible=not source.visible;source_toggle.text="Hide exact retained record" if source.visible else "Show exact retained record")
	content.add_child(source_toggle)
	source=TextEdit.new();source.editable=false;source.custom_minimum_size.y=260
	source.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;content.add_child(source);source.hide()
	feedback_row=HBoxContainer.new();add_child(feedback_row)
	action_notice=label(feedback_row,"",14)
	action_notice.max_lines_visible=2;action_notice.clip_text=true
	action_notice.custom_minimum_size.y=42
	reconcile_button=Button.new();reconcile_button.text="Reconcile request";reconcile_button.custom_minimum_size.y=40;reconcile_button.pressed.connect(reconcile);feedback_row.add_child(reconcile_button)
	add_child(http);http.timeout=8;http.max_redirects=0
	add_child(timer);timer.wait_time=3;timer.timeout.connect(func():render_status();render_detail();poll());timer.start()
	visibility_changed.connect(func():
		if is_visible_in_tree():poll())
	render()

func configure(endpoint:String,visual_fixture:String="") -> void:
	if unresolved():return
	epoch+=1;http.cancel_request();pending=false
	launch_commands.api=endpoint;cancel_commands.api=endpoint
	api=endpoint;fixture=visual_fixture;snapshot={};selected="";review_selected="";row_signature=""
	connection_state="fixture" if not fixture.is_empty() else "unknown"
	render()

func poll(force:bool=false) -> void:
	if pending or not fixture.is_empty() or not is_visible_in_tree() or (connection_state=="unsupported" and not force):return
	pending=true;refresh_button.disabled=true
	if callback.is_valid() and http.request_completed.is_connected(callback):http.request_completed.disconnect(callback)
	callback=received.bind(epoch);http.request_completed.connect(callback)
	if http.request(api+"/v5/snapshot")!=OK:received(1,0,[],PackedByteArray(),epoch)

func received(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray,request_epoch:int) -> void:
	if request_epoch!=epoch:return
	pending=false
	if code==404:
		connection_state="unsupported"
	elif result!=HTTPRequest.RESULT_SUCCESS or code!=200:
		connection_state="offline"
	else:
		var parser:=JSON.new()
		var parse_status:=parser.parse(body.get_string_from_utf8())
		var data=parser.data if parse_status==OK else null
		if not View.valid_snapshot(data):connection_state="unknown"
		elif float(data.observed_at)<float(snapshot.get("observed_at",0)):
			# An old successful response cannot overwrite a newer retained ledger.
			connection_state="unknown"
		else:
			snapshot=data;connection_state="online"
	render()

func apply_fixture(data:Dictionary) -> void:
	if fixture.is_empty():return
	if View.valid_snapshot(data):snapshot=data;connection_state="fixture"
	else:connection_state="unknown"
	render()

func render_status() -> void:
	if notice==null:return
	var state:="Preview fixture · synthetic records" if connection_state=="fixture" else "Core connected" if connection_state=="online" else "Joint operations unavailable on this Core (V5 endpoint not found)" if connection_state=="unsupported" else "Disconnected · retained records are last-known" if connection_state=="offline" else "Unknown · no valid current V5 observation"
	if not snapshot.is_empty():
		if View.stale(snapshot,Time.get_unix_time_from_system()):state+=" · stale observation"
		state+="\nObserved "+View.stamp(snapshot.get("observed_at"))
		state+=" · admission "+("enabled" if snapshot.get("enabled")==true else "disabled")
	if invalid_rows>0:state+="\n%d unsupported mission records omitted; coverage is incomplete." % invalid_rows
	notice.text="Simulation · "+state
	refresh_button.disabled=pending or not fixture.is_empty()
	refresh_actions()

func render() -> void:
	if choose==null:return
	refresh_builds()
	var rows:=View.records(snapshot)
	invalid_rows=snapshot.get("missions",[]).size()-rows.size()
	if review_mode:
		render_reviews();return
	var signature:="missions"+JSON.stringify(rows.map(func(value):return [value.input.id,View.state_label(value),value.input.get("scenario","unknown")]))
	if signature!=row_signature:
		row_signature=signature;choose.clear()
		for record in rows:
			choose.add_item("%s · %s · %s" % [View.state_label(record),str(record.input.get("scenario","unknown")),str(record.input.id)])
			choose.set_item_metadata(choose.item_count-1,record.input.id)
		if rows.is_empty():choose.add_item("No retained joint missions");choose.set_item_metadata(0,"");choose.set_item_disabled(0,true)
	var ids:Array=rows.map(func(value):return str(value.input.id))
	if selected not in ids:selected=str(ids[0]) if not ids.is_empty() else ""
	if not selected.is_empty():choose.select(ids.find(selected))
	choose.tooltip_text=selected if not selected.is_empty() else "No retained joint missions"
	render_status();render_detail()

func render_detail() -> void:
	mission_content.visible=not review_mode and not launch_mode;review_content.visible=review_mode;launch_content.visible=launch_mode
	choose.visible=not launch_mode;source_toggle.visible=not launch_mode
	if launch_mode:
		source.hide();refresh_actions();return
	if review_mode:
		render_review_detail();return
	var record:Dictionary={}
	for value in View.records(snapshot):
		if value.input.id==selected:record=value;break
	var prefix:=""
	if connection_state not in ["online","fixture"] or View.stale(snapshot,Time.get_unix_time_from_system()):prefix="LAST-KNOWN RECORD · current activity is unknown\n\n"
	var scenario:=str(record.get("input",{}).get("scenario","Readiness investigation")).capitalize().replace("-"," ")
	mission_banner.text=("LAST KNOWN · " if not prefix.is_empty() else "")+scenario+" · "+View.state_label(record)
	var allowance:Dictionary=record.get("budget") if record.get("budget") is Dictionary else {}
	budget_strip.text=View.outcome_label(record) if record.get("outcome")!=null else "%s / %s requests reserved · %s tokens accounted" % [View.number(allowance.get("requests_reserved")),View.number(allowance.get("requests_limit")),View.number(allowance.get("tokens_accounted"))]
	var overview:=View.summary(record)
	var metadata_start:=overview.find("\n\n")
	summary.text=prefix+(overview.substr(metadata_start+2) if metadata_start>=0 else overview)
	budget.text=View.budget(record)
	render_handoffs(record)
	render_ledger(record)
	decision.text=JSON.stringify(record.decision,"  ") if record.get("decision")!=null else "No decision recorded."
	var raw:=JSON.stringify(record,"  ")
	if source.text!=raw:source.text=raw

func _notification(what:int) -> void:
	if what==NOTIFICATION_THEME_CHANGED and members!=null:
		members.add_theme_font_size_override("normal_font_size",get_theme_default_font_size())

func scroll_keys(event:InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:return
	var amount:=maxi(40,int(scroll.size.y)-32)
	match event.keycode:
		KEY_PAGEDOWN:scroll.scroll_vertical+=amount
		KEY_PAGEUP:scroll.scroll_vertical-=amount
		KEY_HOME:scroll.scroll_vertical=0
		KEY_END:scroll.scroll_vertical=int(scroll.get_v_scroll_bar().max_value)
		_:return
	scroll.accept_event()

func render_reviews() -> void:
	var rows:=View.opportunities(snapshot)
	var signature:="reviews"+JSON.stringify(rows.map(func(value):return [value.id,value.category,value.get("scenario","not reported")]))
	if signature!=row_signature:
		row_signature=signature;choose.clear()
		for record in rows:
			choose.add_item("%s · %s" % [View.OPPORTUNITY_CATEGORIES[record.category],str(record.get("scenario","not reported"))])
			choose.set_item_metadata(choose.item_count-1,record.id)
		if rows.is_empty():choose.add_item("No proposed reviews reported");choose.set_item_metadata(0,"");choose.set_item_disabled(0,true)
	var ids:Array=rows.map(func(value):return str(value.id))
	if review_selected not in ids:review_selected=str(ids[0]) if not ids.is_empty() else ""
	if not review_selected.is_empty():choose.select(ids.find(review_selected))
	choose.tooltip_text=review_selected if not review_selected.is_empty() else View.opportunity_note(snapshot)
	render_status();render_detail()

func render_review_detail() -> void:
	var record:Dictionary={}
	for value in View.opportunities(snapshot):
		if value.id==review_selected:record=value;break
	var prefix:=""
	if connection_state not in ["online","fixture"] or View.stale(snapshot,Time.get_unix_time_from_system()):prefix="LAST-KNOWN REVIEW · current evidence is unknown\n\n"
	review_note.text=View.opportunity_note(snapshot)
	review_summary.text=prefix+View.opportunity_summary(record)
	review_sources.text=View.opportunity_sources(record)
	review_investigation.text=str(record.get("proposed_investigation","Not reported."))
	var raw:=JSON.stringify(record,"  ")
	if source.text!=raw:source.text=raw

func unresolved() -> bool:
	return (launch_commands!=null and (launch_commands.phase!="" or launch_commands.uncertain)) or (cancel_commands!=null and (cancel_commands.phase!="" or cancel_commands.uncertain))

func select_view(index:int) -> void:
	review_mode=index==1;launch_mode=index==2
	if launch_mode and draft_id.is_empty():draft_id="joint-ui-"+Crypto.new().generate_random_bytes(12).hex_encode()
	render();scroll.scroll_vertical=0

func refresh_builds() -> void:
	if build_picker==null:return
	var builds:Array=snapshot.get("builds") if snapshot.get("builds") is Array else []
	var valid:Array=[]
	for build in builds:
		if build is Dictionary and build.get("digest") is String and build.get("manifest") is Dictionary and build.manifest.get("inference") is bool:valid.append(build)
	var signature:=JSON.stringify(valid)
	if signature==build_signature:return
	build_signature=signature
	var old:Dictionary=build_picker.get_item_metadata(build_picker.selected) if build_picker.selected>=0 and build_picker.get_item_metadata(build_picker.selected) is Dictionary else {}
	build_picker.clear()
	for build in valid:
		build_picker.add_item(("Model inference" if build.manifest.inference else "Scripted control")+" · "+str(build.digest).left(18))
		build_picker.set_item_metadata(build_picker.item_count-1,build)
		if build.digest==old.get("digest"):build_picker.select(build_picker.item_count-1)
	if valid.is_empty():build_picker.add_item("No registered joint builds");build_picker.set_item_disabled(0,true);build_picker.set_item_metadata(0,{})

func chosen_build() -> Dictionary:
	return build_picker.get_item_metadata(build_picker.selected) if build_picker!=null and build_picker.selected>=0 and build_picker.get_item_metadata(build_picker.selected) is Dictionary else {}

func fresh_connection() -> bool:
	return fixture.is_empty() and connection_state=="online" and not View.stale(snapshot,Time.get_unix_time_from_system()) and JointCommands.allowed_origin(api)

func cancel_target() -> String:
	return launch_commands.run_id if launch_commands!=null and (launch_commands.phase!="" or launch_commands.uncertain) else selected

func refresh_actions() -> void:
	if launch_button==null or action_notice==null:return
	feedback_row.visible=not action_notice.text.is_empty() or unresolved()
	action_notice.tooltip_text=action_notice.text
	var active_command:Node=cancel_commands if cancel_commands.phase!="" or cancel_commands.uncertain else launch_commands
	command_detail.visible=unresolved()
	if command_detail.visible:command_detail.text="Operator request · "+active_command.phase+" · "+active_command.run_id+"\n"+action_notice.text
	var build:=chosen_build()
	var blocked:="Preview fixture · commands disabled." if not fixture.is_empty() else "Local Core connection and fresh observation required." if not fresh_connection() else "Joint admission is disabled." if snapshot.get("enabled")!=true else "Resolve the previous request before launching another." if unresolved() else "Choose a registered immutable build." if build.is_empty() else "Ready to launch this public simulation."
	launch_button.disabled=not fresh_connection() or snapshot.get("enabled")!=true or unresolved() or build.is_empty()
	launch_context.text=blocked+"\nRequest  "+(draft_id if not draft_id.is_empty() else "Prepared when Launch mission opens")
	if not build.is_empty():launch_context.text+="\nBuild  "+str(build.digest)+"\n"+("Uses the registered model and its inference settings." if build.manifest.inference else "Scripted control · no model inference.")
	var target:=cancel_target();var terminal:=false
	for record in View.records(snapshot):
		if record.input.id==target:terminal=record.state in ["completed","failed","cancelled"]
	stop_button.text="Cancel pending mission" if target!=selected and not target.is_empty() else "Cancel selected"
	stop_button.tooltip_text="Request cancellation for "+target if not target.is_empty() else "No mission selected"
	stop_button.disabled=fixture!="" or not JointCommands.allowed_origin(api) or target.is_empty() or terminal or cancel_commands.phase!="" or cancel_commands.uncertain or ((review_mode or launch_mode) and launch_commands.phase=="" and not launch_commands.uncertain)
	reconcile_button.visible=launch_commands.uncertain or cancel_commands.uncertain
	reconcile_button.disabled=launch_commands.phase!="" or cancel_commands.phase!=""
	for control in [build_picker,scenario_picker]:control.disabled=unresolved()
	requests.editable=not unresolved();tokens.editable=not unresolved()

func launch_mission() -> void:
	refresh_actions()
	if launch_button.disabled:return
	var request_limit:=JointCommands.commit_integer_spinbox(requests)
	var token_limit:=JointCommands.commit_integer_spinbox(tokens)
	if request_limit<1 or token_limit<1:action_notice.text="Budget must contain whole positive values within the displayed bounds.";return
	if draft_id.is_empty():draft_id="joint-ui-"+Crypto.new().generate_random_bytes(12).hex_encode()
	var build:=chosen_build()
	var payload:={"id":draft_id,"opportunity":draft_id,"build":str(build.digest),"scenario":SCENARIOS[scenario_picker.selected],"inference":bool(build.manifest.inference),"budget":{"requests":request_limit,"tokens":token_limit}}
	launch_commands.receipt={};launch_commands.submit("/v5/missions",payload,draft_id)

func cancel_selected() -> void:
	refresh_actions()
	if stop_button.disabled:return
	var target:=cancel_target()
	cancel_commands.receipt={};cancel_commands.submit("/v5/missions/"+target.uri_encode()+"/cancel",{},target)

func reconcile() -> void:
	if launch_commands.uncertain:launch_commands.submit("",{},"")
	if cancel_commands.uncertain:cancel_commands.submit("",{},"")

func accept_record(command:Node,id:String) -> void:
	epoch+=1;http.cancel_request();pending=false
	var record:Dictionary=command.receipt
	if View.valid_record(record):
		var found:=false
		for index in snapshot.get("missions",[]).size():
			if snapshot.missions[index].input.id==id:snapshot.missions[index]=record;found=true;break
		if not found:
			if not snapshot.get("missions") is Array:snapshot["missions"]=[]
			snapshot.missions.push_front(record)
	selected=id
	if command==launch_commands:draft_id="";view_choice.select(0);launch_mode=false;review_mode=false
	render();poll(true)

func render_handoffs(record:Dictionary) -> void:
	var signature:=JSON.stringify(record.get("tasks",[]))
	if signature==handoff_signature:return
	handoff_signature=signature
	var focused:=get_viewport().gui_get_focus_owner()
	var focus_id:=""
	if focused!=null and handoff_cards.is_ancestor_of(focused):focus_id=str(focused.get_meta("task_id",""))
	for child in handoff_cards.get_children():handoff_cards.remove_child(child);child.queue_free()
	for task in record.get("tasks",[]):
		if not task is Dictionary:continue
		var card:=PanelContainer.new();card.focus_mode=Control.FOCUS_ALL;card.set_meta("task_id",str(task.get("id","")))
		var border:=Color("b5796555") if task.get("state")!="failed" else Color("e18c75")
		card.add_theme_stylebox_override("panel",ConsoleTheme.box(Color("1c1d20e8"),border,14))
		card.focus_entered.connect(func():card.add_theme_stylebox_override("panel",ConsoleTheme.box(Color("24201ee8"),ConsoleTheme.ACCENT,14)))
		card.focus_exited.connect(func():card.add_theme_stylebox_override("panel",ConsoleTheme.box(Color("1c1d20e8"),border,14)))
		handoff_cards.add_child(card)
		var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);card.add_child(column)
		var header:=HBoxContainer.new();column.add_child(header)
		label(header,View.ROLES.get(str(task.get("role","")),"Unknown role"),19)
		var state_label:=label(header,"Round "+View.number(task.get("round"))+" · "+str(task.get("state","unknown")).capitalize(),14)
		state_label.autowrap_mode=TextServer.AUTOWRAP_OFF;state_label.size_flags_horizontal=Control.SIZE_SHRINK_END
		var result:Dictionary=task.get("result") if task.get("result") is Dictionary else {}
		var output:Dictionary=result.get("output") if result.get("output") is Dictionary else {}
		var brief:=str(output.get("summary",task.get("question","No question reported.")))
		if task.get("role")=="lead" and output.get("tasks") is Array:
			var roles:PackedStringArray=[]
			for member in output.tasks:
				if member is Dictionary:roles.append(str(member.get("role","unknown")).capitalize())
			brief="Requested "+" and ".join(roles)+" checks."
		elif task.get("role")=="lead" and output.get("decision") is Dictionary:brief="Proposed "+str(output.decision.get("action","unknown action"))+" · awaiting independent grading."
		if result.is_empty():brief="Awaiting reply · "+brief
		label(column,brief.left(220)+( "…" if brief.length()>220 else ""),16)
		if result.get("status")=="unknown" or (not result.is_empty() and result.get("usage")==null):
			label(column,"Usage not reported · %s tokens accounted." % View.number(task.get("accounted_tokens")),14).add_theme_color_override("font_color",Color("e5b082"))
		var disclosure:=Button.new();disclosure.text="Evidence & accounting";disclosure.custom_minimum_size.y=36;column.add_child(disclosure)
		var detail:=label(column,View.members({"tasks":[task]}),15);detail.autowrap_mode=TextServer.AUTOWRAP_ARBITRARY;detail.hide()
		disclosure.pressed.connect(func():detail.visible=not detail.visible;disclosure.text="Hide evidence & accounting" if detail.visible else "Evidence & accounting")
		if str(task.get("id",""))==focus_id:card.grab_focus()

func ledger_heading(text:String) -> void:
	members.push_color(Color("e9b59d"));members.push_bold();members.add_text(text);members.pop();members.pop();members.add_text("\n")

func ledger_field(title:String,value:String) -> void:
	members.push_color(Color("b9b7b2"));members.add_text(title+"  ");members.pop();members.add_text(value+"\n")

func render_ledger(record:Dictionary) -> void:
	members.clear()
	var tasks:Array=record.get("tasks",[])
	if tasks.is_empty():members.add_text("No member dispatch recorded.");return
	for task in tasks:
		if not task is Dictionary:continue
		var result:Dictionary=task.get("result") if task.get("result") is Dictionary else {}
		ledger_heading("ROUND %s  /  %s  /  %s" % [View.number(task.get("round")),View.ROLES.get(str(task.get("role","")),"Unknown role"),str(task.get("state","unknown")).capitalize()])
		members.add_text(str(task.get("question","Question not reported"))+"\n\n")
		ledger_heading("DISPATCH & ACCOUNTING")
		ledger_field("Task ID",str(task.get("id","not reported")))
		ledger_field("Focus",str(task.get("focus","not reported")))
		ledger_field("Tokens", "%s granted · %s accounted" % [View.number(task.get("tokens")),View.number(task.get("accounted_tokens"))])
		if not result.is_empty():
			ledger_field("Reply",str(result.get("status","unknown"))+" · "+("eligible for diagnostic grading" if task.get("eligible")==true else "not eligible for diagnostic grading"))
			if result.get("usage")==null:ledger_field("Usage","Unknown · accounting may include the full grant")
			if result.get("error")!=null:ledger_field("Error",str(result.error))
			var output:Dictionary=result.get("output") if result.get("output") is Dictionary else {}
			if not output.is_empty():
				members.add_text("\n");ledger_heading("RECORDED REPLY")
				for key in ["diagnosis","summary","rationale","uncertainty","next_question"]:
					if output.get(key)!=null:ledger_field(key.replace("_"," ").capitalize(),str(output[key]))
				if output.get("evidence_ids") is Array:ledger_field("Evidence",", ".join(output.evidence_ids))
				if output.get("tasks") is Array:
					for delegated in output.tasks:
						if not delegated is Dictionary:continue
						ledger_field("Delegation",View.ROLES.get(str(delegated.get("role","")),"Unknown role")+" · "+str(delegated.get("focus","not reported")))
						if delegated.get("question")!=null:ledger_field("Question",str(delegated.question))
				if output.get("decision") is Dictionary:ledger_field("Proposed action",str(output.decision.get("action","not reported")))
		else:members.add_text("No reply recorded · outcome unknown\n")
		members.add_text("\n\n")
