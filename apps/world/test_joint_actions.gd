extends SceneTree
var failures:Array[String]=[]
var api:=""
func check(value:bool,message:String) -> void:
	if not value:failures.append(message)
func _initialize() -> void:run.call_deferred()
func settled(command:Node) -> void:
	var deadline:=Time.get_ticks_msec()+12000
	while command.phase!="" and Time.get_ticks_msec()<deadline:await process_frame
	check(command.phase.is_empty(),"Operator request completed within bounded test deadline")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--api="):api=arg.trim_prefix("--api=")
	if api.is_empty():push_error("Isolated HTTP fixture required");quit(1);return
	var hud=load("res://hud.gd").new();hud.board_fixture="__empty_visual_fixture__";root.add_child(hud);await process_frame
	hud.open_operations();hud.operations.tabs.current_tab=4
	var joint=hud.operations.joint;joint.configure(api,"");joint.poll(true)
	var deadline:=Time.get_ticks_msec()+9000
	while joint.pending and Time.get_ticks_msec()<deadline:await process_frame
	check(joint.connection_state=="online","Read snapshot loads exact build and admission")
	joint.view_choice.select(2);joint.select_view(2)
	joint.requests.get_line_edit().text="6";joint.requests.get_line_edit().text_changed.emit("6")
	joint.tokens.get_line_edit().text="131072";joint.tokens.get_line_edit().text_changed.emit("131072")
	var first_id:String=joint.draft_id
	joint.launch_mission()
	check(joint.launch_commands.phase!="" and joint.launch_button.disabled,"Launch becomes pending and locks duplicate submission")
	check(joint.cancel_target()==first_id and not joint.stop_button.disabled,"Cancellation remains accessible independently of pending launch")
	await settled(joint.launch_commands)
	check(joint.launch_commands.uncertain,"Lost create response plus temporary404 remains unknown")
	check(joint.launch_commands.run_id==first_id and joint.draft_id==first_id,"Unknown result retains the exact original identity")
	joint.launch_mission();check(joint.launch_commands.phase=="","Blocked second launch cannot dispatch a new identity")
	check(not hud.operations.configure("http://127.0.0.1:1",""),"Endpoint change cannot abandon unresolved joint command")
	joint.reconcile();await settled(joint.launch_commands)
	check(not joint.launch_commands.uncertain and joint.selected==first_id,"Exact input reconciliation resolves delayed commit")
	joint.cancel_selected();await settled(joint.cancel_commands)
	check(joint.cancel_commands.uncertain,"Same-ID running GET cannot acknowledge a lost cancellation")
	check(joint.action_notice.text.contains("Outcome unknown"),"Cancellation uncertainty is visible")
	joint.reconcile();await settled(joint.cancel_commands)
	check(not joint.cancel_commands.uncertain and joint.cancel_commands.receipt.state=="cancelled","Cancellation resolves only after retained cancelled state")
	joint.view_choice.select(2);joint.select_view(2);joint.scenario_picker.select(1)
	var rejected_id:String=joint.draft_id;joint.launch_mission();await settled(joint.launch_commands)
	check(not joint.launch_commands.uncertain and joint.action_notice.text.contains("rejected"),"Authoritative policy rejection is distinct from unknown")
	check(joint.draft_id==rejected_id,"Rejected launch preserves inspectable draft identity")
	joint.scenario_picker.select(2);joint.launch_mission();await settled(joint.launch_commands)
	check(joint.launch_commands.uncertain,"Same ID with wrong build cannot reconcile launch intent")
	joint.reconcile();await settled(joint.launch_commands)
	check(not joint.launch_commands.uncertain,"Exact corrected retained input can reconcile without a second POST")
	joint.selected="race-terminal";joint.view_choice.select(0);joint.select_view(0);joint.render()
	joint.cancel_selected();await settled(joint.cancel_commands)
	check(joint.action_notice.text.contains("already terminal") and joint.cancel_commands.receipt.state=="completed","Terminal race is not claimed as successful cancellation")
	joint.launch_commands.uncertain=true;joint.launch_commands.run_id="unknown-on-hide"
	hud.close_panels();hud.open_operations();hud.operations.tabs.current_tab=4
	check(joint.launch_commands.uncertain,"Hiding workspace cannot clear command uncertainty")
	joint.launch_commands.uncertain=false
	hud.queue_free();await process_frame
	for failure in failures:push_error(failure)
	if failures.is_empty():print("JOINT_ACTIONS_PASSED: operator session/origin, exact builds and integer budgets, pending identity, lost create/cancel reconciliation, mismatch, rejection, independent stop, terminal race")
	quit(0 if failures.is_empty() else 1)
