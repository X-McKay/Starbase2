extends SceneTree
var failures:Array[String]=[]
func check(ok:bool,message:String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(800,640); root.content_scale_size=Vector2i(800,640)
	var board=preload("res://command_board.gd").new(); board.large_text=true; board.fixture="synthetic"
	root.add_child(board); board.timer.stop()
	board.snapshot={"enabled":true,"runs":[],"repositories":[],"memory":[],"builds":[{"manifest":{"agent":"watchkeeper","target":{"id":"cluster","kind":"fixture"}}}]}
	board.render(); board.show()
	await process_frame; await process_frame; await process_frame
	var page:ScrollContainer=board.tabs.get_child(0)
	check(page.size.y>=230,"Compact large-text field workspace reserves at least 230 pixels for its form")
	check(board.launch.get_global_rect().end.y<=page.get_global_rect().end.y,"Initial viewport shows Start observation without scrolling")
	check(board.targets.get_global_rect().position.y>=page.get_global_rect().position.y,"Configured target starts inside visible content")
	check(not board.notice.visible,"Empty notice does not consume vertical space")
	board.guidance_toggle.pressed.emit(); await process_frame
	check(board.guidance.visible and not board.tabs.visible and board.briefing.is_visible_in_tree() and board.policy.is_visible_in_tree(),"Info exposes full snapshot and policy in a separate scrollable view")
	board.guidance_toggle.pressed.emit(); await process_frame
	check(board.tabs.visible and not board.guidance.visible,"Back restores selected workspace without stacked header growth")
	for failure in failures: push_error(failure)
	board.queue_free(); await process_frame
	if failures.is_empty(): print("FIELD_COMPACT_PASSED: 800x640 large text target, opt-in, initial action and snapshot/policy access")
	quit(0 if failures.is_empty() else 1)
