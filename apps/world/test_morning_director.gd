extends SceneTree
class Station:
	extends Node3D
	func contacts()->Dictionary:return {"screen":Transform3D(Basis.IDENTITY,position+Vector3(0,1.4,-.5))}
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var director=load("res://morning_director.gd").new()
	var intents={"review":{"unknown":false,"active_count":0},"repair":{"unknown":false,"active_count":0}}
	assert(director.advance(30,intents,false)=="")
	director.start()
	assert(director.advance(0,intents,false)=="review")
	assert(director.shot=="medium" and director.shot_changed)
	assert(director.advance(5.6,intents,false)=="" and director.shot=="over_shoulder" and director.shot_changed)
	intents.repair.active_count=1
	assert(director.advance(7,intents,false)=="repair")
	assert(director.advance(2,intents,false)=="")
	var before:Dictionary=intents.duplicate(true)
	assert(director.advance(30,intents,true)=="")
	assert(intents==before)
	director.stop()
	assert(director.advance(100,intents,false)=="")
	director.start(); intents.repair.unknown=true
	assert(director.advance(0,intents,false)=="review")
	# A second active crew arriving during a minimum shot must not be forgotten.
	director.stop(); director.start()
	intents={"review":{"unknown":false,"active_count":1},"repair":{"unknown":false,"active_count":0}}
	assert(director.advance(0,intents,false)=="review")
	intents.repair.active_count=1
	assert(director.advance(2,intents,false)=="")
	assert(director.advance(4,intents,false)=="repair", "Assignment during minimum shot must remain pending")
	var actor:=Node3D.new();actor.position=Vector3(2,0,3);root.add_child(actor)
	var medium:Dictionary=director.composition(actor,null,true)
	assert(medium.focus.is_finite() and medium.offset.is_finite() and medium.size>0)
	var station:=Station.new();station.position=actor.position;station.rotation.y=PI;root.add_child(station)
	for shot in director.SHOTS:
		director.shot=shot
		var indoor:Dictionary=director.composition(actor,station,true)
		assert(indoor.offset.x>0 and indoor.offset.z>0,"Every indoor Observe shot stays on the authored cutaway side")
	# A solid foreground obstruction moves the camera to one of three bounded
	# cutaway-side candidates while preserving the authored frame size.
	director.shot="medium"
	var baseline:Dictionary=director.composition(actor,station,true)
	var wall:=StaticBody3D.new();root.add_child(wall)
	wall.position=baseline.focus+baseline.offset*.5
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(1.2,2.0,1.2)
	collision.shape=shape;wall.add_child(collision)
	await physics_frame;await physics_frame
	var space:=actor.get_world_3d().direct_space_state
	assert(not director._visible(space,baseline.focus+baseline.offset,actor.global_position+Vector3(0,1.45,0),actor),"Fixture blocks the authored medium shot")
	var clear:Dictionary=director.composition(actor,station,true,space)
	assert(clear.offset!=baseline.offset and clear.size==baseline.size,"Observe chooses a clear cutaway angle without changing scale")
	assert(director._visible(space,clear.focus+clear.offset,actor.global_position+Vector3(0,1.45,0),actor),"Fallback preserves the subject sightline")
	wall.queue_free();await physics_frame
	var receiver:=Node3D.new();receiver.position=actor.position+Vector3(.72,0,0);root.add_child(receiver)
	var pair:Dictionary=director.composition_pair(actor,receiver,space)
	assert(pair.shot=="handoff" and pair.focus.distance_to((actor.position+receiver.position)*.5+Vector3(0,.95,0))<.001)
	assert(pair.size<clear.size and pair.offset.is_finite(),"Two crew share a close, finite handoff composition")
	director.stop();director.start()
	intents={"review":{"unknown":false,"active_count":0},"repair":{"unknown":false,"active_count":0}}
	assert(director.advance(0,intents,false)=="review")
	director.feature("repair")
	assert(director.advance(5.9,intents,false)=="" and director.selected=="review")
	assert(director.advance(.2,intents,false)=="repair","New handoff receives the next eligible Observe subject")
	print("MORNING_DIRECTOR_PASSED: opt-in, priority, three shots, bounded clear sightlines, two-crew frame, reduced motion, no record mutation")
	quit()
