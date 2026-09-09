extends RefCounted
## Physical presentation of a selected run. No API requests, timers or dispatch.
var actor:CharacterBody3D
var navigator:RefCounted
var station:Node3D
var workstation:=Vector3.ZERO
var rest:=Vector3.ZERO
var path:=PackedVector3Array()
var intent:Dictionary={}
var destination:=Vector3(INF,0,0)
var stalled:=0.0
var previous:=Vector3.ZERO

func configure(member:CharacterBody3D,nav:RefCounted,room_station:Node3D,point:Vector3) -> void:
	actor=member; navigator=nav; station=room_station; workstation=point
	rest=actor.position
	# Existing indoor crew start beside their station; provide a nearby clear rest spot.
	if rest.distance_to(workstation)<0.5:
		for offset in [Vector3(0,0,2),Vector3(2,0,0),Vector3(-2,0,0),Vector3(0,0,-2)]:
			var candidate:Vector3=workstation+offset
			if not navigator.route(workstation,candidate).is_empty():
				rest=candidate
				actor.position=rest
				actor.home=rest
				break
	previous=actor.position

func project(next:Dictionary) -> void:
	intent=next
	var goal:=str(intent.get("goal","hold"))
	if goal=="hold":
		path.clear(); destination=Vector3(INF,0,0)
		actor.motion=Vector3.ZERO; actor.presentation_pose=""
		return
	var target:Vector3=workstation if goal=="workstation" else rest
	if target!=destination:
		destination=target
		path=navigator.route(actor.position,destination)
		# Grid routing ends on a half-metre cell. Finish the safe final segment
		# to the authored point instead of falsely treating that cell as arrival.
		if not path.is_empty() and navigator.clear_start_segment(Vector2(path[-1].x,path[-1].z),Vector2(destination.x,destination.z)):
			path.append(destination)
		stalled=0

func advance(delta:float) -> void:
	if station!=null:
		actor.visible=not station.contains(actor.position) or station.cutaway<0.999
	actor.motion=Vector3.ZERO
	actor.presentation_pose=""
	if intent.get("goal","hold")=="hold": return
	if not path.is_empty():
		while not path.is_empty() and actor.position.distance_to(path[0])<0.12: path.remove_at(0)
		if not path.is_empty():
			var movement:Vector3=path[0]-actor.position
			movement.y=0
			actor.motion=movement.normalized()*minf(1.3,movement.length()/maxf(delta,0.001))
			stalled=stalled+delta if actor.position.distance_to(previous)<0.001 else 0.0
			# A blocked depiction must never spin forever or certify arrival.
			if stalled>2.0: path.clear(); actor.motion=Vector3.ZERO
	previous=actor.position
	if actor.motion.is_zero_approx() and actor.position.distance_to(workstation)<0.3 and intent.get("goal")=="workstation":
		actor.presentation_pose=str(intent.get("pose",""))
