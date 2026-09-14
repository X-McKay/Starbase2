extends SceneTree
## Native shader comparison with fixed framing. No domain state or collision edits.
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--water-output="): output=arg.trim_prefix("--water-output=")
	root.size=Vector2i(900,600)
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("8a765e")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("bed4df")
	settings.ambient_light_energy=0.65
	environment.environment=settings
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-55,-30,0)
	light.light_energy=1.1
	scene.add_child(light)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=15
	camera.position=Vector3(9,14,13)
	scene.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current=true
	var pool=preload("res://mineral_basin.gd").new()
	scene.add_child(pool)
	pool.reduced_motion=true
	for view in ["spring","ocean"]:
		var material: ShaderMaterial=pool.water
		if view=="ocean":
			pool.visible=false
			var sea := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size=Vector2(28,22)
			sea.mesh=plane
			material=ShaderMaterial.new()
			material.shader=preload("res://canyon.gdshader")
			material.set_shader_parameter("sea_stacks",PackedVector4Array([Vector4(-5,0,2,1.5),Vector4(5,-3,1.7,2),Vector4(-7,8,1,1),Vector4(7,7,1,1)]))
			sea.material_override=material
			scene.add_child(sea)
			camera.size=29
		var frames: Array[Image]=[]
		for phase in [0.0,5.0,5.0]:
			material.set_shader_parameter("water_time",phase)
			for i in range(3): await process_frame
			await RenderingServer.frame_post_draw
			var frame := root.get_texture().get_image()
			frame.convert(Image.FORMAT_RGB8)
			frames.append(frame)
		if frames[0].get_data()==frames[1].get_data(): failures.append(view+" phase change did not affect actual rendering")
		if frames[1].get_data()!=frames[2].get_data(): failures.append(view+" frozen phase still changed actual rendering")
		if output!="":
			DirAccess.make_dir_recursive_absolute(output)
			frames[0].save_png(output+"/"+view+"-phase0.png")
			frames[1].save_png(output+"/"+view+"-phase5.png")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Water presentation passed: actual spring/ocean phase changes and deterministic frozen frames")
	quit(0 if failures.is_empty() else 1)
