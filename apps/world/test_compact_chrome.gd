extends SceneTree
var failures:Array[String]=[]
var capture_directory:=""
func check(value:bool,message:String) -> void:
	if not value:failures.append(message)
func readable(button:Button) -> bool:
	var font:Font=button.get_theme_font("font")
	for line in button.text.split("\n"):
		if font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x>button.size.x-button.get_theme_stylebox("normal").get_minimum_size().x:return false
	return true
func _initialize() -> void:run.call_deferred()
func picture(name:String) -> void:
	for frame in 4:await process_frame
	if capture_directory.is_empty():return
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(capture_directory.path_join(name+".png"))
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):capture_directory=arg.trim_prefix("--capture=")
	if not capture_directory.is_empty():DirAccess.make_dir_recursive_absolute(capture_directory)
	root.size=Vector2i(800,640);root.content_scale_size=root.size
	var hud=load("res://hud.gd").new();hud.board_fixture="__empty_visual_fixture__";root.add_child(hud);await process_frame
	hud.connection.text="VISUAL TEST FIXTURE · not live operational activity";hud.set_location("PIONEER HABITAT")
	hud.crew_strip.project("repair",{"unknown":true,"run_id":"last-known-fixture"})
	hud.crew_strip.project("review",{"unknown":false,"backend_state":"failed"})
	hud.crew_strip.project("gym",{"unknown":false,"evidence_ready":true})
	for kind in ["watchkeeper","reviewer"]:hud.crew_strip.project(kind,{"unknown":false})
	for large in [true,false]:
		hud.large_text=large;hud.scale_text();hud.sync_world_chrome()
		await picture("compact-large" if large else "compact-normal")
		check(hud.header_panel.get_global_rect().end.y+4<=hud.navigation_bar.get_global_rect().position.y,"Compact navigation is below the complete header with spacing")
		check(hud.crew_strip.get_global_rect().end.y<=root.size.y-15,"Crew strip retains its bottom safe margin")
		check(hud.navigation_background.visible and hud.navigation_background.get_global_rect().encloses(hud.navigation_bar.get_global_rect()),"Compact navigation retains a readable background over bright scenery")
		check(readable(hud.chrome_toggle),"HUD toggle is completely readable")
		for entry in hud.crew_strip.entries.values():check(readable(entry),"Complete compact crew name/status: "+entry.text)
		hud.crew_strip.entries.repair.grab_focus();await process_frame
		var detail=hud.crew_strip.get("status_detail")
		check(detail!=null and detail.text.contains("Last known · offline"),"Keyboard focus exposes exact full offline status")
		await picture("focused-status-large" if large else "focused-status-normal")
		hud.open_room_details("PIONEER HABITAT","Decorative room guide · no operational outcome implied.")
		await picture("guide-large" if large else "guide-normal")
		check(hud.navigation_bar.get_global_rect().end.y+4<=hud.room_details.get_global_rect().position.y,"Compact guide starts below navigation")
		hud.close_panels()
	hud.queue_free();await process_frame
	for failure in failures:push_error(failure)
	if failures.is_empty():print("COMPACT_CHROME_PASSED: separated header/navigation/guide, complete HUD toggle and crew labels, keyboard full status")
	quit(0 if failures.is_empty() else 1)
