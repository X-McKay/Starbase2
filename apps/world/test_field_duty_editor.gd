extends SceneTree
const Board=preload("res://command_board.gd")
class Recorder extends Node:
	var payload:Dictionary={}
	var path:=""
	func submit(endpoint:String,value:Dictionary,_id:String,_lookup:String="") -> void:
		path=endpoint; payload=value.duplicate(true)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var board:=Board.new(); root.add_child(board); board.timer.stop()
	board.online=true
	board.installation_snapshot={"installation":{"capabilities":{"field":{"enabled":true},"inference":{"enabled":true}}}}
	board.snapshot={"enabled":true,"runs":[],"repositories":[],"memory":[],"duties":[],"builds":[{"manifest":{"agent":"reviewer","target":{"id":"configured-github","kind":"github_repository","repository":"owner/repo","allow_inference":true}}}]}
	board.render()
	assert(board.targets.item_count==1 and board.duty_target.item_count==1,"Configured GitHub targets do not require dynamic repository watch")
	assert(not board.observation_inference.button_pressed and not board.duty_inference.button_pressed)
	board.duty_identity.text="watch-example"; board.duty_inference.button_pressed=true; board.duty_interval.value=900
	var request:=board.field_duty_request()
	assert(request=={"id":"watch-example","agent":"reviewer","target":"configured-github","interval_seconds":900,"enabled":true,"inference":true,"generation":0})
	board.snapshot.duties=[request.duplicate(true)]
	assert(board.field_duty_request().is_empty(),"Existing identity must be explicitly loaded before edit")
	board.load_field_duty(request)
	board.duty_interval.value=1800; board.duty_enabled.button_pressed=false
	var changed:=board.field_duty_request()
	assert(changed.generation==1 and changed.inference and not changed.enabled and changed.interval_seconds==1800)
	assert(board.snapshot.duties[0]==request,"Editor must not mutate authoritative record")
	board.snapshot.duties[0].generation=1
	assert(board.field_duty_request().is_empty(),"New retained generation invalidates stale editor")
	board.load_field_duty(board.snapshot.duties[0])
	board.installation_snapshot.installation.capabilities.inference.enabled=false
	board.controls()
	assert(board.observation_inference.disabled and not board.duty_inference.disabled)
	assert(board.field_duty_request().is_empty(),"Unavailable inference cannot be newly submitted")
	board.duty_inference.button_pressed=false
	assert(not board.field_duty_request().is_empty())
	board.fixture="fixture"; board.controls(); assert(board.duty_save.disabled and board.launch.disabled)
	board.fixture=""; board.online=false; board.controls(); assert(board.duty_save.disabled)
	board.new_field_duty(); assert(board.duty_identity.editable and not board.duty_inference.button_pressed)
	board.online=true; board.installation_snapshot.installation.capabilities.inference.enabled=true
	board.controls()
	var real_commands:Node=board.commands; board.remove_child(real_commands); real_commands.queue_free()
	var recorder:=Recorder.new(); board.add_child(recorder); board.commands=recorder
	board.observation_inference.button_pressed=true; board.launch.pressed.emit()
	assert(recorder.path=="/v4/runs" and recorder.payload.inference and recorder.payload.target=="configured-github")
	board.duty_identity.text="new-native-duty"; board.duty_inference.button_pressed=true; board.duty_save.pressed.emit()
	assert(recorder.path=="/v4/duties" and recorder.payload.generation==0 and recorder.payload.inference)
	assert(board.snapshot.duties.size()==1,"Submitting button action never inserts optimistic duty")
	board.duty_identity.text="bad_name"; assert(board.field_duty_request().is_empty())
	board.snapshot.builds[0].manifest.target.allow_inference=false; board.render()
	assert(board.observation_inference.disabled and not board.observation_inference.button_pressed)
	board.load_field_duty(board.snapshot.duties[0])
	board.snapshot.builds=[{"manifest":{"agent":"watchkeeper","target":{"id":"other","kind":"fixture","allow_inference":false}}}]
	board.render()
	assert(board.duty_target.selected==-1 and board.duty_save.disabled,"Removed target must not silently retarget an open edit")
	assert(board.field_duty_request().is_empty())
	board.signature=""; board.render(); assert(board.duty_target.selected==-1,"Missing selection remains blocked on later polls")
	board.queue_free(); await process_frame
	print("Field duty editor checks passed: configured GitHub target, opt-in, exact generations, stale edit refusal, authoritative state and fixture/offline/policy gates")
	quit()
