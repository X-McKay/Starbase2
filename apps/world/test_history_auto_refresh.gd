extends SceneTree

class RecordingRequest extends Node:
	signal request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray)
	var requests: Array = []

	func cancel_request() -> void:
		pass

	func request(url: String) -> int:
		requests.append(url)
		return OK

func _initialize() -> void: run.call_deferred()

func body(value: Variant) -> PackedByteArray:
	return JSON.stringify(value).to_utf8_buffer()

func run() -> void:
	var history = preload("res://run_history.gd").new()
	root.add_child(history)
	await process_frame
	history.configure("http://127.0.0.1:1","")
	history.detail_http.queue_free()
	var request: RecordingRequest = RecordingRequest.new()
	history.add_child(request); history.detail_http=request
	var running: Dictionary={"sequence":1,"input":{"request":{"id":"auto-refresh","kind":"review","target":"sample","profile":"surveyor-v2"}},"state":"running","updated_at":10.25,"report":null}
	history.update_snapshot({"observed_at":100.0,"recent":[running],"active":[]},false)
	history.inspect_run("auto-refresh")
	assert(request.requests.size()==1,"Selection starts one detail request")
	var terminal: Dictionary=running.duplicate(true)
	terminal.state="completed"; terminal.updated_at=11.5
	terminal.report={"summary":{"outcome":"no_findings","finding_count":0.0,"files_reviewed":1.0,"simulation":true},"evidence":{"review":{"findings":[],"errors":[]}}}
	history.update_snapshot({"observed_at":101.0,"recent":[terminal],"active":[]},false)
	await process_frame
	assert(history.auto_detail_revisions.get("auto-refresh","")=="updated:11.5/completed" and request.requests.size()==1,"Terminal snapshot records a desired refresh while the older request is pending")
	history.receive_detail_response(HTTPRequest.RESULT_SUCCESS,200,[],body(running),history.epoch,"auto-refresh",history.detail_serial)
	await process_frame
	assert(request.requests.size()==2,"Older response drains exactly one automatic request for the newer revision")
	history.receive_detail_response(HTTPRequest.RESULT_SUCCESS,200,[],body(terminal),history.epoch,"auto-refresh",history.detail_serial)
	assert(history.selected_run.state=="completed" and history.detail.text.contains("Outcome: No findings") and not history.detail.text.contains("detail refresh required"),"Current terminal detail replaces the stale selection")
	history.update_snapshot({"observed_at":102.0,"recent":[terminal],"active":[]},false)
	await process_frame
	assert(request.requests.size()==2,"An unchanged snapshot revision does not retry detail")
	var accepted: Dictionary=history.selected_run.duplicate(true)
	var old_serial: int=history.detail_serial
	history.detail_serial+=1
	var delayed: Dictionary=running.duplicate(true); delayed.report={"summary":{"outcome":"old"}}
	history.receive_detail_response(HTTPRequest.RESULT_SUCCESS,200,[],body(delayed),history.epoch,"auto-refresh",old_serial)
	assert(history.selected_run==accepted,"Delayed response from the prior selection serial cannot replace current detail")
	history.queue_free(); await process_frame
	print("HISTORY_AUTO_REFRESH_PASSED: pending race, newer revision drain, terminal detail, no retry, serial fence")
	quit()
