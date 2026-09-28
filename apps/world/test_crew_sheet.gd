extends SceneTree
const SheetData=preload("res://crew_sheet_projection.gd")
var failures:Array[String]=[]
var capture_directory:=""
func check(value:bool, message:String) -> void:
	if not value: failures.append(message)
func picture(name:String) -> void:
	# Settle deferred container/scroll layout in both headless and capture modes.
	for frame in 4: await process_frame
	if capture_directory.is_empty(): return
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(capture_directory.path_join(name+".png"))==OK,"Capture saved: "+name)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): capture_directory=arg.trim_prefix("--capture=")
	if not capture_directory.is_empty(): DirAccess.make_dir_recursive_absolute(capture_directory)
	var snapshot:Dictionary={
		"observed_at":1790500000,"worker":{"available":true},
		"progression":{"id":"mender","level":2,"xp":50,"authority":"Disposable synthetic solution.py only; no production effects", "qualifications":[{"build":"sha256:historical-build-with-qualification","scenario":"clamp-v1","run_id":"fixture-historical-run"}]},
		"builds":[{"digest":"sha256:replacement-build-without-qualification", "manifest":{"agent":"mender","profile":"mender-v1","skills":["repair"]}}]
	}
	var original:=snapshot.duplicate(true)
	var sheet:=SheetData.project(snapshot,"mender")
	check(sheet.level=="Level 2 · 50 lifetime XP","Exact identity retains lifetime Level and XP")
	check(sheet.current.contains("not reported") and sheet.current.contains("unassessed"),"Registry or history cannot invent current-build qualification")
	check(sheet.history.contains("historical-build-with-qualification") and sheet.history.contains("fixture-historical-run"),"Historical build and run remain attributable")
	check(not sheet.history.contains("replacement-build") and sheet.equipment.contains("replacement-build"),"Replacement registry and historical qualification stay separate")
	check(sheet.class.contains("not reported"),"Role does not silently assign a permanent Class")
	check(sheet.skills.contains("Rank unassessed") and sheet.skills.contains("registered build"),"Installed manifest entry does not invent proficiency")
	check(SheetData.project(snapshot,"surveyor").level.contains("not reported"),"Mender progression does not leak to another crew member")
	check(SheetData.project(snapshot,"mender",true).freshness.contains("last-known"),"Disconnect preserves explicit historical status")
	check(SheetData.project({},"mender").freshness.contains("not reported"),"Missing observation never appears fresh")
	var malformed:=snapshot.duplicate(true)
	malformed.progression={"id":"other","level":20,"xp":99999}
	check(SheetData.project(malformed,"mender").level.contains("not reported"),"Wrong persistent identity cannot transfer XP")
	check(snapshot==original,"SheetData leaves authoritative input unchanged")
	var hud=load("res://hud.gd").new()
	hud.board_fixture="__empty_visual_fixture__"
	root.add_child(hud)
	await process_frame
	hud.connection.text="Preview fixture · synthetic records · no work is dispatched"
	hud.operations.fixture="__empty_visual_fixture__"
	hud.operations.snapshot=snapshot
	hud.operations.offline=false
	hud.open_place("repair")
	check(hud.dossier_tabs.get_tab_title(3)=="Crew sheet","Crew sheet is a named keyboard tab")
	hud.dossier_tabs.current_tab=3
	var page:ScrollContainer=hud.dossier_tabs.get_child(3)
	check(hud.crew_sheet.stat_grid.get_child_count()==8,"All eight core stats have visible cards")
	check(hud.crew_sheet.fields.freshness.text.contains("VISUAL FIXTURE"),"Fixture provenance visible in sheet")
	for size in [Vector2i(1280,800),Vector2i(800,640)]:
		root.size=size; root.content_scale_size=size
		hud.large_text=size.x<1000; hud.scale_text()
		page.scroll_vertical=0
		for frame in 4: await process_frame
		check(page.get_h_scroll_bar().max_value<=page.size.x,"No horizontal content loss at "+str(size))
		check(hud.dock.get_global_rect().end.y<=size.y,"Close and tabs remain in viewport")
		await picture("sheet-%d-top" % size.x)
		page.scroll_vertical=530
		await picture("sheet-%d-stats" % size.x)
		# The prior screenshot scroll can move the already-focused first card offscreen.
		# Release that focus so every iteration represents a new keyboard focus event.
		root.gui_release_focus()
		for card in hud.crew_sheet.stat_grid.get_children():
			card.grab_focus()
			for frame in 3: await process_frame
			check(page.get_global_rect().encloses(card.get_global_rect()),"Every stat is reachable within keyboard scroll: %s %s page %s card %s" % [str(size),card.get_child(0).get_child(0).text,str(page.get_global_rect()),str(card.get_global_rect())])
		await picture("sheet-%d-cooperation" % size.x)
		page.scroll_vertical=int(hud.crew_sheet.fields.equipment.position.y)-80
		await picture("sheet-%d-equipment" % size.x)
		hud.crew_sheet.evidence_button.grab_focus()
		for frame in 4: await process_frame
		check(page.get_global_rect().intersects(hud.crew_sheet.evidence_button.get_global_rect()),"Keyboard focus scrolls to evidence action")
		await picture("sheet-%d-history" % size.x)
		var event:=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=true;root.push_input(event)
		await process_frame
		event=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=false;root.push_input(event)
		await process_frame
		check(hud.dossier_tabs.current_tab==1,"Keyboard evidence action reaches existing records without dispatch")
		hud.dossier_tabs.current_tab=3
	hud.operations.offline=true;hud.update_crew_guide();page.scroll_vertical=0
	await picture("sheet-disconnected")
	check(hud.crew_sheet.fields.freshness.text.contains("Disconnected"),"Disconnected ledger remains last-known")
	hud.open_place("watchkeeper");hud.dossier_tabs.current_tab=3
	check(hud.crew_sheet.fields.level.text.contains("not reported"),"Crew switch clears another crew's ledger")
	await picture("sheet-unassessed-watchkeeper")
	hud.close_panels();check(not hud.dock.visible,"Close restores world access")
	hud.queue_free();await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CREW_SHEET_PASSED: exact-identity ledger, eight unassessed stats, build/history distinction, fixture/disconnect, compact keyboard navigation")
	quit(0 if failures.is_empty() else 1)
