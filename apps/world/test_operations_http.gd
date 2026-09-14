extends SceneTree
const Operations=preload("res://operations_panel.gd")
var api:=""
var accepted_ids:Array[String]=[]
var reader:=HTTPRequest.new()
func _initialize() -> void: run.call_deferred()
func snapshot() -> Dictionary:
	assert(reader.request(api+"/v2/snapshot")==OK)
	var response=await reader.request_completed
	assert(response[0]==HTTPRequest.RESULT_SUCCESS and response[1]==200)
	return JSON.parse_string(response[3].get_string_from_utf8())
func settled(panel:Node) -> void:
	var deadline:=Time.get_ticks_msec()+6000
	while panel.commands.phase!="" and Time.get_ticks_msec()<deadline: await process_frame
	assert(panel.commands.phase=="")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--api="): api=arg.trim_prefix("--api=")
	assert(api.begins_with("http://127.0.0.1:"))
	root.add_child(reader); reader.timeout=5
	var panel=Operations.new(); root.add_child(panel)
	panel.accepted.connect(func(id:String): accepted_ids.append(id))
	assert(panel.configure(api))
	var data=await snapshot(); panel.update_snapshot(data,false)
	panel.review_button.pressed.emit(); await settled(panel)
	assert(accepted_ids.size()==1)
	panel.candidate.select(1); panel.refresh_controls()
	panel.evaluation_button.pressed.emit(); await settled(panel)
	assert(accepted_ids.size()==2)
	panel.target.select(1); panel.refresh_controls()
	panel.review_button.pressed.emit(); await settled(panel)
	assert(accepted_ids.size()==2 and panel.notice.text.contains("rejected"))
	panel.target.select(0); panel.refresh_controls()
	panel.duty_id.text="synthetic-duty"; panel.interval.value=60
	panel.duty_button.pressed.emit(); await settled(panel)
	assert(accepted_ids.size()==3)
	data=await snapshot(); panel.update_snapshot(data,false)
	assert(data.duties[0].generation==1)
	var pause:Button
	for child in panel.duties.get_children():
		if child is Button: pause=child
	assert(pause!=null); pause.pressed.emit(); await settled(panel)
	assert(accepted_ids.size()==4 and not panel.commands.uncertain)
	assert(panel.notice.text.contains("exact settings and next generation"))
	data=await snapshot(); assert(data.duties[0].generation==2 and not data.duties[0].enabled)
	panel.update_snapshot(data,false)
	panel.history.inspect_run("run-40")
	var deadline:=Time.get_ticks_msec()+5000
	while not panel.history.details.has("run-40") and Time.get_ticks_msec()<deadline: await process_frame
	assert(panel.history.details.has("run-40"))
	panel.history.load_older()
	deadline=Time.get_ticks_msec()+5000
	while panel.history.page_pending and Time.get_ticks_msec()<deadline: await process_frame
	assert(panel.history.page_index==1 and panel.history.pages[1].size()==20)
	assert(panel.history.visible_records()[0].input.request.id=="run-1")
	assert(panel.history.selected=="run-40" and panel.history.selected_run.events.size()==1)
	panel.update_snapshot(data,false)
	assert(panel.history.selected=="run-40" and panel.history.selected_run.events.size()==1)
	panel.history.go_back(); assert(panel.history.page_index==0)
	var unknown:Dictionary=data.duplicate(true); unknown.erase("installation")
	panel.update_snapshot(unknown,false)
	panel.review_button.pressed.emit(); panel.evaluation_button.pressed.emit(); panel.duty_button.pressed.emit()
	assert(panel.commands.phase=="" and accepted_ids.size()==4)
	assert(panel.configure(api,"synthetic-fixture")); panel.update_snapshot(data,false)
	panel.review_button.pressed.emit(); panel.evaluation_button.pressed.emit(); panel.duty_button.pressed.emit(); panel.history.load_latest(); panel.history.inspect_run("run-40")
	assert(panel.commands.phase=="" and accepted_ids.size()==4)
	assert(panel.configure(api)); panel.update_snapshot(data,false)
	panel.duty_id.text="drift-duty"; panel.duty_button.pressed.emit(); await settled(panel)
	assert(panel.commands.uncertain and accepted_ids.size()==4)
	assert(panel.notice.text.contains("unknown") and not panel.configure(api))
	# Retrying while uncertain performs another GET, never another write.
	panel.duty_button.pressed.emit(); await settled(panel)
	assert(panel.commands.uncertain and accepted_ids.size()==4)
	panel.queue_free(); reader.queue_free(); await process_frame
	print("OPERATIONS_HTTP_PASSED")
	quit()
