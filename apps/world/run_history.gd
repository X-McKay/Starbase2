extends VBoxContainer
## Read-only V2 history. Paging never replaces the independently supplied active list.
signal cancel_requested(id: String)
signal selection_changed(run: Dictionary)
const StateView = preload("res://state.gd")
var api := "http://127.0.0.1:8787"
var fixture := ""
var offline := true
var selected := ""
var selected_run: Dictionary = {}
var active: Array = []
var pages: Array = []
var page_index := -1
var details: Dictionary = {}
var latest_records: Dictionary = {}
var detail_serial := 0
var epoch := 0
var page_pending := false
var page_http := HTTPRequest.new()
var detail_http := HTTPRequest.new()
var notice: Label
var list: ItemList
var detail: RichTextLabel
var panes: BoxContainer
var older: Button
var back: Button
var latest: Button
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
	stop=button(controls,"Stop selected run",func():
		if not offline and fixture.is_empty() and cancellable(current_selected()): cancel_requested.emit(selected))
	notice=Label.new(); notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; add_child(notice)
	panes=BoxContainer.new(); panes.add_theme_constant_override("separation",12)
	panes.size_flags_vertical=Control.SIZE_EXPAND_FILL; add_child(panes)
	list=ItemList.new(); list.custom_minimum_size=Vector2(0,140); list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	list.size_flags_vertical=Control.SIZE_EXPAND_FILL
	list.item_selected.connect(func(index): inspect_run(row_ids[index])); panes.add_child(list)
	detail=RichTextLabel.new(); detail.custom_minimum_size=Vector2(0,140); detail.size_flags_vertical=Control.SIZE_EXPAND_FILL
	detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL; detail.size_flags_stretch_ratio=1.4
	detail.selection_enabled=true; detail.bbcode_enabled=false; panes.add_child(detail)
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
	refresh()

func invalidate_requests() -> void:
	epoch+=1; page_pending=false
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
	offline=disconnected
	if snapshot.get("active") is Array: active=records(snapshot.active)
	if snapshot.get("recent") is Array:
		var recent:=records(snapshot.recent)
		if pages.is_empty() or (page_index==0 and JSON.stringify(pages[0])!=JSON.stringify(recent)):
			if page_pending: invalidate_requests()
			# New latest windows invalidate cached cursors, but never replace an older page being inspected.
			pages=[recent]; page_index=0
	# Keep source/events bound to the fetched revision; show current snapshot state separately.
	latest_records.clear()
	for run in records(snapshot.get("recent",[]))+active:
		latest_records[run_id(run)]=run.duplicate(true)
	refresh()

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
	var error:=page_http.request(api+"/v2/runs"+("?before="+str(before) if before>0 else ""))
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
	detail_serial+=1
	selected=id
	selected_run=details.get(id,{}).duplicate(true)
	if selected_run.is_empty():
		for run in visible_records():
			if run_id(run)==id: selected_run=run.duplicate(true); break
	refresh(); selection_changed.emit(selected_run)
	if offline or not fixture.is_empty(): return
	detail_http.cancel_request()
	if detail_callback.is_valid() and detail_http.request_completed.is_connected(detail_callback): detail_http.request_completed.disconnect(detail_callback)
	detail_callback=receive_detail_response.bind(epoch,id,detail_serial)
	detail_http.request_completed.connect(detail_callback,CONNECT_ONE_SHOT)
	if detail_http.request(api+"/v2/runs/"+id.uri_encode())!=OK: notice.text="Detail request could not start; retained evidence remains."

func receive_detail_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int, id: String, serial: int = -1) -> void:
	if generation!=epoch or offline or not fixture.is_empty() or selected!=id or (serial>=0 and serial!=detail_serial): return
	var parsed=JSON.parse_string(body.get_string_from_utf8())
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200 or not valid(parsed) or run_id(parsed)!=id:
		notice.text="Detail unavailable or malformed; retained evidence remains."; return
	details[id]=parsed.duplicate(true); selected_run=parsed.duplicate(true)
	refresh(); selection_changed.emit(selected_run)

func refresh() -> void:
	if not is_instance_valid(list): return
	var active_ids: Dictionary={}
	for run in active: active_ids[run_id(run)]=true
	var rows: Array=[]
	for run in visible_records():
		var id:=run_id(run)
		rows.append([id,("ACTIVE · " if active_ids.has(id) else "")+str(run.state)+" · "+str(run.input.request.get("kind","unknown"))+" · "+id])
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
	stop.disabled=offline or not fixture.is_empty() or not cancellable(current_selected())
	notice.text=("Fixture · " if not fixture.is_empty() else ("Disconnected · retained records · " if offline else ""))+"Review/comparison history · Page "+str(page_index+1)+" · "+str(active.size())+" active"+(" · loading" if page_pending else "")
	if selected_run.is_empty(): detail.text="Select a run to inspect its retained details. Field observations remain in Command."; return
	var report=selected_run.get("report")
	var evidence:="No completion evidence recorded."
	if report is Dictionary: evidence="Retained report. Inspect summary and coverage below; partial coverage is not certification."
	var rendered_detail:="Run "+selected+"\nLatest known state: "+str(current_selected().get("state","unknown"))+"\nRetained detail state: "+str(selected_run.get("state","unknown"))+"\nEvidence summary: "+(JSON.stringify(report.get("summary",{})) if report is Dictionary else "Not recorded")+"\nUpdated: "+str(selected_run.get("updated_at","unknown"))+"\n"+str(selected_run.get("detail",""))+"\n"+evidence+"\n"+("Full detail fetched; polling does not replace this retained record. Select again to refresh.\n" if details.has(selected) else "Summary only; source and events may not be loaded.\n")+"\n"+JSON.stringify(selected_run,"  ")

	if detail.text!=rendered_detail: detail.text=rendered_detail

func _restore_list_scroll(value: float, generation: int, page: int) -> void:
	if generation==epoch and page==page_index and is_instance_valid(list): list.get_v_scroll_bar().value=value

func layout_panes() -> void:
	if panes==null: return
	panes.vertical=size.x<560
	list.custom_minimum_size.y=120 if panes.vertical else 140
