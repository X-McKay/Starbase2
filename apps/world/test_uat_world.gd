extends SceneTree

const StateView=preload("res://state.gd")
const Structures=preload("res://structure_catalog.gd")
var failures:Array[String]=[]

func check(ok:bool,message:String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var failed_repair:Dictionary={
		"input":{"id":"uat-repair","scenario":"clamp-v1"},
		"state":"completed",
		"detail":"ineligible: independent core grading retained",
		"actions":[{"stage":"baseline","inputs":[1,2],"observation":{"exit_code":2,"stdout":"","stderr":"sandbox socket unavailable"}}],
		"summary":{"outcome":"ineligible","baseline_passed":0,"candidate_passed":0,"cases":6,"hard_gate_failures":["baseline: execution or output protocol failure"]}
	}
	var projected:Array=StateView.project({"schema_version":2,"worker":{"available":true},"recent":[],"active":[],"repairs":[failed_repair],"field_runs":[]})
	check(projected.size()==1,"Failed repair remains visible in the projection")
	if projected.size()==1:
		var record:Dictionary=projected[0]
		check(StateView.describe(record,false)=="Execution failed","Execution hard-gate is distinct from completed")
		check(StateView.crew_activity([record],"repair",false)=="Execution failed","Crew activity preserves execution failure")
		check(record.evidence.summary.execution_failed,"Execution failure is explicit in retained evidence")
		check(record.evidence.summary.execution_failures[0].reason.contains("sandbox socket unavailable"),"Action stderr is retained as the failure reason")
		check(record.detail.contains("Execution failed"),"Record detail explains why the terminal run has no valid score")
		var ongoing:Dictionary=record.duplicate(true); ongoing.state="executing"
		check(StateView.describe(ongoing,false)=="Executing","An interim action failure must not replace an active lifecycle state")
	var strip=load("res://crew_strip.gd").new(); root.add_child(strip); await process_frame; await process_frame
	var intent:Dictionary={"unknown":false,"active_count":0,"backend_state":""}
	strip.fit(1280,false)
	strip.project("repair",intent,"Walking home")
	check(strip.entries.repair.text.ends_with("Between assignments"),"Ambient life is omitted from the operational crew strip")
	var before:String=strip.entries.repair.text
	strip.project("repair",intent,"Taking a break")
	check(strip.entries.repair.text==before,"Input or ambient refresh cannot replace operational status")
	strip.fit(800,true)
	check(strip.entries.repair.text.ends_with("Between tasks"),"Compact presentation shortens the label without showing ambient activity")
	strip.entries.repair.grab_focus();await process_frame
	check(strip.status_detail.text=="Rivet · Between assignments","Keyboard focus preserves the full authoritative status in compact mode")
	strip.project("repair",intent,"At home")
	check(strip.status_detail.text=="Rivet · Between assignments","Ambient refresh cannot replace focused full-status evidence")
	var paths:Dictionary=Structures.room_paths()
	check(paths.get("habitat")=="Structures/Habitat","Canonical habitat definition ID resolves to its station")
	check(paths.get("Habitat")=="Structures/Habitat","Existing capitalized habitat callers remain supported")
	var hud=load("res://hud.gd").new(); root.add_child(hud); await process_frame; await process_frame
	hud.open_connection()
	var esc:=InputEventKey.new(); esc.pressed=true; esc.keycode=KEY_ESCAPE; esc.physical_keycode=KEY_ESCAPE
	root.push_input(esc)
	check(not hud.is_open(),"Escape closes a workspace while its LineEdit has focus")
	hud.open_place("repair"); await process_frame
	hud.scenario.show_popup(); await process_frame
	var popup:PopupMenu=hud.scenario.get_popup()
	check(popup.visible,"Repair mode exposes its real OptionButton popup")
	var popup_esc:=InputEventKey.new(); popup_esc.pressed=true; popup_esc.keycode=KEY_ESCAPE; popup_esc.physical_keycode=KEY_ESCAPE
	root.push_input(popup_esc); await process_frame
	check(not popup.visible and hud.is_open(),"Escape dismisses an open OptionButton popup before closing its workspace")
	var f1:=InputEventKey.new(); f1.pressed=true; f1.keycode=KEY_F1; f1.physical_keycode=KEY_F1
	var collapsed:bool=hud.exploration_hud_collapsed
	root.push_input(f1)
	check(hud.exploration_hud_collapsed!=collapsed,"F1 toggles HUD before GUI focus consumes it")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("UAT_WORLD_PASSED")
	quit(0 if failures.is_empty() else 1)
