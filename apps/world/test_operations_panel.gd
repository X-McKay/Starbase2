extends SceneTree
class Recorder extends "res://commands.gd":
	var calls:Array=[]
	func submit(endpoint:String,data:Dictionary,id:String,lookup:String="") -> void:
		calls.append({"path":endpoint,"data":data.duplicate(true),"id":id,"lookup":lookup})
var failures:Array[String]=[]
func check(value:bool,message:String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var panel=preload("res://operations_panel.gd").new()
	panel.fixture="test"; root.add_child(panel)
	await process_frame
	var real=panel.commands; panel.remove_child(real); real.queue_free()
	var recorder:=Recorder.new(); panel.commands=recorder; panel.add_child(recorder)
	var data:Dictionary={"schema_version":2,"observed_at":100,"worker":{"available":true},"recent":[],"active":[],"targets":[{"id":"workspace","label":"Checkout","simulation":false},{"id":"sample","label":"Training","simulation":true}],"builds":[{"digest":"a","manifest":{"profile":"surveyor-v1"}},{"digest":"b","manifest":{"profile":"surveyor-v2"}}],"duties":[],"installation":{"id":"test","capabilities":{"review":{"enabled":true},"evaluation":{"enabled":true},"inference":{"enabled":false}}}}
	panel.update_snapshot(data,false)
	panel.submit_run(false)
	check(recorder.calls.is_empty() and panel.review_button.disabled,"Fixture cannot submit")
	panel.fixture=""; panel.update_snapshot(data,false)
	panel.submit_run(false)
	check(recorder.calls.size()==1 and recorder.calls[0].path=="/v2/runs" and recorder.calls[0].data.kind=="review" and not recorder.calls[0].data.inference,"Explicit local review uses existing API with no inference")
	panel.submit_run(true)
	check(recorder.calls.size()==1,"Identical baseline and candidate are rejected locally")
	panel.candidate.select(1); panel.refresh_controls(); panel.submit_run(true)
	check(recorder.calls.size()==2 and recorder.calls[-1].data.kind=="evaluation" and recorder.calls[-1].data.target=="sample" and recorder.calls[-1].data.profile=="surveyor-v1" and recorder.calls[-1].data.candidate=="surveyor-v2","Comparison uses distinct registered profiles and synthetic target")
	check(recorder.calls[0].id!=recorder.calls[1].id,"Explicit actions receive separate identities")
	data.duties=[{"id":"repository-watch","target":"workspace","profile":"surveyor-v1","enabled":true,"interval_seconds":300,"generation":7}]
	panel.update_snapshot(data,false); panel.save_duty()
	check(recorder.calls[-1].path=="/v2/duties" and recorder.calls[-1].data.generation==7 and recorder.calls[-1].lookup=="/v2/snapshot","Duty edits carry current generation and snapshot reconciliation")
	data.installation.capabilities.review.enabled=false; data.installation.capabilities.evaluation.enabled=false
	panel.update_snapshot(data,false)
	check(panel.review_button.disabled and panel.evaluation_button.disabled and panel.duty_button.disabled,"Disabled policy blocks new work")
	var paused:Dictionary=data.duties[0].duplicate(); paused.enabled=false
	panel.write_duty(paused); panel.cancel_run("active-run")
	check(recorder.calls[-2].data.enabled==false and recorder.calls[-1].path=="/v2/runs/active-run/cancel","Pause and cancellation remain independent of admission policy")
	var count:=recorder.calls.size()
	panel.update_snapshot(data,true); panel.cancel_run("active-run"); panel.write_duty(paused)
	check(recorder.calls.size()==count and panel.briefing.text.begins_with("LAST KNOWN"),"Outage retains truthful briefing and prevents writes")
	recorder.uncertain=true
	check(not panel.configure("http://127.0.0.1:9999"),"Uncertain command fences endpoint changes")
	recorder.uncertain=false
	check(panel.configure("http://127.0.0.1:9999","fixture") and panel.snapshot.is_empty() and panel.history.selected.is_empty(),"New endpoint clears old installation evidence")
	# Match the compact native viewport and panel padding, including large text.
	root.size=Vector2i(800,640); root.content_scale_size=Vector2i(800,640)
	panel.theme=Theme.new(); panel.theme.default_font_size=19
	var frame:=StyleBoxFlat.new(); frame.set_content_margin_all(18); panel.add_theme_stylebox_override("panel",frame)
	panel.offset_left=22; panel.offset_right=-22; panel.offset_top=154; panel.offset_bottom=-80
	panel.update_snapshot(data,false); panel.show()
	await process_frame; await process_frame
	check(not panel.briefing_scroll.visible and panel.tabs.size.y>=250,"Compact form retains at least 250 pixels with briefing collapsed")
	panel.briefing_toggle.pressed.emit()
	check(panel.briefing_scroll.visible and panel.briefing.text.contains("records in snapshot"),"Complete briefing remains keyboard-accessible through disclosure")
	panel.briefing_toggle.pressed.emit(); panel.tabs.current_tab=3
	await process_frame; await process_frame
	check(not panel.history.panes.vertical,"History list and evidence share compact wide viewport")
	check(panel.history.detail.get_global_rect().end.y<=panel.tabs.get_global_rect().end.y+2,"Evidence pane fits without scrolling past the run list")
	panel.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("OPERATIONS_PANEL_PASSED: fixture/policy fencing, review/comparison contracts, duty generation, independent stop/pause, stale briefing and endpoint reset")
	quit(0 if failures.is_empty() else 1)
