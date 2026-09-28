extends SceneTree
const View=preload("res://joint_state.gd")
var failures:Array[String]=[]
var capture_directory:=""
var http_fixture:=""
func check(value:bool,message:String) -> void:
	if not value:failures.append(message)
func picture(name:String) -> void:
	for frame in 4:await process_frame
	if capture_directory.is_empty():return
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(capture_directory.path_join(name+".png"))==OK,"Capture saved "+name)
func _initialize() -> void:run.call_deferred()
func fixture() -> Dictionary:
	var now:=Time.get_unix_time_from_system()
	var task:Dictionary={"id":"r0-workload","role":"workload","round":0,"question":"Do failing probes match the workload route contract?","focus":"overview","tokens":32768,"state":"completed","eligible":true,"accounted_tokens":420,"result":{"status":"completed","usage":{"input_tokens":300,"output_tokens":120},"error":null,"trace":{},"output":{"diagnosis":"unknown","summary":"Probe failures retained; the route contract needs diagnostic logs.","evidence_ids":["observation-fixture-1"],"uncertainty":"Overview alone cannot establish the valid readiness route.","next_question":"Inspect workload diagnostics."}}}
	var mission:Dictionary={"input":{"id":"joint-fixture-1","opportunity":"fixture-readiness-incident","build":"sha256:immutable-joint-fixture","scenario":"route-mismatch","inference":false},"state":"running","created_at":now-30,"updated_at":now-1,"deadline":now+570,"tasks":[{"id":"r0-lead","role":"lead","round":0,"question":"Choose the next investigation tasks.","focus":"overview","tokens":32768,"state":"completed","eligible":true,"accounted_tokens":250,"result":{"status":"completed","usage":{"input_tokens":200,"output_tokens":50},"output":{"tasks":[{"role":"workload","focus":"overview"},{"role":"service","focus":"work"}],"rationale":"Compare probe configuration with useful service work."}}},task,{"id":"r0-service","role":"service","round":0,"question":"Does the service return correct answers?","focus":"work","tokens":32768,"state":"claimed","eligible":false,"accounted_tokens":0,"result":null}],"budget":{"requests_reserved":3,"requests_limit":8,"tokens_reserved":98304,"tokens_limit":262144,"tokens_accounted":670},"decision":null,"outcome":null,"reason":null,"simulation":true,"xp":0}
	var done:Dictionary=mission.duplicate(true)
	done.input.id="joint-fixture-passed";done.state="completed";done.outcome="diagnostic-pass";done.reason="Public scenario diagnosis matched independent grading.";done.decision={"action":"repair","rationale":"A readiness-route correction is proposed; no change executed."}
	var failed:Dictionary=mission.duplicate(true)
	failed.input.id="joint-fixture-failed";failed.state="failed";failed.outcome="unresolved";failed.reason="Specialist reply unavailable; usage conservatively accounted.";failed.tasks[2].state="failed";failed.tasks[2].accounted_tokens=32768;failed.tasks[2].result={"status":"unknown","output":null,"usage":null,"error":"Reply lost after dispatch; no retry."}
	return {"schema_version":5,"simulation":true,"enabled":true,"observed_at":now,"missions":[mission,done,failed],"builds":[{"digest":"fixture-scripted-build","manifest":{"profile":"joint-readiness-v1","inference":false}},{"digest":"fixture-model-build","manifest":{"profile":"joint-readiness-v1","inference":true}}]}
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):capture_directory=arg.trim_prefix("--capture=")
		if arg.begins_with("--http-fixture="):http_fixture=arg.trim_prefix("--http-fixture=")
	if not capture_directory.is_empty():DirAccess.make_dir_recursive_absolute(capture_directory)
	var data:=fixture()
	check(View.valid_snapshot(data),"V5 simulation snapshot admitted")
	check(not View.valid_snapshot({"schema_version":4,"simulation":true,"missions":[],"observed_at":0}),"Other schemas rejected")
	check(not View.valid_snapshot({"schema_version":5,"simulation":false,"missions":[],"observed_at":0}),"Unimplemented live mode rejected")
	check(View.members(data.missions[0]).contains("Mission lead") and View.members(data.missions[0]).contains("Service specialist"),"Member roles derive from actual tasks")
	check(View.members(data.missions[0]).contains("No reply recorded · outcome unknown"),"Claim is not a completed specialist result")
	check(View.outcome_label(data.missions[1]).contains("simulated diagnosis only"),"Diagnostic pass never claims recovered service")
	check(View.stale({"observed_at":1},Time.get_unix_time_from_system()),"Expired observation is stale")
	var hud=load("res://hud.gd").new();hud.board_fixture="__empty_visual_fixture__";root.add_child(hud)
	await process_frame
	hud.connection.text="Preview fixture · no live operation or provider calls"
	hud.open_operations();hud.operations.tabs.current_tab=4
	var joint=hud.operations.joint
	check(not hud.operations.briefing_toggle.visible,"V2 briefing cannot imply a count of V5 missions")
	joint.apply_fixture(data)
	check(joint.choose.item_count==3,"All valid retained mission records listed")
	check(joint.summary.text.contains("joint-fixture-1") and joint.budget.text.contains("98304"),"Selected exact mission and reserved budget visible")
	joint.choose.grab_focus();var focused:Control=root.gui_get_focus_owner()
	joint.apply_fixture(data)
	check(root.gui_get_focus_owner()==focused,"Unchanged snapshot preserves selection focus")
	for size in [Vector2i(1280,800),Vector2i(800,640)]:
		root.size=size;root.content_scale_size=size;hud.large_text=size.x<1000;hud.scale_text()
		joint.scroll.scroll_vertical=0;await picture("joint-%d-summary" % size.x)
		check(joint.scroll.get_h_scroll_bar().max_value<=joint.scroll.size.x,"Joint view has no horizontal overflow")
		check(joint.scroll.size.y>=120,"Compact detail retains at least 120px readable viewport")
		for card in joint.handoff_cards.get_children():check(card.size.y<300,"Collapsed handoff card stays concise; header cannot wrap one character per line")
		joint.scroll.grab_focus()
		var page_event:=InputEventKey.new();page_event.keycode=KEY_PAGEDOWN;page_event.pressed=true;root.push_input(page_event)
		await process_frame
		check(joint.scroll.scroll_vertical>0,"Keyboard Page Down traverses structured detail")
		joint.scroll.scroll_vertical=460;await picture("joint-%d-budget-handoffs" % size.x)
		joint.scroll.scroll_vertical=1100;await picture("joint-%d-specialists" % size.x)
		joint.source_toggle.grab_focus();await picture("joint-%d-evidence" % size.x)
		var event:=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=true;root.push_input(event);await process_frame
		event=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=false;root.push_input(event);await process_frame
		check(joint.source.visible,"Keyboard reveals exact retained record")
		joint.source.hide();joint.source_toggle.text="Show exact retained record"
	joint.selected="joint-fixture-passed";joint.render();joint.scroll.scroll_vertical=0
	await picture("joint-diagnostic-pass")
	check(joint.budget_strip.text.contains("simulated diagnosis only"),"Native view qualifies diagnostic pass")
	joint.selected="joint-fixture-failed";joint.render();joint.scroll.scroll_vertical=0
	await picture("joint-failed")
	check(joint.mission_banner.text.contains("Failed") and joint.members.get_parsed_text().contains("Reply lost"),"Failed and uncertain child retain their own meanings")
	var previous:Dictionary=joint.snapshot.duplicate(true)
	joint.received(0,404,[],PackedByteArray(),joint.epoch)
	check(joint.connection_state=="unsupported" and joint.snapshot==previous,"Optional endpoint 404 preserves evidence without breaking existing world")
	check(joint.summary.text.contains("LAST-KNOWN"),"404 cannot keep old activity current")
	joint.received(1,0,[],PackedByteArray(),joint.epoch)
	await picture("joint-disconnected")
	check(joint.notice.text.contains("Disconnected"),"Transport failure explicitly disconnected")
	var old_epoch:int=joint.epoch
	joint.configure("http://127.0.0.1:1","__empty_visual_fixture__")
	joint.received(0,200,[],JSON.stringify(data).to_utf8_buffer(),old_epoch)
	check(joint.snapshot.is_empty(),"Old connection callback cannot populate new endpoint")
	var old:=data.duplicate(true);old.observed_at=1;joint.apply_fixture(old)
	check(joint.notice.text.contains("stale") and joint.summary.text.contains("LAST-KNOWN"),"Old observations visibly stale")
	await picture("joint-stale")
	joint.apply_fixture(data)
	joint.received(0,200,[],"{}".to_utf8_buffer(),joint.epoch)
	check(joint.connection_state=="unknown" and joint.snapshot==data,"Malformed current response keeps retained records qualified unknown")
	var invalid:=data.duplicate(true);invalid.missions.append({"state":"completed"});joint.apply_fixture(invalid)
	check(joint.notice.text.contains("coverage is incomplete"),"Unsupported records don't imply complete coverage")
	await mission_previews(hud,joint,data)
	await trainer_reviews(hud,joint,data)
	if not http_fixture.is_empty():
		joint.configure(http_fixture,"")
		joint.poll(true)
		await wait_request(joint)
		check(joint.connection_state=="online","Real GET /v5/snapshot parsed by existing transport")
		joint.poll(true)
		await wait_request(joint)
		check(joint.connection_state=="unsupported","Real optional endpoint 404 is isolated")
		joint.poll()
		check(not joint.pending,"404 suppresses automatic repeated requests")
		joint.poll(true)
		await wait_request(joint)
		check(joint.connection_state=="unknown","Explicit refresh retries unavailable endpoint and rejects malformed data")
		joint.configure(http_fixture,"fixture")
		joint.poll(true)
		check(not joint.pending,"Fixture mode suppresses network reads")
		hud.operations.hide()
		joint.configure(http_fixture,"")
		joint.poll(true)
		check(not joint.pending,"Hidden workspace does not poll")
	hud.queue_free();await process_frame
	for failure in failures:push_error(failure)
	if failures.is_empty():print("JOINT_OPERATIONS_PASSED: optional V5, exact records, roles/handoffs, budgets, outcomes, stale/unknown, endpoint fencing, keyboard compact view")
	quit(0 if failures.is_empty() else 1)

func wait_request(joint:Node) -> void:
	var deadline:=Time.get_ticks_msec()+9000
	while joint.pending and Time.get_ticks_msec()<deadline:await process_frame
	check(not joint.pending,"Read request completed within transport deadline")

func trainer_reviews(hud:Node,joint:Node,data:Dictionary) -> void:
	check(View.opportunity_note(data).contains("not reported"),"Older V5 payload is compatible without claiming no opportunities")
	var review_data:=data.duplicate(true)
	review_data["opportunities"]=[{"id":"trainer-fixture-unknown-usage","build":"sha256:immutable-joint-fixture","scenario":"route-mismatch","category":"unknown-usage-or-dispatch","status":"proposed-review","scope":"public-simulation-review","observed_count":2,"source_mission_ids":["joint-fixture-failed","joint-fixture-older-failed"],"sources":[{"mission_id":"joint-fixture-failed","task_ids":["r0-service"],"tokens_accounted":33438,"usage_unknown":true},{"mission_id":"joint-fixture-older-failed","task_ids":["r1-workload","r2-lead"],"tokens_accounted":33718,"usage_unknown":true}],"tokens_accounted":67156,"accounting_overflow":false,"usage_unknown":true,"most_recent_at":data.observed_at,"proposed_investigation":"Review dispatch recovery and missing usage evidence before designing an isolated experiment."}]
	joint.apply_fixture(review_data)
	joint.view_choice.select(1);joint.view_choice.item_selected.emit(1)
	check(joint.review_mode and joint.review_content.visible and not joint.mission_content.visible,"Trainer reviews replace mission detail without dispatch")
	check(joint.review_summary.text.contains("TRAINING NOT STARTED") and joint.review_summary.text.contains("No qualification, XP or adoption"),"Proposed review is not started training or earned capability")
	check(joint.review_summary.text.contains("67156") and joint.review_summary.text.contains("uncertain usage"),"Conservative accounted resources remain qualified")
	check(joint.review_sources.text.contains("joint-fixture-older-failed") and joint.review_sources.text.contains("r2-lead"),"Grouped exact mission/task source identities remain visible")
	check(joint.review_note.text.contains("not priority ranking"),"Stable group order does not imply a utility ranking")
	for size in [Vector2i(1280,800),Vector2i(800,640)]:
		root.size=size;root.content_scale_size=size;hud.large_text=size.x<1000;hud.scale_text()
		joint.scroll.scroll_vertical=0;await picture("trainer-%d-summary" % size.x)
		check(joint.scroll.get_h_scroll_bar().max_value<=joint.scroll.size.x,"Trainer reviews have no horizontal overflow")
		joint.scroll.grab_focus()
		var event:=InputEventKey.new();event.keycode=KEY_PAGEDOWN;event.pressed=true;root.push_input(event);await process_frame
		check(joint.scroll.scroll_vertical>0,"Keyboard scroll reaches proposed review metadata")
		joint.scroll.scroll_vertical=470;await picture("trainer-%d-resources" % size.x)
		joint.source_toggle.grab_focus();await picture("trainer-%d-sources" % size.x)
		check(joint.source.text.contains("trainer-fixture-unknown-usage"),"Raw disclosure targets selected Trainer record, not a prior mission")
	var overflow:=review_data.duplicate(true);overflow.opportunities[0].accounting_overflow=true;overflow.opportunities[0].tokens_accounted=null
	joint.apply_fixture(overflow)
	check(joint.review_summary.text.contains("aggregate overflow") and joint.review_sources.text.contains("33438"),"Overflow cannot render zero aggregate usage or discard exact source costs")
	joint.received(1,0,[],PackedByteArray(),joint.epoch)
	check(joint.review_summary.text.contains("LAST-KNOWN REVIEW"),"Disconnected review proposals remain last-known")
	joint.scroll.scroll_vertical=0;await picture("trainer-disconnected")
	var unsupported:=review_data.duplicate(true);unsupported.opportunities[0].category="self-certified-improvement"
	joint.apply_fixture(unsupported)
	check(joint.review_note.text.contains("coverage is incomplete") and joint.review_selected.is_empty(),"Unrecognized categories cannot invent trusted improvement findings")
	joint.apply_fixture(data)
	check(joint.review_note.text.contains("not reported") and joint.review_selected.is_empty(),"Missing optional field clears prior proposed reviews")
	joint.scroll.scroll_vertical=0;await picture("trainer-older-core")
	var empty:=data.duplicate(true);empty["opportunities"]=[];joint.apply_fixture(empty)
	check(joint.review_note.text.contains("No proposed Trainer reviews"),"Reported empty proposal set differs from unsupported field")
	joint.view_choice.select(0);joint.view_choice.item_selected.emit(0)
	check(joint.selected=="joint-fixture-1" and joint.summary.text.contains("joint-fixture-1"),"Returning from proposals preserves exact selected mission")

func mission_previews(hud:Node,joint:Node,data:Dictionary) -> void:
	joint.apply_fixture(data)
	for size in [Vector2i(1280,800),Vector2i(800,640)]:
		root.size=size;root.content_scale_size=size;hud.large_text=size.x<1000;hud.scale_text()
		joint.view_choice.select(2);joint.select_view(2)
		check(joint.launch_mode and joint.launch_button.disabled,"Launch form is inspectable but fixture cannot dispatch")
		check(joint.build_picker.item_count==2 and joint.chosen_build().manifest.inference==false,"Registered exact build determines inference mode")
		joint.scroll.scroll_vertical=0;await picture("mission-launch-%d-top" % size.x)
		joint.scroll.grab_focus()
		var end_key:=InputEventKey.new();end_key.keycode=KEY_END;end_key.pressed=true;root.push_input(end_key)
		await picture("mission-launch-%d-action" % size.x)
		check(joint.scroll.get_global_rect().intersects(joint.launch_button.get_global_rect()),"Keyboard End reveals the fixture-disabled launch action")
		check(joint.scroll.get_h_scroll_bar().max_value<=joint.scroll.size.x,"Launch form has no horizontal overflow")
	joint.view_choice.select(0);joint.select_view(0);joint.selected="joint-fixture-1";joint.render()
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i(1280,800);hud.large_text=false;hud.scale_text()
	for frame in 4:await process_frame
	joint.scroll.scroll_vertical=int(joint.handoff_cards.global_position.y-joint.scroll.get_child(0).global_position.y);await picture("direction-a-mission-bridge")
	joint.ledger_toggle.button_pressed=true
	for frame in 4:await process_frame
	joint.scroll.scroll_vertical=int(joint.members.global_position.y-joint.scroll.get_child(0).global_position.y);await picture("direction-b-technical-ledger")
	check(not joint.handoff_cards.visible and joint.members.visible,"Technical ledger alternate retains exact handoff text")
	check(joint.members.get_parsed_text().contains("DISPATCH & ACCOUNTING") and joint.members.get_parsed_text().contains("RECORDED REPLY") and joint.members.get_parsed_text().contains("Task ID"),"Technical ledger groups dispatch, accounting and reply with explicit labels")
	root.size=Vector2i(800,640);root.content_scale_size=Vector2i(800,640);hud.large_text=true;hud.scale_text()
	for frame in 4:await process_frame
	joint.scroll.scroll_vertical=int(joint.members.global_position.y-joint.scroll.get_child(0).global_position.y);await picture("direction-b-technical-ledger-compact")
	check(joint.scroll.get_h_scroll_bar().max_value<=joint.scroll.size.x,"Formatted ledger remains readable without horizontal overflow")
	joint.ledger_toggle.button_pressed=false
	joint.view_choice.select(2);joint.select_view(2)
	joint.launch_commands.run_id=joint.draft_id;joint.launch_commands.phase="write"
	joint.launch_commands.feedback.emit("Synthetic pending request · awaiting the Core record for "+joint.draft_id,true)
	joint.scroll.scroll_vertical=0;await picture("mission-pending-preview")
	check(joint.launch_button.disabled and not joint.draft_id.is_empty(),"Pending preview preserves draft identity and prevents duplicate action")
	joint.launch_commands.phase="";joint.action_notice.text="";joint.refresh_actions()
	joint.view_choice.select(0);joint.select_view(0)
