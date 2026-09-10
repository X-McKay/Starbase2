extends SceneTree
const Harness=preload("res://live_duty_controls.gd")
class Transport extends Node:
	var uncertain:=false
	var phase:=""
class Board extends Node:
	var pending:=false
	var snapshot:Dictionary={"duties":[],"runs":[]}
	var commands:=Transport.new()
	var duty_records:=VBoxContainer.new()
	var tabs:=TabContainer.new()
class Scene extends Node:
	var fixture_path:=""
	var api:="http://127.0.0.1:8787"
	var hud:Dictionary={}
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene:=Scene.new(); root.add_child(scene)
	var board:=Board.new(); scene.add_child(board); board.add_child(board.commands); board.add_child(board.duty_records); board.add_child(board.tabs)
	for i in range(5): board.tabs.add_child(Control.new())
	scene.hud={"board":board}
	for id in Harness.DUTIES:
		var duty={"id":id,"agent":"watchkeeper","target":"source","inference":true,"enabled":true,"interval_seconds":300,"generation":4}
		board.snapshot.duties.append(duty)
		board.snapshot.runs.append({"input":{"id":"duty-"+id+"-4-1"},"state":"completed"})
		for enabled in [false,true]:
			var button:=Button.new(); button.set_meta("focus_key",id+("/Resume duty" if enabled else "/Pause duty")); board.duty_records.add_child(button)
			button.pressed.connect(func(): duty.enabled=enabled; duty.generation+=1)
	var harness:=Harness.new()
	var directory:=OS.get_environment("TMPDIR").path_join("starbase2-duty-control-test")
	DirAccess.make_dir_recursive_absolute(directory)
	assert(await harness.run(scene,directory))
	assert(harness.events.size()==8)
	for duty in board.snapshot.duties: assert(duty.enabled and duty.inference and duty.generation==6 and duty.interval_seconds==300)
	board.snapshot.runs=[]
	var blocked:=Harness.new(); assert(not await blocked.run(scene,directory)); assert(blocked.events.is_empty())
	scene.queue_free(); await process_frame
	print("Live duty control harness checks passed: exact named buttons, authoritative generation checks, restoration and timer precondition; synthetic only")
	quit()
