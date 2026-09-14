extends SceneTree
var failures:Array[String]=[]
func check(ok:bool,message:String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json"
	world.board_fixture="__empty_visual_fixture__"
	root.add_child(world)
	await process_frame
	world.set_physics_process(false)
	var morning=preload("res://morning_atmosphere.gd").new()
	world.add_child(morning); morning.install(world)
	check(morning.textiles.size()==4,"Two linen accents per authored doorway")
	check(morning.leaves.size()==36,"Both overhead planters expose authored leaves")
	check(morning.vapors.size()==5,"Steam belongs to five existing mugs")
	check(morning.find_children("*","CollisionObject3D",true,false).is_empty(),"Dressing preserves existing traversal collision")
	check(not morning.is_processing(),"One host-owned update, no autonomous loop")
	var entry:Dictionary=morning.entrances[0]
	morning.update_presentation([entry.point],1.0,false)
	check(entry.lamp.light_energy>0.7,"Physical arrival warms the doorway")
	morning.update_presentation([Vector3(999,0,999)],1.0,false)
	check(is_equal_approx(entry.lamp.light_energy,0.18),"Departure returns steady ambient light")
	var leaf_before:Vector3=morning.leaves[0].node.rotation if not morning.leaves.is_empty() else Vector3.ZERO
	var frozen:float=morning.breeze_time
	morning.update_presentation([entry.point],1.0,true)
	check(morning.leaves.is_empty() or morning.leaves[0].node.rotation.is_equal_approx(leaf_before),"Reduced motion freezes greenery without snapping")
	check(morning.breeze_time==frozen,"Reduced motion preserves cloth phase")
	check(morning.vapors.all(func(mesh):return not mesh.visible),"Reduced motion removes drifting steam")
	check(entry.lamp.light_energy>0.7,"Reduced motion still shows proximity immediately")
	morning.update_presentation([],0.016,false)
	check(morning.breeze_time>frozen and morning.vapors.all(func(mesh):return mesh.visible),"Normal presentation resumes cleanly")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Morning atmosphere checks passed: anchored mugs, overhead dressing, arrival/departure, motion freeze/resume, no collisions or autonomous dispatch")
	world.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
