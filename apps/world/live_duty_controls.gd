extends RefCounted
## Explicit qualification only. No action unless the live capture flag opts in.
const Commands=preload("res://commands.gd")
const DUTIES=["starbase2-watchkeeper-autonomous","starbase2-github-autonomous"]
var events:Array=[]
var failure:=""
func record(directory:String) -> void:
	var file:=FileAccess.open(directory.path_join("live-duty-controls.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"events":events,"failure":failure,"scope":"explicit native Pause/Resume for two named duties; no retry on uncertainty"},"  ")); file.close()
func retained(board:Node,id:String) -> Dictionary:
	for duty in board.snapshot.get("duties",[]):
		if duty.get("id")==id: return duty.duplicate(true)
	return {}
func action_button(board:Node,id:String,enabled:bool) -> Button:
	var key:=id+("/Resume duty" if enabled else "/Pause duty")
	for button in board.duty_records.find_children("*","Button",true,false):
		if button.get_meta("focus_key","")==key: return button
	return null
func run(scene:Node,directory:String) -> bool:
	var board:Node=scene.hud.board
	var tree:SceneTree=scene.get_tree()
	if not scene.fixture_path.is_empty() or not Commands.local_origin(scene.api): return false
	# Validate all preconditions before changing either duty.
	for id in DUTIES:
		var initial:=retained(board,id)
		if initial.is_empty() or not initial.get("enabled",false) or not initial.get("inference",false):
			failure="Expected enabled inference duty missing: "+id; record(directory); return false
		var completed_timer:=false
		for run_record in board.snapshot.get("runs",[]):
			if str(run_record.get("input",{}).get("id","")).begins_with("duty-"+id+"-") and run_record.get("state")=="completed": completed_timer=true
		if not completed_timer:
			failure="Wait for a completed autonomous timer run before control qualification: "+id; record(directory); return false
	for id in DUTIES:
		var original:=retained(board,id)
		for enabled in [false,true]:
			var before:=retained(board,id)
			var expected:Dictionary=preload("res://command_board.gd").duty_change(before,enabled)
			var button:=action_button(board,id,enabled)
			if button==null or button.disabled:
				failure="Native control unavailable: "+id; record(directory); return false
			board.tabs.current_tab=4
			button.grab_focus(); button.pressed.emit()
			events.append({"id":id,"requested":expected,"phase":"submitted via native button"}); record(directory)
			var deadline:=Time.get_ticks_msec()+20000
			var confirmed:=false
			while Time.get_ticks_msec()<deadline:
				await tree.process_frame
				if board.commands.uncertain: break
				if not board.pending and board.commands.phase.is_empty() and Commands.field_duty_reconciled(board.snapshot,expected,id): confirmed=true; break
			if not confirmed:
				failure="Outcome requires reconciliation; no retry: "+id; record(directory); return false
			events.append({"id":id,"retained":retained(board,id),"phase":"confirmed"}); record(directory)
			if DisplayServer.get_name()!="headless":
				await RenderingServer.frame_post_draw
				var path:=directory.path_join("duty-"+id+("-resumed.png" if enabled else "-paused.png"))
				if tree.root.get_texture().get_image().save_png(path)!=OK:
					failure="Cannot retain duty control screenshot: "+id; record(directory)
		var restored:=retained(board,id)
		for key in ["agent","target","inference","interval_seconds","enabled"]:
			if restored.get(key)!=original.get(key):
				failure="Restoration mismatch for "+id+" / "+key; record(directory); return false
	return failure.is_empty()
