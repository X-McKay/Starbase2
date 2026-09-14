extends VBoxContainer
## Read-only V2 history. Paging never replaces the independently supplied active list.
signal cancel_requested(id: String)
signal selection_changed(run: Dictionary)
const StateView = preload("res://state.gd")
var api := preload("res://transport.gd").default_origin()
var fixture := ""
var offline := true
var selected := ""
var selected_run: Dictionary = {}
var active: Array = []
var pages: Array = []
var page_index := -1
var details: Dictionary = {}
var latest_records: Dictionary = {}
var snapshot_revision := -1.0
var auto_detail_revisions: Dictionary = {}
var auto_detail_attempted: Dictionary = {}
var detail_serial := 0
var epoch := 0
var page_pending := false
var detail_pending := false
var page_http = preload("res://transport.gd").create()
var detail_http = preload("res://transport.gd").create()
var notice: Label
var list: ItemList
var detail: RichTextLabel
var full_record: TextEdit
var full_toggle: Button
var panes: BoxContainer
var older: Button
var back: Button
var latest: Button
var refresh_selected: Button
var previous_run_button: Button
var stop: Button
var row_ids: Array[String] = []
var rendered_rows := ""
var rendered_page := -2
var page_callback: Callable
var detail_callback: Callable

func _ready() -> void:
	add_child(page_http); add_child(detail_http)
	for http in [page_http, detail_http]:
		http.timeout=8; http.max_redirects=0
	var controls := HFlowContainer.new(); add_child(controls)
	latest=button(controls,"Latest",load_latest)
	back=button(controls,"Newer page",go_back)
	older=button(controls,"Older page",load_older)
	refresh_selected=button(controls,"Refresh selected",func():
		if not offline and fixture.is_empty() and not selected.is_empty(): inspect_run(selected))
	stop=button(controls,"Stop selected run",func():
		if not offline and fixture.is_empty() and cancellable(current_selected()): cancel_requested.emit(selected))
	notice=Label.new(); notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; add_child(notice)
	panes=BoxContainer.new(); panes.add_theme_constant_override("separation",12)
	panes.size_flags_vertical=Control.SIZE_EXPAND_FILL; add_child(panes)
	list=ItemList.new(); list.custom_minimum_size=Vector2(0,140); list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	list.size_flags_vertical=Control.SIZE_EXPAND_FILL
	list.item_selected.connect(func(index): inspect_run(row_ids[index]))
	list.item_activated.connect(func(index): inspect_run(row_ids[index])); panes.add_child(list)
	detail=RichTextLabel.new(); detail.custom_minimum_size=Vector2(0,140); detail.size_flags_vertical=Control.SIZE_EXPAND_FILL
	detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL; detail.size_flags_stretch_ratio=1.4
	detail.selection_enabled=true; detail.bbcode_enabled=false
	var detail_column:=VBoxContainer.new(); detail_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	detail_column.size_flags_vertical=Control.SIZE_EXPAND_FILL; detail_column.size_flags_stretch_ratio=1.4
	panes.add_child(detail_column); detail_column.add_child(detail)
	full_toggle=button(detail_column,"Source, revisions & full record",func(): full_record.visible=not full_record.visible)
	full_record=TextEdit.new(); full_record.editable=false; full_record.custom_minimum_size.y=200
	full_record.size_flags_vertical=Control.SIZE_EXPAND_FILL; detail_column.add_child(full_record); full_record.hide()
	previous_run_button=button(detail_column,"Open previous run",func():
		var previous:=previous_run_id(selected_run)
		if not previous.is_empty(): inspect_run(previous))
	previous_run_button.hide()
	resized.connect(layout_panes); layout_panes()
	refresh()

func button(parent: Node, title: String, callback: Callable) -> Button:
	var result:=Button.new(); result.text=title; result.custom_minimum_size.y=38
	result.pressed.connect(callback); parent.add_child(result); return result

func configure(endpoint: String, fixture_path: String = "") -> void:
	if endpoint==api and fixture_path==fixture: return
	invalidate_requests()
	api=endpoint; fixture=fixture_path; offline=true
	active.clear(); pages.clear(); details.clear(); latest_records.clear(); page_index=-1; selected=""; selected_run={}
	snapshot_revision=-1.0; auto_detail_revisions.clear(); auto_detail_attempted.clear(); detail_pending=false
	refresh()

func invalidate_requests() -> void:
	epoch+=1; page_pending=false
	detail_pending=false
	page_http.cancel_request(); detail_http.cancel_request()

static func valid(run: Variant) -> bool:
	return StateView.valid_record(run) and run.input.get("request") is Dictionary and run.input.request.get("id") is String and run.get("state") is String

static func run_id(run: Dictionary) -> String:
	return str(run.input.request.id)

static func records(value: Variant) -> Array:
	var result: Array=[]; var seen: Dictionary={}
	if not value is Array: return result
	for run in value:
		if valid(run) and not seen.has(run_id(run)):
			seen[run_id(run)]=true; result.append(run.duplicate(true))
	return result

static func cancellable(run: Dictionary) -> bool:
	return not run.is_empty() and str(run.get("state","unknown")) in ["queued","running","capturing","reviewing","evaluating","executing","analyzing","verifying"]

func update_snapshot(snapshot: Dictionary, disconnected: bool) -> void:
	if disconnected and not offline: invalidate_requests()
	var previous_selected: Dictionary=latest_records.get(selected,{}) if not selected.is_empty() else {}
	offline=disconnected
	var observed:Variant=snapshot.get("observed_at",snapshot.get("revision",-1))
	var incoming_revision:=float(observed) if observed is int or observed is float else -1.0
	if incoming_revision>=0 and incoming_revision<snapshot_revision:
		# An older response cannot move the authoritative projection backwards.
		refresh()
		return
	if incoming_revision>=0: snapshot_revision=incoming_revision
	if snapshot.get("active") is Array: active=records(snapshot.active)
	if snapshot.get("recent") is Array:
		var recent:=records(snapshot.recent)
		if pages.is_empty() or (page_index==0 and JSON.stringify(pages[0])!=JSON.stringify(recent)):
			if page_pending: invalidate_requests()
			# New latest windows invalidate cached cursors, but never replace an older page being inspected.
			pages=[recent]; page_index=0
	# Keep source/events bound to the fetched revision; show current snapshot state separately.
	latest_records.clear()
	for run in records(snapshot.get("recent",[]))+records(snapshot.get("active",[])):
		var id:=run_id(run)
		var prior:Dictionary=latest_records.get(id,{})
		if prior.is_empty() or float(run.get("updated_at",0))>=float(prior.get("updated_at",0)):
			latest_records[id]=run.duplicate(true)
	refresh()
	var current:Dictionary=latest_records.get(selected,{}) if not selected.is_empty() else {}
	if not current.is_empty() and _selected_detail_needs_refresh(previous_selected,current):
		var revision:=detail_revision(current)
		auto_detail_revisions[selected]=revision
		# Defer until the current projection has rendered the changed row.
		_refresh_selected_detail.call_deferred(selected,revision)

func current_selected() -> Dictionary:
	var current: Dictionary=latest_records.get(selected,selected_run)
	if float(selected_run.get("updated_at",0))>float(current.get("updated_at",0)): return selected_run
	return current

func visible_records() -> Array:
	var combined: Array=active.duplicate(true)
	if page_index>=0 and page_index<pages.size(): combined.append_array(pages[page_index])
	return records(combined)

func cursor() -> int:
	if page_index<0 or page_index>=pages.size() or pages[page_index].is_empty(): return -1
	var result:int=9223372036854775807
	for run in pages[page_index]:
		var sequence=run.get("sequence")
		if not (sequence is int or sequence is float) or float(sequence)!=floorf(float(sequence)) or sequence<=0: return -1
		result=mini(result,int(sequence))
	return result

func load_latest() -> void: request_page(-1,true)
func load_older() -> void:
	if page_pending: return
	if page_index+1<pages.size(): page_index+=1; refresh(); return
	var before:=cursor()
	if before>0: request_page(before,false)
func go_back() -> void:
	if page_index>0 and not page_pending: page_index-=1; refresh()

func request_page(before: int, reset: bool) -> void:
	if offline or not fixture.is_empty() or page_pending: return
	page_pending=true; refresh()
	if page_callback.is_valid() and page_http.request_completed.is_connected(page_callback): page_http.request_completed.disconnect(page_callback)
	# Capture the generation by value, rather than reading the current generation in callbacks.
	page_callback=receive_page_response.bind(epoch,reset,before)
	page_http.request_completed.connect(page_callback,CONNECT_ONE_SHOT)
	var error: int = page_http.request(api+"/v2/runs"+("?before="+str(before) if before>0 else ""))
	if error!=OK: page_pending=false; refresh(); notice.text="History request could not start; retained records remain."

func receive_page_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int, reset: bool, before: int) -> void:
	receive_page(generation,result,code,body,reset,before)

func receive_page(generation: int, result: int, code: int, body: PackedByteArray, reset: bool, before: int) -> void:
	if generation!=epoch or offline or not fixture.is_empty(): return
	page_pending=false
	var parsed=JSON.parse_string(body.get_string_from_utf8())
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200 or not parsed is Dictionary or not parsed.get("runs") is Array:
		refresh(); notice.text="History unavailable or malformed; retained records remain."; return
	var page:=records(parsed.runs)
	if page.size()>20 or page.size()!=parsed.runs.size() or page.any(func(run): return not (run.get("sequence") is int or run.get("sequence") is float) or float(run.sequence)!=floorf(float(run.sequence)) or run.sequence<=0 or (before>0 and run.sequence>=before)):
		refresh(); notice.text="Malformed history page; retained records remain."; return
	if reset: pages=[page]; page_index=0
	else: pages.append(page); page_index=pages.size()-1
	refresh()

func inspect_run(id: String) -> void:
	if selected!=id and is_instance_valid(full_record): full_record.hide()
	detail_serial+=1
	selected=id
	selected_run=details.get(id,{}).duplicate(true)
	if selected_run.is_empty():
		for run in visible_records():
			if run_id(run)==id: selected_run=run.duplicate(true); break
	refresh(); selection_changed.emit(selected_run)
	if offline or not fixture.is_empty(): return
	_request_detail(id)

func _request_detail(id: String) -> void:
	detail_pending=false
	detail_http.cancel_request()
	if detail_callback.is_valid() and detail_http.request_completed.is_connected(detail_callback): detail_http.request_completed.disconnect(detail_callback)
	detail_callback=receive_detail_response.bind(epoch,id,detail_serial)
	detail_http.request_completed.connect(detail_callback,CONNECT_ONE_SHOT)
	detail_pending=true
	if detail_http.request(api+"/v2/runs/"+id.uri_encode())!=OK:
		detail_pending=false
		notice.text="Detail request could not start; retained evidence remains."
	else:
		refresh()

func _refresh_selected_detail(id: String, revision: String) -> void:
	if id!=selected or offline or not fixture.is_empty() or detail_pending: return
	if auto_detail_revisions.get(id,"")!=revision or auto_detail_attempted.get(id,"")==revision: return
	auto_detail_attempted[id]=revision
	_request_detail(id)

func _selected_detail_needs_refresh(previous: Dictionary, current: Dictionary) -> bool:
	if selected.is_empty() or current.is_empty() or offline or not fixture.is_empty(): return false
	# Only a changed authoritative run revision can trigger an automatic fetch.
	# Snapshot observed_at changes every poll, so it is deliberately not used here.
	var changed:=previous.is_empty() or detail_revision(previous)!=detail_revision(current) or str(previous.get("state",""))!=str(current.get("state",""))
	if not changed: return false
	var state:=str(current.get("state","unknown"))
	if state not in ["completed","failed","cancelled"]: return false
	var fetched:=selected_run
	return fetched.is_empty() or detail_revision(fetched)!=detail_revision(current) or str(fetched.get("state",""))!=state

func receive_detail_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int, id: String, serial: int = -1) -> void:
	if generation!=epoch or offline or not fixture.is_empty() or selected!=id or (serial>=0 and serial!=detail_serial): return
	detail_pending=false
	var parsed=JSON.parse_string(body.get_string_from_utf8())
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200 or not valid(parsed) or run_id(parsed)!=id:
		notice.text="Detail unavailable or malformed; retained evidence remains."
		var desired_after_failure:=str(auto_detail_revisions.get(id,""))
		if not desired_after_failure.is_empty() and auto_detail_attempted.get(id,"")!=desired_after_failure:
			_refresh_selected_detail.call_deferred(id,desired_after_failure)
		return
	details[id]=parsed.duplicate(true); selected_run=parsed.duplicate(true)
	refresh(); selection_changed.emit(selected_run)
	var desired:=str(auto_detail_revisions.get(id,""))
	if not desired.is_empty() and desired!=detail_revision(parsed):
		_refresh_selected_detail.call_deferred(id,desired)

func refresh() -> void:
	if not is_instance_valid(list): return
	var active_ids: Dictionary={}
	for run in active: active_ids[run_id(run)]=true
	var rows: Array=[]
	for run in visible_records():
		var id:=run_id(run)
		rows.append([id,history_row(run,active_ids.has(id))])
	var signature:=JSON.stringify(rows)
	if signature!=rendered_rows:
		var scroll:=list.get_v_scroll_bar().value if rendered_page==page_index else 0.0
		list.clear(); row_ids.clear()
		for row in rows:
			row_ids.append(row[0]); list.add_item(row[1]); list.set_item_tooltip(list.item_count-1,row[1])
		rendered_rows=signature
		_restore_list_scroll.call_deferred(scroll,epoch,page_index)
	rendered_page=page_index
	list.deselect_all()
	if row_ids.has(selected): list.select(row_ids.find(selected))
	latest.disabled=offline or not fixture.is_empty() or page_pending
	back.disabled=page_index<=0 or page_pending
	older.disabled=page_pending or (page_index+1>=pages.size() and (offline or not fixture.is_empty() or cursor()<1 or pages[page_index].size()<20))
	refresh_selected.disabled=offline or not fixture.is_empty() or selected.is_empty()
	stop.disabled=offline or not fixture.is_empty() or not cancellable(current_selected())
	stop.tooltip_text="This run has ended; there is no active work to cancel." if current_selected().get("state","") in ["completed","failed","cancelled"] else "Stop selected active run"
	notice.text=("Fixture · " if not fixture.is_empty() else ("Disconnected · retained records · " if offline else ""))+"Review/comparison history · Page "+str(page_index+1)+" · "+str(active.size())+" active"+(" · loading" if page_pending else "")
	full_toggle.visible=not selected_run.is_empty()
	previous_run_button.visible=not previous_run_id(selected_run).is_empty()
	if selected_run.is_empty():
		detail.text="Select a run to inspect its retained details. Field observations remain in Command."
		full_record.text=""; full_record.hide(); return
	var rendered_detail:=structured_detail(selected_run)
	if detail.text!=rendered_detail: detail.text=rendered_detail
	var raw:=JSON.stringify(presentation_record(selected_run),"  ")
	if full_record.text!=raw: full_record.text=raw

func history_row(run: Dictionary, is_active: bool) -> String:
	var request:Dictionary=run.input.get("request",{})
	var kind:=str(request.get("kind","unknown")).capitalize()
	var target:=str(request.get("target",request.get("scenario","unknown")))
	var profile:=str(request.get("profile",request.get("candidate","")))
	var outcome:=outcome_label(run)
	var result:=relative_time(run.get("updated_at",run.get("created_at",0)))+" · "+kind+" · "+target
	if not profile.is_empty(): result+=" · "+profile
	result+=" · "+outcome
	var previous:=previous_run_id(run)
	if not previous.is_empty(): result+=" · repeats "+previous
	if is_active: result="ACTIVE · "+result
	return result

func structured_detail(run: Dictionary) -> String:
	var current:Dictionary=current_selected()
	var stale:=detail_is_stale(run,current)
	var request:Dictionary=run.input.get("request",{})
	var report:Dictionary=run.get("report") if run.get("report") is Dictionary else {}
	var summary:=report_summary(report)
	var findings:=findings_for(report)
	var lines: Array[String]=[]
	var outcome:=outcome_label(run)
	if stale:
		lines.append("Current state: "+str(current.get("state","unknown"))+" · detail refresh required")
	else:
		lines.append("Outcome: "+outcome+" · state "+str(current.get("state","unknown")))
	lines.append("Target: "+str(request.get("target",request.get("scenario","Not recorded")))+target_qualifier(summary)+" · Build: "+str(request.get("profile","Not recorded")))
	lines.append("Updated: "+timestamp(run.get("updated_at",0))+" · Run: "+run_id(run))
	if stale:
		lines.append("Last fetched state: "+str(run.get("state","unknown"))+"; evidence below is from that older revision.")
		return "\n".join(lines)
	if report.is_empty():
		lines.append("Details: no completion report recorded yet.")
		return "\n".join(lines)
	if request.get("candidate","") is String and not str(request.get("candidate","")).is_empty(): lines.append("Candidate build: "+str(request.candidate))
	if summary.has("baseline_passed") or summary.has("candidate_passed"):
		lines.append("Scores: baseline "+format_count(summary.get("baseline_passed",0))+" / "+format_count(summary.get("cases",0))+" · candidate "+format_count(summary.get("candidate_passed",0))+" / "+format_count(summary.get("cases",0)))
	lines.append("")
	var finding_label:=" · "+format_count(findings.size()) if not findings.is_empty() else " · none recorded"
	if findings.is_empty() and summary.get("finding_count",0)>0: finding_label=" · details not fetched"
	lines.append("FINDINGS"+finding_label)
	for finding in findings:
		if not finding is Dictionary: continue
		var file:=str(finding.get("file",finding.get("path",finding.get("subject","Not recorded"))))
		var line:=format_count(finding.get("line","Not recorded"))
		var code:=str(finding.get("code","Not recorded"))
		var message:=str(finding.get("message",finding.get("summary",finding.get("subject","Not recorded"))))
		lines.append(file+" · line "+line+" · "+code)
		lines.append("Message: "+message)
		var action:Variant=finding.get("suggested_action",finding.get("recommendation",null))
		if action!=null and not str(action).is_empty(): lines.append("Suggested action: "+str(action))
	var review:=review_evidence(report)
	if not review.is_empty():
		lines.append("")
		lines.append("RESULT DETAILS")
		if review.has("engine"): lines.append("Engine: "+str(review.engine))
		if review.has("files_reviewed") and not summary.has("files_reviewed"): lines.append("Files reviewed: "+format_count(review.files_reviewed))
		if review.get("errors") is Array and not review.errors.is_empty():
			lines.append("Coverage limitations")
			for omission in review.errors:
				if omission is Dictionary: lines.append(str(omission.get("path","unknown"))+" · "+str(omission.get("reason","not recorded")))
	var coverage=report.get("coverage")
	if coverage is Array and not coverage.is_empty():
		if review.is_empty(): lines.append("\nRESULT DETAILS")
		lines.append("Coverage limitations")
		for item in coverage: lines.append(str(item))
	var previous:=previous_run_id(run)
	if not previous.is_empty(): lines.append("Repeat: this result repeats run "+previous+".")
	if summary.has("qualification"): lines.append("Qualification: "+str(summary.qualification))
	if summary.has("uncertainty"): lines.append("Uncertainty: "+str(summary.uncertainty))
	if summary.has("coverage"): lines.append("Coverage: "+str(summary.coverage))
	if details.has(selected): lines.append("Full detail fetched; polling does not replace this retained record.")
	else: lines.append("Summary only; source and events may not be loaded.")
	return "\n".join(lines)

func detail_is_stale(run: Dictionary, current: Dictionary) -> bool:
	if current.is_empty(): return false
	return detail_revision(run)!=detail_revision(current) or str(run.get("state",""))!=str(current.get("state",""))

static func detail_revision(run: Dictionary) -> String:
	if run.has("updated_at") and (run.updated_at is int or run.updated_at is float): return "updated:"+str(float(run.updated_at))+"/"+str(run.get("state","unknown"))
	if run.has("created_at") and (run.created_at is int or run.created_at is float): return "created:"+str(float(run.created_at))+"/"+str(run.get("state","unknown"))
	return "state:"+str(run.get("state","unknown"))

static func report_summary(report: Dictionary) -> Dictionary:
	if report.get("summary") is Dictionary: return report.summary
	if report.get("evidence") is Dictionary and report.evidence.get("summary") is Dictionary: return report.evidence.summary
	return {}

static func findings_for(report: Dictionary) -> Array:
	if report.get("findings") is Array: return report.findings
	var evidence=report.get("evidence")
	if evidence is Dictionary:
		if evidence.get("findings") is Array: return evidence.findings
		if evidence.get("review") is Dictionary and evidence.review.get("findings") is Array: return evidence.review.findings
	var summary=report.get("summary")
	if summary is Dictionary and summary.get("findings") is Array: return summary.findings
	return []

static func review_evidence(report: Dictionary) -> Dictionary:
	var evidence=report.get("evidence")
	if evidence is Dictionary and evidence.get("review") is Dictionary: return evidence.review
	if report.get("review") is Dictionary: return report.review
	return {}

static func outcome_label(run: Dictionary) -> String:
	var report:Dictionary=run.get("report") if run.get("report") is Dictionary else {}
	var summary:=report_summary(report)
	return outcome_label_from_summary(summary) if not summary.is_empty() else str(run.get("state","unknown")).capitalize().replace("_"," ")

static func outcome_label_from_summary(summary: Dictionary) -> String:
	var value:=str(summary.get("outcome","unknown"))
	return {"no_change":"No change","no_findings":"No findings","findings":"Findings","improved":"Improved","regressed":"Regressed","incomplete":"Incomplete","inconclusive":"Inconclusive","ineligible":"Ineligible","failed":"Failed"}.get(value,value.replace("_"," "))

static func previous_run_id(run: Dictionary) -> String:
	var report:Dictionary=run.get("report") if run.get("report") is Dictionary else {}
	var summary:=report_summary(report)
	return str(summary.get("previous_run","")) if summary.get("previous_run","") is String else ""

static func target_qualifier(summary: Dictionary) -> String:
	return " · synthetic" if summary.get("simulation",summary.get("synthetic_task",false)) else ""

static func format_count(value: Variant) -> String:
	if value is int: return str(value)
	if value is float and is_equal_approx(value,floor(value)): return str(int(value))
	return str(value)

static func relative_time(value: Variant) -> String:
	if not (value is int or value is float) or value<=0: return "time unavailable"
	var seconds:=maxi(0,int(Time.get_unix_time_from_system()-float(value)))
	if seconds<60: return "just now" if seconds<10 else str(seconds)+"s ago"
	if seconds<3600: return str(int(seconds/60))+"m ago"
	if seconds<86400: return str(int(seconds/3600))+"h ago"
	return str(int(seconds/86400))+"d ago"

static func presentation_record(run: Dictionary) -> Dictionary:
	var result:=run.duplicate(true)
	redact_inference(result)
	return result

static func redact_inference(value: Variant) -> void:
	if value is Dictionary:
		for key in value.keys():
			var name:=str(key).to_lower()
			if name in ["endpoint","provider_endpoint","provider_url","base_url"] and value[key] is String:
				value[key]="[redacted; see Connection · Capabilities]"
			else: redact_inference(value[key])
	elif value is Array:
		for item in value: redact_inference(item)

func _restore_list_scroll(value: float, generation: int, page: int) -> void:
	if generation==epoch and page==page_index and is_instance_valid(list): list.get_v_scroll_bar().value=value

func layout_panes() -> void:
	if panes==null: return
	panes.vertical=size.x<560
	list.custom_minimum_size.y=120 if panes.vertical else 140
	# Compact workspaces use the page's scroll area for readable evidence,
	# instead of trapping the result inside a second, few-line viewport.
	var compact:=size.x<800
	detail.fit_content=compact
	detail.scroll_active=not compact
	back.text="Newer" if compact else "Newer page"
	older.text="Older" if compact else "Older page"
	refresh_selected.text="Refresh" if compact else "Refresh selected"
	stop.text="Stop" if compact else "Stop selected run"
	refresh_selected.tooltip_text="Refresh selected run"


static func timestamp(value:Variant) -> String:
	if not (value is int or value is float) or value<=0: return "Unavailable"
	return Time.get_datetime_string_from_unix_time(int(value)).replace("T"," ")+" UTC"
