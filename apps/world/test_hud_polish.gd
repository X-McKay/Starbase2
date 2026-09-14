extends SceneTree
## Focused regression checks for exploration chrome and dossier empty states.
var failures:Array[String]=[]
func check(value:bool,message:String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var hud=load("res://hud.gd").new()
	root.add_child(hud)
	await process_frame
	await process_frame
	check(not hud.exploration_hud_collapsed,"Exploration HUD starts expanded")
	hud.toggle_exploration_hud()
	check(hud.exploration_hud_collapsed,"HUD toggle enters compact exploration mode")
	check(not hud.crew_strip.visible and not hud.prompt_panel.visible,"Collapsed HUD removes dense world overlays")
	check(hud.chrome_toggle.text.contains("Show HUD"),"Collapsed HUD keeps a visible restore control")
	hud.toggle_exploration_hud()
	check(hud.crew_strip.visible and hud.prompt_panel.visible,"HUD toggle restores exploration overlays")
	hud.update_list([])
	check(hud.list.item_count==1 and hud.list.get_item_text(0)=="No retained assignments","Empty dossier names the missing assignment")
	check(hud.list.is_item_disabled(0),"Empty dossier selector is clearly unavailable")
	check(hud.stop.disabled and not hud.stop.visible and not hud.record_metadata.visible,"Empty dossier hides irrelevant cancellation and missing metadata")
	hud.open_operations()
	check(hud.navigation_background.visible==hud.navigation_bar.vertical,"Open workspace keeps a readable navigation background")
	hud.open_place("repair")
	check(hud.dossier_tabs.current_tab==0 and hud.list.get_parent()!=hud.dossier_scroll.get_child(0),"Profile opens before assignment records")
	hud.operations.fixture=""; hud.operations.offline=true; hud.update_crew_guide()
	check(hud.crew_availability.text.contains("Disconnected"),"Crew profile keeps offline availability explicit")
	hud.board.targets.clear()
	for role in ["watchkeeper","reviewer"]:
		hud.board.targets.add_item(role)
		hud.board.targets.set_item_metadata(hud.board.targets.item_count-1,{"agent":role,"id":role,"kind":"fixture"})
	hud.open_place("reviewer"); hud.open_crew_workflow()
	check(hud.board.targets.selected==1,"Prism route selects the reviewer target instead of the first target")
	hud.open_place("watchkeeper"); hud.open_crew_workflow()
	check(hud.board.targets.selected==0,"Wes route selects the watchkeeper target")
	hud.board.targets.remove_item(1)
	hud.open_place("reviewer"); hud.open_crew_workflow()
	check(hud.board.targets.selected==-1 and hud.board.launch.disabled,"Missing reviewer target does not select another crew capability")
	hud.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("HUD_POLISH_PASSED: collapsible exploration chrome and explicit dossier empty state")
	quit(0 if failures.is_empty() else 1)
