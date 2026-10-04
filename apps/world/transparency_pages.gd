extends Node
## Feeds pages 2 and 3 (workstation screen, handoff dialogue) from the world's
## authoritative inputs: the polled /v7 summary, the full mission record read
## here, /v8 activity notes and the shared freshness rule. Read-only; opening or
## stepping through these pages never dispatches work.
const Story = preload("res://mission_story.gd")
const SdlcCrew = preload("res://sdlc_crew.gd")
const Workstation = preload("res://workstation_screen.gd")
const Handoff = preload("res://handoff_dialogue.gd")
const MissionRecord = preload("res://mission_record.gd")
const KINDS := ["review", "repair", "reviewer"]
var world: Node
var record: Node
var kind := ""
var review_index := -1
var fixture_files_loaded := false

func setup(owner_world: Node) -> void:
	name = "TransparencyPages"
	world = owner_world
	record = MissionRecord.new()
	add_child(record)
	record.changed.connect(func(_id: String): refresh())
	var hud = world.hud
	hud.workstation_screen.crew_step.connect(step_crew)
	hud.workstation_screen.handoff_requested.connect(open_handoff)
	hud.workstation_screen.close_requested.connect(func(): hud.close_panels())
	hud.handoff_dialogue.review_step.connect(step_review)
	hud.handoff_dialogue.workstation_requested.connect(func(): open_workstation(kind))
	hud.handoff_dialogue.close_requested.connect(func(): hud.close_panels())
	hud.crew_strip.console_requested.connect(func(): open_workstation())
	hud.crew_strip.handoff_requested.connect(open_handoff)

func visible_page() -> bool:
	var hud = world.hud
	return hud.workstation_screen.visible or hud.handoff_dialogue.visible

func sync_source() -> void:
	var path: String = world.stream_fixture_path
	if not path.is_empty():
		var listed = world.event_stream.fixture_header.get("v7_missions")
		if not fixture_files_loaded:
			var files := {}
			if listed is Dictionary:
				for id in listed: files[str(id)] = path.get_base_dir().path_join(str(listed[id]))
			record.use_fixtures(files, world.event_stream.fixture_time_offset)
			fixture_files_loaded = true
		record.fixture_offset = world.event_stream.fixture_time_offset
	elif fixture_files_loaded or record.api != world.api:
		fixture_files_loaded = false
		record.set_api(world.api)

## The crew member a console opens for: the watched or strip-focused SDLC crew,
## else whoever the latest mission's state assigns, else Rivet.
func default_kind() -> String:
	var focused: String = world.follow_kind()
	if focused in KINDS: return focused
	var summary := latest_summary()
	var role: String = SdlcCrew.ASSIGNED.get(str(summary.get("state", "")), "implementer")
	for candidate in KINDS:
		if SdlcCrew.ROLES[candidate] == role: return candidate
	return "repair"

func latest_summary() -> Dictionary:
	var found := {}
	for mission in world.hud.board.sdlc_missions.snapshot.get("missions", []):
		if mission is Dictionary and (found.is_empty() or float(mission.get("updated_at", 0)) > float(found.get("updated_at", 0))): found = mission
	return found

func mission_for(crew: String) -> String:
	var motions: Dictionary = world.crew_motions
	if motions.has(crew):
		var id := str(motions[crew].intent.get("sdlc_mission_id", ""))
		if not id.is_empty(): return id
	return str(latest_summary().get("id", ""))

func open_workstation(crew: String = "") -> void:
	kind = crew if crew in KINDS else default_kind()
	world.hud.close_panels()
	world.hud.workstation_screen.open()
	world.hud.sync_world_chrome()
	refresh()

func open_handoff() -> void:
	if kind.is_empty(): kind = default_kind()
	review_index = -1
	world.hud.close_panels()
	world.hud.handoff_dialogue.open()
	world.hud.sync_world_chrome()
	refresh()

func toggle_workstation() -> void:
	if world.hud.workstation_screen.visible: world.hud.close_panels()
	else: open_workstation()

func toggle_handoff() -> void:
	if world.hud.handoff_dialogue.visible: world.hud.close_panels()
	else: open_handoff()

func step_crew(direction: int) -> void:
	var index := KINDS.find(kind)
	kind = KINDS[posmod(index + direction, KINDS.size())]
	refresh()

func step_review(direction: int) -> void:
	var model: Dictionary = world.hud.handoff_dialogue.model
	var count := maxi(1, int(model.get("count", 1)))
	var current := int(model.get("index", count - 1))
	review_index = clampi(current + direction, 0, count - 1)
	refresh()

func stream_verdicts() -> Dictionary:
	var out := {}
	for entry in world.live_activity.entries:
		if entry.kind != "record": continue
		var payload: Dictionary = entry.evt.payload
		if str(entry.evt.get("type", "")) == "mission.stage" and payload.get("verdict") is String: out[str(payload.get("key", ""))] = payload.verdict
	return out

func context(crew: String) -> Dictionary:
	var sdlc = world.hud.board.sdlc_missions
	var mission := mission_for(crew)
	var summary: Dictionary = preload("res://live_activity.gd").mission_summary(sdlc.snapshot, mission)
	record.want(mission if not summary.is_empty() else "", summary)
	var role: String = SdlcCrew.ROLES.get(crew, "")
	var now: int = world.event_stream.now_msec() if world.event_stream != null else Time.get_ticks_msec()
	var stream_live: bool = world.stream_live()
	var latest: Dictionary = world.live_activity.latest.get(mission + "|" + role, {})
	var act: Dictionary = world.live_activity.current(mission, role, now, stream_live)
	return {"kind":crew, "name":str(world.hud.crew_strip.NAMES.get(crew, crew)).split(" ")[0], "role":role, "mission":mission,
		"summary":summary, "record":record.record if record.id == mission else {}, "record_status":record.status if record.id == mission else "none",
		"record_age":record.age_seconds(), "freshness":world.freshness_model(),
		"snapshot_current":sdlc.online and Time.get_ticks_msec() - sdlc.received_at_msec < 15000,
		"stream_live":stream_live, "note":Story.dict(latest.get("payload")), "note_fresh":bool(act.get("fresh", false)),
		"observed":world.live_activity.usage_for(mission, role), "fixture":not world.stream_fixture_path.is_empty(),
		"index":review_index, "verdicts":stream_verdicts()}

func refresh() -> void:
	if world == null or not visible_page(): return
	sync_source()
	if kind.is_empty(): kind = default_kind()
	var ctx := context(kind)
	var hud = world.hud
	if hud.workstation_screen.visible: hud.workstation_screen.render(Workstation.build(ctx))
	if hud.handoff_dialogue.visible: hud.handoff_dialogue.render(Handoff.build(ctx))
