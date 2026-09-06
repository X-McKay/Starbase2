extends SceneTree
const Layout=preload("res://surface_layout.gd")
const Navigation=preload("res://navigation.gd")
const Paths=preload("res://colony_paths.gd")
const Geography=preload("res://geography.gd")
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var reserved := [Rect2(-31,5.1,6,1.9)]
	for plot in Layout.RESERVED_PLOTS: reserved.append(Rect2(plot-Vector2(5,3.7),Vector2(10,7.4)))
	var footprints := Layout.rock_bounds()
	for crater in Layout.CRATERS:
		footprints.append(Rect2(Vector2(crater.x,crater.z)-Vector2.ONE*crater.y*1.1,Vector2.ONE*crater.y*2.2))
	for rect in footprints:
		for corner in [rect.position,rect.end,Vector2(rect.end.x,rect.position.y),Vector2(rect.position.x,rect.end.y)]:
			check(Geography.contains(corner,0.7),"Scatter must remain inside shelf")
		for block in Navigation.PROPS+Navigation.STRUCTURES+reserved:
			check(not rect.intersects(block.grow(0.25)),"Scatter overlaps existing landmark: "+str(rect))
		check(rect.get_center().distance_to(Layout.LANDING_CENTER)>Layout.LANDING_RADIUS+0.1+rect.size.length()*0.5,"Scatter overlaps landing pad")
		for line in Paths.LINES:
			for point in Paths.points(line):
				check(not rect.grow(1.85).has_point(Vector2(point.x,point.z)),"Scatter overlaps walking corridor: "+str(rect))
	var nav := Navigation.new()
	for item in Layout.OUTCROPS:
		check(nav.route(Vector3(0,0,5.5),Vector3(item.at.x,0,item.at.y)).is_empty(),"Click route must reject solid outcrop")
	for crater in Layout.CRATERS:
		check(not nav.route(Vector3(0,0,5.5),Vector3(crater.x,0,crater.z)).is_empty(),"Shallow crater remains walkable")
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	world.set_physics_process(false)
	var operator=world.get_node("Operator")
	operator.position=Vector3(-34,0,-19)
	operator.motion=Vector3(0,0,-4)
	await create_timer(0.7).timeout
	check(operator.position.z> -20.4,"Physical movement must stop at the outcrop")
	operator.motion=Vector3.ZERO
	check(not nav.route(operator.position,Vector3(-30,0,-19)).is_empty(),"Routing recovers after outcrop contact")
	operator.position=Vector3(4.5,0,20)
	operator.motion=Vector3(0,0,-4)
	await create_timer(1.0).timeout
	check(operator.position.z<17,"Shallow crater is a traversable scar, not an invisible wall")
	operator.motion=Vector3.ZERO
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Surface scatter checks passed: shelf/path/landmark clearance, blocked outcrop routes and physics, traversable craters")
	quit(0 if failures.is_empty() else 1)
