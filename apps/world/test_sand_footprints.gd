extends SceneTree
## Cosmetic contact/fade/budget and native physical travel acceptance.
var failures:Array[String]=[]
var output:=""
var world:Node3D
func check(value:bool,message:String)->void:
	if not value:failures.append(message);push_error(message)
func _initialize()->void:run.call_deferred()
func picture(label:String)->void:
	if output.is_empty():return
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(output.path_join(label+".png"))==OK,"Save native footprint view")
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800)
	world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json";world.board_fixture="__empty_visual_fixture__";world.player_preferences_path=""
	root.add_child(world);await process_frame;await physics_frame
	world.isolate_capture_input()
	world.hud.reduced=false;world.apply_settings()
	var actor:Node3D=world.get_node("Operator")
	var prints:Node3D=world.footprints
	# Find a physically clear soil strip without depending on decorative scatter.
	var start:=Vector3.INF
	for z in range(-15,20):
		if start.is_finite():break
		for x in range(-15,20):
			var good:=true
			for step in range(25):
				var point:=Vector3(x+step*0.25,0,z)
				if not prints.accepts(point,PI/2) or world.navigator.grid.is_point_solid(Vector2i(roundi(point.x*2),roundi(point.z*2))):good=false;break
			if good:start=Vector3(x,0,z);break
	check(start.is_finite(),"Six-metre physical soil strip exists")
	if not start.is_finite():quit(1);return
	print("SOIL_STRIP ",start)
	actor.position=start;world.overview=start
	for pair in world.crew_pairs():pair[1].set_physics_process(false)
	world.set_physics_process(false)
	actor.motion=Vector3.ZERO
	for frame in 3:await physics_frame
	var initial:int=prints.emitted
	for frame in 30:await physics_frame
	check(prints.emitted==initial,"Stationary feet create no prints")
	world.zoom=9.0;world._process(1)
	await picture("before-walking")
	actor.motion=Vector3(3,0,0)
	for frame in 110:await physics_frame
	actor.motion=Vector3.ZERO
	await physics_frame
	check(actor.position.x>start.x+5,"Physical movement crosses soil")
	check(prints.emitted>=initial+3,"Real grounded gait contacts leave multiple imprints")
	for entry in prints.entries:
		check(absf(entry.point.y)<0.055,"Print follows a grounded deformed sole")
		# Dummy headless rendering returns identity, not submitted MultiMesh data.
		# The native execution of this test checks the actual render transform.
		if DisplayServer.get_name()!="headless":
			var height:float=prints.marks.multimesh.get_instance_transform(entry.slot).origin.y
			check(height>prints.SOIL_HEIGHT and height<prints.SOIL_HEIGHT+0.005,"Impression lies within 5mm of rendered soil")
	world.overview=start+Vector3(3,0,0);world._process(1)
	await picture("fresh-trail-close")
	world.zoom=34.0/pow(1.2,2);world._process(1)
	await picture("fresh-trail-gameplay")
	world.zoom=9.0;world._process(1)
	prints.advance(17.0);await picture("fading-trail")
	prints.advance(25.0);check(prints.entries.is_empty(),"All footprints expire without growing retained history")
	await picture("expired-trail")
	check(not prints.accepts(Vector3(start.x,0.2,start.z),0),"Airborne feet rejected")
	check(not prints.accepts(Vector3(0,0,5.5),0),"Paving rejected")
	check(not prints.accepts(Vector3(-6,0,23),0),"Commons deck rejected")
	check(not prints.accepts(Vector3(999,0,999),0),"Outside terrain rejected")
	world.hud.reduced=true;world.apply_settings();initial=prints.emitted
	actor.motion=Vector3(-3,0,0)
	for frame in 60:await physics_frame
	actor.motion=Vector3.ZERO;await physics_frame
	check(prints.emitted==initial and not prints.visible,"Reduced motion suppresses trail effect without stopping walking")
	world.hud.reduced=false;world.apply_settings()
	actor.position=start+Vector3(7,0,1)
	for pair in world.crew_pairs():
		var crew:Node3D=pair[1]
		var home:Vector3=crew.position
		crew.position=start;crew.visible=true;crew.motion=Vector3.ZERO;crew.set_physics_process(true)
		for frame in 3:await physics_frame
		initial=prints.emitted;crew.motion=Vector3(3,0,0)
		for frame in 65:await physics_frame
		crew.motion=Vector3.ZERO;await physics_frame
		check(prints.emitted>initial,"Crew deformed-sole contacts leave prints: "+str(pair[0]))
		crew.position=home;crew.set_physics_process(false)
	for index in 180:prints.stamp(start+Vector3(index*0.001,0,0),0)
	check(prints.entries.size()==prints.CAPACITY and prints.marks.multimesh.instance_count==prints.CAPACITY,"Repeated crossings use bounded shared render pool")
	check(world.commands.payload.is_empty() and world.hud.operations.commands.payload.is_empty(),"Surface feedback dispatches no work")
	if not output.is_empty():
		var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"strip":str(start),"emitted":prints.emitted,"pool_capacity":prints.CAPACITY,"failures":failures},"  "))
	world.queue_free();await process_frame
	if failures.is_empty():print("SAND_FOOTPRINTS_PASSED")
	quit(0 if failures.is_empty() else 1)
