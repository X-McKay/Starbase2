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
const SHOTS := ["medium", "over_shoulder", "equipment"]

func start() -> void:
	enabled=true; elapsed=30.0; selected=""; cursor=0; seen_active.clear(); pending_active.clear()
	shot="medium"; shot_elapsed=30.0; shot_changed=true

func stop() -> void:
	enabled=false; selected=""; elapsed=0.0; seen_active.clear(); pending_active.clear()
	shot="medium"; shot_elapsed=0.0; shot_changed=false

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
	shot="medium"; shot_elapsed=0.0; shot_changed=true
	pending_active.erase(next)
	return selected

func composition(actor:Node3D,station:Node3D,indoors:bool) -> Dictionary:
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
	match shot:
		"over_shoulder":
			focus=actor_position.lerp(screen,.42)+up*.15
			offset=Vector3(2.3,2.9,3.8) if indoors else forward*4.2+right*2.1+up*3.6
			size=5.8 if indoors else 6.8
		"equipment":
			focus=actor_position.lerp(screen,.64)+up*.05
			offset=Vector3(3.5,3.2,4.3) if indoors else forward*3.2-right*3.0+up*4.6
			size=5.2 if indoors else 6.2
		_:
			focus=actor_position.lerp(screen,.22)+up*.18
			offset=Vector3(4.8,4.4,6.8) if indoors else forward*6.5+right*4.0+up*8.5
			size=8.2 if indoors else 9.4
	return {"focus":focus,"offset":offset,"size":size,"shot":shot}
