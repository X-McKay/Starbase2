extends SceneTree
const ConsoleTheme=preload("res://console_theme.gd")
var failures:Array[String]=[]
func check(value:bool,message:String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var theme:=ConsoleTheme.make_theme()
	check(theme.default_font_size>=16,"Console body text is at least 16px")
	check(ConsoleTheme.panel_style().bg_color.a>=0.9,"Dense console panels remain legible over scenery")
	var focus:=theme.get_stylebox("focus","Button") as StyleBoxFlat
	check(focus.border_width_left>=2 and focus.border_color==ConsoleTheme.ACCENT,"Keyboard focus has a strong outline")
	var selected:=theme.get_stylebox("tab_selected","TabContainer") as StyleBoxFlat
	check(selected.border_width_bottom>=3,"Selected tab has a shape cue beyond text color")
	var disabled_primary:=Button.new(); root.add_child(disabled_primary); ConsoleTheme.primary(disabled_primary)
	check((disabled_primary.get_theme_stylebox("disabled") as StyleBoxFlat).bg_color.a>=0.8 and (disabled_primary.get_theme_color("font_disabled_color")==ConsoleTheme.MUTED),"Disabled primary actions use neutral styling")
	var board=preload("res://command_board.gd").new()
	board.fixture="test"; root.add_child(board); board.timer.stop()
	var panel=preload("res://operations_panel.gd").new()
	panel.fixture="test"; root.add_child(panel)
	await process_frame
	check(board.launch.custom_minimum_size.y>=40 and panel.review_button.custom_minimum_size.y>=40,"Primary action targets are at least 40px")
	board.snapshot={"runs":[],"repositories":[],"memory":[],"builds":[],"duties":[]}; board.render()
	panel.update_snapshot({"recent":[],"active":[],"targets":[],"builds":[],"duties":[]},true)
	check(panel.target.get_item_text(0)=="No targets available" and panel.profile.get_item_text(0)=="No registered builds available","Empty selectors explain unavailable targets and builds")
	check(panel.heading.text.contains("FIXTURE"),"Fixture remains prominent in the Operations header")
	panel.fixture=""; panel.update_snapshot(panel.snapshot,true)
	check(panel.heading.text.contains("LAST KNOWN"),"Disconnected retained records cannot appear live")
	check(panel.briefing_toggle.text.contains("0 records"),"Briefing disclosure exposes authoritative record count")
	check(board.launch.disabled and panel.review_button.disabled,"Readability changes preserve command fences")
	disabled_primary.queue_free(); board.queue_free(); panel.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CONSOLE_THEME_PASSED: contrast, type, focus, selected tab, action targets, snapshot status and command fences")
	quit(0 if failures.is_empty() else 1)
