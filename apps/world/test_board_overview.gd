extends SceneTree
const Board=preload("res://command_board.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	assert(Board.run_message({"state":"cancelled","detail":"Stop requested"}).begins_with("Cancellation acknowledged"))
	var records: Array=[]
	for i in range(40): records.append({"input":{"id":str(i),"target":"repo-a"},"state":"completed","updated_at":2000+i})
	records.append({"input":{"id":"active","target":"repo-a"},"state":"running","updated_at":100})
	assert(Board.ordered_runs(records)[0].input.id=="active")
	assert(Board.ordered_runs(records).size()==31)
	var watch={"id":"repo-a","config":{"enabled":true,"removed":false,"interval_seconds":30}}
	var status=Board.watch_status(watch,records,10000)
	assert(status.text.contains("Busy") and status.text.contains("time unavailable"))
	assert(not status.overdue)
	records[0].source_observed_at=1000
	status=Board.watch_status(watch,records,10000)
	assert(status.overdue and status.text.contains("Source observed"))
	watch.config.enabled=false
	assert(Board.watch_status(watch,records,10000).text.contains("Paused"))
	assert(not Board.watch_status(watch,records,10000).overdue)
	assert(Board.briefing_text({"runs":records,"repositories":[watch]},10000).contains("41 runs"))
	var board=Board.new(); root.add_child(board); board.timer.stop()
	board.snapshot={"enabled":true,"runs":[],"repositories":[],"builds":[],"memory":[]}
	board.online=true
	board.set_installation({"installation":{"capabilities":{"field":{"enabled":false,"reason":"Paused policy"},"memory":{"enabled":false,"reason":"Recall off"}}}},false)
	assert(board.watch_save.disabled)
	assert(board.policy.text.contains("Paused policy"))
	var stop=board.button(board.runs,"Stop observation",func(): pass,true)
	board.controls(); assert(not stop.disabled)
	board.fixture="oldfixture"; board.fixture_details={"old":{}}
	board.commands.uncertain=true
	board.set_api("http://127.0.0.1:18801")
	assert(board.api=="http://127.0.0.1:8787" and board.fixture=="oldfixture")
	board.commands.uncertain=false
	board.set_api("http://127.0.0.1:18801")
	assert(board.snapshot.is_empty() and board.fixture_details.is_empty() and board.fixture.is_empty())
	assert(board.commands.api==board.api and not board.online)
	board.queue_free(); await process_frame
	print("Board overview passed: active retention, source-time truth, bounded briefing, policy/cancel separation, endpoint reset")
	quit()
