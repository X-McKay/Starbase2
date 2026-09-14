extends SceneTree
## Native workspace navigation and truthful dossier metadata, independent of providers.
var failures:Array[String]=[]
var capture_directory:=""
func capture(name:String) -> void:
	if capture_directory.is_empty(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_directory.path_join(name+".png"))
func check(value:bool,message:String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): capture_directory=arg.trim_prefix("--capture=")
	if not capture_directory.is_empty(): DirAccess.make_dir_recursive_absolute(capture_directory)
	var hud=load("res://hud.gd").new()
	hud.board_fixture="__empty_visual_fixture__"
	root.add_child(hud)
	await process_frame
	await process_frame
	check(hud.nav_buttons.field.tooltip_text.contains("B"),"Field operations keyboard route is discoverable")
	hud.nav_buttons.field.pressed.emit()
	check(hud.board.visible and not hud.crew_strip.visible,"Field operations opens native workspace with unobstructed chrome")
	hud.nav_buttons.work.pressed.emit()
	check(hud.operations.visible and not hud.board.visible,"Work replaces Field ops as one active workspace")
	hud.nav_buttons.settings.pressed.emit()
	check(hud.help.visible and not hud.operations.visible,"Settings replaces Work")
	check(hud.nav_buttons.connection.tooltip_text.contains("O"),"Connection is reachable directly from navigation")
	check(hud.settings_tabs.get_tab_count()==4,"Display, Audio, Controls and Character grouped tabs are available")
	check(hud.settings_buttons[hud.settings_tabs.current_tab].has_focus(),"Settings keyboard focus starts at tab navigation")
	hud.open_place("review")
	check(hud.portrait.crew_kind=="review","Portrait receives Surveyor identity")
	var surveyor_model_id:int=hud.portrait.model.get_instance_id()
	check(hud.dossier_tabs.is_tab_hidden(2),"Synthetic repair practice is not offered for other crew")
	check(not hud.progression.visible,"No invented progression for other crew")
	hud.open_place("repair")
	check(hud.portrait.crew_kind=="repair" and hud.portrait.model.get_instance_id()!=surveyor_model_id,"Changing crew replaces the actual character portrait")
	check(hud.portrait.viewport.render_target_update_mode!=SubViewport.UPDATE_ALWAYS,"Visible portrait does not render continuously")
	check(not hud.dossier_tabs.is_tab_hidden(2),"Mender practice has a dedicated reachable tab")
	check(hud.evidence.get_parent().get_parent().name=="Evidence","Evidence has its own scrollable workspace")
	var records:Array=[{"input":{"id":"review-readable","kind":"repair","target":"synthetic-clamp"},"state":"failed","updated_at":1760000000,"build":{"id":"build-immutable-123"}}]
	hud.update_list(records)
	hud.status.text="Failed · synthetic fixture"
	hud.details.text="This isolated UI test has no production connection."
	check(hud.record_metadata.text.contains("build-immutable-123") and hud.record_metadata.text.contains("synthetic-clamp"),"Dossier includes exact retained build and target")
	check(hud.record_metadata.text.contains("UTC"),"Recorded update has explicit UTC timestamp")
	await process_frame
	await capture("dossier")
	check(hud.crew_record_labels.repair.text.contains("synthetic-clamp") and hud.crew_record_labels.repair.text.contains("Failed"),"Directory rows show retained target and state")
	hud.toggle_directory()
	await process_frame
	await capture("crew-places")
	check(hud.building_search.is_visible_in_tree(),"Building search remains above directory scroll areas")
	hud.building_search.text="Habitat"
	hud.filter_buildings("Habitat")
	check(hud.directory_tabs.current_tab==1,"Building search reveals Places without a separate navigation action")
	hud.close_panels()
	hud.update_list([])
	check(hud.record_metadata.text.contains("None retained") and hud.record_metadata.text.contains("Not reported"),"Absent identity metadata is explicit rather than invented")
	for size in [Vector2i(1280,800),Vector2i(800,640)]:
		root.content_scale_size=size
		root.size=size
		hud.large_text=true; hud.scale_text()
		check(hud.navigation_bar.vertical==(size.x>=1000),"Navigation uses a wide left rail and compact horizontal bar")
		hud.open_place("repair")
		await process_frame
		check(hud.portrait.viewport.render_target_update_mode!=SubViewport.UPDATE_ALWAYS,"Visible portrait uses bounded refresh")
		if size.x<1000:
			check(hud.portrait.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Compact hidden portrait does not render")
		hud.toggle_settings()
		await process_frame
		check(hud.portrait.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Closing dossier disables its portrait viewport")
		await process_frame
		for item in hud.navigation_bar.get_children():
			var font:Font=item.get_theme_font("font")
			var required:float=font.get_string_size(item.text,HORIZONTAL_ALIGNMENT_LEFT,-1,item.get_theme_font_size("font_size")).x+item.get_theme_stylebox("normal").get_minimum_size().x
			if item.icon!=null: required+=minf(20,item.icon.get_width())+item.get_theme_constant("h_separation")
			check(required<=item.size.x,"Navigation does not truncate: "+item.text)
			check(Rect2(Vector2.ZERO,Vector2(size)).encloses(item.get_global_rect()),"Navigation stays within viewport: "+item.text)
		for index in range(4):
			hud.settings_tabs.current_tab=index
			await process_frame
			check(hud.help.get_global_rect().end.y<=size.y,"Settings bottom and close remain in bounds")
			var page:ScrollContainer=hud.settings_tabs.get_child(index)
			check(page.get_h_scroll_bar().max_value<=page.size.x,"Settings has no hidden horizontal content")
			await capture("settings-%s-%d" % [str(size.x),index])
		hud.close_panels()
		check(hud.crew_strip.visible and hud.prompt_panel.visible,"Close restores world controls")
	hud.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CONSOLE_HUD_PASSED: truthful dossier, native navigation, grouped settings, compact and large text")
	quit(0 if failures.is_empty() else 1)
