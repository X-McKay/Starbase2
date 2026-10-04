extends Node
## Reads one full retained mission record from GET /v7/missions/{id} for the
## workstation screen and handoff dialogue. Read-only. It refetches when the
## polled summary for that mission changes (the stream asks for a sooner /v7
## poll, which changes the summary). A failed read keeps the last known record
## and reports it as unavailable; it never fabricates a record.
## Fixture mode reads the synthetic record named by the stream fixture header.
signal changed(id: String)
var api := preload("res://transport.gd").default_origin()
var http = preload("res://transport.gd").create()
var fixtures: Dictionary = {}  # mission id -> absolute fixture file
var fixture_offset := 0.0
var fixture_mode := false
var id := ""
var record: Dictionary = {}
var status := "none"  # none | loading | live | unavailable | fixture | missing
var read_msec := 0
var signature := ""
var pending := ""
var pending_id := ""
var attempt_msec := 0
const RETRY_MSEC := 10000

func _ready() -> void:
	name = "MissionRecord"
	add_child(http)
	http.timeout = 8
	http.max_redirects = 0
	http.body_size_limit = 16777216
	http.request_completed.connect(received)

func set_api(value: String) -> void:
	if not pending.is_empty(): http.cancel_request()
	api = value
	fixture_mode = false
	fixtures = {}
	clear()

func clear() -> void:
	id = ""; record = {}; status = "none"; signature = ""; pending = ""; read_msec = 0

func use_fixtures(files: Dictionary, offset: float) -> void:
	fixture_mode = true
	fixtures = files
	fixture_offset = offset
	clear()

func age_seconds() -> float:
	return (Time.get_ticks_msec() - read_msec) / 1000.0 if read_msec > 0 else -1.0

## Ask for the record of `mission`; `summary` is its latest polled summary.
func want(mission: String, summary: Dictionary) -> void:
	if mission.is_empty():
		if not id.is_empty(): clear(); changed.emit("")
		return
	var next := mission + JSON.stringify([summary.get("updated_at"), summary.get("event_count"), summary.get("state")])
	if mission != id:
		if not pending.is_empty(): http.cancel_request(); pending = ""
		id = mission; record = {}; status = "loading"; signature = ""; read_msec = 0
	if not pending.is_empty(): return
	if next == signature and not (status == "unavailable" and Time.get_ticks_msec() - attempt_msec >= RETRY_MSEC): return
	if fixture_mode:
		load_fixture(mission, next)
		return
	pending = next
	pending_id = mission
	attempt_msec = Time.get_ticks_msec()
	var result: int = http.request(api + "/v7/missions/" + mission.uri_encode())
	if result != OK: received(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())

func load_fixture(mission: String, next: String) -> void:
	signature = next
	var path := str(fixtures.get(mission, ""))
	var data = JSON.parse_string(FileAccess.get_file_as_string(path)) if not path.is_empty() and FileAccess.file_exists(path) else null
	if data is Dictionary and str(data.get("id", "")) == mission:
		record = preload("res://event_stream.gd").rebase(data, fixture_offset)
		status = "fixture"
		read_msec = Time.get_ticks_msec()
	else:
		record = {}
		status = "missing"
	changed.emit(mission)

func received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var requested := pending
	pending = ""
	if requested.is_empty() or pending_id != id: return
	var data = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	if data is Dictionary and str(data.get("id", "")) == id:
		record = data
		status = "live"
		read_msec = Time.get_ticks_msec()
		signature = requested
	else:
		# Keep the last known record; the screen marks it unavailable.
		status = "missing" if code == 404 else "unavailable"
		signature = requested
	changed.emit(id)
