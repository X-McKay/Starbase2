extends SceneTree
func _initialize() -> void: run.call_deferred()
func text_of(node:Node) -> String:
	var text:=""
	for item in node.find_children("*","Label",true,false): text+=item.text+"\n"
	return text
func run() -> void:
	var board=preload("res://command_board.gd").new(); board.fixture="test-only"; root.add_child(board); board.timer.stop(); board.show(); board.tabs.current_tab=5
	var view=board.sdlc_missions; view.timer.stop()
	var contract={"id":"fixture-capability","digest":"sha256:fixture","objective":"Synthetic operating-view acceptance","editable_paths":["src/example.py"],"merge":false}
	var assignments=[{"crew":"moss","role":"lead","task":"diagnose","requires":[],"evidence":"investigating"},{"crew":"rivet","role":"implementer","task":"implement","requires":["diagnose"],"evidence":"implementing"}]
	var record={"id":"fixture-mission","state":"testing","updated_at":12345,"input":{"repository":"X-McKay/algent","revision":"a".repeat(40)},"capability":contract,"coordination":{"assignments":assignments,"reservation":"algent:fixture","max_rounds":3},"evidence":{"investigating":{"summary":"Captured baseline; outcome not yet determined"}},"pr_observation":{"state":"open","head":"b".repeat(40),"observed_at":12345}}
	view.snapshot={"schema_version":7,"missions":[record],"capability_catalog":{"capabilities":[contract]},"coordination":{"admission":"publication_requires_resolution","can_discover":false,"resolution":"Fresh lifecycle observation required; no automatic merge"}}
	view.render(); await process_frame
	assert(text_of(view.operating).contains("PUBLICATION REQUIRES RESOLUTION"))
	var words:=text_of(view.content)
	assert(words.contains("Moss · lead · diagnose") and words.contains("Rivet · implementer · implement"))
	assert(words.contains("implementing · not recorded") and words.contains("investigating · retained (not a success claim)"))
	assert(words.contains("OPEN · last known / fixture") and words.contains("b".repeat(40)))
	assert(words.contains("not prove a crew member is currently executing"))
	view.fixture=false; view.online=true; view.received_at_msec=Time.get_ticks_msec()-16000; view._process(0)
	assert(not view.online and view.status.text.contains("STALE") and view.cancel.disabled)
	view.received(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify(view.snapshot).to_utf8_buffer())
	assert(view.online and view.selected=="fixture-mission","Reconnect preserves selection")
	view.fixture=true; view.large_text=true
	for size in [Vector2i(1280,800),Vector2i(800,640)]:
		root.size=size; root.content_scale_size=size; view.render_mission(); await process_frame; await process_frame
		for button in view.content.find_children("*","Button",true,false):
			if button.text.begins_with("Inspect pinned contract"):
				button.grab_focus(); button.pressed.emit()
				assert(button.has_focus())
		for _frame in 6: await process_frame
		var scroll=board.tabs.get_child(5)
		scroll.ensure_control_visible(root.gui_get_focus_owner())
		for _frame in 6: await process_frame
		assert(view.size.x<=size.x)
		assert(scroll.get_global_rect().encloses(root.gui_get_focus_owner().get_global_rect()))
		if "--capture" in OS.get_cmdline_user_args():
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("res://../../evidence/world/sdlc-coordination-20260928/coordination-%d.png"%size.x)
			for heading in view.content.find_children("*","Label",true,false):
				if heading.text.begins_with("Moss ·"):
					scroll.scroll_vertical+=int(heading.global_position.y-scroll.global_position.y)-12
					break
			for _frame in 6: await process_frame
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("res://../../evidence/world/sdlc-coordination-20260928/dependencies-%d.png"%size.x)
	view.snapshot={"schema_version":7,"missions":[{"id":"old","input":{},"state":"blocked"}]}; view.render()
	assert(text_of(view.content).contains("legacy or unknown") and text_of(view.operating).contains("ADMISSION · UNKNOWN"))
	view.snapshot={"schema_version":7,"missions":[]}; view.render()
	assert(text_of(view.content).contains("No mission records") and text_of(view.operating).contains("Catalog unavailable"))
	board.queue_free(); await process_frame
	print("SDLC coordination checks passed: contracts, planned dependencies, missing evidence, PR freshness, stale/reconnect, legacy/empty records and keyboard layout")
	quit()
