extends SceneTree
const Lights=preload("res://paving_lights.gd")
const Paving=preload("res://colony_paving.gd")
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var light=Lights.new()
	root.add_child(light)
	check(light.get_child_count()==5,"Border lighting stays in five batched meshes")
	check(not light.is_processing(),"Border lighting needs no CPU animation loop")
	check(light.find_children("*","CollisionObject3D",true,false).is_empty(),"Border lights must not narrow walkways")
	check(Lights.pad_edges().size()==Paving.foundation_cells().size()*4,"Every rectangular pad gets all four illuminated sides")
	for rect in Lights.pad_edges():
		for point in [rect.position,rect.end]:
			check(Paving.pad_tiles().has(Paving.cell_at(point)),"Blue border must stay inside dark pad")
	for edge in Lights.road_edges():
		check(not Paving.cells().has(edge.cell+edge.normal),"Road outline must not cross a junction or pad entry")
		check(Paving.road_tiles().has(Paving.cell_at(edge.at)),"Road fixtures must sit on road paving")
	var lamps=Lights.beacons()
	check(lamps.size()>20,"Road network needs spaced runway lights")
	for lamp in lamps:
		for offset in [Vector2(-0.14,-0.14),Vector2(0.14,0.14)]:
			check(Paving.road_tiles().has(Paving.cell_at(lamp+offset)),"Inset lamps must remain inside the two-tile road")
	# Straight southern road: paired rows with exactly three-metre spacing.
	var south: Array[float]=[]
	for lamp in lamps:
		if is_equal_approx(lamp.y,29.85) and lamp.x>-20 and lamp.x< -3: south.append(lamp.x)
	south.sort()
	check(south.size()>=4,"Southern straight needs regular edge lights")
	for i in range(1,south.size()): check(is_equal_approx(south[i]-south[i-1],3.0),"Runway lights must be spaced three metres apart")
	light.reduced_motion=true
	check(light.beacon_material.get_shader_parameter("motion_enabled")==false,"Reduced motion must stop beacon flashing")
	light.reduced_motion=false
	check(light.beacon_material.get_shader_parameter("motion_enabled")==true,"Normal motion resumes the pulse")
	light.free()
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	world.hud.reduced=true
	world.apply_settings()
	check(not world.get_node("Terrace/PavingLights").beacon_material.get_shader_parameter("motion_enabled"),"Settings must reach actual colony lights")
	world.hud.reduced=false
	world.apply_settings()
	check(world.get_node("Terrace/PavingLights").beacon_material.get_shader_parameter("motion_enabled"),"Settings must resume actual colony lights")
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Paving light checks passed: all pad borders, exposed road edges, inset fixtures, three-metre spacing, reduced-motion settings, five meshes, no collision or CPU polling")
	quit(0 if failures.is_empty() else 1)
