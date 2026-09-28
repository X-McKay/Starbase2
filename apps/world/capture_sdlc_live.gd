extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1280,800); root.content_scale_size=Vector2i(1280,800)
	var board=preload("res://command_board.gd").new(); root.add_child(board)
	board.open(); board.tabs.current_tab=5
	var panel=board.sdlc_missions
	panel.poll()
	var deadline:=Time.get_ticks_msec()+15000
	while not panel.online and Time.get_ticks_msec()<deadline: await process_frame
	assert(panel.online,"Live V7 snapshot required")
	for _frame in 8: await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://../../evidence/world/sdlc-missions-20260928/live-overview.png")
	var scroll=board.tabs.get_child(5)
	scroll.scroll_vertical=500
	for _frame in 4: await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://../../evidence/world/sdlc-missions-20260928/live-evidence.png")
	for heading in panel.content.find_children("*","Label",true,false):
		if heading.text=="EXTERNAL VERIFICATION":
			scroll.scroll_vertical+=int(heading.global_position.y-scroll.global_position.y)-12
			for _frame in 6: await process_frame
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("res://../../evidence/world/sdlc-missions-20260928/live-verification.png")
			break
	var links=panel.content.find_children("*","LinkButton",true,false)
	if not links.is_empty():
		scroll.ensure_control_visible(links[0])
		for _frame in 8: await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("res://../../evidence/world/sdlc-missions-20260928/live-publication.png")
	print("Live SDLC native capture: "+str(panel.snapshot.missions.size())+" missions; selected state "+str(panel.mission_record().get("state"))+"; fixture="+str(panel.fixture)+"; command phase="+str(panel.commands.phase))
	board.queue_free(); await process_frame; quit()
