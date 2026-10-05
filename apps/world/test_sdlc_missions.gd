extends SceneTree
const View=preload("res://sdlc_missions.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(800,640); root.content_scale_size=Vector2i(800,640)
	var board=preload("res://command_board.gd").new(); board.fixture="test-only"; board.api="http://127.0.0.1:1"; root.add_child(board); board.timer.stop(); board.show(); board.tabs.current_tab=5
	var view=board.sdlc_missions; view.timer.stop()
	var record={"id":"pilot-1","input":{"id":"pilot-1","repository":"X-McKay/algent","revision":"abcdef123456","opportunity":"Regression test for unsafe input handling","build":"sha256:fixture"},"state":"testing","updated_at":12345,"events":[{"role":"lead","state":"investigating","data":{"summary":"Reproduced failing input"}},{"role":"implementer","state":"testing","data":{"summary":"Handed candidate to independent verifier"}}],"evidence":{"testing":{"baseline":{"passed":false,"cases":["regression failed"]},"candidate":{"passed":true,"cases":["regression passed"]},"verdict":"passed"}},"publication":null}
	view.snapshot={"schema_version":7,"verification_enabled":true,"enabled":true,"policy":{"enabled":true,"repository":"X-McKay/algent","publish":false,"max_missions":1,"merge":false},"missions":[record]}; view.render(); await process_frame
	assert(view.cancel.disabled,"Fixture cannot cancel real work")
	assert(view.status.text.contains("FIXTURE"))
	var words:=text_of(view.content)
	assert(words.contains("Baseline") and words.contains("Candidate") and words.contains("verdict".capitalize()))
	assert(words.contains("lead") and words.contains("implementer") and words.contains("CI status · unknown"))
	view.fixture=false; view.online=true; view.controls(); assert(not view.cancel.disabled)
	record.cancel_requested=true; view.controls(); assert(view.cancel.disabled)
	record.cancel_requested=false; view.controls()
	view.commands.uncertain=true; view.controls(); assert(view.cancel.disabled and view.reconcile.visible)
	view.commands.path="/v7/missions/pilot-1/cancel"; view.commands.run_id="pilot-1"; view.commands.phase="reconcile"
	view.commands._response(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify(record).to_utf8_buffer())
	assert(view.commands.uncertain,"Finding an active mission is not proof of cancellation")
	view.commands.phase="reconcile"
	var cancelled:Dictionary=record.duplicate(true); cancelled.state="cancelled"
	view.commands._response(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify(cancelled).to_utf8_buffer())
	assert(not view.commands.uncertain)
	view.received(HTTPRequest.RESULT_SUCCESS,404,PackedStringArray(),PackedByteArray())
	assert(not view.online and view.cancel.disabled and view.status.text.contains("V7 not installed"))
	assert(view.mission_record().id=="pilot-1","Unavailable service preserves last known evidence")
	record.state="awaiting_review"; record.publication={"status":"claimed","branch":"starbase/pilot-1","authority":"PR only; no merge"}; record.evidence.submitted={"url":"https://github.com/X-McKay/algent/pull/12","number":12}; record.evidence.awaiting_review={"ci":{"status":"failed","reason":"GitHub Actions billing limit"}}
	view.fixture=true; view.render(); view.render_mission(); await process_frame
	assert(text_of(view.content).contains("not a merge"))
	assert(view.cancel.disabled)
	assert(View.safe_pr_url(record.evidence.submitted.url,"X-McKay/algent"))
	assert(View.safe_pr_url(record.evidence.submitted.url,"x-mckay/algent"))
	assert(not View.safe_pr_url("https://github.com/other/repo/pull/12","X-McKay/algent"))
	assert(not View.safe_pr_url("https://github.com/X-McKay/algent/pull/12?redirect=evil","X-McKay/algent"))
	var verification={"id":"verify-1","input":{"id":"verify-1","head":"a".repeat(40),"build":{}},"state":"verifying","cancel_requested":false,"updated_at":12346,"evidence":{"verified":{"outcome":"infrastructure_blocked","infrastructure_error":"Sandbox unavailable","observations":{"exit_code":1},"public":{"exit_code":1}}},"effects":[]}
	record.verifications=[verification]
	view.render_mission(); await process_frame
	words=text_of(view.content)
	assert(words.contains("EXTERNAL VERIFICATION") and words.contains("infrastructure blocked") and words.contains("Sandbox unavailable"))
	assert(words.contains("a".repeat(40)) and words.contains("separate from GitHub Actions"))
	for stop in view.content.find_children("*","Button",true,false):
		if stop.has_meta("verification_cancel_id"): assert(stop.disabled,"Fixture verification commands are fenced")
	view.cancel_verification("verify-1"); assert(view.commands.phase.is_empty())
	view.received(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify({"schema_version":7,"missions":[]}).to_utf8_buffer())
	assert(view.mission_record().id=="pilot-1","Late network responses cannot overwrite a fixture")
	view.commands.path="/v7/missions/pilot-1/verifications/verify-1/cancel"; view.commands.run_id="verify-1"; view.commands.uncertain=true; view.commands.phase="reconcile"
	var cancelled_child:Dictionary=verification.duplicate(true); cancelled_child.cancel_requested=true
	view.commands._response(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify(cancelled_child).to_utf8_buffer())
	assert(not view.commands.uncertain,"Nested cancellation boolean is authoritative before stage changes")
	verification.state="completed"; verification.evidence.verified={"outcome":"passed","observations":{"exit_code":0},"public":{"exit_code":0}}; verification.evidence.completed={"status":"success","head":"a".repeat(40),"scope":"conversation history"}
	view.render_mission(); await process_frame
	assert(text_of(view.content).contains("Core outcome · passed") and view.cancel.disabled)
	assert(text_of(view.content).contains("GITHUB ACTIONS / PR FOLLOW-UP") and text_of(view.content).contains("GitHub Actions billing limit"),"Independent pass does not erase Actions failure")
	for size in [Vector2i(1280,800),Vector2i(800,640)]:
		root.size=size; root.content_scale_size=size; await process_frame; await process_frame
		if "--capture" in OS.get_cmdline_user_args(): await create_timer(0.15).timeout
		assert(view.size.x<=size.x,"Evidence remains inside horizontal bounds")
		view.choices.grab_focus(); assert(view.choices.has_focus())
		if "--capture" in OS.get_cmdline_user_args():
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("res://../../evidence/world/sdlc-missions-20260928/mission-%d.png"%size.x)
			for control in view.content.find_children("*","Button",true,false):
				if control.text.begins_with("Inspect verifier evidence"):
					control.grab_focus()
					board.tabs.get_child(5).ensure_control_visible(control)
			for _frame in 8: await process_frame
			var focused=root.gui_get_focus_owner()
			assert(focused!=null and focused.text.begins_with("Inspect verifier evidence"))
			board.tabs.get_child(5).ensure_control_visible(focused)
			await create_timer(0.1).timeout
			assert(board.tabs.get_child(5).get_global_rect().encloses(focused.get_global_rect()),"Keyboard verifier evidence control must be visible")
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("res://../../evidence/world/sdlc-missions-20260928/verifier-%d.png"%size.x)
			view.content.get_child(view.content.get_child_count()-2).grab_focus()
			for _frame in 6: await process_frame
			board.tabs.get_child(5).scroll_vertical=int(board.tabs.get_child(5).get_v_scroll_bar().max_value)
			for _frame in 3: await process_frame
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("res://../../evidence/world/sdlc-missions-20260928/evidence-%d.png"%size.x)
	# Bounded V7 summaries: the list and controls use the summary; the full record
	# arrives separately and unknown evidence is never rendered as success.
	var summary={"id":"pilot-2","state":"testing","repository":"X-McKay/algent","objective":"Preserve history order","current_stage":"testing","updated_at":12400,"cancel_requested":false,"policy_generation":1,"input":{"id":"pilot-2","repository":"X-McKay/algent","revision":"b".repeat(40),"opportunity":"persistence-history"},"verifications":[],"latest_event":{"key":"testing-1","stage":"testing","at":12400,"label":"testing","role":null},"recent_events":[],"event_count":3,"publication":{"state":"none"},"stage_evidence":{"plan":{"decision":"implement","rationale":"Reproduced","task":"Fix","role":"lead"},"testing":null,"reviewing":null}}
	view.fixture=false; view.online=true; view.selected="pilot-2"; view.signature=""
	view.snapshot={"schema_version":7,"view":"summary","enabled":true,"policy":{"enabled":true},"missions":[summary]}
	view.render(); await process_frame
	words=text_of(view.content)
	assert(words.contains("STAGE EVIDENCE SUMMARY") and words.contains("Testing · not recorded") and words.contains("loading full mission record"),"Summary view marks missing evidence and pending detail")
	assert(not view.cancel.disabled,"Command availability comes from the polled summary")
	assert(view.detail_pending_id=="pilot-2","Selecting a summary requests its full record")
	view.detail_http.cancel_request()
	var full:Dictionary=record.duplicate(true); full.id="pilot-2"; full.state="testing"; full.erase("verifications")
	view.received_detail(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify(full).to_utf8_buffer())
	await process_frame
	assert(view.mission_record().has("evidence") and text_of(view.content).contains("CURRENT STAGE EVIDENCE"),"Full record replaces the summary view")
	view.detail_pending=view.selected+"stale"; view.detail_pending_id="pilot-2"
	view.received_detail(HTTPRequest.RESULT_SUCCESS,500,PackedStringArray(),PackedByteArray())
	assert(view.detail_status=="unavailable" and text_of(view.content).contains("Full record refresh failed"),"Failed refresh keeps last known detail visibly")
	view.detail_http.cancel_request(); view.detail_pending=""; view.detail_pending_id=""
	board.queue_free(); await process_frame
	print("SDLC mission checks passed: policy, baseline/candidate, crew handoffs, pending/last-known state, fixture fences, bounded summaries and keyboard bounds")
	quit()
func text_of(node:Node) -> String:
	var text:=""
	for item in node.find_children("*","Label",true,false): text+=item.text+"\n"
	return text
