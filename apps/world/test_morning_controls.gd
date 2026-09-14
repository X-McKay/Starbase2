extends SceneTree
## Offline input/occlusion acceptance; no API or provider calls.
var failures:Array[String]=[]
func check(ok:bool,message:String) -> void:
	if not ok: failures.append(message)
func key(world:Node,code:Key) -> void:
	var event:=InputEventKey.new(); event.physical_keycode=code; event.pressed=true
	world._unhandled_key_input(event)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json"
	world.board_fixture="__empty_visual_fixture__"
	root.add_child(world)
	await process_frame; await physics_frame
	var records:Dictionary=world.snapshot.duplicate(true)
	var player:Vector3=world.get_node("Operator").position
	world.station_signals.visible_context="repair"
	key(world,KEY_I)
	check(world.hud.station_records.visible and world.hud.station_records.selected_station=="repair","I matches the visible Workshop badge instead of defaulting to Command")
	key(world,KEY_ESCAPE)
	world.station_signals.visible_context=""
	key(world,KEY_K)
	check(world.hud.briefing.visible,"K opens retained-history briefing")
	check(not world.morning_director.enabled,"Briefing stops automatic observation")
	check(world.hud.briefing.dismiss.has_focus(),"Briefing immediately gives keyboard focus to dismiss")
	check(world.get_node("Structures/Habitat").cutaway==0.0,"Explicit briefing immediately reveals Habitat visual surfaces")
	world._process(1.0/60.0)
	var reading_focus:Vector3=world.daybook.global_position+Vector3(1,0.4,0)-world.camera.global_basis.x*3.5
	check(world.camera_focus.distance_to(reading_focus)<0.01,"Briefing camera reaches reading view in one frame without sweeping across terrain")
	key(world,KEY_ESCAPE)
	check(not world.hud.briefing.visible,"Escape dismisses briefing")
	key(world,KEY_V)
	check(world.morning_director.enabled and world.hud.observing,"V opts into observation")
	await physics_frame
	check(not world.hud.crew_strip.rows.visible,"Observation collapses large roster")
	world._physics_process(1.0/60.0)
	var selected_actor:Node3D=world.get_node(world.MEMBERS[world.watched_crew])
	world._process(1.0/60.0)
	check(world.camera_focus.distance_to(selected_actor.position)<5.0,"Observation cuts to its subject without sweeping across unrelated terrain")
	check(not world.observation_camera_cut,"Shot cut is consumed after one rendered update")
	key(world,KEY_V)
	check(not world.morning_director.enabled and not world.hud.observing,"Second V restores ordinary controls")
	key(world,KEY_V); key(world,KEY_ESCAPE)
	check(not world.morning_director.enabled and world.watched_crew.is_empty(),"Escape exits camera selection")
	world.hud.reduced=true; world.apply_settings()
	key(world,KEY_V)
	check(not world.morning_director.enabled,"Reduced motion refuses automatic camera movement")
	key(world,KEY_K)
	check(world.hud.briefing.visible,"Reduced motion preserves briefing access")
	world.hud.briefing.update_records([],true,0,true)
	check(world.hud.briefing.freshness.text.contains("OFFLINE / STALE"),"Disconnected briefing stays explicitly stale")
	check(world.hud.briefing.summary.text.contains("last known"),"Stale counts are qualified")
	world.daybook.update_records(world.hud.briefing.model)
	check(world.daybook.caption.text.contains("Last known"),"Physical daybook retains stale qualification")
	key(world,KEY_ESCAPE)
	for viewport_size in [Vector2i(1280,800),Vector2i(800,640)]:
		root.size=viewport_size; root.content_scale_size=viewport_size
		world.hud.large_text=true; world.hud.scale_text()
		await process_frame; await process_frame
		var strip=world.hud.crew_strip
		check(root.get_visible_rect().encloses(strip.get_global_rect()),"Crew strip fits "+str(viewport_size))
		for button in strip.find_children("*","Button",true,false):
			check(button.is_visible_in_tree(),"Compact control remains visible: "+button.text)
			check(strip.get_global_rect().encloses(button.get_global_rect()),"Compact control stays inside strip: "+button.text)
			check(button.size.x>=70,"Compact action keeps useful click width: "+button.text)
			if button.text.contains("["):
				var font:Font=button.get_theme_font("font")
				var width:=font.get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
				check(width<=button.size.x-button.get_theme_stylebox("normal").get_minimum_size().x,"Compact action text fits: "+button.text)
		key(world,KEY_K); await process_frame
		check(root.get_visible_rect().encloses(world.hud.briefing.get_global_rect()),"Compact briefing stays on screen")
		check(not world.hud.briefing.get_global_rect().intersects(strip.get_global_rect()) or not strip.is_visible_in_tree(),"Briefing does not cover crew controls")
		key(world,KEY_ESCAPE)
	check(world.snapshot==records,"Presentation controls never mutate authoritative snapshot")
	check(world.get_node("Operator").position==player,"Observation and briefing do not teleport operator")
	check(world.commands.payload.is_empty() and world.commands.phase.is_empty(),"Morning controls never dispatch commands")
	key(world,KEY_K)
	for frame in range(8): await physics_frame
	var actual_point:Vector2=world.camera.unproject_position(world.daybook.global_position+Vector3(0,0.24,0))
	check(world.daybook.hit(world.camera,actual_point),"Authored Habitat table permits visible daybook selection")
	check(world.watched_crew.is_empty(),"Briefing has no residual actor-follow camera")
	check(not world.hud.crew_strip.is_visible_in_tree(),"Briefing hides dense world chrome")
	world.queue_free(); await process_frame; await physics_frame
	# Isolated physical ray: a book may be projected onscreen yet occluded by a wall.
	var stage:=Node3D.new(); root.add_child(stage)
	var camera:=Camera3D.new(); stage.add_child(camera)
	camera.position=Vector3(0,1,4); camera.look_at(Vector3(0,0.24,0)); camera.current=true
	var book=preload("res://morning_daybook.gd").new(); stage.add_child(book)
	await process_frame; await physics_frame
	var point:=camera.unproject_position(book.global_position+Vector3(0,0.24,0))
	check(book.hit(camera,point),"Visible daybook accepts pointer at its actual projection")
	check(not book.hit(camera,point+Vector2(250,250)),"Daybook rejects unrelated world clicks")
	book.hide(); check(not book.hit(camera,point),"Hidden room daybook rejects pointer")
	book.show()
	var wall:=StaticBody3D.new(); wall.position=Vector3(0,0.6,2); stage.add_child(wall)
	var collision:=CollisionShape3D.new(); var shape:=BoxShape3D.new()
	shape.size=Vector3(3,3,0.2); collision.shape=shape; wall.add_child(collision)
	await physics_frame; await physics_frame
	check(not book.hit(camera,point),"Solid wall blocks spatial daybook selection")
	stage.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("MORNING_CONTROLS_PASSED: daybook visibility/occlusion, K/V/Esc, compact controls, reduced/stale, no teleport or dispatch")
	quit(0 if failures.is_empty() else 1)
