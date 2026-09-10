extends RefCounted
## Native qualification; read-only unless named duty controls are explicitly opted in.
var failures:Array[String]=[]
var captures:Array[String]=[]
var output:=""
func check(value:bool,message:String) -> void:
	if not value: failures.append(message); push_error(message)
func shot(tree:SceneTree,name:String) -> void:
	for i in range(12): await tree.process_frame
	await RenderingServer.frame_post_draw
	check(tree.root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Cannot save "+name)
	captures.append(name)
	print("LIVE_CAPTURE ",name)
func run(scene:Node,directory:String) -> void:
	print("LIVE_REVIEW_START")
	var tree:SceneTree=scene.get_tree()
	output=directory
	if not scene.fixture_path.is_empty() or not preload("res://commands.gd").local_origin(scene.api):
		push_error("Live review requires an explicit private loopback Core without fixtures")
		tree.quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var deadline:=Time.get_ticks_msec()+15000
	while scene.disconnected and Time.get_ticks_msec()<deadline: await tree.process_frame
	check(not scene.disconnected,"Live Core snapshot was not received")
	check(not scene.snapshot.get("installation",{}).is_empty(),"Core installation metadata missing")
	var initial_ids:Array=scene.missions.map(func(m): return str(m.input.id))
	check(not initial_ids.is_empty(),"Live review requires retained backend work")
	scene.colony_overview=true
	await shot(tree,"live-colony")
	print("OPENING_CONNECTION")
	scene.hud.open_connection()
	await shot(tree,"live-connection")
	scene.enter_room("review")
	scene.hud.open_board()
	deadline=Time.get_ticks_msec()+15000
	while not scene.hud.board.online and Time.get_ticks_msec()<deadline: await tree.process_frame
	check(scene.hud.board.online,"Live Command board not connected")
	await shot(tree,"live-command")
	scene.hud.board.tabs.current_tab=1
	await shot(tree,"live-repositories")
	var fields:Array=scene.snapshot.get("field_runs",[]).filter(func(run): return run.get("state")=="completed" and run.get("summary")!=null)
	if not fields.is_empty():
		scene.hud.board.inspect(str(fields[0].input.id))
		deadline=Time.get_ticks_msec()+10000
		while scene.hud.board.detail_http.get_http_client_status()!=HTTPClient.STATUS_DISCONNECTED and Time.get_ticks_msec()<deadline: await tree.process_frame
		await shot(tree,"live-evidence")
	# Real reasoning acceptance uses retained records only; this harness never starts a run.
	var require_reasoning:bool="--require-reasoning-evidence" in OS.get_cmdline_user_args()
	for agent in ["watchkeeper","reviewer"]:
		var candidates:Array=fields.filter(func(run): return run.input.get("agent")==agent and run.get("summary",{}).get("advisory_status")=="unverified")
		if require_reasoning: check(not candidates.is_empty(),"Retained real reasoning missing for "+agent)
		if candidates.is_empty(): continue
		var selected:Dictionary=candidates[0]
		scene.hud.board.inspect(str(selected.input.id))
		deadline=Time.get_ticks_msec()+10000
		while scene.hud.board.detail_http.get_http_client_status()!=HTTPClient.STATUS_DISCONNECTED and Time.get_ticks_msec()<deadline: await tree.process_frame
		await shot(tree,"live-reasoning-"+agent)
		var evidence_text:=""
		for line in scene.hud.board.detail.find_children("*","Label",true,false): evidence_text+=line.text
		check(evidence_text.contains("UNVERIFIED") and evidence_text.contains("RETAINED SOURCE"),"Reasoning detail must show real source and unverified model advice: "+agent)
		check(not evidence_text.contains("NO SOURCE CAPTURED"),"Reasoning detail lacks source: "+agent)
	var saved_size:Vector2i=tree.root.size
	tree.root.size=Vector2i(800,640)
	scene.hud.large_text=true; scene.hud.scale_text()
	scene.hud.open_connection()
	await shot(tree,"live-compact")
	tree.root.size=saved_size
	scene.hud.large_text=false; scene.hud.scale_text()
	# Deliberately stop client reads to exercise its existing five-second watchdog.
	# Backend work continues; this is a client outage, not a service health claim.
	var outage_ids:Array=scene.missions.map(func(m): return str(m.input.id))
	scene.poll_timer.stop(); scene.http.cancel_request()
	deadline=Time.get_ticks_msec()+6500
	while not scene.disconnected and Time.get_ticks_msec()<deadline: await tree.process_frame
	check(scene.disconnected,"Snapshot watchdog did not mark interrupted reads stale")
	check(scene.missions.map(func(m): return str(m.input.id))==outage_ids,"Client outage lost retained work")
	await shot(tree,"live-disconnected")
	scene.poll_timer.start(); scene.poll()
	deadline=Time.get_ticks_msec()+10000
	while scene.disconnected and Time.get_ticks_msec()<deadline: await tree.process_frame
	check(not scene.disconnected,"Client did not reconnect")
	await shot(tree,"live-reconnected")
	check(scene.commands.payload.is_empty() and scene.hud.board.commands.payload.is_empty(),"Read-only native qualification dispatched a command")
	var control_opt_in:bool="--qualify-duty-controls" in OS.get_cmdline_user_args()
	if control_opt_in:
		scene.hud.open_board()
		var control_check:=preload("res://live_duty_controls.gd").new()
		check(await control_check.run(scene,output),"Explicit native duty control acceptance failed: "+control_check.failure)
		await shot(tree,"live-duties-restored")
	var record:Dictionary={"api":scene.api,"installation":scene.snapshot.get("installation"),"observed_at":scene.snapshot.get("observed_at"),"run_ids":initial_ids,"outage_run_ids":outage_ids,"captures":captures,"failures":failures,"fixture":false,"client_outage_test":true,"commands_dispatched":control_opt_in,"duty_controls_opt_in":control_opt_in}
	var file:=FileAccess.open(output.path_join("live-review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(record,"  ")); file.close()
	if failures.is_empty(): print("LIVE_WORLD_CAPTURE_PASSED: live metadata, retained runs, evidence, compact UI, client outage and reconnect; duty controls opt-in="+str(control_opt_in))
	tree.quit(0 if failures.is_empty() else 1)
