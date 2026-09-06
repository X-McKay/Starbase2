extends Node3D
## Native art pilot only. No core connection or operational commands.
const Crew = preload("res://crew_art.gd")
var camera := Camera3D.new()
var sun := DirectionalLight3D.new()
var interior: Node3D
var exterior: Node3D
var heading: Label
var note: Label
var interior_view := true
var alternate_camera := false
var work_light := false
var capture_path := ""
var frame := 0
var times: Array[float] = []
var last_frame_usec := 0
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): capture_path=arg.trim_prefix("--capture=")
		if arg=="--exterior": interior_view=false
		if arg=="--work-light": work_light=true
		if arg=="--alternate-camera": alternate_camera=true
	interior=preload("res://scenes/kit/workshop_interior.tscn").instantiate()
	exterior=preload("res://scenes/kit/workshop_exterior.tscn").instantiate()
	add_child(interior)
	add_child(exterior)
	for pair in [["operator",Vector3(1.4,0,2.8)],["mender",Vector3(-1.5,0,-1.4)]]:
		var sprite := Sprite3D.new()
		sprite.texture=Crew.pose(pair[0])
		sprite.pixel_size=2.8/sprite.texture.get_height()
		sprite.position=pair[1]+Vector3(0,1.36,0)
		sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.alpha_cut=SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.shaded=true
		interior.add_child(sprite)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=15.8
	add_child(camera)
	camera.current=true
	sun.rotation_degrees=Vector3(-55,-25,0)
	sun.shadow_enabled=true
	add_child(sun)
	var world_environment := WorldEnvironment.new()
	world_environment.environment=Environment.new()
	world_environment.environment.background_mode=Environment.BG_COLOR
	world_environment.environment.background_color=Color("0d1828")
	world_environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	world_environment.environment.ambient_light_color=Color("aec5d0")
	world_environment.environment.ambient_light_energy=0.5
	add_child(world_environment)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(ui)
	heading=label(ui,"",Vector2(28,24),26)
	note=label(ui,"",Vector2(28,62),15)
	var buttons := HBoxContainer.new()
	buttons.position=Vector2(28,105)
	ui.add_child(buttons)
	for item in [["1  Interior",func(): interior_view=true; update_view()],["2  Exterior",func(): interior_view=false; update_view()],["C  Camera",func(): alternate_camera=not alternate_camera; update_view()],["L  Lighting",func(): work_light=not work_light; update_view()],["R  Roof",func(): exterior.get_node("Roof").visible=not exterior.get_node("Roof").visible]]:
		var button := Button.new()
		button.text=item[0]
		button.custom_minimum_size=Vector2(130,36)
		button.pressed.connect(item[1])
		buttons.add_child(button)
	var footer := label(ui,"ART PILOT · Shared PNG kit on geometry · Decorative consoles · No live agent activity",Vector2(28,754),15)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	footer.offset_top=-45
	footer.offset_left=28
	update_view()
func label(parent: Node,value: String,pos: Vector2,size: int) -> Label:
	var node := Label.new()
	node.text=value
	node.position=pos
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",Color("d7e5e0"))
	parent.add_child(node)
	return node
func update_view() -> void:
	interior.visible=interior_view
	exterior.visible=not interior_view
	heading.text="ASTER KIT / "+("WORKSHOP INTERIOR" if interior_view else "FIELD LAB EXTERIOR")
	note.text="Same atlas, reusable scene modules. " + ("Cool work light." if work_light else "Neutral daylight.")
	camera.position=Vector3(-9 if alternate_camera else 8,14,18)
	camera.look_at(Vector3(0,2.0,0))
	sun.light_color=Color("8dc8e1") if work_light else Color("fff0d5")
	sun.light_energy=0.45 if work_light else 0.95
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_1: interior_view=true
		KEY_2: interior_view=false
		KEY_C: alternate_camera=not alternate_camera
		KEY_L: work_light=not work_light
		KEY_R: exterior.get_node("Roof").visible=not exterior.get_node("Roof").visible
	update_view()
func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	frame+=1
	if frame>30 and last_frame_usec>0: times.append((now-last_frame_usec)/1000.0)
	last_frame_usec=now
	if frame==180 and capture_path!="":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture_path)
		times.sort()
		var file := FileAccess.open(capture_path+".json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"art_pilot":true,"live_activity":false,"interior":interior_view,"work_light":work_light,"alternate_camera":alternate_camera,"frames":times.size(),"sampling":"monotonic process-frame intervals; capped at 60 FPS; not GPU render time","viewport":str(get_viewport().get_visible_rect().size),"median_ms":times[times.size()/2],"p95_ms":times[int(times.size()*0.95)],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)},"  "))
		get_tree().quit()
