extends SceneTree
var failures: Array[String]=[]
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var basin=world.get_node("Terrace/MineralBasin")
	var canyon=world.get_node("Terrace/Landform")
	await create_timer(0.1).timeout
	check(canyon.water_time>0.0,"Canyon waves should animate normally")
	check(basin.water_time>0.0,"Decorative water should animate normally")
	world.hud.reduced=true
	world.apply_settings()
	var frozen: float=basin.water_time
	var canyon_frozen: float=canyon.water_time
	await create_timer(0.1).timeout
	check(canyon.water_time==canyon_frozen,"Reduced motion must freeze canyon waves")
	check(is_equal_approx(canyon.river_material.get_shader_parameter("water_time"),canyon_frozen),"Canyon material must retain frozen phase")
	check(basin.water_time==frozen,"Reduced motion must freeze water")
	check(is_equal_approx(basin.water.get_shader_parameter("water_time"),frozen),"Rendered water phase must stay frozen")
	world.hud.reduced=false
	world.apply_settings()
	await create_timer(0.1).timeout
	check(canyon.water_time>canyon_frozen,"Canyon waves should resume")
	check(basin.water_time>frozen,"Water should resume after reduced motion is disabled")
	world.enter_room("repair")
	frozen=basin.water_time
	canyon_frozen=canyon.water_time
	await create_timer(0.1).timeout
	check(canyon.water_time==canyon_frozen,"Hidden canyon waves should pause")
	check(basin.water_time==frozen,"Hidden exterior should not advance ambient water")
	world.exit_room()
	for node in [basin.get_node("WaterSurface"),basin.get_node("MineralBank")]:
		var bounds: AABB=node.get_aabb()
		check(bounds.position.x>=-6 and bounds.end.x<=6 and bounds.position.z>=-5 and bounds.end.z<=5,"Spring artwork must fit its existing blocked footprint")
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Environment checks passed: animated/frozen/resumed spring and canyon water, room visibility, shore footprint")
	quit(0 if failures.is_empty() else 1)
