extends SceneTree
var failures:Array[String]=[]
func check(ok:bool,message:String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var panel=load("res://operations_panel.gd").new(); panel.fixture="fixture"; root.add_child(panel); panel.show()
	await process_frame; await process_frame
	var before:Vector2=panel.tabs.position
	panel.commands.feedback.emit("Request accepted · watching authoritative state.",false)
	await process_frame; await process_frame
	check(panel.tabs.position==before,"Feedback must not move form controls")
	var strip=load("res://crew_strip.gd").new(); root.add_child(strip)
	var intent={"unknown":false,"active_count":0}
	strip.project("repair",intent,"Walking home"); var walking:String=strip.entries.repair.text
	strip.project("repair",intent)
	check(strip.entries.repair.text==walking,"Operational crew status must not change when ambient activity is omitted")
	panel.queue_free(); strip.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("UAT_REGRESSIONS_PASSED")
	quit(0 if failures.is_empty() else 1)
