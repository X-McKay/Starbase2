extends SceneTree
const Presentation=preload("res://crew_presentation.gd")
func _initialize() -> void:
	var p=Presentation.new()
	var run={"input":{"id":"one","kind":"evaluation"},"state":"queued","updated_at":1.0,"stale":false,"evidence":null}
	var original=run.duplicate(true)
	var a=p.update([run],"gym",false,false,1)
	assert(a.run_id=="one" and a.goal=="workstation" and a.pose=="" and a.active_count==1)
	assert(run==original,"Presentation must not mutate domain records")
	run.state="running";run.updated_at=2
	a=p.update([run],"gym",false,false,2)
	assert(a.pose=="console" and a.goal=="workstation")
	assert(p.update([original],"gym",false,false,1).backend_state=="running","Old snapshot cannot replay queued travel")
	var second=run.duplicate(true);second.input.id="two";second.updated_at=3
	a=p.update([run,second],"gym",false,false,3)
	assert(a.run_id=="one" and a.active_count==2 and a.label=="2 open runs","Keep assignment while a newer concurrent run updates")
	a=p.update([run,second],"gym",false,false,3,{"known":true,"enabled":false})
	assert(a.goal=="workstation" and a.duty_label.is_empty(),"Pausing future duties must not interrupt an active assignment")
	second.updated_at=4
	a=p.update([second,run],"gym",false,false,4)
	assert(a.run_id=="one","Input reorder and new progress must not bounce assignment")
	a=p.update([],"gym",true,false,4)
	assert(a.goal=="hold" and a.pose=="" and a.unknown and not a.evidence_ready)
	second.state="completed";second.evidence={"summary":{"outcome":"no_change"}};second.updated_at=5
	a=p.update([second],"gym",false,false,5)
	assert(a.run_id=="two" and a.goal=="home" and a.active_count==0 and a.evidence_ready,"Reconnect must coalesce directly to terminal evidence")
	assert(a.label=="Verified no change")
	a=p.update([second],"gym",false,true,5)
	assert(a.goal=="hold" and a.pose=="" and a.evidence_ready)
	run.stale=true
	a=p.update([run],"gym",false,false,6)
	assert(a.goal=="hold" and a.unknown and a.label.begins_with("Stale"))
	run.stale=false;run.state="cancel_requested"
	a=p.update([run],"gym",false,false,7)
	assert(a.goal=="hold" and a.pose=="" and not a.evidence_ready)
	run.state="completed";run.evidence=null
	a=p.update([run],"gym",false,false,8)
	assert(not a.evidence_ready and a.goal=="hold" and a.unknown and a.label.begins_with("Unknown"))
	a=p.update([],"gym",false,false,9)
	assert(a.run_id=="" and a.active_count==0 and a.goal=="home")
	a=p.update([],"gym",false,false,10,{"known":true,"enabled":true})
	assert(a.goal=="home" and a.duty_label=="On duty · waiting")
	a=p.update([],"gym",false,false,11,{"known":true,"enabled":false})
	assert(a.goal=="home" and a.duty_label=="Duty paused")
	print("CREW_PRESENTATION_PASSED: intent only, chronological coalescing, concurrency, offline/stale, reduced motion, evidence and cancellation")
	quit()
