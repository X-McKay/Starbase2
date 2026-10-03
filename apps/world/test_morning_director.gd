extends SceneTree
class Station:
	extends Node3D
	func contacts()->Dictionary:return {"screen":Transform3D(Basis.IDENTITY,position+Vector3(0,1.4,-.5))}
func _initialize() -> void:
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
	print("MORNING_DIRECTOR_PASSED: opt-in, real assignment priority, three smooth shot types, reduced motion, no record mutation")
	quit()
