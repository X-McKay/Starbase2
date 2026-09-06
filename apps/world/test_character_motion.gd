extends SceneTree
const Actor=preload("res://actor.gd")
const Catalog=preload("res://characters/catalog.gd")
var actor
var contacts:=0
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world:=Node3D.new(); root.add_child(world)
	actor=Actor.new(); actor.character_definition=Catalog.get_definition("operator",true)
	world.add_child(actor); actor.foot_contact.connect(func(): contacts+=1)
	var wall:=StaticBody3D.new(); wall.position=Vector3(1,0,0)
	var collider:=CollisionShape3D.new(); var shape:=BoxShape3D.new(); shape.size=Vector3(.2,4,10)
	collider.shape=shape; wall.add_child(collider); world.add_child(wall)
	actor.motion=Vector3(3,0,0)
	for i in range(60): await physics_frame
	assert(actor.position.x<.7,"Real collision stops actor")
	var phase:float=actor.gait.phase; var steps:=contacts
	for i in range(20): await physics_frame
	print("wall sample: ",phase," -> ",actor.gait.phase,"; contacts ",steps," -> ",contacts,"; position ",actor.position)
	assert(is_equal_approx(phase,actor.gait.phase) and contacts==steps,"Pushing wall must not animate or sound")
	assert(actor.sprite.animation=="idle_right")
	actor.motion=Vector3(0,0,2)
	for i in range(15): await physics_frame
	assert(actor.sprite.animation=="walk_front")
	assert(actor.gait.phase!=0,"Turning retains phase")
	actor.reduced_motion=true
	for i in range(2): await physics_frame
	assert(actor.sprite.animation=="idle_front","Reduced motion uses still poses")
	actor.motion=Vector3.ZERO; actor.position=Vector3(-3,0,0)
	for i in range(2): await physics_frame
	assert(actor.gait.phase==0,"Teleport resets gait")
	print("Actual CharacterBody3D wall collision, turns, reduced motion and teleport passed")
	quit()
