extends SceneTree
## Native sign-off captures for the live crew view, from the synthetic stream
## fixture only. No API connection or work dispatch. Run under a real renderer:
## xvfb-run -a -s "-screen 0 1440x900x24" godot --path apps/world --rendering-driver opengl3 --script capture_transparency_live.gd
const STREAM := "res://../../fixtures/world/transparency/stream.jsonl"
var output := "res://../../evidence/world/transparency-20261004"
var failures: Array[String] = []
var world: Node3D
var notes: Dictionary = {}
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void: run.call_deferred()

func picture(name: String) -> void:
	# The software renderer can take a second per frame; refresh the overlays
	# immediately before drawing so the captured text matches the captured state.
	world.update_live_view(1.0)
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	check(image.save_png(ProjectSettings.globalize_path(output).path_join(name + ".png")) == OK, "Saved " + name)
	notes[name] = {"size":str(image.get_size()), "badge":world.hud.freshness_badge.text,
		"activity":world.hud.live_view.activity_rows.filter(func(row): return row.row.visible).map(func(row): return row.time.text + " " + row.glyph.text + " " + row.text.text),
		"card":world.hud.live_view.card_lines.filter(func(label): return label.visible).map(func(label): return label.text) if world.hud.live_view.card.visible else [],
		"gate":[world.hud.live_view.gate_summary.text, world.hud.live_view.gate_policy.text, world.hud.live_view.gate_budget.text] + world.hud.live_view.gate_checks.map(func(label): return label.text),
		"rivet_strip":world.hud.crew_strip.entries.repair.text, "stream_state":world.event_stream.state,
		"v7_snapshot_age_s":(Time.get_ticks_msec()-world.hud.board.sdlc_missions.received_at_msec)/1000.0}
	print("CAPTURED ", name, " ", JSON.stringify(notes[name]))

func settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until: await process_frame

func resize(size: Vector2i) -> void:
	root.size = size
	root.content_scale_size = size
	for _frame in 6: await process_frame

## Replay from the first frame and wait until the final heartbeat has arrived.
func replay() -> void:
	world.restart_stream_fixture()
	var deadline := Time.get_ticks_msec() + 20000
	while not world.event_stream.fixture_done() and Time.get_ticks_msec() < deadline: await process_frame
	check(world.event_stream.fixture_done(), "Fixture replay finished")
	await settle(0.3)
	world.update_live_view(1.0)

func live_checks(tag: String) -> void:
	var hud = world.hud
	check(hud.freshness_badge.text.begins_with("[~] LIVE · last event"), tag + " badge live: " + hud.freshness_badge.text)
	check(hud.freshness_badge.text.ends_with("SYNTHETIC REPLAY"), tag + " replay is labelled synthetic")
	check(hud.live_view.card.visible and hud.live_view.card_lines[0].text == "RIVET · IMPLEMENTER", tag + " follow-card on Rivet")
	check(hud.live_view.card_lines[2].text == "[>] Running tests", tag + " card verb: " + hud.live_view.card_lines[2].text)
	check(hud.live_view.gate_checks[2].text == "[x] Reviewer · changes requested · 2 findings", tag + " reviewer gate check")
	check(hud.crew_strip.entries.repair.text.contains("Running tests"), tag + " crew strip verb: " + hud.crew_strip.entries.repair.text)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if DisplayServer.get_name() == "headless":
		push_error("Native transparency capture requires a renderer")
		quit(1)
		return
	create_timer(240).timeout.connect(func(): push_error("Transparency capture watchdog"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	await resize(Vector2i(1440, 900))
	world = load("res://main.tscn").instantiate()
	world.stream_fixture_path = STREAM
	root.add_child(world)
	world.isolate_capture_input()
	await process_frame
	check(world.fixture_path.ends_with("world-snapshot.json") and not world.hud.board.fixture.is_empty(), "Offline fixtures only")
	check(world.event_stream.fixture_mode and world.event_stream.client == null, "No network stream")
	world.hud.close_panels()
	world.watch_crew("repair")
	# Let Rivet reach the workstation before the replay so the frame shows work, not travel.
	var deadline := Time.get_ticks_msec() + 45000
	var motion = world.crew_motions.repair
	while Time.get_ticks_msec() < deadline and (not motion.path.is_empty() or motion.intent.get("goal") != "workstation"): await physics_frame
	await settle(2.0)
	await replay()
	live_checks("1440")
	check(world.hud.live_view.activity_panel.visible and world.hud.live_view.activity_rows.filter(func(row): return row.row.visible).size() == 6, "Six activity rows")
	await picture("live-crew-view")
	world.event_stream.pause_fixture()
	deadline = Time.get_ticks_msec() + 20000
	while world.event_stream.state != "stale" and Time.get_ticks_msec() < deadline: await process_frame
	world.update_live_view(1.0)
	check(world.hud.freshness_badge.text.begins_with("[?] STALE · last event"), "Stale badge: " + world.hud.freshness_badge.text)
	check(world.hud.live_view.card_lines[2].text == "[?] Activity unknown · stream not live", "Stale card: " + world.hud.live_view.card_lines[2].text)
	check(not world.hud.crew_strip.entries.repair.text.contains("Running tests"), "Strip falls back from a stale verb: " + world.hud.crew_strip.entries.repair.text)
	check(world.hud.live_view.activity_title.text == "ACTIVITY · LAST KNOWN", "Activity marked last known")
	await picture("live-crew-view-stale")
	await resize(Vector2i(960, 700))
	await replay()
	live_checks("960")
	check(world.hud.live_view.activity_tab.visible and not world.hud.live_view.activity_panel.visible, "Activity collapsed at 960 px")
	await picture("live-crew-view-compact")
	world.hud.large_text = true
	world.hud.scale_text()
	world.hud.sync_world_chrome()
	await replay()
	await picture("live-crew-view-compact-large")
	var file := FileAccess.open(ProjectSettings.globalize_path(output).path_join("captures.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"fixture":STREAM, "synthetic":true, "engine":Engine.get_version_info().string,
		"renderer":RenderingServer.get_current_rendering_driver_name(), "captures":notes}, "  "))
	file.close()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("TRANSPARENCY_CAPTURE_PASSED: live, stale, compact and compact large-text captures")
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
