extends RefCounted
## Explicit offline self-check inside the exported executable/PCK.
## Explicit failures: assertions can be compiled out of release builds.
var failures:Array[String]=[]
func check(condition:bool, message:String) -> void:
	if not condition: failures.append(message); push_error(message)

func walk(tree:SceneTree,scene:Node,target:Vector3,station:Node3D) -> void:
	scene.route=scene.travel_route(target)
	check(not scene.route.is_empty(),"Packaged physical route missing: "+str(target))
	var actor=scene.get_node("Operator")
	var previous:Vector3=actor.position
	for tick in range(600):
		await tree.physics_frame
		check(actor.position.distance_to(previous)<0.22,"Packaged walking teleported")
		previous=actor.position
		if scene.route.is_empty(): break
	check(actor.position.distance_to(target)<0.45,"Packaged physical arrival failed: "+str(target))
	check(scene.active_building==station,"Packaged crossing selected wrong room")

func run(tree:SceneTree, scene:Node) -> void:
	check(not ResourceLoader.exists("res://test_state.gd"),"Development tests leaked into release")
	check(not ResourceLoader.exists("res://probe_station_hands.gd"),"Development hand diagnostics leaked into release")
	check(not ResourceLoader.exists("res://workstations/test_interaction_station.gd"),"Development furniture test leaked into release")
	check(not ResourceLoader.exists("res://characters/illustrated_import.gd"),"Art importer leaked into release")
	check(FileAccess.file_exists("res://characters/catalog.json"),"Missing character catalog")
	check(FileAccess.file_exists("res://characters/hand_contact_probes.json"),"Missing calibrated hand contact data")
	check(ResourceLoader.exists("res://characters/environment_interaction.gd"),"Missing environment interaction driver")
	check(ResourceLoader.exists("res://workstations/interaction_station.gd"),"Missing authored interaction furniture")
	check(ResourceLoader.exists("res://workstations/seated_console.gd"),"Missing seated Command furniture")
	check(ResourceLoader.exists("res://characters/seated_footwork.gd"),"Missing grounded chair transitions")
	check(not ResourceLoader.exists("res://test_seated_work_animation.gd"),"Development seated animation tests leaked into release")
	check(FileAccess.file_exists("res://assets/kits/aster-v1/manifest.json"),"Missing surface catalog")
	var catalog=load("res://characters/catalog.gd")
	var definition=catalog.get_definition("operator")
	var actor=load("res://actor.gd").new()
	actor.position=Vector3(1000,0,1000)
	tree.root.add_child(actor)
	for direction in range(4):
		var clip:String="walk_"+definition.DIRECTIONS[direction]
		check(definition.frames().has_animation(clip),"Missing packaged clip "+clip)
		actor.motion=[Vector3(0,0,3.2),Vector3(0,0,-3.2),Vector3(-3.2,0,0),Vector3(3.2,0,0)][direction]
		var observed:Dictionary={}
		for i in range(75):
			await tree.physics_frame
			if actor.sprite.animation==clip: observed[actor.sprite.frame]=true
		check(observed.size()==(8 if direction==3 else 4),"Packaged playback failed: "+clip)
		actor.reduced_motion=true
		for i in range(3): await tree.physics_frame
		check(actor.sprite.animation=="idle_"+definition.DIRECTIONS[direction],"Reduced motion failed: "+clip)
		actor.reduced_motion=false
	check(actor.model_visual!=null and not actor.sprite.visible,"Packaged native character missing")
	actor.free()
	var engineer=scene.get_node("Mender").model_visual
	for clip in ["idle","walk","run","console"]:
		check(engineer.animation.has_animation(clip),"Missing packaged engineer clip "+clip)
	# Load the actual colony and every authored interior using the supplied fixture.
	for i in range(5): await tree.process_frame
	check(scene.fixture_path!="","Export checks require an isolated fixture")
	for resource in ["joint_operations.gd","joint_commands.gd","joint_state.gd","learning_panel.gd","learning_commands.gd","characters/slate_choreography.gd","characters/work_attention.gd"]:
		check(ResourceLoader.exists("res://"+resource),"Missing packaged local-cycle dependency: "+resource)
	var operations=scene.hud.operations
	check(operations.joint!=null and operations.learning!=null,"Packaged mission and Practice views missing")
	check(scene.footprints!=null and scene.footprints.marks.multimesh.instance_count==128,"Packaged bounded sand footprint effect missing")
	check(ResourceLoader.exists("res://sand_print.gdshader"),"Packaged footprint material missing")
	check(ResourceLoader.exists("res://shadow_quality.gd"),"Packaged bounded shadow configuration missing")
	check(ResourceLoader.exists("res://crew_contact_shadow.gdshader"),"Packaged soft crew contact material missing")
	check(ResourceLoader.exists("res://structures/interior_sightlines.gd"),"Packaged roof sightline configuration missing")
	check(not operations.joint.fixture.is_empty() and not operations.learning.fixture.is_empty(),"Packaged local-cycle review must remain fixture fenced")
	check(operations.learning.enable_button.disabled and operations.learning.stop_button.disabled and operations.learning.cancel_button.disabled,"Packaged Practice fixture enabled mutation")

	check(scene.get_node("Operator").character_definition.id=="operator","Wrong production character")
	check(scene.get_node("Operator").model_visual.hair_bone>=0,"Packaged secondary-motion rig missing")
	check(scene.decorative_vents.size()==4,"Packaged four-room ventilation missing")
	check(not scene.hud.sound_enabled and not scene.foley.enabled,"Packaged review must default muted")
	var old_reduced:bool=scene.hud.reduced
	scene.hud.reduced=true
	scene.apply_settings()
	var basin=scene.get_node("Terrace/MineralBasin")
	var river=scene.get_node("Terrace/Landform")
	var clocks=Vector2(basin.water_time,river.water_time)
	for tick in range(8): await tree.process_frame
	check(clocks.is_equal_approx(Vector2(basin.water_time,river.water_time)),"Packaged water reduced-motion clocks drifted")
	for vent in scene.decorative_vents: check(vent.reduced_motion,"Packaged vent ignored reduced motion")
	check(scene.get_node("Operator").model_visual.secondary.angles.length()<0.001,"Packaged hair ignored reduced motion")
	scene.hud.reduced=old_reduced
	scene.apply_settings()
	for kind in ["review","repair","gym","watchkeeper","reviewer","Habitat","Greenhouse"]:
		scene.enter_room(kind)
		for i in range(3): await tree.process_frame
		check(scene.active_room!=null,"Packaged interior missing: "+kind)
		if scene.active_room!=null:
			check(scene.active_room.definition.seamless,"Packaged room must be continuous")
			check(not scene.travel_route(scene.active_building.return_position()).is_empty(),"Packaged exit route missing")
		scene.exit_room()
	for station in scene.get_node("Structures").get_children():
		var player=scene.get_node("Operator")
		player.position=station.return_position()
		player.motion=Vector3.ZERO
		await tree.physics_frame
		await walk(tree,scene,station.room.content.get_node("WalkTarget").global_position,station)
		check(station.cutaway<0.01,"Packaged interior cutaway failed")
		await walk(tree,scene,station.room.to_global(station.room.console_point),station)
		await walk(tree,scene,station.return_position()+Vector3(0,0,3),null)
		for tick in range(60): await tree.physics_frame
		check(station.openness==0 and not station.door_collision.disabled,"Packaged airlock does not close")
		check(scene.commands.payload.is_empty(),"Packaged travel dispatched work")
		print("EXPORTED_JOURNEY ",station.definition.id)
	if failures.is_empty(): print("EXPORTED WORLD PASSED: catalogs, character playback, reduced motion, five physical console/exit journeys and seven direct entry points; development scripts excluded")
	tree.quit(0 if failures.is_empty() else 1)
