extends SceneTree
const Board=preload("res://command_board.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.content_scale_size=Vector2i(960,720)
	root.size=Vector2i(960,720)
	var board:=Board.new()
	root.add_child(board)
	board.timer.stop()
	board.fixture="test-only"
	board.snapshot={"enabled":true,"runs":[],"builds":[],"repositories":[],"memory":[]}
	board.render(); board.show()
	await process_frame
	assert(board.launch.disabled and board.watch_save.disabled)
	assert(board.watches.get_child(0).text.contains("No repositories"))
	var run_record={"input":{"id":"sample","agent":"reviewer","target":"repo-a"},"state":"completed","updated_at":1000,"detail":"Partial coverage","snapshot":{"data":{"simulation":true}},"report":{"findings":[{"code":"S307","subject":"fixture/repo#7 / x.py","line":2,"summary":"Unsafe dynamic evaluation","recommendation":"Inspect the changed input handling."}],"coverage":["Unsupported language"],"memory":{"status":"empty"}}}
	board.fixture_details={"sample":run_record}
	board.inspect("sample")
	assert(board.tabs.current_tab==3)
	var text:=""
	for l in board.detail.find_children("*","Label",true,false): text+=l.text
	assert(text.contains("S307") and text.contains("SYNTHETIC") and text.contains("Coverage limit"))
	board.fixture=""; board.online=false; board.controls()
	assert(board.launch.disabled)
	assert(board.get_global_rect().end.x<=960 and board.get_global_rect().end.y<=720)
	board.queue_free(); await process_frame
	print("Command board checks passed: fixture/offline command fences, findings, coverage and compact bounds")
	quit()
