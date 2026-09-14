extends SceneTree
## Isolated real CharacterBody3D motion for all six selected production definitions.
const Actor=preload("res://actor.gd")
const Catalog=preload("res://characters/catalog.gd")
const Motion=preload("res://crew_motion.gd")
class DirectNavigator extends RefCounted:
	func route(_from:Vector3,to:Vector3)->PackedVector3Array:return PackedVector3Array([to])
	func clear_start_segment(_from:Vector2,_to:Vector2)->bool:return true
var failures:Array=[]
var records:Array=[]
var members:Array=[]
var node:Node3D
func check(ok:bool,label:String)->void:
	if not ok and not failures.has(label):failures.append(label)
func _initialize()->void:run.call_deferred()
func frames(count:int)->void:
	for tick in range(count):
		for m in members:m.motion.advance(1.0/60.0)
		await physics_frame
		for m in members:
			var step:float=m.actor.position.distance_to(m.previous)
			m.max_step=maxf(m.max_step,step);m.distance+=step;m.previous=m.actor.position
func run()->void:
	node=Node3D.new();root.add_child(node)
	var roles=["operator","mender","surveyor","trainer","watchkeeper","reviewer"]
	if "--include-cybercat" in OS.get_cmdline_user_args():roles.append("cybercat")
	for i in range(roles.size()):
		var actor=Actor.new();actor.character_definition=Catalog.get_definition(roles[i]);actor.position=Vector3(0,0,i*5)
		node.add_child(actor)
		var wall=StaticBody3D.new();wall.position=Vector3(1,1,i*5)
		var collider=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=Vector3(.2,3,2)
		collider.shape=shape;wall.add_child(collider);node.add_child(wall)
		var motion=Motion.new();motion.configure(actor,DirectNavigator.new(),null,Vector3(3,0,i*5))
		var member={"role":roles[i],"actor":actor,"motion":motion,"previous":actor.position,"max_step":0.0,"distance":0.0,"contacts":0}
		actor.foot_contact.connect(func():member.contacts+=1)
		members.append(member)
	await physics_frame
	for m in members:m.motion.project({"goal":"workstation","pose":"console"})
	await frames(240)
	for m in members:
		check(m.motion.route_blocked,m.role+" bounded collision stall")
		check(m.actor.position.x<.63 and m.actor.position.x>.3,m.role+" real wall stops body")
		check(m.actor.motion.is_zero_approx() and m.actor.presentation_pose.is_empty(),m.role+" blocked never falsely poses")
		m.blocked_position=m.actor.position;m.blocked_phase=m.actor.gait.phase;m.blocked_contacts=m.contacts
	await frames(30)
	for m in members:
		check(m.actor.position.is_equal_approx(m.blocked_position),m.role+" blocked stable position")
		check(is_equal_approx(m.blocked_phase,m.actor.gait.phase) and m.contacts==m.blocked_contacts,m.role+" no collision skating cadence or footsteps")
		m.motion.project({"goal":"hold"})
		m.motion.workstation=m.actor.position+Vector3(0,0,2.5)
		m.motion.seated=true
		m.motion.project({"goal":"workstation","pose":"console"})
		m.interrupt_position=m.actor.position
	await frames(45)
	for m in members:
		check(m.actor.position.distance_to(m.interrupt_position)<.001 and m.actor.presentation_pose=="stand",m.role+" seated interruption waits for stand")
	await frames(60)
	for m in members:
		check(m.actor.position.distance_to(m.interrupt_position)>.5,m.role+" seated interruption resumes actual movement")
		check(m.actor.presentation_pose!="console",m.role+" no early work pose")
		m.motion.project({"goal":"hold"});m.held_position=m.actor.position
	await frames(30)
	for m in members:
		check(m.actor.position.distance_to(m.held_position)<.001 and m.actor.motion.is_zero_approx(),m.role+" interruption hold stops without teleport")
		m.motion.project({"goal":"workstation","pose":"console"})
	await frames(180)
	for m in members:
		check(m.actor.position.distance_to(m.motion.workstation)<.12 and m.actor.motion.is_zero_approx() and m.actor.presentation_pose=="console",m.role+" resumed route arrives stopped")
		check(m.max_step<1.3/60.0+.002,m.role+" bounded displacement")
		records.append({"role":m.role,"model":m.actor.character_definition.model_scene.resource_path,"distance":m.distance,"max_frame_displacement":m.max_step,"blocked_position":str(m.blocked_position),"arrival_distance":m.actor.position.distance_to(m.motion.workstation),"stopped":m.actor.motion.is_zero_approx(),"clip":m.actor.model_visual.clip})
	var output="res://../../evidence/crew-motion-validation/travel/six-cast-diagnostic.json"
	if "--include-cybercat" in OS.get_cmdline_user_args():output="res://../../evidence/cybercat/selection/seven-cast-collision.json"
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"records":records,"failures":failures,"scope":"Isolated six production CharacterBody3D models; actual physics wall; controller stand/hold/resume; no authored world route in this diagnostic"},"  "))
	for failure in failures:push_error(failure)
	print("SIX_CAST_TRAVEL_DIAGNOSTIC: records=",records.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
