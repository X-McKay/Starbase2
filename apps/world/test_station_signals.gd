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
	var component := Signals.new(); root.add_child(component)
	component.configure({"review":Vector3(0,2,0), "repair":Vector3(15,2,0), "gym":Vector3(35,2,0)})
	var camera := Camera3D.new(); root.add_child(camera); camera.position=Vector3(0,5,15); camera.look_at(Vector3.ZERO)
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
	component.update_view(camera,Vector3.ZERO,false,true)
	check(component.labels.review.font_size==36,"Large text supported without motion")
	var inspections: Array = []
	component.inspect_requested.connect(func(context: String): inspections.append(context))
	await process_frame
	var target: Vector3 = component.labels.review.global_position
	var point := camera.unproject_position(target)
	check(component.hit(camera,point) and inspections==["review"],"Visible badge emits read-only inspection context")
	var wall := StaticBody3D.new(); root.add_child(wall)
	wall.position=(camera.global_position+target)*0.5
	var collision := CollisionShape3D.new(); collision.shape=BoxShape3D.new(); collision.shape.size=Vector3(8,8,1); wall.add_child(collision)
	await physics_frame; await physics_frame
	check(not component.hit(camera,point) and inspections.size()==1,"Solid occluder blocks hidden building inspection")
	wall.queue_free()
	component.queue_free(); camera.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("STATION_SIGNALS_PASSED: authoritative aggregates, retained outcomes, stale/unknown, nearest visibility, large text")
	quit(0 if failures.is_empty() else 1)
