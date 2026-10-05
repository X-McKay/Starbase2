extends Node
## Client for Core's `GET /v8/events` Server-Sent Events stream.
## The stream reports that a record changed and when. Record routes remain
## authoritative: consumers refetch them and never rebuild state from events.
## Native builds read the streamed body with HTTPClient; Web builds use the
## browser EventSource through web_request.js. Fixture mode replays a JSONL
## file of frames with relative timing and never opens a connection.
signal record_event(evt: Dictionary)
signal activity(evt: Dictionary)
signal reset(reason: String)
signal connection_changed(state: String)

const CONNECTING := "connecting"
const LIVE := "live"
const STALE := "stale"
const OFFLINE := "offline"
const PATH := "/v8/events"
const MAX_BACKOFF_SECONDS := 30.0
const CONNECT_TIMEOUT_MSEC := 10000
const MAX_CHUNKS_PER_FRAME := 16

## Incremental `text/event-stream` parser (WHATWG HTML §9.2.6). Feed it bytes as
## they arrive; it returns complete frames and keeps partial lines buffered.
class Parser:
	extends RefCounted
	const MAX_LINE_BYTES := 1048576
	var buffer := PackedByteArray()
	var data_lines := PackedStringArray()
	var event_type := ""
	var last_id := ""
	var retry_ms := -1
	var started := false
	var overflow := false
	var comments := 0

	func feed(chunk: PackedByteArray) -> Array:
		buffer.append_array(chunk)
		if not started and buffer.size() >= 3:
			started = true
			if buffer[0] == 0xEF and buffer[1] == 0xBB and buffer[2] == 0xBF: buffer = buffer.slice(3)
		var frames: Array = []
		var start := 0
		while start < buffer.size():
			var lf := buffer.find(10, start)
			var cr := buffer.find(13, start)
			var end := -1
			var next := -1
			if cr >= 0 and (lf < 0 or cr < lf):
				# A trailing CR may be the first half of CRLF; wait for the next byte.
				if cr + 1 >= buffer.size(): break
				end = cr
				next = cr + (2 if buffer[cr + 1] == 10 else 1)
			elif lf >= 0:
				end = lf
				next = lf + 1
			else: break
			var raw := buffer.slice(start, end)
			var frame = line(raw.get_string_from_utf8(), raw.has(0))
			start = next
			if frame != null: frames.append(frame)
		buffer = buffer.slice(start)
		if buffer.size() > MAX_LINE_BYTES:
			overflow = true
			buffer.clear()
		return frames

	func line(text: String, has_nul: bool = false) -> Variant:
		if text.is_empty(): return dispatch()
		if text.begins_with(":"):
			comments += 1
			return null
		var field := text
		var value := ""
		var colon := text.find(":")
		if colon >= 0:
			field = text.substr(0, colon)
			value = text.substr(colon + 1)
			if value.begins_with(" "): value = value.substr(1)
		match field:
			"event": event_type = value
			"data": data_lines.append(value)
			"id":
				if not has_nul: last_id = value
			"retry":
				if not value.is_empty() and value.is_valid_int() and not value.contains("-") and not value.contains("+"): retry_ms = int(value)
		return null

	func dispatch() -> Variant:
		var kind := event_type if not event_type.is_empty() else "message"
		var has_data := not data_lines.is_empty()
		var data := "\n".join(data_lines)
		var retry := retry_ms
		event_type = ""
		data_lines = PackedStringArray()
		retry_ms = -1
		if not has_data:
			return {"event": "", "data": "", "id": last_id, "retry": retry} if retry >= 0 else null
		return {"event": kind, "data": data, "id": last_id, "retry": retry}

var origin := ""
var state := OFFLINE
var last_event_id := ""
var heartbeat_seconds := 5.0
var retry_seconds := 3.0
var failures := 0
var resets := 0
var malformed := 0
var last_failure := ""
var last_frame_msec := -1
var last_record_msec := -1
var ready_seen := false
var running := false
var clock_offset_msec := 0
var parser := Parser.new()
var client: HTTPClient
var phase := ""
var phase_started_msec := 0
var next_attempt_msec := -1
var web_bridge: JavaScriptObject
var web_callback: JavaScriptObject
var fixture_mode := false
var fixture_frames: Array = []
var fixture_header: Dictionary = {}
var fixture_index := 0
var fixture_started_msec := 0
var fixture_paused := false
var fixture_time_offset := 0.0
var fixture_path := ""

func now_msec() -> int:
	return Time.get_ticks_msec() + clock_offset_msec

## Seconds since the last frame of any kind (record, activity note, ready or
## heartbeat); -1 before the first frame. A heartbeat is liveness evidence only.
func last_event_age_seconds() -> float:
	return -1.0 if last_frame_msec < 0 else maxf(0.0, (now_msec() - last_frame_msec) / 1000.0)

func last_record_age_seconds() -> float:
	return -1.0 if last_record_msec < 0 else maxf(0.0, (now_msec() - last_record_msec) / 1000.0)

## A missed heartbeat window: two heartbeat periods plus one second of slack.
func stale_after_seconds() -> float:
	return heartbeat_seconds * 2.0 + 1.0

## Three missed heartbeats means the connection is treated as lost.
func drop_after_seconds() -> float:
	return heartbeat_seconds * 3.0 + 1.0

func start(api: String) -> void:
	stop()
	origin = api.trim_suffix("/")
	running = true
	failures = 0
	set_state(CONNECTING)
	open()

func stop() -> void:
	close()
	running = false
	fixture_mode = false
	next_attempt_msec = -1
	ready_seen = false
	set_state(OFFLINE)

func set_state(value: String) -> void:
	if state == value: return
	state = value
	connection_changed.emit(value)

func close() -> void:
	if client != null: client.close()
	client = null
	if web_bridge != null: web_bridge.close()
	phase = ""

func open() -> void:
	parser = Parser.new()
	parser.last_id = last_event_id
	ready_seen = false
	phase_started_msec = now_msec()
	if OS.has_feature("web"):
		open_web()
		return
	var target := split_origin(origin)
	if target.is_empty():
		fail("invalid origin")
		return
	client = HTTPClient.new()
	var tls: TLSOptions = TLSOptions.client() if target.tls else null
	if client.connect_to_host(target.host, target.port, tls) != OK:
		fail("connect")
		return
	phase = "connecting"

static func split_origin(value: String) -> Dictionary:
	var tls := value.begins_with("https://")
	if not tls and not value.begins_with("http://"): return {}
	var rest := value.substr(8 if tls else 7)
	if rest.contains("/") or rest.contains("@") or rest.is_empty(): return {}
	var host := rest
	var port := 443 if tls else 80
	var colon := rest.rfind(":")
	if colon > 0 and not rest.ends_with("]"):
		host = rest.substr(0, colon)
		var digits := rest.substr(colon + 1)
		if not digits.is_valid_int() or int(digits) <= 0 or int(digits) > 65535: return {}
		port = int(digits)
	return {"tls": tls, "host": host, "port": port}

func request_headers() -> PackedStringArray:
	var headers := PackedStringArray(["Accept: text/event-stream", "Cache-Control: no-cache"])
	if not last_event_id.is_empty(): headers.append("Last-Event-ID: " + last_event_id)
	return headers

func fail(reason: String) -> void:
	close()
	last_failure = reason
	ready_seen = false
	if not running or fixture_mode: return
	failures += 1
	var delay := minf(MAX_BACKOFF_SECONDS, retry_seconds * pow(2.0, failures - 1))
	if reason == "unsupported": delay = MAX_BACKOFF_SECONDS
	next_attempt_msec = now_msec() + int(delay * 1000.0)
	phase = "waiting"
	set_state(OFFLINE)

func backoff_seconds() -> float:
	return -1.0 if next_attempt_msec < 0 else maxf(0.0, (next_attempt_msec - now_msec()) / 1000.0)

func _process(_delta: float) -> void:
	if fixture_mode: advance_fixture()
	elif running:
		if phase == "waiting" and now_msec() >= next_attempt_msec:
			next_attempt_msec = -1
			open()
		elif client != null: poll_native()
	check_staleness()

func check_staleness() -> void:
	if not ready_seen: return
	var age := last_event_age_seconds()
	if age > drop_after_seconds():
		if fixture_mode:
			ready_seen = false
			set_state(OFFLINE)
		else: fail("heartbeat missed")
	elif age > stale_after_seconds(): set_state(STALE)

func poll_native() -> void:
	client.poll()
	var status := client.get_status()
	match phase:
		"connecting":
			if status == HTTPClient.STATUS_CONNECTED:
				if client.request(HTTPClient.METHOD_GET, PATH, request_headers()) != OK: fail("request")
				else: phase = "requesting"
			elif status in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
				if now_msec() - phase_started_msec > CONNECT_TIMEOUT_MSEC: fail("timeout")
			else: fail("connect")
		"requesting":
			if status == HTTPClient.STATUS_REQUESTING:
				if now_msec() - phase_started_msec > CONNECT_TIMEOUT_MSEC: fail("timeout")
			elif status == HTTPClient.STATUS_BODY or status == HTTPClient.STATUS_CONNECTED:
				var code := client.get_response_code()
				var content_type := ""
				for header in client.get_response_headers():
					if header.to_lower().begins_with("content-type:"): content_type = header.substr(13).strip_edges().to_lower()
				if code == 404: fail("unsupported")
				elif code != 200 or not content_type.begins_with("text/event-stream"): fail("http " + str(code))
				else: phase = "body"
			else: fail("request")
		"body":
			if status != HTTPClient.STATUS_BODY:
				fail("closed")
				return
			for _i in MAX_CHUNKS_PER_FRAME:
				var chunk := client.read_response_body_chunk()
				if chunk.is_empty(): break
				feed(chunk)
				if client == null: return

## Parse streamed bytes and act on each complete frame. Public for tests.
func feed(chunk: PackedByteArray) -> void:
	for frame in parser.feed(chunk): handle_frame(frame)
	if parser.overflow:
		malformed += 1
		fail("line too long")

func handle_frame(frame: Dictionary) -> void:
	last_event_id = str(frame.get("id", last_event_id))
	var retry := int(frame.get("retry", -1))
	if retry >= 0: retry_seconds = clampf(retry / 1000.0, 0.5, MAX_BACKOFF_SECONDS)
	var text := str(frame.get("data", ""))
	if text.is_empty(): return
	last_frame_msec = now_msec()
	var json := JSON.new()
	var data = json.data if json.parse(text) == OK else null
	if not data is Dictionary:
		malformed += 1
		return
	if fixture_mode and fixture_time_offset != 0.0 and (data.get("at") is float or data.get("at") is int):
		data["at"] = float(data["at"]) + fixture_time_offset
	match str(frame.get("event", "")):
		"ready":
			var beat = data.get("heartbeat_seconds", 5)
			heartbeat_seconds = clampf(float(beat), 1.0, 60.0) if beat is float or beat is int else 5.0
			failures = 0
			ready_seen = true
			set_state(LIVE)
		"heartbeat":
			if ready_seen: set_state(LIVE)
		"reset":
			resets += 1
			reset.emit(str(data.get("reason", "unknown")))
		"record":
			last_record_msec = last_frame_msec
			if ready_seen: set_state(LIVE)
			if str(data.get("type", "")) == "mission.activity" or data.get("retained", true) == false: activity.emit(data)
			else: record_event.emit(data)

# --- Web: browser EventSource. The browser reconnects with Last-Event-ID on its
# own; when it gives up (readyState CLOSED) this node reopens with ?after=<id>.
func open_web() -> void:
	if web_bridge == null:
		if JavaScriptBridge.get_interface("StarbaseEventSource") == null:
			JavaScriptBridge.eval(FileAccess.get_file_as_string("res://web_request.js"), true)
		web_callback = JavaScriptBridge.create_callback(web_message)
		var factory := JavaScriptBridge.get_interface("StarbaseEventSource")
		if factory != null: web_bridge = factory.create(web_callback)
	if web_bridge == null:
		fail("unavailable")
		return
	var target := origin + PATH + ("?after=" + last_event_id.uri_encode() if not last_event_id.is_empty() else "")
	if not web_bridge.open(target):
		fail("refused")
		return
	phase = "web"

func web_message(args: Array) -> void:
	var message = JSON.parse_string(str(args[0]))
	if not message is Array or message.is_empty(): return
	match str(message[0]):
		"frame":
			var id := str(message[3]) if message.size() > 3 else ""
			handle_frame({"event": str(message[1]), "data": str(message[2]), "id": id if not id.is_empty() else last_event_id, "retry": -1})
		"error":
			if message.size() > 1 and int(message[1]) == 2: fail("closed")
			else:
				ready_seen = false
				set_state(OFFLINE)

# --- Fixture replay. Lines are JSON objects: an optional header with "fixture",
# then frames {"t": seconds, "event", "id", "data": {...}} or {"t", "raw": "..."}
# where raw text goes through the same parser as network bytes.
func start_fixture(path: String, speed: float = 1.0) -> bool:
	stop()
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty(): return false
	fixture_frames.clear()
	fixture_header = {}
	for row in text.split("\n", false):
		if row.strip_edges().is_empty(): continue
		var item = JSON.parse_string(row)
		if not item is Dictionary: return false
		if item.has("fixture") and fixture_header.is_empty(): fixture_header = item
		else:
			item["t"] = float(item.get("t", 0.0)) / maxf(speed, 0.01)
			fixture_frames.append(item)
	fixture_path = path
	fixture_mode = true
	running = true
	fixture_index = 0
	fixture_paused = false
	fixture_started_msec = now_msec()
	var final_t: float = float(fixture_frames[-1].t) if not fixture_frames.is_empty() else 0.0
	var reference = fixture_header.get("reference_time")
	# Rebase synthetic timestamps so the last frame is stamped "now" at replay end.
	fixture_time_offset = Time.get_unix_time_from_system() + final_t - float(reference) if reference is float or reference is int else 0.0
	parser = Parser.new()
	set_state(CONNECTING)
	return true

## Restart replay timing once the consumer is in the tree (scene load can be slow).
func restart_fixture_clock() -> void:
	fixture_started_msec = now_msec()

const TIME_KEYS := ["at", "updated_at", "created_at", "expires_at", "observed_at", "pr_observed_at"]

## Shift synthetic fixture timestamps by `offset` seconds, recursively.
static func rebase(value: Variant, offset: float) -> Variant:
	if offset == 0.0: return value
	if value is Dictionary:
		var result := {}
		for key in value:
			var item = value[key]
			result[key] = item + offset if str(key) in TIME_KEYS and (item is float or item is int) and float(item) > 0.0 else rebase(item, offset)
		return result
	if value is Array: return value.map(func(item): return rebase(item, offset))
	return value

func fixture_done() -> bool:
	return fixture_mode and fixture_index >= fixture_frames.size()

## Stop delivering fixture frames, as if the server went silent.
func pause_fixture() -> void:
	fixture_paused = true

func advance_fixture() -> void:
	if fixture_paused: return
	var elapsed := (now_msec() - fixture_started_msec) / 1000.0
	while fixture_index < fixture_frames.size() and float(fixture_frames[fixture_index].t) <= elapsed:
		var item: Dictionary = fixture_frames[fixture_index]
		fixture_index += 1
		if item.has("raw"): feed(str(item.raw).to_utf8_buffer())
		else:
			handle_frame({"event": str(item.get("event", "")), "data": JSON.stringify(item.get("data", {})),
				"id": str(item.get("id", last_event_id)), "retry": int(item.get("retry", -1))})
		if not fixture_mode: return

func _exit_tree() -> void:
	close()
