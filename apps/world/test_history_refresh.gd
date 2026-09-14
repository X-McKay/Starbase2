extends SceneTree
func _initialize() -> void: run.call_deferred()
func record(sequence: int, state: String = "completed") -> Dictionary:
	return {"sequence":sequence,"input":{"request":{"id":"run-"+str(sequence),"kind":"review"}},"state":state,"updated_at":sequence,"report":null}
func run() -> void:
	var history=load("res://run_history.gd").new()
	root.add_child(history)
	await process_frame
	var buttons=history.find_children("*","Button",true,false).filter(func(b): return b.text in ["Refresh selected","Refresh"])
	if buttons.size()!=1:
		push_error("A selected history row needs an explicit keyboard-accessible refresh action")
		history.queue_free(); await process_frame; quit(1); return
	history.configure("http://127.0.0.1:1","fixture")
	var running_record={"sequence":1,"input":{"request":{"id":"same-row","kind":"review"}},"state":"running","updated_at":1,"report":null}
	history.update_snapshot({"recent":[running_record],"active":[]},false)
	history.inspect_run("same-row")
	assert(buttons[0].disabled,"Fixture inspection must not enable HTTP refresh")
	var readable:=record(2)
	readable.input.request.target="sample"; readable.input.request.profile="surveyor-v2"
	readable.input.builds=[{"manifest":{"inference":{"endpoint":"https://private.example/v1"}}}]
	readable.report={"summary":{"outcome":"no_change","previous_run":"run-1","files_reviewed":1.0,"finding_count":1.0,"simulation":true},"evidence":{"review":{"findings":[{"file":"metrics.py","line":2.0,"code":"S307","message":"Use a safe parser."}],"errors":[{"path":"README.md","reason":"unsupported"}],"files_reviewed":1.0}}}
	history.update_snapshot({"recent":[readable],"active":[]},false)
	history.inspect_run("run-2")
	assert(history.list.get_item_text(0).contains("No change") and history.list.get_item_text(0).contains("repeats run-1"),"History rows expose normalized outcomes and repeat identity")
	assert(history.detail.text.contains("metrics.py") and history.detail.text.contains("S307") and history.detail.text.contains("Use a safe parser") and history.detail.text.contains("unsupported"),"Review details render labelled findings and coverage")
	assert(history.full_record.text.contains("redacted; see Connection") and not history.full_record.text.contains("private.example"),"Raw presentation redacts inference endpoints")
	assert(history.selected_run.input.builds[0].manifest.inference.endpoint=="https://private.example/v1","Endpoint redaction does not mutate retained evidence")
	history.inspect_run("same-row")
	history.fixture=""; history.refresh()
	assert(not buttons[0].disabled and buttons[0].focus_mode==Control.FOCUS_ALL)
	var serial=history.detail_serial
	buttons[0].pressed.emit()
	assert(history.detail_serial==serial+1 and history.selected=="same-row")
	history.detail_http.cancel_request()
	var updated=running_record.duplicate(true); updated.state="completed"; updated.updated_at=2; updated.report={"summary":{"outcome":"Evidence retained"}}
	history.receive_detail_response(HTTPRequest.RESULT_SUCCESS,200,[],JSON.stringify(updated).to_utf8_buffer(),history.epoch,"same-row",history.detail_serial)
	assert(history.selected_run.state=="completed" and history.detail.text.contains("Evidence retained"))
	history.update_snapshot({"recent":[updated],"active":[]},true)
	assert(buttons[0].disabled)
	history.queue_free(); await process_frame
	print("HISTORY_REFRESH_PASSED: same selection refresh, newer detail, keyboard focus and fixture/offline fencing")
	quit()
