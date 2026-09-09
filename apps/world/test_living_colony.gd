extends SceneTree
const Commons=preload("res://living_commons.gd")
var failures:Array[String]=[]
func check(value:bool,message:String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func key(world:Node,code:Key) -> void:
	var event:=InputEventKey.new()
	event.physical_keycode=code
	event.pressed=true
	world._unhandled_key_input(event)
func walk(world:Node,target:Vector3) -> void:
	world.route=world.travel_route(target)
	check(not world.route.is_empty(),"Living colony route exists to "+str(target))
	for tick in range(900):
		await physics_frame
		if world.route.is_empty(): break
	await physics_frame
	await physics_frame
	check(world.get_node("Operator").position.distance_to(target)<0.45,"Living colony physically reaches "+str(target))
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json"
	world.board_fixture="__empty_visual_fixture__"
	root.add_child(world)
	await process_frame
	await physics_frame
	var actor=world.get_node("Operator")
	var commons_path:=Vector3(Commons.FOOTPRINT.end.x-2.0,0,Commons.ORIGIN.z)
	await walk(world,commons_path)
	check(world.hud.location.text=="CONSERVATORY COMMONS","Commons location comes from actual arrival")
	check(not actor.label.visible and not world.hud.roster.is_visible_in_tree(),"Exploration avoids permanent names and roster")
	check(world.hud.connection.text.contains("FIXTURE"),"Quiet header preserves fixture truth")
	var ambience=world.get_node("RoomAmbience/DecorativeRoomTone")
	check(not ambience.playing,"Decorative ambience defaults muted in the actual world")
	world.hud.sound_enabled=true
	world.apply_settings()
	check(ambience.playing,"Explicit sound setting enables commons ambience")
	world.hud.sound_enabled=false
	world.apply_settings()
	check(not ambience.playing,"Muting stops current room ambience immediately")
	world.set_physics_process(false)
	for block in Commons.BLOCKS:
		var center:=Vector3(block.get_center().x,0,block.get_center().y)
		check(world.travel_route(center).is_empty(),"Commons furniture rejects navigation")
		actor.position=center+Vector3(0,0,block.size.y/2+0.8)
		actor.motion=Vector3(0,0,-3.7)
		for tick in range(25): await physics_frame
		check(actor.position.z>center.z+block.size.y/2+0.26,"Commons furniture physically stops movement")
		actor.motion=Vector3.ZERO
	world.set_physics_process(true)
	for station in world.get_node("Structures").get_children():
		var id:=str(station.definition.id)
		if id not in ["review","gym","habitat","greenhouse"]: continue
		actor.position=station.return_position()
		actor.motion=Vector3.ZERO
		await physics_frame
		var content=station.room.content
		var console:Vector3=content.get_node("Console").global_position
		await walk(world,console)
		check(world.active_building==station,"Primary console route enters matching room")
		var nearest_prop:=INF
		var point:Vector2=Vector2(station.room.console_point.x,station.room.console_point.z)
		for block in station.room.blocks:
			nearest_prop=minf(nearest_prop,point.distance_to(point.clamp(block.position,block.end)))
		check(nearest_prop>=0.25 and nearest_prop<=2.0,id+": primary console stands beside accessible furniture ("+str(nearest_prop)+" m)")
		check(content.has_node("CameraFocus") and content.has_node("CameraPosition"),"Room supplies authored camera anchors")
		if not content.has_node("CameraFocus") or not content.has_node("CameraPosition"): continue
		world.hud.reduced=false
		for tick in range(150): await process_frame
		check(world.camera_focus.distance_to(content.get_node("CameraFocus").global_position)<0.08,"Actual room camera consumes authored focus")
		check(world.camera.position.distance_to(content.get_node("CameraPosition").global_position)<0.08,"Actual room camera consumes authored position")
		check(world.hud.location.text==station.definition.title,"Header identifies entered room")
		world.hud.reduced=true
		world.apply_settings()
		world.camera_focus+=Vector3(8,0,0)
		await physics_frame
		await process_frame
		check(world.camera_focus.distance_to(content.get_node("CameraFocus").global_position)<0.01,"Reduced motion uses immediate authored camera")
		check(station.cutaway==0,"Reduced motion immediately reveals room")
		if id=="review":
			key(world,KEY_E)
			await process_frame
			check(world.hud.board.visible,"E at mission table opens existing Command board")
			world.hud.close_panels()
		if id in ["habitat","greenhouse"]:
			key(world,KEY_E)
			check(world.hud.room_details.visible,"E opens descriptive guide for unbound room")
			check(world.hud.room_detail_title.text==station.definition.title,"Room guide identifies exact scenery")
			check(not world.hud.room_detail_body.text.is_empty(),"Room guide has authored descriptive content")
			key(world,KEY_ESCAPE)
			check(not world.hud.room_details.visible,"Escape closes room guide")
			world.exit_room()
			world.enter_room(str(station.name))
			await physics_frame
			await physics_frame
			key(world,KEY_E)
			check(world.hud.room_details.visible,"Direct visit offers identical descriptive guide")
			key(world,KEY_ESCAPE)
		world.exit_room()
		world.hud.reduced=false
		print("LIVING_ROOM ",id)
	actor.position=commons_path
	await physics_frame
	await physics_frame
	key(world,KEY_B)
	check(world.hud.board.visible,"B opens identical board outside Command")
	world.hud.close_panels()
	for pair in world.crew_pairs():
		if actor.position.distance_to(pair[1].position)>4.5:
			check(not pair[1].label.visible,"Distant crew names remain hidden")
	check(world.commands.payload.is_empty() and world.hud.board.commands.payload.is_empty(),"Travel, inspection and presentation never dispatch")
	world.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("LIVING_COLONY_PASSED: commons contacts, physical primary-console access, authored cameras, quiet truthful HUD, reduced motion and identical non-spatial Command")
	quit(0 if failures.is_empty() else 1)
