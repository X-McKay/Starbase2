extends RefCounted
## Explicit offline self-check inside the exported executable/PCK.
## Explicit failures: assertions can be compiled out of release builds.
var failures:Array[String]=[]
func check(condition:bool, message:String) -> void:
	if not condition: failures.append(message); push_error(message)

func run(tree:SceneTree, scene:Node) -> void:
	check(not ResourceLoader.exists("res://test_state.gd"),"Development tests leaked into release")
	check(not ResourceLoader.exists("res://characters/illustrated_import.gd"),"Art importer leaked into release")
	check(FileAccess.file_exists("res://characters/catalog.json"),"Missing character catalog")
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
	check(scene.get_node("Operator").character_definition.id=="operator","Wrong production character")
	for kind in ["review","repair","gym","watchkeeper","reviewer","Habitat","Greenhouse"]:
		scene.enter_room(kind)
		for i in range(3): await tree.process_frame
		check(scene.active_room!=null,"Packaged interior missing: "+kind)
		if scene.active_room!=null:
			check(scene.active_room.definition.seamless,"Packaged room must be continuous")
			check(not scene.travel_route(scene.active_building.return_position()).is_empty(),"Packaged exit route missing")
		scene.exit_room()
	if failures.is_empty(): print("EXPORTED WORLD PASSED: catalogs, four-direction playback, reduced motion, colony, five continuous interiors and seven room entry points; development scripts excluded")
	tree.quit(0 if failures.is_empty() else 1)
