extends VBoxContainer
## V7 is authoritative. Inspecting a mission never dispatches work.
const Commands = preload("res://commands.gd")
var api := preload("res://transport.gd").default_origin()
var fixture := false
var large_text := false
var snapshot: Dictionary = {}
var online := false
var observe_in_background := false
var received_at_msec := 0
signal snapshot_changed
var selected := ""
var http = preload("res://transport.gd").create()
var commands: Node
var timer := Timer.new()
var status: Label
var policy: Label
var operating: VBoxContainer
var operating_signature := ""
var choices: OptionButton
var content: VBoxContainer
var feedback: Label
var cancel: Button
var reconcile: Button
var signature := ""

func label(parent: Node, text: String, size: int = 16) -> Label:
	var item := Label.new(); item.text=text
	item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_font_size_override("font_size",size+(3 if large_text else 0)); parent.add_child(item)
	return item

func _ready() -> void:
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",12)
	add_theme_font_size_override("font_size",19 if large_text else 16)
	label(self,"AUTONOMOUS SDLC MISSIONS",21)
	status=label(self,"Not connected · open this tab to read mission records.")
	policy=label(self,"Standing policy not reported.")
	operating=VBoxContainer.new(); operating.add_theme_constant_override("separation",8); add_child(operating)
	choices=OptionButton.new(); choices.fit_to_longest_item=false; choices.custom_minimum_size.y=40; add_child(choices)
	choices.item_selected.connect(func(index:int): selected=str(choices.get_item_metadata(index)); render_mission())
	content=VBoxContainer.new(); content.add_theme_constant_override("separation",10); add_child(content)
	cancel=Button.new(); cancel.text="Stop future mission actions"; cancel.custom_minimum_size.y=40; add_child(cancel)
	cancel.pressed.connect(cancel_selected)
	feedback=label(self,"")
	reconcile=Button.new(); reconcile.text="Reconcile uncertain stop request"; reconcile.custom_minimum_size.y=40; add_child(reconcile)
	reconcile.pressed.connect(func():
		if not fixture and online and commands.uncertain: commands.submit("",{},""))
	commands=Commands.new(); commands.api=api; add_child(commands)
	commands.feedback.connect(func(message:String,_busy:bool): feedback.text=message; controls())
	commands.accepted.connect(func(_id:String): poll())
	add_child(http); http.timeout=4; http.max_redirects=0; http.body_size_limit=4194304
	http.request_completed.connect(received)
	timer.wait_time=5; timer.timeout.connect(poll); add_child(timer); timer.start()
	visibility_changed.connect(poll)
	render()

func set_api(value:String) -> void:
	if commands.uncertain or not commands.phase.is_empty(): return
	http.cancel_request(); api=value; commands.api=value
	snapshot.clear(); selected=""; signature=""; online=false; render(); poll()

func poll() -> void:
	if fixture or (not observe_in_background and not is_visible_in_tree()) or http.get_http_client_status()!=HTTPClient.STATUS_DISCONNECTED: return
	var result:int=http.request(api+"/v7/snapshot")
	if result!=OK: received(HTTPRequest.RESULT_CANT_CONNECT,0,[],PackedByteArray())

func received(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray) -> void:
	if fixture: return
	var data=JSON.parse_string(body.get_string_from_utf8()) if code==200 else null
	online=result==HTTPRequest.RESULT_SUCCESS and code==200 and data is Dictionary and data.get("schema_version")==7 and data.get("missions") is Array
	if online:
		snapshot=data
		received_at_msec=Time.get_ticks_msec()
	status.text=("LIVE · read-only inspection" if online else "UNAVAILABLE · "+("V7 not installed" if code==404 else "connection or contract failure")+" · retained records are last known")
	if fixture: status.text="FIXTURE · synthetic records · commands disabled"
	render()
	snapshot_changed.emit()

func observation_current() -> bool:
	return online and (received_at_msec==0 or Time.get_ticks_msec()-received_at_msec<=15000)

func _process(_delta:float) -> void:
	if not fixture and online and not observation_current():
		online=false
		status.text="STALE · no current snapshot · retained records are last known"
		render()

func disclosure(parent:Node,title:String) -> VBoxContainer:
	var button:=Button.new(); button.text=title; button.custom_minimum_size.y=40; button.clip_text=true; button.tooltip_text=title
	var body:=VBoxContainer.new(); body.add_theme_constant_override("separation",8)
	parent.add_child(button); parent.add_child(body); body.hide()
	button.pressed.connect(func(): body.visible=not body.visible)
	return body

func render_operating() -> void:
	var next_signature:=str(online)+JSON.stringify([snapshot.get("coordination"),snapshot.get("capability_catalog")])
	if next_signature==operating_signature: return
	operating_signature=next_signature
	for child in operating.get_children(): operating.remove_child(child); child.queue_free()
	var coordination:Dictionary=snapshot.get("coordination",{}) if snapshot.get("coordination") is Dictionary else {}
	var admission:=str(coordination.get("admission","unknown")).replace("_"," ")
	label(operating,"MISSION ADMISSION · "+admission.to_upper(),18)
	if not online: label(operating,"Last known / fixture capacity · readiness is not current authorization.")
	elif coordination.get("admission")=="ready": label(operating,"Core reports admission capacity. Each effect still requires fresh authorization.")
	if coordination.has("resolution"): label(operating,str(coordination.resolution))
	var details:=disclosure(operating,"Inspect installed capability contracts and coordination")
	label(details,"Installed capabilities describe supported work, not authority or crew proficiency.")
	render_value(details,snapshot.get("capability_catalog","Catalog unavailable · older or incomplete snapshot"))
	render_value(details,coordination)
	var ledger:=TextEdit.new(); ledger.text=JSON.stringify({"capability_catalog":snapshot.get("capability_catalog"),"coordination":coordination},"  "); ledger.editable=false; ledger.custom_minimum_size.y=180; ledger.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY; details.add_child(ledger)

func render() -> void:
	if policy==null: return
	if fixture: status.text="FIXTURE · synthetic records · commands disabled"
	var p=snapshot.get("policy",{})
	policy.text="Standing policy · "+("enabled" if snapshot.get("enabled",false) and p is Dictionary and p.get("enabled",false) else "disabled or unknown")
	if p is Dictionary:
		policy.text+=" · "+str(p.get("repository","repository unknown"))+"\nPR publication · "+("allowed" if p.get("publish",false) else "not authorized")+" · Mission limit · "+str(int(p.get("max_missions",0)))
		if p.get("expires_at") is float or p.get("expires_at") is int: policy.text+=" · Expires "+Time.get_datetime_string_from_unix_time(int(p.expires_at)).replace("T"," ")+" UTC"
	render_operating()
	var new_signature:=str(online)+JSON.stringify(snapshot)
	if signature!=new_signature:
		signature=new_signature
		choices.clear()
		var ordered:Array=snapshot.get("missions",[]).duplicate()
		ordered.sort_custom(func(a,b): return float(a.get("updated_at",0))>float(b.get("updated_at",0)))
		for mission in ordered:
			if not mission is Dictionary: continue
			var input:Dictionary=mission.get("input",{})
			var id:=str(mission.get("id",input.get("id","")))
			choices.add_item(str(input.get("repository","Unknown repository"))+" · "+str(mission.get("state","unknown"))+" · "+id)
			choices.set_item_metadata(choices.item_count-1,id)
			if id==selected: choices.select(choices.item_count-1)
		if choices.item_count>0: selected=str(choices.get_item_metadata(choices.selected))
		render_mission()
	controls()

func mission_record() -> Dictionary:
	for record in snapshot.get("missions",[]):
		if record is Dictionary and str(record.get("id",record.get("input",{}).get("id","")))==selected: return record
	return {}

func render_mission() -> void:
	for child in content.get_children(): content.remove_child(child); child.queue_free()
	var record:=mission_record()
	if record.is_empty(): label(content,"No mission records available. Repository observation alone does not authorize a change."); controls(); return
	var input:Dictionary=record.get("input",{})
	label(content,"MISSION · "+str(record.get("state","unknown")).replace("_"," ").to_upper(),19)
	label(content,"OPPORTUNITY",18)
	render_value(content,input.get("opportunity","Not reported"))
	label(content,"Repository · "+str(input.get("repository","Unknown"))+"\nPinned revision · "+str(input.get("revision","Unknown")))
	var updated=record.get("updated_at")
	var updated_text:=Time.get_datetime_string_from_unix_time(int(updated)).replace("T"," ")+" UTC" if updated is float or updated is int else str(updated)
	label(content,"Updated · "+updated_text+" · "+("live record" if online and not fixture else "last known / fixture"))
	var state:=str(record.get("state","unknown"))
	if state in ["submitted","awaiting_review"]: label(content,"PR submitted · awaiting external review. This is not a merge, production verification, or an XP award.")
	if state=="cancel_requested" or record.get("cancel_requested",false): label(content,"Stop requested · already-started effects may still complete. Await reconciliation.")
	render_coordination(record)
	render_verifications(record)
	var evidence=record.get("evidence",{})
	if evidence is Dictionary and evidence.get(state) is Dictionary:
		label(content,"GITHUB ACTIONS / PR FOLLOW-UP" if state=="awaiting_review" else "CURRENT STAGE EVIDENCE",18)
		var current:Dictionary=evidence[state]
		if state in ["blocked","failed","cancelled","awaiting_review","submitted"]: render_value(content,current)
		else:
			for key in ["role","summary","status","verdict","reason","scope"]:
				if current.has(key): label(content,str(key).capitalize()+" · "+str(current[key]))
	if evidence is Dictionary:
		for stage in ["investigating","implementing","testing","reviewing","ready_to_publish","publishing","submitted","awaiting_review","blocked","failed","cancelled"]:
			if evidence.has(stage):
				label(content,stage.to_upper()+" · retained evidence",18)
				render_value(content,evidence[stage])
	var publication=record.get("publication")
	if publication is Dictionary:
		label(content,"PUBLICATION AUTHORITY",18); render_value(content,publication)
		var submitted:Dictionary=evidence.get("submitted",{}) if evidence is Dictionary and evidence.get("submitted",{}) is Dictionary else {}
		var url:=str(submitted.get("url",publication.get("url",publication.get("pr_url",""))))
		if safe_pr_url(url,str(input.get("repository",""))):
			var link:=LinkButton.new(); link.text="Open pull request in GitHub"; link.custom_minimum_size.y=40; content.add_child(link)
			link.pressed.connect(func(): OS.shell_open(url))
	else: label(content,"Publication · none recorded.")
	if not (evidence is Dictionary and evidence.has("awaiting_review")): label(content,"CI status · unknown until provider evidence is retained.")
	label(content,"CREW HANDOFFS & EVENTS",18)
	for event in record.get("events",[]):
		if event is Dictionary:
			var entry:Dictionary=event.get("event",event)
			var data:Dictionary=entry.get("data",{}) if entry.get("data",{}) is Dictionary else {}
			label(content,str(entry.get("stage",entry.get("state","event"))).replace("_"," ").capitalize()+" · "+str(data.get("role",entry.get("role","Core record"))))
			if data.has("summary"): label(content,str(data.summary))
	var raw:=TextEdit.new(); raw.text=JSON.stringify(record,"  "); raw.editable=false
	raw.custom_minimum_size.y=220; raw.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	var disclosure:=Button.new(); disclosure.text="Show technical ledger"; disclosure.custom_minimum_size.y=40
	content.add_child(disclosure); content.add_child(raw); raw.hide()
	disclosure.pressed.connect(func(): raw.visible=not raw.visible; disclosure.text="Hide technical ledger" if raw.visible else "Show technical ledger")
	controls()

func render_coordination(record:Dictionary) -> void:
	var contract:Dictionary=record.get("capability",{}) if record.get("capability") is Dictionary else {}
	if contract.is_empty():
		label(content,"Capability contract · not recorded (legacy or unknown). No assignment inferred.")
	else:
		label(content,"CAPABILITY · "+str(contract.get("id","unknown")),18)
		label(content,str(contract.get("objective","Objective not reported")))
		var details:=disclosure(content,"Inspect pinned contract, crew assignments and dependencies")
		label(details,"Pinned contract digest · "+str(contract.get("digest","unknown")))
		label(details,"Assignments are a retained plan; they do not prove a crew member is currently executing.")
		var plan:Dictionary=record.get("coordination",{}) if record.get("coordination") is Dictionary else {}
		var evidence:Dictionary=record.get("evidence",{}) if record.get("evidence") is Dictionary else {}
		var tasks:Array=plan.get("assignments",[]) if plan.get("assignments") is Array else []
		if tasks.is_empty(): label(details,"Crew assignment plan · unavailable")
		for task in tasks:
			if not task is Dictionary: continue
			label(details,str(task.get("crew","unknown crew")).capitalize()+" · "+str(task.get("role","unknown role"))+" · "+str(task.get("task","unknown task")),18)
			label(details,"Requires · "+(", ".join(task.requires) if task.get("requires") is Array and not task.requires.is_empty() else "No task dependencies recorded"))
			var key:=str(task.get("evidence",""))
			label(details,"Dependency evidence · "+key+" · "+("retained (not a success claim)" if evidence.has(key) else "not recorded"))
			if evidence.has(key): render_value(details,evidence[key])
		label(details,"Reservation · "+str(plan.get("reservation","unknown"))+" · Round limit · "+str(plan.get("max_rounds","unknown")))
		var contract_details:=disclosure(details,"Inspect full pinned contract")
		render_value(contract_details,contract)
	var observed:Dictionary=record.get("pr_observation",{}) if record.get("pr_observation") is Dictionary else {}
	if observed.is_empty():
		label(content,"PR lifecycle · unknown · no retained provider checkpoint")
	else:
		var at:float=float(observed.get("observed_at",0))
		var fresh:=observation_current() and at>0 and absf(Time.get_unix_time_from_system()-at)<=60
		label(content,"PR LIFECYCLE · "+str(observed.get("state","unknown")).to_upper()+" · "+("recent checkpoint" if fresh and not fixture else "last known / fixture"),18)
		label(content,"Observed head · "+str(observed.get("head","unknown"))+"\nObserved at · "+(Time.get_datetime_string_from_unix_time(int(at)).replace("T"," ")+" UTC" if at>0 else "unknown"))
		label(content,"Provider lifecycle does not imply Starbase merged this PR or grant XP. Admission above remains Core-owned.")

func verification_record(id:String) -> Dictionary:
	for item in mission_record().get("verifications",[]):
		if item is Dictionary and str(item.get("id",""))==id: return item
	return {}

func render_verifications(record:Dictionary) -> void:
	var verifications:Array=record.get("verifications",[]).duplicate()
	if verifications.is_empty(): return
	label(content,"EXTERNAL VERIFICATION",19)
	if not snapshot.get("verification_enabled",false): label(content,"Verification capability disabled · retained records and stop controls remain available.")
	label(content,"Exact-head verification is separate from GitHub Actions. Its result does not imply a merge or award XP.")
	verifications.sort_custom(func(a,b): return float(a.get("updated_at",0))>float(b.get("updated_at",0)))
	for item in verifications.slice(0,12):
		if not item is Dictionary: continue
		var id:=str(item.get("id",""))
		var stage:=str(item.get("state","unknown"))
		var input:Dictionary=item.get("input",{})
		var evidence:Dictionary=item.get("evidence",{})
		var verified:Dictionary=evidence.get("verified",{}) if evidence.get("verified",{}) is Dictionary else {}
		label(content,"VERIFICATION · "+stage.replace("_"," ").to_upper(),18)
		label(content,"Record · "+id+"\nObserved PR head · "+str(input.get("head","unknown")))
		label(content,"Core outcome · "+str(verified.get("outcome","not available")).replace("_"," "))
		label(content,"Scope · "+str(verified.get("scope","Retained bounded tests only; no application-wide safety assessment.")))
		if item.get("cancel_requested",false): label(content,"Stop requested · current effects may still need reconciliation.")
		if verified.has("infrastructure_error"): label(content,"Verification infrastructure · "+str(verified.infrastructure_error))
		if evidence.has("blocked"): render_value(content,evidence.blocked)
		if evidence.has("completed"):
			label(content,"Status publication / updated-head receipt",16)
			render_value(content,evidence.completed)
		var details:=VBoxContainer.new(); details.add_theme_constant_override("separation",8)
		var show_evidence:=Button.new(); show_evidence.text="Inspect verifier evidence · "+id; show_evidence.custom_minimum_size.y=40; show_evidence.clip_text=true; show_evidence.tooltip_text="Inspect verifier evidence · "+id
		content.add_child(show_evidence); content.add_child(details); details.hide()
		show_evidence.pressed.connect(func(): details.visible=not details.visible)
		for key in ["verifying","verified","repairing","testing","reviewing","ready_to_update","updating"]:
			if evidence.has(key): label(details,key.replace("_"," ").capitalize(),18); render_value(details,evidence[key])
		if not item.get("effects",{}).is_empty(): label(details,"Retained effects · candidate head differs from observed PR head when a repair is proposed",16); render_value(details,item.effects)
		var stop:=Button.new(); stop.text="Stop verification"; stop.custom_minimum_size.y=40
		stop.set_meta("verification_cancel_id",id); content.add_child(stop)
		stop.pressed.connect(func(): cancel_verification(id))
	if verifications.size()>12: label(content,"Additional verification history remains in the technical ledger.")

func cancel_verification(id:String) -> void:
	var item:=verification_record(id)
	if fixture or not online or item.is_empty() or item.get("cancel_requested",false) or item.get("state") in ["completed","blocked","cancelled"] or commands.uncertain or not commands.phase.is_empty(): return
	var endpoint:="/v7/missions/"+selected.uri_encode()+"/verifications/"+id.uri_encode()
	commands.submit(endpoint+"/cancel",{},id,endpoint)

func render_value(parent:Node,value:Variant,depth:int=0) -> void:
	# Plain labels intentionally do not interpret provider/model text as markup.
	# Keep the narrative bounded; the expandable ledger retains exact evidence.
	if depth>=4:
		label(parent,str(value).left(1000)); return
	if value is Dictionary:
		for key in value:
			if str(key) in ["sources","stdout","stderr","diff","before","after"]:
				if not str(value[key]).is_empty(): label(parent,str(key).capitalize()+" · retained in technical ledger")
				continue
			if value[key] is Dictionary or value[key] is Array:
				label(parent,str(key).replace("_"," ").capitalize(),16)
				var margin:=MarginContainer.new(); margin.add_theme_constant_override("margin_left",16); parent.add_child(margin)
				var nested:=VBoxContainer.new(); nested.add_theme_constant_override("separation",6); margin.add_child(nested)
				render_value(nested,value[key],depth+1)
			else: label(parent,str(key).replace("_"," ").capitalize()+" · "+str(value[key]).left(1000))
	elif value is Array:
		for item in value.slice(0,40): render_value(parent,item,depth+1)
		if value.size()>40: label(parent,"Additional records retained in technical ledger.")
	else: label(parent,str(value).left(1000))

static func safe_pr_url(url:String,repository:String) -> bool:
	if repository.split("/").size()!=2: return false
	var prefix:="https://github.com/"+repository+"/pull/"
	var number:=url.substr(prefix.length())
	return url.to_lower().begins_with(prefix.to_lower()) and number.is_valid_int() and int(number)>0 and str(int(number))==number

func controls() -> void:
	if cancel==null or commands==null: return
	var state:=str(mission_record().get("state",""))
	cancel.disabled=fixture or not online or selected.is_empty() or mission_record().get("cancel_requested",false) or state in ["","failed","blocked","cancelled","cancel_requested","submitted","awaiting_review"] or commands.uncertain or not commands.phase.is_empty()
	for stop in content.find_children("*","Button",true,false):
		if stop.has_meta("verification_cancel_id"):
			var item:=verification_record(str(stop.get_meta("verification_cancel_id")))
			stop.disabled=fixture or not online or item.get("cancel_requested",false) or item.get("state") in ["completed","blocked","cancelled"] or commands.uncertain or not commands.phase.is_empty()
	reconcile.visible=commands.uncertain
	reconcile.disabled=fixture or not online or not commands.phase.is_empty()

func cancel_selected() -> void:
	controls()
	if cancel.disabled: return
	commands.submit("/v7/missions/"+selected.uri_encode()+"/cancel",{},selected,"/v7/missions/"+selected.uri_encode())
