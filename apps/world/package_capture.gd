extends RefCounted
## Explicit offline native package review; all walking uses real world physics.
var failures:Array[String]=[]
var records:Array[Dictionary]=[]
var frames:Array[Image]=[]
var motion_samples:Array[Dictionary]=[]
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
	var previous:Vector3=actor.position
	var previous_tick := Engine.get_physics_frames()
	for tick in range(1200):
		await tree.physics_frame
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
	check(actor.position.distance_to(target)<0.45,"Native review physical arrival failed")
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
	check(scene.commands.payload.is_empty(),"Native review dispatched work")
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
	if file!=null: file.store_string(JSON.stringify({"captures":records,"motion_frames":frames.size(),"motion_samples":motion_samples,"fixture":true,"live_world_presentation":scene.is_processing(),"failures":failures},"  "))
	if failures.is_empty(): print("EXPORTED_STRUCTURES_CAPTURE_PASSED")
	tree.quit(0 if failures.is_empty() else 1)
