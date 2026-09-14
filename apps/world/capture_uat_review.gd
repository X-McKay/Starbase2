extends SceneTree
## Isolated native UAT regression views. No command or provider dispatch.
var output:=""
func _initialize() -> void: run.call_deferred()
func picture(name:String) -> void:
	for frame in 4: await process_frame
	RenderingServer.force_draw(false)
	assert(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK)
func run() -> void:
	create_timer(110).timeout.connect(func(): push_error("UAT native capture timed out"); quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): output=arg.trim_prefix("--capture-dir=")
	if output.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(output)
	var w=load("res://main.tscn").instantiate()
	w.fixture_path="res://../../fixtures/world/stale.json"; w.board_fixture="__empty_visual_fixture__"
	w.capture_input_isolated=true; root.add_child(w)
	for frame in 5: await process_frame
	var run={"sequence":1,"input":{"request":{"id":"uat-review","kind":"review","target":"sample","profile":"surveyor-v2"},"build":{"digest":"fixture-digest","manifest":{"profile":"surveyor-v2","inference":{"endpoint":"https://private.example/v1"}}}},"state":"completed","updated_at":1789340400,"detail":"Synthetic review completed","report":{"summary":{"outcome":"findings","files_reviewed":1,"finding_count":2,"simulation":true,"qualification":"Advisory static analysis; not proof of repository safety"},"evidence":{"review":{"files_reviewed":1,"errors":[],"findings":[{"file":"fixture.py","line":3,"code":"S307","message":"Use of possibly insecure function; consider using a safer alternative."},{"file":"fixture.py","line":8,"code":"B006","message":"Do not use mutable data structures for argument defaults."}],"coverage":[]}}}}
	var data={"schema_version":2,"observed_at":1789340400,"worker":{"available":true},"recent":[run],"active":[],"targets":[{"id":"sample","label":"Training repository","simulation":true}],"builds":[{"manifest":{"profile":"surveyor-v2"}}],"duties":[]}
	data["repairs"]=[{"input":{"id":"uat-repair","scenario":"clamp-v1","mode":"control-good"},"state":"completed","detail":"ineligible: independent core grading retained","actions":[{"stage":"baseline","observation":{"exit_code":2,"stderr":"Sandbox socket path too long; configure a shorter MSB_HOME.","stdout":""}}],"summary":{"outcome":"ineligible","baseline_passed":0,"candidate_passed":0,"cases":6,"hard_gate_failures":["baseline: execution or output protocol failure"],"synthetic_task":true,"qualification":"This exact build and fixture only; no production authority"}}]
	w.receive_snapshot(data)
	w.hud.operations.update_snapshot(data,false)
	w.hud.open_operations(); var panel=w.hud.operations
	for view in [Vector2i(1280,800),Vector2i(800,640)]:
		root.size=view; root.content_scale_size=view
		w.hud.large_text=view.x==800; w.hud.scale_text()
		w.hud.open_operations(); panel.tabs.current_tab=0
		await picture(str(view.x)+"-review-before")
		var before:Vector2=panel.review_button.global_position
		panel.commands.feedback.emit("Request accepted · watching authoritative state.",false)
		await picture(str(view.x)+"-review-feedback")
		if before!=panel.review_button.global_position:
			push_error("Feedback moved the action"); quit(1); return
		panel.tabs.current_tab=3; panel.history.inspect_run("uat-review")
		await picture(str(view.x)+"-history")
		if view.x==800:
			var history_scroll:ScrollContainer=panel.tabs.get_child(3)
			history_scroll.scroll_vertical+=int(panel.history.detail.global_position.y-history_scroll.global_position.y)
			await picture("800-history-findings")
		if not panel.history.detail.text.contains("S307"):
			push_error("Finding absent"); quit(1); return
		if panel.history.full_record.text.contains("private.example"):
			push_error("Endpoint not redacted"); quit(1); return
		w.hud.open_place("repair"); w.show_mission(); w.hud.dossier_tabs.current_tab=1
		await picture(str(view.x)+"-repair-failure")
		if not w.hud.evidence.text.contains("socket path too long") or w.hud.evidence.text.contains("0/6"):
			push_error("Repair execution error must be visible without invalid score"); quit(1); return
	assert(panel.commands.phase.is_empty() and w.commands.phase.is_empty())
	print("UAT_NATIVE_CAPTURE_PASSED: stable feedback, readable findings, raw endpoint redaction, fixture-only")
	w.queue_free(); await process_frame; quit()
