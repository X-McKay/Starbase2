extends RefCounted
## Explicit offline native package review; all walking uses real world physics.
var failures:Array[String]=[]
var records:Array[Dictionary]=[]
var frames:Array[Image]=[]
var motion_samples:Array[Dictionary]=[]
var journeys:Array[Dictionary]=[]
var output := ""
func check(value:bool,message:String) -> void:
	if not value: failures.append(message); push_error(message)
func capture(tree:SceneTree,name:String,actor:Node3D) -> void:
	await RenderingServer.frame_post_draw
	var image=tree.root.get_texture().get_image()
	check(image.save_png(output.path_join(name+".png"))==OK,"Cannot save native capture: "+name)
	records.append({"name":name,"position":[actor.position.x,actor.position.y,actor.position.z]})
func walk(tree:SceneTree,scene:Node,target:Vector3,context:Node3D,record_motion:bool=false) -> void:
	scene.route=scene.travel_route(target)
	check(not scene.route.is_empty(),"Native review route missing")
	var actor=scene.get_node("Operator")
	var start:Vector3=actor.position
	var previous:Vector3=actor.position
	var previous_tick := Engine.get_physics_frames()
	var manual_input_seen:=false
	for tick in range(1200):
		await tree.physics_frame
		for key in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT]:
			manual_input_seen=manual_input_seen or Input.is_physical_key_pressed(key)
		var elapsed_ticks := maxi(1,Engine.get_physics_frames()-previous_tick)
		check(actor.position.distance_to(previous)<=scene.TRAVEL_SPEED*float(elapsed_ticks)/Engine.physics_ticks_per_second+0.03,"Native review walking teleported")
		previous=actor.position
		previous_tick=Engine.get_physics_frames()
		if record_motion and tick%8==0 and frames.size()<12:
			await RenderingServer.frame_post_draw
			var frame=tree.root.get_texture().get_image()
			frames.append(frame)
			motion_samples.append({"physics_frame":Engine.get_physics_frames(),"position":[actor.position.x,actor.position.y,actor.position.z]})
		if scene.route.is_empty(): break
	var arrival := {"start":str(start),"target":str(target),"actual":str(actor.position),"remaining_route":str(scene.route),"manual_input_seen":manual_input_seen,"panel_open":scene.hud.is_open(),"context":str(context),"distance":actor.position.distance_to(target)}
	var collisions:Array=[]
	for index in actor.get_slide_collision_count():
		var collision=actor.get_slide_collision(index)
		collisions.append({"collider":str(collision.get_collider()),"normal":str(collision.get_normal())})
	arrival["collisions"]=collisions
	journeys.append(arrival)
	print("NATIVE_JOURNEY_RESULT ",JSON.stringify(arrival))
	check(actor.position.distance_to(target)<0.45,"Native review physical arrival failed: "+JSON.stringify(arrival))
	check(scene.active_building==context,"Native review crossing selected wrong room")
func run(tree:SceneTree,scene:Node,directory:String) -> void:
	output=directory
	check(not scene.fixture_path.is_empty(),"Native review requires offline fixture")
	if not failures.is_empty(): tree.quit(1); return
	# Exercise the actual camera, contextual HUD and room presentation updates.
	check(scene.is_processing(),"Native review requires live world presentation")
	var actor=scene.get_node("Operator")
	for station in scene.get_node("Structures").get_children():
		var id := str(station.definition.id)
		if id not in ["review","gym","habitat","greenhouse"]: continue
		actor.position=station.return_position()+Vector3(0,0,3)
		actor.motion=Vector3.ZERO
		for tick in range(120): await tree.physics_frame
		await capture(tree,id+"-exterior",actor)
		await walk(tree,scene,station.room.content.get_node("WalkTarget").global_position,station,id=="review")
		check(station.cutaway<0.01 and station.room.visible,"Native cutaway failed: "+id)
		await walk(tree,scene,station.room.to_global(station.room.console_point),station)
		for tick in range(90): await tree.physics_frame
		await capture(tree,id+"-interior",actor)
		if id=="review":
			var event:=InputEventKey.new()
			event.physical_keycode=KEY_E
			event.pressed=true
			scene._unhandled_key_input(event)
			check(scene.hud.board.visible,"Native primary table interaction opens Command")
			for tick in range(90): await tree.physics_frame
			await capture(tree,"command-workspace",actor)
			var original_size:Vector2i=tree.root.size
			var original_scale:Vector2i=tree.root.content_scale_size
			tree.root.content_scale_size=Vector2i(800,640)
			tree.root.size=Vector2i(800,640)
			scene.hud.large_text=true
			scene.hud.scale_text()
			for tick in range(45): await tree.physics_frame
			check(scene.hud.board.workspace_rect().end.x<=800,"Large-text narrow workspace fits")
			await capture(tree,"command-workspace-compact",actor)
			tree.root.content_scale_size=original_scale
			tree.root.size=original_size
			scene.hud.large_text=false
			scene.hud.scale_text()
			scene.hud.close_panels()
		if id in ["habitat","greenhouse"]:
			var guide_event:=InputEventKey.new()
			guide_event.physical_keycode=KEY_E
			guide_event.pressed=true
			scene._unhandled_key_input(guide_event)
			check(scene.hud.room_details.visible,"Native room guide opens")
			for tick in range(60): await tree.physics_frame
			await capture(tree,id+"-guide",actor)
			scene.hud.close_panels()
		await walk(tree,scene,station.return_position()+Vector3(0,0,3),null)
		for tick in range(60): await tree.physics_frame
		check(station.openness==0 and not station.door_collision.disabled,"Native airlock closure failed: "+id)
		print("NATIVE_EXPORTED_JOURNEY ",id)
	var commons=preload("res://living_commons.gd")
	await walk(tree,scene,Vector3(commons.FOOTPRINT.end.x-2.0,0,commons.ORIGIN.z),null)
	for tick in range(90): await tree.physics_frame
	check(scene.hud.location.text=="CONSERVATORY COMMONS","Native commons arrival updates location")
	await capture(tree,"living-commons",actor)
	var water_block:Rect2=preload("res://surface_layout.gd").NATURAL_BLOCKS[0]
	var shore:=Vector3(water_block.get_center().x,0,water_block.end.y+2.0)
	await walk(tree,scene,shore,null)
	for tick in range(90): await tree.physics_frame
	await capture(tree,"inhabited-water",actor)
	scene.hud.reduced=true
	scene.apply_settings()
	for tick in range(30): await tree.physics_frame
	await capture(tree,"inhabited-water-reduced",actor)
	scene.hud.reduced=false
	scene.apply_settings()
	scene.colony_overview=true
	for tick in range(90): await tree.physics_frame
	await capture(tree,"living-colony",actor)
	await capture_operations(tree,scene,actor)
	check(scene.commands.payload.is_empty(),"Native review dispatched work")
	check(scene.hud.operations.commands.payload.is_empty(),"Native operations review dispatched work")
	check(frames.size()>=4,"Missing physical motion samples")
	if frames.size()>=4:
		# A native frame strip preserves visible displacement and pose progression.
		var sheet=Image.create(1280,240*3,false,Image.FORMAT_RGB8)
		for index in frames.size():
			frames[index].resize(320,240,Image.INTERPOLATE_LANCZOS)
			frames[index].convert(Image.FORMAT_RGB8)
			sheet.blit_rect(frames[index],Rect2i(0,0,320,240),Vector2i((index%4)*320,(index/4)*240))
		check(sheet.save_png(output.path_join("review-motion.png"))==OK,"Cannot save motion evidence")
	var file=FileAccess.open(output.path_join("structure-captures.json"),FileAccess.WRITE)
	check(file!=null,"Cannot write native capture manifest")
	if file!=null: file.store_string(JSON.stringify({"captures":records,"journeys":journeys,"motion_frames":frames.size(),"motion_samples":motion_samples,"fixture":true,"live_world_presentation":scene.is_processing(),"failures":failures},"  "))
	if failures.is_empty(): print("EXPORTED_STRUCTURES_CAPTURE_PASSED")
	tree.quit(0 if failures.is_empty() else 1)

func capture_operations(tree:SceneTree,scene:Node,actor:Node3D) -> void:
	# Explicit synthetic retained records; never contact an operator or worker API.
	var data:Dictionary={"schema_version":2,"observed_at":1788920000,"worker":{"available":true,"seen_at":1788919999},"active":[],"recent":[],"targets":[{"id":"workspace","label":"Packaged application","simulation":false},{"id":"sample","label":"Training repository","simulation":true}],"builds":[{"digest":"fixture-v1","manifest":{"profile":"surveyor-v1"}},{"digest":"fixture-v2","manifest":{"profile":"surveyor-v2"}}],"duties":[{"id":"fixture-review-watch","target":"sample","profile":"surveyor-v2","interval_seconds":300,"enabled":false,"generation":2}],"installation":{"id":"fixture-starbase2","capabilities":{"accept_work":{"enabled":true},"review":{"enabled":true},"evaluation":{"enabled":true},"inference":{"enabled":false}}}}
	for index in range(20):
		var run:Dictionary={"sequence":30-index,"input":{"request":{"id":"fixture-review-"+str(30-index),"kind":"review","target":"sample","profile":"surveyor-v2"},"builds":data.builds},"state":"completed","created_at":1788919800,"updated_at":1788919900,"detail":"Synthetic retained Python review; no provider accessed.","report":{"summary":{"outcome":"incomplete","finding_count":0,"files_reviewed":2,"qualification":"Partial synthetic coverage. Unsupported files excluded; not a certification.","synthetic_task":true}},"events":[{"state":"completed","at":1788919900,"detail":"Fixture evidence retained"}]}
		data.recent.append(run)
	var active:Dictionary=data.recent[0].duplicate(true)
	active.input.request.id="fixture-active-assignment"; active.sequence=1; active.state="running"; active.report=null
	data.active=[active]
	var compare:Dictionary=active.duplicate(true); compare.input.request.kind="evaluation"; compare.input.request.id="fixture-queued-comparison"; compare.state="queued"
	data.active.append(compare)
	scene.receive_snapshot(data)
	scene.enter_room("review")
	scene.hud.close_panels()
	var review_station=scene.get_node(scene.STATIONS.review)
	await walk(tree,scene,review_station.room.to_global(review_station.room.console_point),review_station)
	scene.adjust_zoom(-1)
	scene.adjust_zoom(-1)
	for tick in range(120): await tree.physics_frame
	check(scene.get_node("Surveyor").label.visible,"Assignment markers visible near assigned crew")
	await capture(tree,"operations-task-markers",actor)
	scene.adjust_zoom(1)
	scene.adjust_zoom(1)
	scene.hud.open_operations()
	for tick in range(12): await tree.process_frame
	await capture(tree,"operations-review",actor)
	scene.hud.operations.briefing_toggle.pressed.emit()
	for tick in range(12): await tree.process_frame
	await capture(tree,"operations-briefing",actor)
	scene.hud.operations.briefing_toggle.pressed.emit()
	scene.hud.operations.tabs.current_tab=1
	for tick in range(12): await tree.process_frame
	await capture(tree,"operations-comparison",actor)
	scene.hud.operations.tabs.current_tab=2
	for tick in range(12): await tree.process_frame
	await capture(tree,"operations-duties",actor)
	scene.hud.operations.tabs.current_tab=3
	scene.hud.operations.history.load_latest()
	scene.hud.operations.history.inspect_run("fixture-review-30")
	for tick in range(12): await tree.process_frame
	await capture(tree,"operations-history",actor)
	var original_size:Vector2i=tree.root.size
	var original_scale:Vector2i=tree.root.content_scale_size
	tree.root.content_scale_size=Vector2i(800,640); tree.root.size=Vector2i(800,640)
	scene.hud.large_text=true; scene.hud.scale_text(); scene.hud.operations.tabs.current_tab=0
	for tick in range(12): await tree.process_frame
	check(scene.hud.operations.get_global_rect().end.x<=800,"Operations narrow viewport fits")
	await capture(tree,"operations-compact",actor)
	scene.disconnected=true; scene.show_mission()
	await capture(tree,"operations-disconnected",actor)
	tree.root.content_scale_size=original_scale; tree.root.size=original_size
	scene.hud.large_text=false; scene.hud.scale_text(); scene.hud.close_panels()
	scene.hud.open_connection()
	for tick in range(12): await tree.process_frame
	await capture(tree,"operations-heartbeat",actor)
