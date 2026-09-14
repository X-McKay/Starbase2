extends SceneTree
const Briefing = preload("res://morning_briefing.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func record(id: String, stamp: int, state: String = "completed", kind: String = "watchkeeper") -> Dictionary:
	return {"input":{"id":id, "kind":kind, "target":"fixture-target"}, "state":state, "updated_at":stamp, "stale":false, "evidence":{"summary":{"outcome":"partial", "source_kind":"field"}}}
func run() -> void:
	var records: Array = [null, {}, {"input":7}, record("active", 20, "running")]
	for i in range(8): records.append(record("terminal-"+str(i), i+1))
	records.append(record("terminal-7", 1, "failed"))
	records.append(record("unknown", 21, "unknown"))
	var model: Dictionary = Briefing.project(records, false, 30)
	check(model.reports.size() == 5 and model.retained_count == 8, "Recent terminal history is bounded and deduplicated")
	check(model.unknown_count == 1, "Unknown records are distinct from known open work")
	check(model.active_count == 1 and model.reports[0].id == "terminal-7", "Active records are counted separately and historical order uses recorded time")
	check(model.reports[0].status == "Completed · partial", "Partial outcome stays partial without success claims")
	for state in ["queued","running","cancel_requested","executing","analyzing","evaluating","verifying","capturing","reviewing"]:
		var active_model:Dictionary=Briefing.project([record("active-state",22,state,"repair")],false,30)
		check(active_model.active_count==1 and active_model.unknown_count==0,"Supported active state remains open: "+state)
	var missing := record("missing", 50); missing.evidence = null
	var cancelled := record("cancel", 40, "cancelled")
	var untimed := record("untimed", 0, "failed"); untimed.updated_at = null
	model = Briefing.project([missing, cancelled, untimed], true, 30, true)
	check(model.reports[0].status.contains("evidence missing") and model.reports[1].status == "Cancelled", "Missing evidence and cancellation remain distinct")
	check(model.reports[2].stamp == 0 and model.disconnected and model.fixture, "Unknown timestamp and offline fixture truth survive")
	var panel := Briefing.new(); root.add_child(panel)
	panel.update_records([missing, cancelled, untimed], true, 30, true)
	panel.present()
	check(panel.freshness.text.contains("FIXTURE") and panel.freshness.text.contains("OFFLINE / STALE"), "Visible freshness is explicit")
	check(panel.summary.text.contains("HISTORICAL") and panel.summary.text.contains("last known"), "History never masquerades as live activity")
	var emitted: Array = []
	panel.inspect_requested.connect(func(id: String, context: String): emitted.append([id, context]))
	var buttons := panel.reports.find_children("*", "Button", true, false)
	buttons[0].pressed.emit()
	var stable_button=buttons[0]
	panel.set_large_text(false)
	panel.update_records([missing,cancelled,untimed],true,31,true)
	check(panel.reports.find_children("*","Button",true,false)[0]==stable_button,"Unchanged snapshot and font setting preserve pointer target identity")
	check(emitted == [["missing", "watchkeeper"]], "Evidence selection emits exact authoritative identity, including missing detail")
	buttons[1].grab_focus()
	panel.update_records([record("new", 60), missing, cancelled, untimed], false, 61, true)
	check(root.gui_get_focus_owner().get_meta("record_key") == "watchkeeper:cancel", "Refresh preserves keyboard focus by identity")
	panel.search.text = "cancel"
	panel.refresh()
	check(panel.filtered_reports().size() == 1 and panel.results_count.text == "1 / 4 in window", "Search filters the bounded window with an honest denominator")
	panel.search.text = ""
	panel.state_filter.select(3); panel.refresh()
	check(panel.filtered_reports().size() == 1 and panel.filtered_reports()[0].id == "untimed", "Failed filter uses authoritative state")
	panel.state_filter.select(0); panel.refresh()
	for window_size in [Vector2i(1280, 800), Vector2i(800, 640)]:
		root.size = window_size; root.content_scale_size = window_size
		panel.set_large_text(true); panel.layout()
		await process_frame; await process_frame
		print("BRIEFING_BOUNDS ", panel.get_global_rect(), " viewport ", root.get_visible_rect(), " minimum ", panel.get_combined_minimum_size())
		check(root.get_visible_rect().encloses(panel.get_global_rect()), "Large-text briefing fits compact and native viewports")
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--briefing-capture-dir="):
				var destination := arg.trim_prefix("--briefing-capture-dir=")
				DirAccess.make_dir_recursive_absolute(destination)
				RenderingServer.force_draw(false)
				var capture := root.get_texture().get_image()
				check(capture.save_png(destination+"/briefing-"+str(window_size.x)+".png") == OK, "Native capture saved")
		check(panel.size.x <= root.size.x-40 and panel.size.y < root.size.y, "Workspace preserves viewport margins")
	panel.reset()
	check(panel.reports.find_children("*", "Button", true, false).is_empty() and panel.freshness.text.contains("UNKNOWN"), "Endpoint reset discards unrelated retained history")
	panel.dismiss.pressed.emit(); check(not panel.visible, "Keyboard-focusable dismiss closes briefing")
	panel.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("MORNING_BRIEFING_PASSED: bounded historical truth, exact evidence identity, offline/fixture/missing states, focus and compact scaling")
	quit(0 if failures.is_empty() else 1)
