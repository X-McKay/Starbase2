extends SceneTree
## Isolated source inspection. No API requests or operational state.
var model: Node3D
var player: AnimationPlayer
var camera: Camera3D
var angle := 0.0
var walking := true
var reduced := false
var elapsed := 0.0
var captured := false

func _initialize() -> void:
	call_deferred("build")

func build() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("182735")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c0d5e5")
	environment.environment.ambient_light_energy = 0.7
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,-30,0)
	light.light_energy = 1.5
	stage.add_child(light)
	var ground := MeshInstance3D.new()
	var plane := CylinderMesh.new()
	plane.top_radius = 2.2
	plane.bottom_radius = 2.2
	plane.height = 0.08
	ground.mesh = plane
	ground.position.y = -0.06
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("405361")
	ground.material_override = material
	stage.add_child(ground)
	model = load("res://assets/characters/cybercat-player/character.glb").instantiate()
	stage.add_child(model)
	player = model.find_children("*", "AnimationPlayer", true, false)[0]
	var clips := player.get_animation_list()
	var clip := ""
	for candidate in clips:
		if candidate != "RESET": clip = candidate
	assert(not clip.is_empty(), "Export must contain a walk animation")
	player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	player.play(clip)
	player.advance(0)
	var bounds := AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	print("SOURCE_BOUNDS ", bounds)
	assert(not first and bounds.size.y > 0.0, "Export must contain a visible character")
	# This skinned mesh's static AABB is in bind space, not posed world space.
	# The imported source has an authored 0.10 m floor offset.
	model.position.y = -0.10
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.5
	stage.add_child(camera)
	update_camera()
	var ui := CanvasLayer.new()
	stage.add_child(ui)
	var panel := VBoxContainer.new()
	panel.position = Vector2(24,24)
	ui.add_child(panel)
	var title := Label.new()
	title.text = "MESHY / BLENDER — CHARACTER STUDY"
	title.add_theme_font_size_override("font_size",24)
	panel.add_child(title)
	var detail := Label.new()
	detail.text = "Reference-based Cybercat · authored rig · textured 3D mesh\nDecorative walk preview; no crew assignment or backend activity."
	panel.add_child(detail)
	for item in [["Walk / idle [Space]", toggle_walk, KEY_SPACE], ["Turn left [Left]", turn_left, KEY_LEFT], ["Turn right [Right]", turn_right, KEY_RIGHT], ["Reduced motion [R]", toggle_reduced, KEY_R]]:
		var button := Button.new()
		button.text = item[0]
		button.pressed.connect(item[1])
		button.shortcut = Shortcut.new()
		var key := InputEventKey.new()
		key.keycode = item[2]
		button.shortcut.events = [key]
		panel.add_child(button)
	print("MESHY_PREVIEW_READY clips=", clips, " bounds=", bounds)
	if "--verify" in OS.get_cmdline_user_args():
		var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		assert(skeleton.get_bone_count() == 24)
		player.seek(0.1,true)
		var pose := skeleton.get_bone_pose_rotation(1)
		player.seek(0.5,true)
		assert(not pose.is_equal_approx(skeleton.get_bone_pose_rotation(1)), "Walk must animate bones")
		toggle_reduced()
		assert(player.speed_scale == 0.0)
		await process_frame
		var key := InputEventKey.new()
		key.keycode = KEY_RIGHT
		key.pressed = true
		Input.parse_input_event(key)
		await process_frame
		assert(is_equal_approx(angle, PI/4), "Right shortcut must rotate the preview")
		print("MESHY_PREVIEW_VERIFIED skeleton, animation, reduced motion")
		quit()

func update_camera() -> void:
	if "--closeup" in OS.get_cmdline_user_args():
		camera.size = 1.0
		camera.position = Vector3(sin(angle)*5,1.6,cos(angle)*5)
		camera.look_at(Vector3(0,1.45,0))
		return
	camera.position = Vector3(sin(angle)*5,2.3,cos(angle)*5)
	camera.look_at(Vector3(0,0.9,0))

func toggle_walk() -> void:
	walking = not walking
	player.speed_scale = 1.0 if walking and not reduced else 0.0
	player.play("walk" if walking and not reduced else "idle")
	player.advance(0)

func toggle_reduced() -> void:
	reduced = not reduced
	player.speed_scale = 1.0 if walking and not reduced else 0.0
	player.play("walk" if walking and not reduced else "idle")
	player.advance(0)

func turn_left() -> void:
	angle -= PI/4
	update_camera()

func turn_right() -> void:
	angle += PI/4
	update_camera()

func _process(delta: float) -> bool:
	elapsed += delta
	if player and elapsed > 2 and not captured and "--capture" in OS.get_cmdline_user_args():
		captured = true
		await RenderingServer.frame_post_draw
		var output := "res://../../evidence/meshy-blender/character.png"
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--capture-path="): output = argument.trim_prefix("--capture-path=")
		root.get_texture().get_image().save_png(output)
		quit()
	return false
