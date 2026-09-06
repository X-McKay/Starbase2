extends SceneTree
const Kit = preload("res://kit_art.gd")
var failures: Array[String] = []
func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var data := Kit.definition()
	var texture: Texture2D = load(data.atlas)
	var pixels := texture.get_image()
	for surface in data.surfaces:
		var material := Kit.material(surface)
		var region: Vector4 = material.get_shader_parameter("region")
		check(region.x>=0 and region.y>=0 and region.z>0 and region.w>0 and region.x+region.z<=1 and region.y+region.w<=1,"Invalid UV region: "+surface)
		check(material==Kit.material(surface),"Material not reused: "+surface)
		# This opaque surface shader deliberately samples RGB only; source alpha
		# is not a sprite cutout contract. Verify useful color content instead.
		var darkest := 1.0
		var brightest := 0.0
		for y in range(ceili(region.y*pixels.get_height()),floori((region.y+region.w)*pixels.get_height())):
			for x in range(ceili(region.x*pixels.get_width()),floori((region.x+region.z)*pixels.get_width())):
				var luminance := pixels.get_pixel(x,y).get_luminance()
				darkest=minf(darkest,luminance)
				brightest=maxf(brightest,luminance)
		check(brightest-darkest>0.1,"Missing artwork in surface: "+surface)
	var module := preload("res://scenes/kit/module.tscn").instantiate()
	root.add_child(module)
	await process_frame
	check(module.built.find_children("*","StaticBody3D",true,false).size()==1,"Wall needs one independent collision body")
	module.kind="console"
	module.solid=false
	await process_frame
	await process_frame
	check(module.get_child_count()==1,"Editor rebuild accumulated module children")
	check(module.built.find_children("*","StaticBody3D",true,false).is_empty(),"Decorative variant still blocks movement")
	module.queue_free()
	var room := preload("res://scenes/kit/showroom.tscn").instantiate()
	root.add_child(room)
	await process_frame
	check(room.interior.visible and not room.exterior.visible,"Showroom must start in interior")
	for key in [KEY_2,KEY_C,KEY_L,KEY_R]:
		var event := InputEventKey.new()
		event.physical_keycode=key
		event.pressed=true
		room._unhandled_key_input(event)
	check(room.exterior.visible and not room.interior.visible,"Keyboard exterior switch failed")
	check(room.alternate_camera and room.work_light,"Camera or lighting keyboard control failed")
	check(not room.exterior.get_node("Roof").visible,"Roof cutaway control failed")
	check(room.heading.text.contains("EXTERIOR"),"Visible scene and label disagree")
	room.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Art kit checks passed: atlas regions, shared materials, collision separation, editor rebuild, keyboard scene/camera/light/roof")
	quit(0 if failures.is_empty() else 1)
