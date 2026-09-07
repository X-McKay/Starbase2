extends SceneTree
const Actor = preload("res://actor.gd")
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		printerr("FAILED: ",message)
		failed = true

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var actor := Actor.new()
	root.add_child(actor)
	await physics_frame
	check(actor.model_visual != null and not actor.sprite.visible, "Operator uses the detailed model")
	var visual = actor.model_visual
	check(visual.animation.has_animation("walk") and visual.animation.has_animation("idle"), "Both clips import")
	actor.motion = Vector3(2,0,0)
	for tick in range(12): await physics_frame
	check(visual.clip == "walk" and actor.gait.phase > 0, "Displacement advances walk")
	check(is_equal_approx(visual.rotation.y,PI/2), "Model faces travel")
	actor.motion = Vector3.ZERO
	await physics_frame
	await physics_frame
	check(visual.clip == "idle", "Stopping selects neutral idle")
	actor.reduced_motion = true
	actor.motion = Vector3(0,0,2)
	for tick in range(4): await physics_frame
	check(visual.clip == "idle", "Reduced motion disables skeletal gait")
	actor.reduced_motion = false
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(5,3,0.2)
	wall.add_child(shape)
	root.add_child(wall)
	wall.position = actor.position + Vector3(0,1,0.55)
	for tick in range(45): await physics_frame
	check(not actor.gait.moving and visual.clip == "idle", "Collision stops skeletal walking")
	actor.free()
	wall.free()
	print("MESHY_CHARACTER_CHECKS_COMPLETE failed=",failed)
	quit(1 if failed else 0)
