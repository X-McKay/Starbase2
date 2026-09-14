extends SceneTree
const Presentation=preload("res://crew_presentation.gd")
var failures: Array[String]=[]
func check(value:bool,message:String) -> void:
	if not value: failures.append(message)
func record(id:String,state:String,evidence:Variant=null) -> Dictionary:
	return {"input":{"id":id,"kind":"repair"},"state":state,"updated_at":1.0,"stale":false,"evidence":evidence}
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var actor=preload("res://actor.gd").new()
	# Exercise the shared label renderer without loading a character asset.
	actor.label=Label3D.new()
	actor.display_name="MENDER"
	var controller=Presentation.new()
	var icons:Array=[]
	var labels:Array=[]
	var tick:=0.0
	for pair in [["queued","queued"],["executing","active"],["completed","evidence"],["failed","failed"],["cancel_requested","cancel_pending"],["unknown","unknown"],["cancelled","cancelled"]]:
		tick+=1
		var input:=record("marker-run",pair[0],{"summary":{"outcome":"partial"}} if pair[0]=="completed" else null)
		var original:=input.duplicate(true)
		var intent:Dictionary=controller.update([input],"repair",false,false,tick)
		check(intent.task_markers.size()==1 and intent.task_markers[0].status==pair[1],"Explicit marker for "+pair[0])
		icons.append(intent.task_markers[0].icon); labels.append(intent.task_markers[0].text)
		actor.project_assignment(intent)
		var normal:String=actor.label.text
		check(normal.contains(intent.task_markers[0].icon) and normal.contains(intent.task_markers[0].text),"Icon plus text, never color alone")
		var reduced:Dictionary=controller.update([input],"repair",false,true,tick)
		actor.project_assignment(reduced,true)
		check(actor.label.text==normal and actor.label.font_size==22,"Reduced motion/large text retain exact meaning")
		check(input==original,"Presentation leaves authoritative records unchanged")
	check(icons.size()==7 and _unique(icons)==7 and _unique(labels)==7,"Seven statuses have distinct icons and text")
	var missing:Dictionary=controller.update([record("missing","completed")],"repair",false,false,20)
	check(missing.task_markers[0].status=="unknown","Completed without evidence never gets an evidence marker")
	var stale:=record("stale","running"); stale.stale=true
	check(controller.update([stale],"repair",false,false,21).task_markers[0].status=="unknown","Stale activity is unknown")
	var many:Array=[]
	for i in range(8): many.append(record("concurrent-%d" % i,"running"))
	many[0].state="completed";many[0].evidence={"summary":{}}
	var burst:Dictionary=controller.update(many,"repair",false,false,22)
	check(burst.task_markers.size()==3 and burst.marker_overflow==5 and burst.active_count==7,"Concurrent records are bounded without inventing crew")
	check(burst.task_markers[0].run_id==burst.run_id and burst.task_markers[1].status=="evidence","Assignment stays first and recent evidence remains visible during active work")
	actor.project_assignment(burst)
	check(actor.label.text.count("\n")==1 and actor.label.text.contains("7 tasks") and actor.label.get_meta("retained_count")==8,"One compact cue retains concurrency without stacked run labels")
	var offline:Dictionary=controller.update([],"repair",true,false,23)
	check(offline.task_markers.all(func(m):return m.status=="unknown"),"Disconnected evidence and activity cannot look current")
	var reconnect:Dictionary=controller.update([record("new","failed")],"repair",false,false,24)
	check(reconnect.task_markers.size()==1 and reconnect.task_markers[0].status=="failed" and reconnect.marker_overflow==0,"Reconnect coalesces current records without marker history")
	actor.label.free(); actor.label=null; actor.free()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("TASK_MARKERS_PASSED: seven color-independent states, evidence/unknown guards, reduced motion, scaled text, bounded concurrency, reconnect, immutable records")
	quit(0 if failures.is_empty() else 1)
func _unique(values:Array) -> int:
	var keys:Dictionary={}
	for value in values: keys[value]=true
	return keys.size()
