extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene=load("res://characters/showroom.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	assert(scene.actors.size()==2 and not scene.foley.enabled)
	assert(scene.actors[0].sprite.offset.y>0,"Foot pivot raises artwork above the ground")
	scene.toggle_light(); scene.wall_test()
	await process_frame
	assert(scene.walking and not scene.dark)
	scene.reset()
	assert(not scene.walking)
	print("Character showroom controls, default mute, and sprite anchoring passed")
	quit()
