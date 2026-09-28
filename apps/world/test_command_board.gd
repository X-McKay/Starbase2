extends SceneTree
const Board=preload("res://command_board.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.content_scale_size=Vector2i(960,720)
	root.size=Vector2i(960,720)
	var board:=Board.new()
	root.add_child(board)
	board.timer.stop()
	board.fixture="test-only"
	board.snapshot={"enabled":true,"runs":[],"builds":[],"repositories":[],"memory":[]}
	board.render(); board.show()
	await process_frame
	assert(board.launch.disabled and board.watch_save.disabled)
	assert(board.watches.get_child(0).text.contains("No repositories"))
	board.snapshot.builds=[{"manifest":{"agent":"watchkeeper","target":{"id":"cluster-live","kind":"kubernetes","inference_min_interval_seconds":900,"daily_inference_limit":8}}}]
	board.snapshot.duties=[{"id":"watch-cluster","agent":"watchkeeper","target":"cluster-live","enabled":true,"interval_seconds":60,"generation":3,"inference":true},{"id":"missing-target","agent":"reviewer","target":"missing","enabled":false,"interval_seconds":120,"generation":0}]
	var original: Dictionary=board.snapshot.duties[0].duplicate(true)
	var request:=Board.duty_change(original,false)
	assert(request.inference and request.generation==4 and not request.enabled)
	assert(board.snapshot.duties[0]==original,"Creating request must not optimistically alter duty state")
	var Commands=preload("res://commands.gd")
	assert(Commands.field_duty_reconciled({"duties":[request]},request,"watch-cluster"))
	var wrong: Dictionary=request.duplicate(true); wrong.inference=false
	assert(not Commands.field_duty_reconciled({"duties":[wrong]},request,"watch-cluster"))
	wrong=request.duplicate(true); wrong.generation=5
	assert(not Commands.field_duty_reconciled({"duties":[wrong]},request,"watch-cluster"))
	board.render()
	var duty_text:=""
	for l in board.duty_records.find_children("*","Label",true,false): duty_text+=l.text
	assert(duty_text.contains("watch-cluster") and duty_text.contains("AI cooldown 900 s") and duty_text.contains("Daily admission limit 8"))
	assert(duty_text.contains("missing-target") and duty_text.contains("policy unknown"))
	var run_record={"input":{"id":"sample","agent":"reviewer","target":"repo-a"},"state":"completed","updated_at":1000,"detail":"Partial coverage","snapshot":{"data":{"simulation":true}},"report":{"findings":[{"code":"S307","subject":"fixture/repo#7 / x.py","line":2,"summary":"Unsafe dynamic evaluation","recommendation":"Inspect the changed input handling."}],"coverage":["Unsupported language"],"memory":{"status":"empty"}}}
	run_record.snapshot.data.health={"default_branch":"main","head":null,"issues":[],"issues_complete":false,"ci":[],"ci_complete":false}
	board.fixture_details={"sample":run_record}
	board.inspect("sample")
	assert(board.tabs.current_tab==3)
	var text:=""
	for l in board.detail.find_children("*","Label",true,false): text+=l.text
	assert(text.contains("S307") and text.contains("SYNTHETIC") and text.contains("Coverage limit"))
	assert(text.contains("Unknown · not captured") and text.contains("bounded / incomplete") and text.contains("does not mean passing checks"))
	var now:=Time.get_unix_time_from_system()
	var fleet: Array=[]
	for i in 45:
		var latest: Dictionary={} if i==0 else {"input":{"id":"run-"+str(i),"target":"repo-"+str(i)},"state":"failed" if i==1 else "completed","detail":"Read only","source_observed_at":now-10,"updated_at":now-5}
		if i==2: latest.summary={"finding_count":3}
		fleet.append({"id":"repo-"+str(i),"config":{"repository":"owner/repo-%02d"%i,"enabled":true,"removed":false,"interval_seconds":300,"generation":0},"latest_run":latest})
	board.snapshot.repositories=fleet
	board.render()
	assert(board.fleet_summary.text.contains("45 watches · 45 shown"))
	assert(board.fleet_summary.text.contains("43 fresh source") and board.fleet_summary.text.contains("1 failed") and board.fleet_summary.text.contains("1 no source"))
	assert(board.fleet_summary.text.contains("1 repositories with findings"))
	assert(Board.watch_status(fleet[2],[],now).finding_count==3)
	assert(Board.watch_status(fleet[2],[],now).latest.input.id=="run-2","Latest watch record survives absence from global run window")
	assert(Board.watch_status(fleet[2],[],now+2000).state=="stale")
	board.watch_filter.select(1); board.render_watches(); board.controls()
	assert(board.fleet_summary.text.contains("45 watches · 3 shown"))
	var attention_text:=""
	for l in board.watches.find_children("*","Label",true,false): attention_text+=l.text
	assert(attention_text.contains("repo-02 · FRESH SOURCE") and attention_text.contains("3 retained advisory findings"),"Fresh source with findings remains in Needs attention")
	board.watch_search.text="repo-01"; board.render_watches(); board.controls()
	assert(board.fleet_summary.text.contains("45 watches · 1 shown"))
	for b in board.watches.find_children("*","Button",true,false):
		if b.text=="Observe now": assert(b.disabled,"Fixture observations cannot dispatch")
	board.watch_search.text=""; board.watch_filter.select(0); board.render_watches(); board.controls()
	var last: Button=board.watches.get_child(board.watches.get_child_count()-1).get_child(0)
	board.tabs.current_tab=1
	await process_frame; await process_frame
	last.grab_focus()
	await process_frame; await process_frame
	assert(board.tabs.get_child(1).scroll_vertical>0,"Keyboard focus scrolls to final fleet row")
	if "--capture-fleet" in OS.get_cmdline_user_args():
		for viewport_size in [Vector2i(1280,800),Vector2i(800,640)]:
			root.size=viewport_size; root.content_scale_size=viewport_size
			board.layout_workspace(); board.tabs.get_child(1).scroll_vertical=0
			last.release_focus()
			for frame in 5: await process_frame
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("res://../../evidence/world/repository-fleet-20260928/findings-fleet-%d.png"%viewport_size.x)
			board.tabs.get_child(1).scroll_vertical=420
			for frame in 3: await process_frame
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("res://../../evidence/world/repository-fleet-20260928/findings-fleet-rows-%d.png"%viewport_size.x)
		board.watch_filter.select(1); board.render_watches(); board.controls()
		for frame in 4: await process_frame
		board.tabs.get_child(1).scroll_vertical=99999
		for frame in 3: await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("res://../../evidence/world/repository-fleet-20260928/findings-attention-800.png")
	board.fixture=""; board.online=false; board.controls()
	assert(board.launch.disabled)
	assert(board.get_global_rect().end.x<=root.size.x and board.get_global_rect().end.y<=root.size.y)
	board.queue_free(); await process_frame
	print("Command board checks passed: fixture/offline command fences, findings, coverage and compact bounds")
	quit()
