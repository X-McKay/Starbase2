extends SceneTree
const Status=preload("res://connection_status.gd")
var failures:Array[String]=[]
func check(value:bool,message:String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var snapshot:Dictionary={"schema_version":2,"recent":[],"worker":{"available":false},"installation":{"id":"test-colony","environment":"local","capabilities":{"accept_work":{"enabled":true,"reason":"Accepting work"},"field":{"enabled":true,"reason":"Read-only field observations"},"repair":{"enabled":false,"reason":"Practice disabled"}}}}
	check(Status.valid(snapshot),"Additive snapshot accepted")
	check(Status.headline(snapshot,false,false).contains("WORKER UNAVAILABLE"),"Policy enabled does not mean available worker")
	check(Status.enabled(snapshot,"field") and not Status.enabled(snapshot,"repair"),"Capability policy is explicit")
	check(Status.headline(snapshot,true,false).contains("DISCONNECTED"),"Disconnected retains last-known meaning")
	check(Status.headline(snapshot,false,true).contains("FIXTURE"),"Fixture cannot label itself live")
	snapshot.installation.capabilities.accept_work.enabled=false
	check(Status.headline(snapshot,false,false).contains("STOPPED"),"Stopped admission distinguished from empty work")
	check(not Status.enabled({},"field"),"Missing metadata is unknown, not enabled")
	check(Status.valid({"schema_version":2,"recent":[],"worker":{}}),"Old compatible snapshot still readable")
	for broken in [null,[],{"schema_version":3,"recent":[]},{"schema_version":2,"recent":[],"worker":null},{"schema_version":2,"recent":[],"worker":{},"active":"wrong"}]:
		check(not Status.valid(broken),"Malformed transport payload rejected")
	var hud=preload("res://hud.gd").new()
	hud.board_fixture="__empty_visual_fixture__"
	root.add_child(hud)
	await process_frame
	var requested:Array[String]=[]
	hud.connect_requested.connect(func(value:String): requested.append(value))
	hud.open_connection()
	check(hud.connection_panel.endpoint.has_focus(),"Connection screen keyboard focus")
	hud.connection_panel.endpoint.text="https://remote.example"
	hud.connection_panel.request_connection()
	check(requested.is_empty(),"Connection UI preserves private loopback boundary")
	hud.connection_panel.endpoint.text="http://127.0.0.1:18801"
	hud.connection_panel.request_connection()
	check(requested==["http://127.0.0.1:18801"],"Explicit local endpoint accepted")
	hud.connection_panel.refresh("http://127.0.0.1:18801",snapshot,false,false,0,"Awaiting source",true)
	check(hud.connection_panel.reconnect.disabled,"Unresolved command fences installation switching")
	check(hud.connection_panel.health.text.contains("Worker heartbeat: not reported"),"Missing heartbeat is explicit independently of availability")
	snapshot.worker={"available":true,"seen_at":1788919709.437842}
	hud.connection_panel.refresh("http://127.0.0.1:18801",snapshot,false,false,0,"",false)
	check(hud.connection_panel.health.text.contains("Worker heartbeat: 2026-09-09 02:08:29 UTC") and hud.connection_panel.health.text.contains("Core receipt: none"),"Heartbeat uses backend seen_at, independently of receipt")
	check(not hud.connection_panel.health.text.contains("stale / last-known"),"Available worker heartbeat has no invented stale status")
	snapshot.worker.available=false
	hud.connection_panel.refresh("http://127.0.0.1:18801",snapshot,false,false,0,"",false)
	check(hud.connection_panel.health.text.contains("2026-09-09 02:08:29 UTC · stale / last-known"),"Unavailable worker retains its stale heartbeat timestamp")
	snapshot.worker.available=true
	hud.connection_panel.refresh("http://127.0.0.1:18801",snapshot,true,false,0,"",false)
	check(hud.connection_panel.health.text.contains("2026-09-09 02:08:29 UTC · stale / last-known"),"Disconnected Core cannot present a retained heartbeat as current")
	for seen in [null,"1788919709",-1.0,NAN,INF]:
		snapshot.worker.seen_at=seen
		check(hud.connection_panel.worker_heartbeat(snapshot,false)=="not reported","Absent or malformed heartbeat never invents a date")
	for size in [Vector2i(1280,800),Vector2i(800,640)]:
		root.content_scale_size=size; root.size=size
		hud.large_text=true; hud.scale_text()
		await process_frame
		await process_frame
		var bounds:Rect2=hud.connection_panel.get_global_rect()
		check(bounds.position.x>=0 and bounds.end.x<=size.x and bounds.end.y<=size.y,"Connection panel fits compact/large text")
	hud.close_panels()
	check(not hud.is_open(),"Escape-equivalent closes connection UI")
	var journal_found:=false
	for control in hud.find_children("*","Button",true,false):
		if control.text.begins_with("Journal"):
			journal_found=true
			control.pressed.emit()
			check(hud.operations.visible,"Journal opens native operations")
			hud.close_panels()
	check(journal_found,"Native Journal control is reachable")
	hud.open_connection()
	hud.connection_panel.journal_requested.emit()
	check(hud.operations.visible and not hud.connection_panel.visible,"Connection routes to native operations")
	hud.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CONNECTION_STATUS_PASSED: explicit policy, worker/offline/fixture distinctions, additive schema, endpoint boundary, pending fence, keyboard and responsive panel")
	quit(0 if failures.is_empty() else 1)
