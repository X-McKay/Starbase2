extends SceneTree
const Signals = preload("res://station_signals.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func record(id: String, kind: String, state: String, stamp: int = 1) -> Dictionary:
	return {"input":{"id":id,"kind":kind}, "state":state, "updated_at":stamp, "stale":false, "evidence":{"summary":{"outcome":"partial"}}}
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var records: Array = [record("a","review","running"), record("b","watchkeeper","completed"), record("c","reviewer","failed"), record("d","repair","cancelled"), record("e","evaluation","queued"), record("f","review","unrecognized"), null, {"input":7}]
	records.append(record("a","review","completed",0))
	var projected := Signals.project(records,false,10)
	check(projected.review.active == 1 and projected.review.results == 2 and projected.review.unknown == 1,"Command aggregates three resident roles, deduplicates newest state, preserves unknown")
	check(projected.repair.results == 1 and projected.gym.active == 1,"Repair cancellation and evaluation context remain distinct")
	check(Signals.label_text("review",projected.review).contains("retained results") and not Signals.label_text("review",projected.review).contains("success"),"Retained count does not invent success or complete history")
	for state in Signals.OPEN:
		check(Signals.project([record("a","repair",state)],false,10).repair.active == 1,"Supported open state: "+state)
	var stale := record("s","review","running"); stale.stale=true
	var missing := record("m","review","completed"); missing.evidence=null
	projected=Signals.project([stale,missing],false,10)
	check(projected.review.stale==1 and projected.review.results==1 and projected.review.evidence==0 and projected.review.missing_evidence==1,"Stale state and missing evidence retain honest counts")
	check(Signals.label_text("review",projected.review).contains("STALE · last known"),"Individual stale records mark aggregate stale")
	check(Signals.label_text("review",projected.review).contains("missing evidence"),"Completion without evidence is explicitly marked")
	check(Signals.label_text("review",projected.review,false).begins_with("COMMAND ·") and not Signals.label_text("review",projected.review,false).contains("retained results"),"Distant station badges use restrained hierarchy")
	check(Signals.label_text("repair",Signals.project([],false,0).repair,false).contains("UNKNOWN") and not Signals.label_text("repair",Signals.project([],false,0).repair,false).contains("Awaiting records"),"Distant unknown badge stays truthful and concise")
	projected=Signals.project(records,true,10,true)
	check(Signals.label_text("review",projected.review).contains("OFFLINE") and Signals.label_text("review",projected.review).contains("FIXTURE"),"Offline and fixture labels survive")
	check(Signals.label_text("repair",Signals.project([],false,0).repair).contains("UNKNOWN"),"Unobserved snapshot never appears idle")
	var failed_result := Signals.label_text("review",Signals.project([record("failed","review","failed")],false,10).review,false)
	var retained_result := Signals.label_text("review",Signals.project([record("completed","review","completed")],false,10).review,false)
	check(failed_result != retained_result and failed_result.contains("FAILED"),"Distant badge distinguishes retained failure from completed records")
	var unchanged := record("unchanged","review","completed"); unchanged.evidence.summary.outcome="no_change"
	check(Signals.label_text("review",Signals.project([unchanged],false,10).review).contains("no change"),"Recorded no-change result has its own marker")
	var blocked := record("blocked","review","completed"); blocked.evidence.summary.outcome="blocked"
	var cancelled := record("cancelled","review","cancelled")
	var broken_execution := record("broken","repair","completed"); broken_execution.evidence.summary.execution_failed=true
	check(Signals.project([broken_execution],false,10).repair.failed==1,"Terminal repair execution error remains a retained failure")
	var states: Array = [record("failed","review","failed"),blocked,cancelled,unchanged]
	var markers: Array[String] = []
	for state_record in states:
		markers.append(Signals.label_text("review",Signals.project([state_record],false,10).review,false))
	check(markers[0].contains("[!]") and markers[1].contains("[#]") and markers[2].contains("[x]") and markers[3].contains("[=]"),"Failure, blocked, cancellation and no-change have non-color markers")
	states.append(record("active","review","running"))
	var mixed: Dictionary = Signals.project(states,false,10).review
	var mixed_label := Signals.label_text("review",mixed)
	check(mixed_label.contains("1 open") and mixed_label.contains("4 retained results") and mixed_label.contains("1 failed") and mixed_label.contains("1 blocked") and mixed_label.contains("1 cancelled") and mixed_label.contains("1 no change"),"Mixed records preserve open work and each retained result distinction")
	check(not mixed_label.contains("SUCCESS") and not mixed_label.contains("VERIFIED"),"Result markers do not promote a completion into independent verification")
	check(Signals.label_text("review",Signals.project(states,true,10).review,false).contains("OFFLINE"),"Offline status takes precedence over retained outcomes")
	states[0].stale=true
	check(Signals.label_text("review",Signals.project(states,false,10).review,false).contains("STALE"),"Stale status takes precedence over retained outcomes")
	check(Signals.project([record("same","review","failed",1),record("same","review","completed",2)],false,10).review.failed==0,"A superseded failure cannot persist in a newer record projection")
	check(Signals.label_text("review",Signals.project([],false,10).review,false).contains("NO RETAINED RECORDS"),"An observed empty snapshot never claims idle or healthy")
	var component := Signals.new(); root.add_child(component)
	component.configure({"review":Vector3(0,2,0), "repair":Vector3(15,2,0), "gym":Vector3(35,2,0)})
	# Screen-space clearance depends on a real-sized viewport. Headless Godot
	# starts at 64x64, where the safe top band cannot be represented.
	root.size=Vector2i(1280,800); root.content_scale_size=Vector2i(1280,800)
	var camera := Camera3D.new(); root.add_child(camera); camera.position=Vector3(0,5,15); camera.look_at(Vector3.ZERO)
	await process_frame
	component.update_records(records,false,10)
	component.update_view(camera,Vector3.ZERO)
	check(component.visible_context=="review" and component.labels.review.visible and not component.labels.repair.visible,"Only nearest building badge visible")
	var original_y: float = component.anchors.review.y
	check(component.labels.review.global_position.y >= original_y,"Nearby badge is lifted into a safe band above the focus actor")
	component.update_view(camera,Vector3.ZERO,true)
	check(component.visible_context.is_empty() and not component.labels.review.visible,"Observation and interiors can suppress exterior clutter")
	component.update_view(camera,Vector3(100,0,0))
	check(component.visible_context.is_empty(),"Distant badges are culled")
	component.update_view(camera,Vector3(60,0,0))
	check(component.visible_context=="gym" and component.labels.gym.visible and component.labels.gym.font_size==20 and component.labels.gym.text.begins_with("TRIAL HALL"),"Distant station badge is compact and restrained")
	component.set_selected_context("repair")
	component.update_view(camera,Vector3(60,0,0))
	check(component.visible_context=="repair" and component.labels.repair.visible,"Selected station wins within the restrained interaction range")
	component.set_selected_context("")
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=20
	component.update_view(camera,Vector3.ZERO,false,false)
	var normal_height: float = component.labels.review.font_size * component.labels.review.pixel_size
	component.update_view(camera,Vector3.ZERO,false,true)
	check(component.labels.review.font_size==36,"Large text supported without motion")
	check(component.labels.review.font_size * component.labels.review.pixel_size > normal_height * 1.15,"Large text increases apparent size, not only texture resolution")
	var inspections: Array = []
	component.inspect_requested.connect(func(context: String): inspections.append(context))
	states[0].stale=false
	component.update_records(states,false,10)
	component.update_view(camera,Vector3.ZERO,false,true)
	await process_frame
	var target: Vector3 = component.labels.review.global_position
	var point := camera.unproject_position(target)
	check(component.hit(camera,point) and inspections==["review"],"Visible badge emits read-only inspection context")
	var half_size: Vector2 = component._screen_half_size(camera,component.labels.review)
	check(half_size.y>30 and component.hit(camera,point+Vector2(0,half_size.y-2)),"Every visible line of a large mixed-result badge is inspectable")
	check(not component.hit(camera,point+Vector2(half_size.x+20,0)),"Inspection hit target remains bounded to the projected badge")
	var wall := StaticBody3D.new(); root.add_child(wall)
	wall.position=(camera.global_position+target)*0.5
	var collision := CollisionShape3D.new(); collision.shape=BoxShape3D.new(); collision.shape.size=Vector3(8,8,1); wall.add_child(collision)
	await physics_frame; await physics_frame
	check(not component.hit(camera,point) and inspections.size()==2,"Solid occluder blocks hidden building inspection")
	wall.queue_free()
	component.queue_free(); camera.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("STATION_SIGNALS_PASSED: authoritative aggregates, retained outcomes, stale/unknown, nearest visibility, large text")
	quit(0 if failures.is_empty() else 1)
