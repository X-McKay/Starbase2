extends SceneTree
## Smoke-workspace behavior: summaries stay concise; full source and exact identity remain accessible.
var failures:Array[String]=[]
func check(ok:bool,message:String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var panel=preload("res://operations_panel.gd").new(); panel.fixture="synthetic"; root.add_child(panel)
	var record:Dictionary={"input":{"request":{"id":"exact-review","kind":"review"}},"state":"completed","updated_at":100,"report":{"summary":{"outcome":"no-change"},"coverage":["Python only"]},"events":[{"secret_test_marker":"retained-event"}]}
	panel.update_snapshot({"schema_version":2,"recent":[record],"active":[],"targets":[],"builds":[],"duties":[]},true)
	panel.history.inspect_run("exact-review")
	check(panel.review_status.text.contains("1 review records"),"Review count comes from authoritative projection")
	check(panel.review_status.text.contains("commands disabled"),"Fixture availability is explicit")
	check(not panel.history.full_record.visible,"Full JSON is initially collapsed")
	check(not panel.history.detail.text.contains("retained-event") and panel.history.full_record.text.contains("retained-event"),"Source remains available without occupying summary")
	check(panel.history.detail.text.contains("exact-review") and panel.history.detail.text.contains("Python only") and panel.history.detail.text.contains("UTC"),"Identity, coverage and timestamp remain visible")
	panel.history.full_toggle.pressed.emit()
	check(panel.history.full_record.visible,"Keyboard activated disclosure reveals full source")
	var board=preload("res://command_board.gd").new(); board.fixture="synthetic"; root.add_child(board); board.timer.stop()
	board.fixture=""; board.online=true
	board.snapshot={"enabled":true,"memory":[{"id":"episode","finding":{"summary":"Review retained finding"},"agent":"reviewer","target":"repository","decision":"proposed","revision":1,"source_run":"exact-source"}]}
	board.set_installation({"installation":{"capabilities":{"memory":{"enabled":false,"reason":"Disabled for this installation"}}}},false)
	board.render()
	var review_count:=0
	for action in board.memories.find_children("*","Button",true,false):
		if action.has_meta("memory_review"):
			review_count+=1; check(action.disabled,"Disabled memory cannot expose enabled review actions")
	check(review_count==2 and board.memory_status.text.contains("DISABLED"),"Disabled memory retains proposals and readable policy")
	board.commands.uncertain=true; board.controls()
	check(board.reconcile.visible and not board.reconcile.disabled and board.watch_save.disabled,"Uncertain outcome exposes reconciliation and fences new actions")
	board.queue_free(); panel.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("EMBER_OPERATIONS_PASSED: count, fixture label, exact identity, retained source disclosure, memory policy")
	quit(0 if failures.is_empty() else 1)
