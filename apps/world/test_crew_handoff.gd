extends SceneTree
const Handoff=preload("res://crew_handoff.gd")
const Navigation=preload("res://navigation.gd")
func _initialize() -> void:
	var controller=Handoff.new()
	var mission={"id":"mission-1","updated_at":1,"events":[{"role":"lead","state":"investigating"},{"role":"implementer","state":"implementing"}]}
	var older={"id":"mission-older","updated_at":0,"events":[{"role":"lead","state":"investigating"},{"role":"reviewer","state":"complete"}]}
	var snapshot={"schema_version":7,"missions":[older,mission]}
	assert(not controller.observe(snapshot,true,false),"Retained history does not replay on startup")
	assert(not controller.observe(snapshot,true,false),"Unchanged polling does not replay a handoff")
	mission.events.append({"role":"reviewer","state":"testing"});mission.updated_at=2
	assert(controller.observe(snapshot,true,false) and controller.active(),"New exact role transition starts one presentation")
	assert(controller.current.giver=="repair" and controller.current.receiver=="reviewer")
	assert(controller.current.mission_id=="mission-1","Newest mission owns the projected handoff regardless of list order")
	var base={"goal":"workstation","pose":"console","label":"Testing retained candidate","unknown":false}
	var giver:Dictionary=controller.override("repair",base,false)
	var receiver:Dictionary=controller.override("reviewer",base,false)
	assert(giver.goal=="handoff" and giver.exchange_role=="giver" and giver.label==base.label)
	assert(receiver.goal=="handoff" and receiver.exchange_role=="receiver")
	var nav=Navigation.new()
	assert(not nav.route(Handoff.WEST,Handoff.EAST).is_empty(),"Authored Commons handoff anchors have a physical route")
	assert(not controller.advance(44,false,false) and controller.active(),"Travel is bounded without ending the presentation early")
	assert(controller.advance(6,true,false) and not controller.active(),"Six seconds of arrived interaction completes locally")
	var first_live=Handoff.new()
	var one_event={"schema_version":7,"missions":[{"id":"mission-live","updated_at":1,"events":[{"role":"lead","state":"investigating"}]}]}
	assert(not first_live.observe(one_event,true,false))
	one_event.missions[0].events.append({"role":"implementer","state":"implementing"});one_event.missions[0].updated_at=2
	assert(first_live.observe(one_event,true,false),"The first transition observed during the session is eligible")
	mission.events.append({"role":"lead","state":"reviewing"});mission.updated_at=3
	assert(not controller.observe(snapshot,false,false),"Stale evidence cannot animate a handoff")
	mission.events.append({"role":"implementer","state":"repairing"});mission.updated_at=4
	assert(not controller.observe(snapshot,true,true),"Reduced motion cannot start a handoff")
	assert(mission.events.size()==5,"Presentation never mutates authoritative history")
	print("CREW_HANDOFF_PASSED: new exact event only, physical anchors, truthful labels, stale/reduced suppression, bounded completion")
	quit()
