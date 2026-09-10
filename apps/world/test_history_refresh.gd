extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var history=load("res://run_history.gd").new()
	root.add_child(history)
	await process_frame
	var buttons=history.find_children("*","Button",true,false).filter(func(b): return b.text=="Refresh selected")
	if buttons.size()!=1:
		push_error("A selected history row needs an explicit keyboard-accessible refresh action")
		history.queue_free(); await process_frame; quit(1); return
	history.configure("http://127.0.0.1:1","fixture")
	var record={"sequence":1,"input":{"request":{"id":"same-row","kind":"review"}},"state":"running","updated_at":1,"report":null}
	history.update_snapshot({"recent":[record],"active":[]},false)
	history.inspect_run("same-row")
	assert(buttons[0].disabled,"Fixture inspection must not enable HTTP refresh")
	history.fixture=""; history.refresh()
	assert(not buttons[0].disabled and buttons[0].focus_mode==Control.FOCUS_ALL)
	var serial=history.detail_serial
	buttons[0].pressed.emit()
	assert(history.detail_serial==serial+1 and history.selected=="same-row")
	history.detail_http.cancel_request()
	var updated=record.duplicate(true); updated.state="completed"; updated.updated_at=2; updated.report={"summary":{"outcome":"Evidence retained"}}
	history.receive_detail_response(HTTPRequest.RESULT_SUCCESS,200,[],JSON.stringify(updated).to_utf8_buffer(),history.epoch,"same-row",history.detail_serial)
	assert(history.selected_run.state=="completed" and history.detail.text.contains("Evidence retained"))
	history.update_snapshot({"recent":[updated],"active":[]},true)
	assert(buttons[0].disabled)
	history.queue_free(); await process_frame
	print("HISTORY_REFRESH_PASSED: same selection refresh, newer detail, keyboard focus and fixture/offline fencing")
	quit()
