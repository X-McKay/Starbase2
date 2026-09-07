extends SceneTree
## Layout, tone and comfort checks for the native HUD at both supported viewports.
## Headless layout is not a visual review; captures accompany the handoff.
const HUD=preload("res://hud.gd")
const UI=preload("res://ui_theme.gd")
const StateView=preload("res://state.gd")
var failures: Array[String]=[]
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func inside(control: Control, label: String) -> void:
	var rect := control.get_global_rect()
	var view := root.get_visible_rect().size
	check(rect.position.x>=-0.5 and rect.position.y>=-0.5 and rect.end.x<=view.x+0.5 and rect.end.y<=view.y+0.5,label+" stays inside %s: %s" % [str(view),str(rect)])
func settle() -> void:
	for i in range(3): await process_frame
func _initialize() -> void: run.call_deferred()
func run() -> void:
	# Every tone StateView can produce has a distinct shape, except offline/unknown
	# which intentionally share "no information" and differ by their text.
	var shapes := {}
	for tone in ["idle","stale","unknown","failed","no_change","verified","pending"]:
		var shape: String=UI.TONES[tone][1]
		check(not shapes.has(shape),"Tone shapes must differ without color: "+tone+" reuses "+shape)
		shapes[shape]=tone
	check(UI.TONES["offline"][1]==UI.TONES["unknown"][1],"Offline and unknown share the no-information shape")
	var board_snapshot := {"enabled":true,"observed_at":1000,"builds":[{"manifest":{"agent":"reviewer","target":{"id":"repo-a","kind":"fixture","repository":"fixture/repo"}}}],
		"runs":[{"input":{"id":"run-1","agent":"reviewer","target":"repo-a"},"state":"running","updated_at":900,"detail":"Observing","summary":null}],
		"repositories":[{"id":"repo-a","config":{"repository":"fixture/repo","enabled":true,"removed":false,"interval_seconds":300,"generation":1}}],
		"memory":[{"id":"m1","finding":{"summary":"Sample observation"},"agent":"reviewer","target":"repo-a","decision":"proposed","revision":1,"source_run":"run-1"}],"duties":[]}
	for layout in [[Vector2i(1280,800),false],[Vector2i(960,720),true]]:
		root.content_scale_size=layout[0]
		root.size=layout[0]
		var compact: bool=layout[1]
		var hud=HUD.new()
		hud.compact=compact
		hud.board_fixture="test-only"
		root.add_child(hud)
		hud.board.timer.stop()
		await settle()
		var tag := " (compact)" if compact else " (normal)"
		# Masthead, nav and bottom bar.
		for b in hud.root.find_children("*","Button",true,false):
			if b.has_meta("kbd"): check(b.get_meta("kbd").visible,"Key cap present on "+b.text+tag)
		hud.set_roster([["Mender","Stale · work unknown","stale"],["Surveyor","Failed","failed"],["Trainer","Inconclusive","unknown"],["Watchkeeper","No recorded work","idle"],["PR Reviewer","No recorded work","idle"]])
		await settle()
		check(hud.roster.get_child_count()==5,"Five crew chips"+tag)
		check(hud.roster.get_child(0).get_meta("badge").get_meta("tone")=="stale","Chip carries its tone"+tag)
		check(hud.roster.get_child(0).get_meta("badge").get_node("Text").text.contains("Stale"),"Chip text keeps the state word"+tag)
		for control in hud.roster.get_parent().get_children(): inside(control,"Bottom bar row"+tag)
		hud.set_prompt([["F","Enter TRIAL HALL"],"·",["E","Inspect nearby crew"]])
		await settle()
		check(not hud.prompt.visible and hud.prompt_row.get_child_count()==4,"Structured prompt renders key caps"+tag)
		inside(hud.prompt_row,"Prompt row"+tag)
		hud.set_prompt("Plain prompt")
		check(hud.prompt.visible and hud.prompt.text=="Plain prompt","Plain prompt falls back to text"+tag)
		hud.set_connection("Stale · no snapshot for five seconds","stale")
		check(hud.connection.text.begins_with("Stale") and hud.connection_badge.get_meta("tone")=="stale","Connection badge text and tone"+tag)
		# Inspector dock, including larger text.
		hud.open_place("repair")
		hud.set_status(StateView.describe({"state":"running","stale":true},false),StateView.tone({"state":"running","stale":true},false))
		hud.set_progression("Mender · Level 2 · 50 verified XP","verified")
		hud.set_command_status("Request accepted · watching authoritative state.",false)
		await settle()
		check(hud.dock.visible and not hud.scrim.visible,"Dock is a side panel without a scrim"+tag)
		check(hud.status.text.begins_with("Stale") and hud.status_badge.get_meta("tone")=="stale","Status badge mirrors StateView"+tag)
		check(hud.command_strip.visible,"Command feedback strip appears with a message"+tag)
		inside(hud.dock,"Dock"+tag)
		hud.large_text=true; hud.scale_text()
		await settle()
		inside(hud.dock,"Dock with larger text"+tag)
		for control in hud.roster.get_parent().get_children(): inside(control,"Bottom bar row with larger text"+tag)
		check(hud.root.theme.default_font_size==UI.size("body",true),"Theme rebuilt for larger text"+tag)
		hud.large_text=false; hud.scale_text()
		hud.set_command_status("",false)
		check(not hud.command_strip.visible,"Empty feedback hides the strip"+tag)
		# Modal panels take a scrim and keep keyboard focus inside.
		hud.toggle_directory()
		await settle()
		check(hud.directory.visible and hud.scrim.visible and not hud.dock.visible,"Directory replaces the dock behind a scrim"+tag)
		check(root.gui_get_focus_owner()==hud.directory_first,"Directory focuses its first action"+tag)
		check(hud.crew_badges["repair"].get_node("Text").text.contains("Stale"),"Directory crew rows show roster activity"+tag)
		inside(hud.directory,"Directory"+tag)
		hud.toggle_help()
		await settle()
		check(hud.help.visible and not hud.directory.visible and root.gui_get_focus_owner()==hud.help_first,"Help replaces the directory and focuses its first toggle"+tag)
		inside(hud.help,"Help"+tag)
		hud.board.snapshot=board_snapshot
		hud.board.render()
		hud.open_board()
		await settle()
		check(hud.board.visible and hud.scrim.visible and not hud.help.visible,"Board opens behind a scrim"+tag)
		inside(hud.board,"Board"+tag)
		for column in [hud.board.runs,hud.board.watches,hud.board.memories]:
			check(column.get_child_count()==1 and column.get_child(0) is PanelContainer,"Board renders one card per record"+tag)
		for b in hud.board.find_children("*","Button",true,false):
			if not b.text.is_empty() and not b.clip_text and b.theme_type_variation!="IconButton": check(b.get_combined_minimum_size().x>48,"Board button keeps its caption: "+b.text+tag)
		check(hud.board.launch.disabled and hud.board.watch_save.disabled,"Fixture keeps mutations disabled"+tag)
		var glyphs: Array = hud.board.find_children("Glyph","",true,false)
		check(glyphs.size()>=5,"Board records carry shape glyphs"+tag)
		hud.board.tabs.current_tab=3
		hud.board.inspect("missing")
		await settle()
		inside(hud.board,"Board evidence page"+tag)
		hud.close_panels()
		check(not hud.is_open() and not hud.scrim.visible,"Escape path closes everything"+tag)
		# Toast and reduced motion.
		hud.notify("Verified achievement retained","verified",2.0)
		await settle()
		check(hud.toast.visible and hud.toast_badge.get_node("Text").text.contains("Verified"),"Toast shows the notice"+tag)
		inside(hud.toast,"Toast"+tag)
		hud.reduced=true
		hud.open_place("gym")
		check(hud.dock.modulate==Color.WHITE,"Reduced motion reveals panels immediately"+tag)
		check(not hud.repair_form.visible,"Gym inspector hides the repair form"+tag)
		hud.close_panels()
		for l in hud.root.find_children("*","Label",true,false):
			check(l.get_theme_font_size("font_size")>=11,"Label font size floor: "+l.text.left(24)+tag)
		hud.queue_free()
		await settle()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("UI checks passed: distinct tone shapes, key caps, roster chips, structured prompts, dock/directory/help/board bounds at 1280x800 and 960x720 with larger text, scrim and focus handling, toast and reduced motion")
	quit(0 if failures.is_empty() else 1)
