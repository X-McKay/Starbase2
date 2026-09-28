extends SceneTree
## Native camera-pan diagnostic in the real fixture world; no backend effects.
var output:=""
var zoom_path:=false
var production_only:=false
func _initialize() -> void:run.call_deferred()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg=="--zoom-path":zoom_path=true
		if arg=="--production-only":production_only=true
	assert(not output.is_empty() and DisplayServer.get_name()!="headless")
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(120).timeout.connect(func():push_error("SHADOW_CAPTURE_TIMEOUT");quit(1))
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json";world.board_fixture="__empty_visual_fixture__";world.player_preferences_path=""
	root.add_child(world);world.isolate_capture_input()
	await process_frame;await physics_frame
	world.hud.reduced=true;world.apply_settings();world.hud.root.hide()
	for frame in range(6):await process_frame
	world.process_mode=Node.PROCESS_MODE_DISABLED
	var sun:DirectionalLight3D
	for child in world.get_children():
		if child is DirectionalLight3D:sun=child;break
	var camera:Camera3D=world.camera
	var original={"far":camera.far,"mode":sun.directional_shadow_mode,"max_distance":sun.directional_shadow_max_distance,"bias":sun.shadow_bias,"normal_bias":sun.shadow_normal_bias,"atlas":ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"),"filter":ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality")}
	var variants=[{"id":"baseline","mode":2,"far":4000.0},{"id":"single-map","mode":0,"far":4000.0},{"id":"bounded-cascade","mode":2,"far":160.0},{"id":"bounded-single","mode":0,"far":160.0},{"id":"single-far240","mode":0,"far":240.0}]
	if zoom_path:variants=[{"id":"baseline-zoom","mode":2,"far":4000.0},{"id":"bounded-zoom","mode":0,"far":-1.0}]
	if production_only:variants=[{"id":"production-zoom" if zoom_path else "production-pan","mode":sun.directional_shadow_mode,"far":-1.0}]
	var report={"fixture":true,"original":original,"variants":[],"renderer":RenderingServer.get_video_adapter_name(),"limits":"World frozen for shadow isolation; moving real native orthographic camera. Ground point luminance includes image resampling/material effects, not GPU timing."}
	for variant in variants:
		sun.directional_shadow_mode=variant.mode;camera.far=maxf(variant.far,160.0);camera.size=world.zoom
		DirAccess.make_dir_recursive_absolute(output.path_join(variant.id))
		var frames:Array=[]
		for frame in range(24):
			var focus:=Vector3(2.0+float(frame)*.075,0,-19.0)
			if zoom_path:camera.size=18.0+float(frame)*.6
			camera.position=focus+Vector3(10,36,46);camera.look_at(focus)
			if variant.far<0:camera.far=preload("res://shadow_quality.gd").depth_for_view(camera.size,Vector3(10,36,46))
			await process_frame;RenderingServer.force_draw(false)
			var picture:=root.get_texture().get_image()
			assert(picture.save_png(output.path_join(variant.id).path_join("%02d.png"%frame))==OK)
			var values:Array=[]
			for z in range(32):
				for x in range(40):
					var p:=camera.unproject_position(Vector3(8.0+float(x)*.22,.10,-25.0+float(z)*.22))
					if p.x<1 or p.y<1 or p.x>=picture.get_width()-1 or p.y>=picture.get_height()-1:values.append(-1.0);continue
					var ix:=floori(p.x);var iy:=floori(p.y);var t:=p-Vector2(ix,iy)
					var color:Color=picture.get_pixel(ix,iy).lerp(picture.get_pixel(ix+1,iy),t.x).lerp(picture.get_pixel(ix,iy+1).lerp(picture.get_pixel(ix+1,iy+1),t.x),t.y)
					values.append(color.get_luminance())
			frames.append({"camera":str(camera.position),"size":camera.size,"far":camera.far,"samples":values})
		report.variants.append({"settings":variant,"frames":frames})
	if production_only:
		camera.size=284.0;camera.position=Vector3(10,32,46);camera.look_at(Vector3(0,-4,0))
		for distance in [4000.0,preload("res://shadow_quality.gd").depth_for_view(camera.size,Vector3(10,36,46))]:
			camera.far=distance;await process_frame;RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png(output.path_join("map-max-reference.png" if distance==4000.0 else "map-max-bounded.png"))
		world.process_mode=Node.PROCESS_MODE_INHERIT;world.enter_room("habitat");world.hud.close_panels();world.hud.root.hide()
		for frame in range(12):await process_frame
		RenderingServer.force_draw(false);root.get_texture().get_image().save_png(output.path_join("habitat-final.png"))
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report))
	assert(world.commands.payload.is_empty());print("SHADOW_STABILITY_CAPTURE_PASSED");quit()
