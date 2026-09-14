extends SceneTree
const Motion=preload("res://crew_motion.gd")
class Member extends CharacterBody3D:
	var motion:=Vector3.ZERO
	var presentation_pose:=""
class Navigator extends RefCounted:
	var blocked:=false
	var calls:=0
	func route(_from:Vector3,to:Vector3) -> PackedVector3Array:
		calls+=1
		return PackedVector3Array() if blocked else PackedVector3Array([to])
	func clear_start_segment(_from:Vector2,_to:Vector2) -> bool: return true
class Room extends Node3D:
	var cutaway:=1.0
	func contains(point:Vector3) -> bool: return point.x>5
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var nav=Navigator.new();var shared:Dictionary={}
	var room=Room.new();root.add_child(room)
	var anchors:Array=[{"id":"seat","position":Vector3(1,0,0),"pose":"sit","facing":Vector3(1,0,2)},{"id":"commons","position":Vector3(3,0,0),"pose":"relax"},{"id":"window","position":Vector3(6,0,0),"pose":"relax"}]
	var actors:Array=[];var motions:Array=[]
	for id in ["one","two"]:
		var actor=Member.new();root.add_child(actor);actors.append(actor)
		var motion=Motion.new();motion.configure(actor,nav,null,Vector3(10,0,0));motion.configure_home(id,anchors,[room],shared)
		motion.project({"goal":"home"});motions.append(motion)
	assert(shared.size()==2 and motions[0].anchor.id!=motions[1].anchor.id,"Crew reserve distinct home destinations")
	for tick in range(600):
		for m in motions:
			m.advance(1.0/60);m.actor.position+=m.actor.motion/60
	for m in motions:
		assert(m.actor.position.distance_to(m.destination)<0.3 and not m.ambient_activity.is_empty(),"Physical movement reaches authored anchor before idle pose")
	var old_anchor:String=motions[0].anchor.id
	motions[0].advance(40)
	assert(motions[0].anchor.id!=old_anchor and shared.size()==2,"Bounded cosmetic dwell rotates to a free anchor without competing for occupied seats")
	var copy=Motion.new();copy.configure(actors[0],nav,null,Vector3(10,0,0));copy.configure_home("one",anchors,[room],{})
	copy.project({"goal":"home"})
	assert(copy.anchor.id==old_anchor,"Stable identity produces deterministic first-home choice")
	var m=motions[0];m.anchor={"id":"seat","position":m.actor.position,"pose":"sit"};m.destination=m.actor.position;m.path.clear()
	m.advance(0.01);assert(m.actor.presentation_pose=="sit")
	m.project({"goal":"workstation","pose":"console"});m.advance(0.1)
	assert(m.actor.presentation_pose=="stand" and m.actor.motion.is_zero_approx(),"Assignment interrupts seated life with bounded stand transition")
	for tick in range(20): m.advance(0.1)
	assert(m.actor.motion.length()>0 and m.actor.presentation_pose!="console","No work pose before actual station arrival")
	m.project({"goal":"home"});assert(m.destination!=m.workstation,"Fast completion redirects immediately home")
	m.project({"goal":"hold"});var retained:Vector3=m.actor.position;m.advance(100)
	assert(m.actor.motion.is_zero_approx() and m.actor.presentation_pose.is_empty() and m.actor.position==retained,"Reduced/offline hold never teleports or invents activity")
	m.actor.position=Vector3(6,0,0);m.advance(0.1);assert(not m.actor.visible,"Closed home interior hides crew even when workstation elsewhere")
	room.cutaway=0;m.advance(0.1);assert(m.actor.visible,"Opening occupied interior reveals crew")
	nav.blocked=true;m.project({"goal":"workstation","pose":"console"});var calls:int=nav.calls
	for tick in range(200): m.advance(0.1);m.project({"goal":"workstation","pose":"console"})
	assert(m.route_blocked and nav.calls==calls and m.actor.presentation_pose.is_empty(),"Failed routes are explicit, bounded and never falsely arrive")
	nav.blocked=false;m.project({"goal":"hold"});m.project({"goal":"workstation","pose":"console"})
	for tick in range(30): m.advance(0.1)
	assert(m.route_blocked and m.actor.motion.is_zero_approx(),"Collision stall stops within bounded time")
	for actor in actors: actor.queue_free()
	room.queue_free();await process_frame
	print("CREW_HOME_PASSED: occupancy, physical arrival, assignment interruption, early completion, holds, cross-room visibility and bounded failed routes")
	quit()
