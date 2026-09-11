extends RefCounted
## Offline native visual rehearsal. Fixture records never dispatch work.
var scene:Node3D
var tree:SceneTree
var output:=""
var started:=0
var failures:Array[String]=[]
var captures:Array=[]
var samples:Array=[]
var stopped:=false
var observation:=0.0

func check(ok:bool,message:String) -> void:
	if not ok and not failures.has(message): failures.append(message)

func tick() -> bool:
	await tree.physics_frame
	if Time.get_ticks_msec()-started>175000:
		check(false,"Native rehearsal exceeded175-second wall-clock bound")
		return false
	return true

func picture(name:String) -> void:
	# Explicit offline capture only: background native windows may not emit
	# frame_post_draw until focused. Render once without waiting on window focus.
	RenderingServer.force_draw(false)
	var image:Image=tree.root.get_texture().get_image()
	check(image.save_png(output.path_join(name+".png"))==OK,"Capture failed: "+name)
	captures.append(name+".png")

func project(records:Array) -> void:
	observation+=1
	scene.receive_snapshot({"schema_version":2,"observed_at":observation,"recent":[],"active":[],"repairs":[],"worker":{"available":true},"field_runs":records})

func record(id:String,state:String) -> Dictionary:
	var run:Dictionary={"input":{"id":id,"agent":"reviewer","target":"shift-change-offline"},"state":state,"updated_at":observation+1,"created_at":observation,"detail":"OFFLINE visual rehearsal"}
	if state=="completed": run["summary"]={"outcome":"no_findings","finding_count":0,"simulation":true,"source_kind":"field","memory_status":"disabled"}
	return run

func sample(label:String,motion:RefCounted) -> void:
	var actor:Node3D=motion.actor
	samples.append({"label":label,"wall_ms":Time.get_ticks_msec()-started,
		"position":[actor.position.x,actor.position.y,actor.position.z],
		"pose":actor.presentation_pose,"clip":actor.model_visual.clip,
		"goal":motion.intent.get("goal"),"route_blocked":motion.route_blocked,
		"backend_state":motion.intent.get("backend_state"),"evidence_ready":motion.intent.get("evidence_ready",false)})

func run(host:SceneTree,world:Node3D,directory:String,mode:String="domestic") -> void:
	tree=host;scene=world;output=directory;started=Time.get_ticks_msec();observation=Time.get_unix_time_from_system()+10
	# Check the fence before changing any fixture state or creating output.
	if scene.fixture_path.is_empty() or scene.hud.board.fixture.is_empty() or not scene.capture_input_isolated or mode not in ["domestic","journey"]:
		push_error("Shift Change capture requires isolated world AND board fixtures and a valid mode")
		tree.quit(1);return
	if DirAccess.make_dir_recursive_absolute(output)!=OK:
		push_error("Cannot create Shift Change capture output");tree.quit(1);return
	var watchdog:SceneTreeTimer=tree.create_timer(179.0)
	watchdog.timeout.connect(func():
		if not stopped:
			check(false,"Native capture watchdog expired")
			finish(mode))
	var anchors:Array=load("res://shift_change_anchors.gd").collect(scene)
	var by_id:Dictionary={}
	for anchor in anchors: by_id[anchor.id]=anchor
	var home_ids:Array=["GalleyConversation","LoungeConversation","QuietReader","GardenWest","DoorwayPause"]
	check(home_ids.all(func(id):return by_id.has(id)),"Required authored home anchors absent")
	if not failures.is_empty(): finish(mode);return
	# Explicit initial fixture staging: no teleport occurs after this starting setup.
	# One metre approach allows actual physics and sit-down transitions to be observed quickly.
	var index:=0
	for kind in scene.crew_motions:
		var motion:RefCounted=scene.crew_motions[kind]
		motion.release_anchor()
		var chosen:Dictionary=by_id[home_ids[index]]
		motion.configure_home(kind,[chosen],motion.rooms,{})
		motion.actor.position=chosen.position+Vector3(0,0,1.0)
		motion.intent={};motion.destination=Vector3(INF,0,0);motion.path.clear()
		index+=1
	project([])
	scene.enter_room("Habitat")
	var selected:RefCounted=scene.crew_motions.reviewer
	for step in range(360):
		if not await tick(): finish(mode);return
		if selected.actor.model_visual.clip=="social/seated": break
	check(selected.actor.position.distance_to(by_id.DoorwayPause.position)<0.3,"Reviewer physically reaches authored seat")
	check(selected.actor.model_visual.clip=="social/seated","Real rig reaches seated animation")
	await picture(mode+"-occupied-habitat")
	sample("seated",selected)
	for frame in range(4):
		for step in range(8):
			if not await tick(): finish(mode);return
		await picture(mode+"-seated-%02d"%frame)
	project([record("shift-change-long","running")])
	for frame in range(5):
		for step in range(8):
			if not await tick(): finish(mode);return
		sample("stand-%d"%frame,selected)
		await picture(mode+"-stand-%02d"%frame)
	check(samples.any(func(s):return str(s.clip)=="social/stand_up"),"Assignment uses actual stand-up clip")
	if mode=="domestic":
		project([record("shift-change-long","completed")])
		check(selected.intent.evidence_ready,"Fast completion exposes evidence immediately")
		check(selected.intent.goal=="home","Fast completion turns home without workstation gate")
		await picture("domestic-fast-report")
		finish(mode);return
	# Long fixture stays running until physical arrival; this is not a backend timing claim.
	var departed:Vector3=selected.actor.position
	while selected.actor.presentation_pose!="console":
		if not await tick(): finish(mode);return
		if selected.route_blocked: check(false,"Physical station route blocked");finish(mode);return
	check(selected.actor.position.distance_to(departed)>2,"Selected real actor physically travels")
	check(selected.actor.position.distance_to(selected.workstation)<0.3,"Console pose only at actual station")
	scene.enter_room("review")
	for step in range(120):
		if not await tick(): finish(mode);return
	sample("working",selected);await picture("journey-console-arrival")
	project([record("shift-change-long","completed")])
	check(selected.intent.evidence_ready,"Terminal evidence appears before return-home travel")
	sample("report-ready",selected);await picture("journey-report-ready")
	while selected.actor.model_visual.clip!="social/seated":
		if not await tick(): finish(mode);return
		if selected.route_blocked: check(false,"Physical home route blocked");finish(mode);return
	scene.enter_room("Habitat")
	for step in range(120):
		if not await tick(): finish(mode);return
	sample("returned-home",selected);await picture("journey-home")
	project([record("shift-change-short","running")])
	for step in range(12):
		if not await tick(): finish(mode);return
	project([record("shift-change-short","completed")])
	check(selected.intent.goal=="home" and selected.intent.evidence_ready,"Short job redirects without false console work")
	scene.disconnected=true;scene.update_crew_presentation()
	for step in range(5):
		if not await tick(): finish(mode);return
	check(selected.actor.motion.is_zero_approx() and selected.actor.presentation_pose.is_empty(),"Offline suppresses motion and work")
	sample("offline",selected);await picture("journey-offline")
	project([record("shift-change-short","completed")])
	check(selected.intent.evidence_ready and selected.intent.goal=="home","Reconnect coalesces to retained result")
	await picture("journey-reconnected")
	finish(mode)

func finish(mode:String) -> void:
	if stopped:return
	stopped=true
	check(scene.http.get_http_client_status()==HTTPClient.STATUS_DISCONNECTED,"Fixture world must not issue live snapshot requests")
	check(scene.commands.payload.is_empty() and scene.hud.board.commands.payload.is_empty(),"Rehearsal must not dispatch commands")
	var report:Dictionary={"mode":mode,"status":"passed" if failures.is_empty() else "failed","fixture":true,"initial_positions_staged":true,"physics_after_staging":true,"captures":captures,"samples":samples,"failures":failures,"wall_ms":Time.get_ticks_msec()-started,"viewport":str(tree.root.size),"engine":Engine.get_version_info(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	var frame_times:Array=scene.frame_times.duplicate()
	frame_times.sort()
	if not frame_times.is_empty():
		report["frame_samples"]=frame_times.size()
		report["median_frame_ms"]=frame_times[frame_times.size()/2]
		report["p95_frame_ms"]=frame_times[mini(frame_times.size()-1,int(frame_times.size()*0.95))]
	var file:FileAccess=FileAccess.open(output.path_join(mode+"-report.json"),FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"  "))
	for failure in failures:push_error(failure)
	print("SHIFT_CHANGE_CAPTURE_", "PASSED" if failures.is_empty() else "FAILED", " ",mode)
	tree.quit(0 if failures.is_empty() else 1)
