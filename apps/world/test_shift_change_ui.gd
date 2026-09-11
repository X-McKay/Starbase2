extends SceneTree
var failures:Array[String]=[]
func check(value:bool,message:String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var hud=preload("res://hud.gd").new()
	hud.board_fixture="__empty_visual_fixture__"
	root.add_child(hud)
	await process_frame
	await process_frame
	var strip=hud.crew_strip
	var base:Dictionary={"unknown":false,"active_count":0,"backend_state":"unknown","label":"No recorded work","duty_label":"Duty paused"}
	strip.project("watchkeeper",base,"Taking a break")
	check(strip.entries.watchkeeper.text.contains("Taking a break"),"Local domestic activity remains visible without claiming work")
	var offline:Dictionary=base.duplicate(); offline.unknown=true
	strip.project("watchkeeper",offline,"Taking a break")
	check(not strip.entries.watchkeeper.text.contains("Taking a break"),"Unknown backend state suppresses confident activity caption")
	var active:Dictionary=base.duplicate(); active.active_count=1; active.backend_state="cancel_requested"
	strip.project("watchkeeper",active)
	check(strip.entries.watchkeeper.text.contains("Cancel pending"),"Cancellation is distinct from working")
	var cancelled:Dictionary=base.duplicate(); cancelled.backend_state="cancelled"
	strip.project("watchkeeper",cancelled,"Taking a break")
	check(strip.entries.watchkeeper.text.contains("Cancelled"),"Completed cancellation stays distinct from local activity")
	strip.project("watchkeeper",base,"At home",true)
	check(strip.entries.watchkeeper.text.contains("route blocked"),"A blocked return is visible even without active work")
	var selected:Array=[]
	hud.place_selected.connect(func(kind):selected.append(kind))
	strip.entries.watchkeeper.pressed.emit()
	check(hud.dock.visible and hud.filter_kind=="watchkeeper" and selected==["watchkeeper"],"Crew strip uses the same native inspector from anywhere")
	var watch:Array=[]
	hud.watch_requested.connect(func(kind):watch.append(kind))
	for button in hud.dock.find_children("*","Button",true,false):
		if button.text=="Watch this crew member": button.pressed.emit()
	check(watch==["watchkeeper"],"Watching is an explicit action, separate from selecting a record")
	hud.open_board()
	await process_frame
	check(not strip.is_visible_in_tree() and not hud.prompt.is_visible_in_tree(),"Expanded command records hide world chrome")
	hud.close_panels()
	await process_frame
	check(strip.is_visible_in_tree() and hud.prompt.is_visible_in_tree(),"Closing records restores the world controls")
	hud.open_place("watchkeeper")
	for size in [Vector2i(1280,800),Vector2i(800,640)]:
		root.size=size; root.content_scale_size=size
		hud.large_text=true; hud.scale_text()
		await process_frame
		await process_frame
		print("SHIFT_STRIP_BOUNDS ",size," ",strip.get_global_rect()," viewport ",root.get_visible_rect())
		check(root.get_visible_rect().encloses(strip.get_global_rect()),"Crew strip fits native and compact viewport")
		check(strip.get_global_rect().position.y>=hud.dock.get_global_rect().end.y,"Inspector and crew strip do not cover one another")
		for kind in strip.entries:
			check(strip.entries[kind].size.x>=100,"Every crew selection has a useful target width")
	hud.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("SHIFT_CHANGE_UI_PASSED: truthful domestic/work states, explicit watching, native inspection and compact layout")
	quit(0 if failures.is_empty() else 1)
