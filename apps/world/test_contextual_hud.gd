extends SceneTree
## Public HUD controls remain available while permanent chrome becomes smaller.
var failures:Array[String]=[]
func check(value:bool,message:String) -> void:
	if not value: failures.append(message)
func readable(button:Button) -> bool:
	var font:Font=button.get_theme_font("font")
	var width:float=font.get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
	return width<=button.size.x-button.get_theme_stylebox("normal").get_minimum_size().x
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var hud=load("res://hud.gd").new()
	hud.board_fixture="__empty_visual_fixture__"
	root.add_child(hud)
	await process_frame
	await process_frame
	check(not hud.roster.is_visible_in_tree(),"Crew summary is absent from permanent world chrome")
	check(hud.prompt_panel.size.y<70,"Default context strip remains compact")
	hud.roster.text="Surveyor: Stale · no fresh evidence"
	hud.set_crew_summary(true)
	check(not hud.roster.is_visible_in_tree(),"Enabling summary cannot overlay the closed directory")
	hud.toggle_directory()
	await process_frame
	check(hud.roster.is_visible_in_tree(),"Directory exposes requested crew summary")
	check(hud.roster.text.contains("Stale"),"Context layout preserves authoritative roster text")
	check(hud.directory.find_children("*","Button",true,false)[0].has_focus(),"Directory retains first-command keyboard focus")
	hud.summary_toggles[1].toggled.emit(false)
	check(not hud.roster.visible and not hud.summary_toggles[0].button_pressed,"Both summary controls share the same preference")
	hud.set_location("SURVEY COMMAND")
	check(hud.location.text=="SURVEY COMMAND","World can supply exact current location")
	var zooms:Array[int]=[]
	hud.zoom_requested.connect(func(direction:int): zooms.append(direction))
	for name in ["ZoomIn","ZoomOut"]:
		hud.root.find_child(name,true,false).pressed.emit()
	check(zooms==[-1,1],"Named zoom controls preserve existing signal contract")
	for size in [Vector2i(1280,800),Vector2i(800,640)]:
		root.content_scale_size=size
		root.size=size
		hud.large_text=true
		hud.scale_text()
		hud.open_place("repair")
		await process_frame
		await process_frame
		for item in hud.navigation_bar.get_children():
			check(readable(item),"Navigation label must fit without clipping: "+item.text)
		hud.open_room_details("BOTANICAL HOUSE","Cultivation and water systems. This room guide describes scenery; it does not imply an operational result.")
		for panel in [hud.dock,hud.help,hud.room_details]:
			panel.show()
			await process_frame
			var bounds:Rect2=panel.get_global_rect()
			print("HUD_BOUNDS ",size," ",panel.name," ",bounds)
			check(bounds.position.x>=0 and bounds.end.x<=size.x,"Large-text panels remain inside viewport")
			check(bounds.position.y>=0 and bounds.end.y<=size.y,"Scrollable panels remain vertically reachable")
			panel.hide()
		hud.close_panels()
		hud.board.open()
		await process_frame
		await process_frame
		var workspace:Rect2=hud.board.workspace_rect()
		var dismiss:Button=hud.board.find_children("*","Button",true,false)[0]
		check(readable(dismiss) and dismiss.tooltip_text.contains("Esc"),"Close remains fully readable with keyboard shortcut available")
		check(workspace.position.x>=0 and workspace.end.x<=size.x and workspace.end.y<=size.y,"Command workspace remains inside canvas")
		check(hud.board.is_docked==(size.x>=1000),"Command workspace chooses docked or full available width")
		if size.x>=1000:
			check(workspace.position.x>=184 and workspace.end.x<=size.x-22,"Wide Command workspace leaves the navigation rail accessible")
		else:
			check(workspace.size.x>=size.x-44,"Narrow Command view uses the available width")
		hud.close_panels()
	hud.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CONTEXTUAL_HUD_PASSED: compact chrome, truthful optional roster, location, zoom signals, keyboard focus and responsive large text")
	quit(0 if failures.is_empty() else 1)
