extends SceneTree
const Preferences=preload("res://player_preferences.gd")
const Catalog=preload("res://characters/catalog.gd")
var failures:Array=[]
var captures:=""
var config_path:=""
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message)
func _initialize()->void:run.call_deferred()
func capture(name:String)->void:
	if captures.is_empty():return
	await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(captures.path_join(name+".png"))
func make_world():
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json";world.board_fixture="__empty_visual_fixture__"
	world.player_preferences_path=config_path
	root.add_child(world)
	return world
func run()->void:
	root.content_scale_size=Vector2i(1280,800);root.size=Vector2i(1280,800)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):captures=arg.trim_prefix("--capture-dir=")
	if not captures.is_empty():DirAccess.make_dir_recursive_absolute(captures)
	config_path=OS.get_environment("TMPDIR").path_join("starbase2-player-test-"+str(OS.get_process_id())+".cfg")
	if config_path.is_empty():config_path="/tmp/starbase2-player-test.cfg"
	check(Catalog.definitions().has("cybercat"),"Real Cybercat catalog entry required")
	if not failures.is_empty():finish();return
	Preferences.write_character("operator",config_path)
	var world=make_world();await process_frame;await physics_frame
	world.isolate_capture_input()
	var actor=world.get_node("Operator")
	var actor_id:int=actor.get_instance_id();var collider_ids:Array=[]
	for child in actor.get_children():
		if child is CollisionShape3D:collider_ids.append(child.get_instance_id())
	var npc_defs:Dictionary={}
	for pair in world.crew_pairs():npc_defs[pair[0]]=pair[1].character_definition
	var snapshot:Dictionary=world.snapshot.duplicate(true)
	check(world.player_character_id=="operator","Default is Sho Junko")
	check(actor.character_definition==Catalog.get_definition("operator","--character-pilot" in OS.get_cmdline_user_args()),"Explicit operator pilot flag preserved")
	world.hud.toggle_settings();world.hud.select_settings(3)
	world.hud.player_character_buttons.cybercat.grab_focus()
	check(world.hud.player_character_buttons.cybercat.has_focus(),"Cybercat keyboard focus reachable")
	await capture("selector-sho-junko-1280")
	# Start physical travel, then reopen Settings (which normally pauses movement).
	world.hud.close_panels()
	world.route=world.travel_route(actor.position+Vector3(0,0,3))
	actor.motion=Vector3(0,0,1.3)
	var moving_start:Vector3=actor.position
	for tick in range(10):await physics_frame
	check(actor.position.distance_to(moving_start)>.01 and actor.gait.moving,"Switch case begins during measured physical travel")
	world.hud.toggle_settings();world.hud.select_settings(3)
	var visual_heading:float=actor.model_visual.rotation.y if actor.model_visual!=null else 0.0
	var route:PackedVector3Array=world.route.duplicate();var pos:Vector3=actor.position
	var motion:Vector3=actor.motion;var phase:float=actor.gait.phase
	world.hud.player_character_buttons.cybercat.pressed.emit()
	check(world.player_character_id=="cybercat" and actor.character_definition==Catalog.get_definition("cybercat"),"Settings applies actual Cybercat definition")
	check(actor.position==pos and actor.motion==motion and actor.gait.phase==phase and world.route==route,"Switch preserves position motion route and gait")
	check(actor.get_instance_id()==actor_id,"Switch preserves CharacterBody")
	check(is_equal_approx(actor.model_visual.rotation.y,visual_heading),"Switch preserves displayed facing during travel")
	for child in actor.get_children():
		if child is CollisionShape3D:check(child.get_instance_id() in collider_ids,"No replacement collider")
	check(actor.find_children("*","CollisionShape3D",false,false).size()==collider_ids.size(),"No duplicate collider")
	check(actor.find_children("*","Node3D",false,false).filter(func(n):return n.get_script()==load("res://characters/model_visual.gd")).size()==1,"Exactly one model visual")
	check(Preferences.read_character(config_path)=="cybercat","Cybercat selection saved")
	await capture("selector-cybercat-1280")
	world.route.clear();actor.motion=Vector3.ZERO;world.hud.close_panels()
	await capture("world-cybercat")
	root.content_scale_size=Vector2i(800,640);root.size=Vector2i(800,640);world.hud.large_text=true;world.hud.scale_text();world.hud.toggle_settings();world.hud.select_settings(3)
	await process_frame;await process_frame
	for pick in world.hud.player_character_buttons.values():
		check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(pick.get_global_rect()),"Compact large-text character choice remains inside viewport")
	await capture("selector-cybercat-800-large")
	world.hud.reduced=true;world.apply_settings()
	pos=actor.position;world.hud.player_character_buttons.operator.pressed.emit()
	check(actor.reduced_motion and actor.position==pos and world.player_character_id=="operator","Switch back preserves reduced motion and position")
	for pair in world.crew_pairs():check(pair[1].character_definition==npc_defs[pair[0]],"NPC identity unchanged: "+pair[0])
	check(world.snapshot==snapshot and world.commands.payload.is_empty() and world.commands.phase.is_empty(),"No operational state mutation or dispatch")
	world.set_player_character("cybercat")
	world.queue_free();await process_frame
	world=make_world();await process_frame;await physics_frame
	check(world.player_character_id=="cybercat","New world restores persisted Cybercat")
	world.set_player_character("unknown-invalid")
	check(world.player_character_id=="operator" and Preferences.read_character(config_path)=="operator","Invalid choice falls back and persists Sho Junko")
	var config=ConfigFile.new();config.set_value("player","character","not-a-character");config.save(config_path)
	check(Preferences.read_character(config_path)=="operator","Invalid persisted id falls back")
	FileAccess.open(config_path,FileAccess.WRITE).store_string("not a config file")
	check(Preferences.read_character(config_path)=="operator","Malformed preferences fall back")
	world.queue_free();await process_frame
	DirAccess.remove_absolute(config_path)
	finish()
func finish()->void:
	for failure in failures:push_error(failure)
	print("PLAYER_CHARACTER_SELECTION: failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
