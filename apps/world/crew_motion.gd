extends RefCounted
## Cosmetic physical life. Reservations and dwell clocks never dispatch backend work.
var actor:CharacterBody3D
var navigator:RefCounted
var station:Node3D
var rooms:Array=[]
var workstation:=Vector3.ZERO
var rest:=Vector3.ZERO
var path:=PackedVector3Array()
var intent:Dictionary={}
var destination:=Vector3(INF,0,0)
var stalled:=0.0
var previous:=Vector3.ZERO
var route_blocked:=false
var ambient_activity:=""
var ambient_facing:=Vector3(INF,0,0)
var member_id:=""
var anchors:Array=[]
var reservations:Dictionary={}
var anchor:Dictionary={}
var cycle:=0
var dwell:=0.0
var seed_value:=0
var seated:=false
var stand_remaining:=0.0

func configure(member:CharacterBody3D,nav:RefCounted,room_station:Node3D,point:Vector3) -> void:
	actor=member; navigator=nav; station=room_station; workstation=point
	rest=actor.position; previous=actor.position
	rooms=[station] if station!=null else []

func configure_home(identity:String,home_anchors:Array,all_rooms:Array,shared_reservations:Dictionary) -> void:
	member_id=identity; anchors=home_anchors.duplicate(true); rooms=all_rooms
	reservations=shared_reservations
	seed_value=absi(identity.hash())

func release_anchor() -> void:
	if not anchor.is_empty() and reservations.get(anchor.id)==member_id: reservations.erase(anchor.id)
	anchor={}; dwell=0; ambient_activity=""

func choose_home() -> Vector3:
	var old_anchor:Dictionary=anchor
	var old_id:String=str(anchor.get("id",""))
	release_anchor()
	for offset in range(anchors.size()):
		var candidate:Dictionary=anchors[(seed_value+cycle+offset)%anchors.size()]
		if reservations.has(candidate.id) or (anchors.size()>1 and candidate.id==old_id): continue
		anchor=candidate
		reservations[anchor.id]=member_id
		cycle+=1
		return anchor.position
	if not old_anchor.is_empty() and not reservations.has(old_id):
		anchor=old_anchor; reservations[old_id]=member_id; cycle+=1
		return anchor.position
	# No free authored anchor: hold current position instead of stacking crew.
	return actor.position if not anchors.is_empty() else rest

func route_to(target:Vector3) -> void:
	if seated and actor.position.distance_to(target)>=0.3:
		stand_remaining=1.0; seated=false
	destination=target; stalled=0; previous=actor.position
	path=navigator.route(actor.position,destination)
	if not path.is_empty() and navigator.clear_start_segment(Vector2(path[-1].x,path[-1].z),Vector2(destination.x,destination.z)):
		path.append(destination)
	route_blocked=path.is_empty() and actor.position.distance_to(destination)>=0.3

func project(next:Dictionary) -> void:
	var old_goal:String=str(intent.get("goal","hold"))
	intent=next
	var goal:String=str(intent.get("goal","hold"))
	if goal=="hold":
		path.clear(); destination=Vector3(INF,0,0); route_blocked=false
		actor.motion=Vector3.ZERO; actor.presentation_pose=""; ambient_activity=""
		stand_remaining=0; seated=false
		return
	if goal=="workstation":
		release_anchor()
		if destination!=workstation: route_to(workstation)
	elif old_goal!="home" or not is_finite(destination.x):
		var target:Vector3=anchor.position if not anchor.is_empty() else choose_home()
		route_to(target)

func advance(delta:float) -> void:
	actor.visible=true
	for room in rooms:
		if is_instance_valid(room) and room.contains(actor.position) and room.cutaway>=0.999:
			actor.visible=false; break
	actor.motion=Vector3.ZERO; actor.presentation_pose=""; ambient_activity=""; ambient_facing=Vector3(INF,0,0)
	if intent.get("goal","hold")=="hold": return
	if stand_remaining>0:
		actor.presentation_pose="stand"
		stand_remaining=maxf(0,stand_remaining-delta)
		previous=actor.position
		return
	if not path.is_empty():
		while not path.is_empty() and actor.position.distance_to(path[0])<0.12: path.remove_at(0)
		if not path.is_empty():
			var movement:Vector3=path[0]-actor.position; movement.y=0
			actor.motion=movement.normalized()*minf(1.3,movement.length()/maxf(delta,0.001))
			stalled=stalled+delta if actor.position.distance_to(previous)<0.001 else 0.0
			if stalled>2.0:
				path.clear(); actor.motion=Vector3.ZERO; route_blocked=true
	previous=actor.position
	if route_blocked or not actor.motion.is_zero_approx(): return
	if actor.position.distance_to(destination)>=0.3: return
	if intent.get("goal")=="workstation":
		actor.presentation_pose=str(intent.get("pose",""))
	elif not anchor.is_empty():
		ambient_activity=str(anchor.get("pose","relax"))
		actor.presentation_pose=ambient_activity
		seated=ambient_activity=="sit"
		ambient_facing=anchor.get("facing",Vector3(INF,0,0))
		dwell+=maxf(delta,0)
		if dwell>=18.0+float((seed_value+cycle*7)%19): route_to(choose_home())
