extends SceneTree
func _initialize() -> void:
	var director=load("res://morning_director.gd").new()
	var intents={"review":{"unknown":false,"active_count":0},"repair":{"unknown":false,"active_count":0}}
	assert(director.advance(30,intents,false)=="")
	director.start()
	assert(director.advance(0,intents,false)=="review")
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
	print("MORNING_DIRECTOR_PASSED: opt-in, real assignment priority, minimum shot, reduced motion, no record mutation")
	quit()
