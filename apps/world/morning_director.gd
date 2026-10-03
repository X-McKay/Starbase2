extends RefCounted
## Optional observation camera selection. Never changes crew or backend state.
var enabled := false
var elapsed := 0.0
var selected := ""
var cursor := 0
var seen_active: Dictionary = {}
var pending_active: Array = []
var shot := "medium"
var shot_elapsed := 0.0
var shot_changed := false
var featured := ""
const SHOTS := ["medium", "over_shoulder", "equipment"]

func start() -> void:
	enabled=true; elapsed=30.0; selected=""; cursor=0; seen_active.clear(); pending_active.clear()
	shot="medium"; shot_elapsed=30.0; shot_changed=true
	featured=""

func stop() -> void:
	enabled=false; selected=""; elapsed=0.0; seen_active.clear(); pending_active.clear()
	shot="medium"; shot_elapsed=0.0; shot_changed=false
	featured=""

func feature(kind:String) -> void:
	# A newly observed handoff may be offered the next eligible shot. This is
	# camera priority only; it never changes the crew's assignment.
	featured=kind

func advance(delta:float, intents:Dictionary, reduced:bool) -> String:
	shot_changed=false
	if not enabled or reduced: return ""
	elapsed+=delta
	shot_elapsed+=delta
	var candidates:Array=intents.keys()
	if candidates.is_empty(): return ""
	var active:Array=[]
	for kind in candidates:
		var intent:Dictionary=intents[kind]
		if not intent.get("unknown",true) and int(intent.get("active_count",0))>0:
			active.append(kind)
	if featured in candidates and featured not in active: active.append(featured)
	# A fresh assignment may interrupt a quiet shot, with a minimum shot duration.
	for kind in active:
		if not seen_active.has(kind) and kind not in pending_active: pending_active.append(kind)
	pending_active=pending_active.filter(func(kind):return kind in active and kind != selected)
	var newly_active:Array=pending_active
	var next:=selected
	if elapsed>=6.0 and not active.is_empty() and (selected not in active or not newly_active.is_empty()): next=str(newly_active[0] if not newly_active.is_empty() else active[0])
	elif elapsed>=18.0:
		var pool:Array=active if not active.is_empty() else candidates
		next=str(pool[cursor%pool.size()]); cursor+=1
	seen_active.clear()
	for kind in active: seen_active[kind]=true
	if next==selected:
		if shot_elapsed>=5.5:
			shot=SHOTS[(SHOTS.find(shot)+1)%SHOTS.size()]
			shot_elapsed=0.0; shot_changed=true
		return ""
	selected=next; elapsed=0.0
	if selected==featured:featured=""
	shot="medium"; shot_elapsed=0.0; shot_changed=true
	pending_active.erase(next)
	return selected

func _visible(space:PhysicsDirectSpaceState3D,from:Vector3,to:Vector3,actor:Node3D,partner:Node3D=null) -> bool:
	if space==null:return true
	var ray:=PhysicsRayQueryParameters3D.create(from,to)
	# Crew bodies are the intended subject. The query should test set dressing
	# between the camera and the subject, not stop on the subject's own capsule.
	if actor is CollisionObject3D:ray.exclude=[actor.get_rid()]
	if partner is CollisionObject3D:
		var excluded:Array[RID]=ray.exclude
		excluded.append(partner.get_rid())
		ray.exclude=excluded
	for attempt in 4:
		var hit:Dictionary=space.intersect_ray(ray)
		if hit.is_empty() or hit.position.distance_to(to)<0.16:return true
		var collider:CollisionObject3D=hit.get("collider")
		# Terrace navigation proxies are taller than their visible props. They
		# should keep crew out of set dressing, not hide a visibly clear shot.
		if collider!=null and collider.get_parent()!=null and collider.get_parent().name=="Terrace" and collider.get_child_count()==1 and collider.get_child(0) is CollisionShape3D:
			var excluded:Array[RID]=ray.exclude
			excluded.append(collider.get_rid())
			ray.exclude=excluded
			continue
		return false
	return false

func _choose_offset(space:PhysicsDirectSpaceState3D,focus:Vector3,targets:Array,offsets:Array,actor:Node3D,partner:Node3D=null) -> Vector3:
	var best:Vector3=offsets[0]
	var best_score:float=-INF
	for index in range(offsets.size()):
		var offset:Vector3=offsets[index]
		var score:float=-float(index)*0.04 # Preserve the authored angle on a tie.
		for target in targets:
			if _visible(space,focus+offset,target,actor,partner):score+=1.0
		if score>best_score:best_score=score;best=offset
	return best

func composition(actor:Node3D,station:Node3D,indoors:bool,space:PhysicsDirectSpaceState3D=null) -> Dictionary:
	# Camera choreography is local presentation. It never changes assignment or travel.
	var actor_position:=actor.global_position if actor.is_inside_tree() else actor.position
	var focus:=actor_position+Vector3(0,0.9,0)
	var offset:=Vector3(8,18,23)
	var size:=10.0
	if indoors:
		offset=Vector3(5,11,14);size=8.8
	if not is_instance_valid(station):
		return {"focus":focus,"offset":offset,"size":size,"shot":shot}
	var station_basis:Basis=station.global_basis if station.is_inside_tree() else station.basis
	var forward:=station_basis.z.normalized()
	var right:=station_basis.x.normalized()
	var up:=Vector3.UP
	var contacts:Dictionary=station.contacts() if station.has_method("contacts") else {}
	var screen:Vector3=contacts.get("screen",Transform3D(Basis.IDENTITY,focus)).origin
	var offsets:Array=[]
	match shot:
		"over_shoulder":
			focus=actor_position.lerp(screen,.42)+up*.15
			offset=Vector3(2.3,2.9,3.8) if indoors else forward*4.2+right*2.1+up*3.6
			offsets=[offset,Vector3(4.2,3.5,3.2),Vector3(1.7,3.8,5.1)] if indoors else [offset,forward*4.5-right*2.3+up*3.8,forward*5.1+up*4.4]
			size=5.8 if indoors else 6.8
		"equipment":
			focus=actor_position.lerp(screen,.64)+up*.05
			offset=Vector3(3.5,3.2,4.3) if indoors else forward*3.2-right*3.0+up*4.6
			offsets=[offset,Vector3(5.1,3.9,3.0),Vector3(2.0,4.2,5.4)] if indoors else [offset,forward*4.0+right*2.2+up*4.7,forward*5.4+up*5.0]
			size=5.2 if indoors else 6.2
		_:
			focus=actor_position.lerp(screen,.22)+up*.18
			offset=Vector3(4.8,4.4,6.8) if indoors else forward*6.5+right*4.0+up*8.5
			offsets=[offset,Vector3(6.8,5.0,5.9),Vector3(3.2,5.5,8.0)] if indoors else [offset,forward*6.5-right*4.0+up*8.5,forward*8.0+up*9.2]
			size=8.2 if indoors else 9.4
	offset=_choose_offset(space,focus,[actor_position+up*1.45,actor_position+up*.85,screen],offsets,actor)
	return {"focus":focus,"offset":offset,"size":size,"shot":shot}

func composition_pair(giver:Node3D,receiver:Node3D,space:PhysicsDirectSpaceState3D=null) -> Dictionary:
	var left:=giver.global_position if giver.is_inside_tree() else giver.position
	var right:=receiver.global_position if receiver.is_inside_tree() else receiver.position
	var focus:Vector3=(left+right)*.5+Vector3(0,.95,0)
	# Side angles keep the low Commons rail and the planter out of the exchange.
	var offsets:Array=[Vector3(3.5,1.7,-2.0),Vector3(2.6,1.8,1.0),Vector3(3.8,2.5,4.8)]
	var offset:=_choose_offset(space,focus,[left+Vector3(0,1.45,0),right+Vector3(0,1.45,0),focus+Vector3(0,.17,0)],offsets,giver,receiver)
	return {"focus":focus,"offset":offset,"size":4.7,"shot":"handoff"}
