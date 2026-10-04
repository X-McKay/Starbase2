extends SceneTree
## SSE parsing, resume, reset, staleness and the one freshness rule. Includes a
## loopback chunked SSE server so the native HTTPClient path runs for real.
const Stream = preload("res://event_stream.gd")
const Freshness = preload("res://freshness.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: run.call_deferred()

func frames_of(parser, chunks: Array) -> Array:
	var all: Array = []
	for chunk in chunks: all.append_array(parser.feed(chunk if chunk is PackedByteArray else str(chunk).to_utf8_buffer()))
	return all

func parsing() -> void:
	var parser = Stream.Parser.new()
	var frames := frames_of(parser, ["﻿: comment line\nevent: record\nid: ep-1\ndata: {\"a\":\ndata:  1}\n\n"])
	check(frames.size() == 1 and frames[0].event == "record" and frames[0].id == "ep-1", "BOM, comment, event and id")
	check(frames[0].data == "{\"a\":\n 1}" and JSON.parse_string(frames[0].data).a == 1, "Multi-line data joins with a newline and keeps the second space")
	check(parser.comments == 1, "Comments are ignored, not dispatched")
	# The same frame split at every byte boundary, including inside CRLF and a multibyte rune.
	var text := "event: heartbeat\r\ndata: {\"label\":\"· é\"}\r\n\r\nevent: record\rdata: x\r\r\n"
	var bytes := text.to_utf8_buffer()
	for cut in range(1, bytes.size()):
		var split = Stream.Parser.new()
		var got := frames_of(split, [bytes.slice(0, cut), bytes.slice(cut)])
		check(got.size() == 2 and got[0].event == "heartbeat" and JSON.parse_string(got[0].data).label == "· é" and got[1].data == "x", "Split chunk at byte %d" % cut)
	var one = Stream.Parser.new()
	var trickle: Array = []
	for index in bytes.size(): trickle.append_array(one.feed(bytes.slice(index, index + 1)))
	check(trickle.size() == 2, "Byte-at-a-time delivery")
	var pending = Stream.Parser.new()
	check(pending.feed("data: q\r\r".to_utf8_buffer()).is_empty(), "A trailing CR waits: it may be the first half of CRLF")
	check(pending.feed("\n".to_utf8_buffer()).size() == 1, "The next byte completes the blank line")
	var ids = Stream.Parser.new()
	var list := frames_of(ids, ["id: ep-7\ndata: a\n\n", "data: b\n\n", "event: heartbeat\ndata: {}\n\n", "id\ndata: c\n\n"])
	check(list[0].id == "ep-7" and list[1].id == "ep-7" and list[2].id == "ep-7", "Last event id persists across frames without id")
	check(list[3].id == "", "A bare id field clears the last event id")
	var misc = Stream.Parser.new()
	list = frames_of(misc, ["retry: 2500\n\n", "retry: soon\ndata: y\n\n", "event: x\n\n", "data\n\n", "field without colon\ndata: z\n\n"])
	check(list.size() == 4 and list[0].retry == 2500 and list[0].data == "", "Retry-only frame reports the new reconnection time")
	check(list[1].retry == -1 and list[1].data == "y", "Invalid retry ignored")
	check(list[2].data == "" and list[2].event == "message", "Bare data field dispatches an empty data line")
	check(list[3].data == "z", "Unknown fields ignored; event type resets after dispatch")
	var long = Stream.Parser.new()
	long.feed(PackedByteArray([65]).duplicate())
	var big := PackedByteArray(); big.resize(Stream.Parser.MAX_LINE_BYTES + 2); big.fill(65)
	long.feed(big)
	check(long.overflow and long.buffer.is_empty(), "Unbounded lines are dropped, not buffered forever")

func routing_and_state() -> void:
	var stream = Stream.new()
	root.add_child(stream)
	var seen := {"record": [], "activity": [], "reset": [], "states": []}
	stream.record_event.connect(func(evt): seen.record.append(evt))
	stream.activity.connect(func(evt): seen.activity.append(evt))
	stream.reset.connect(func(reason): seen.reset.append(reason))
	stream.connection_changed.connect(func(state): seen.states.append(state))
	stream.running = true
	stream.set_state(Stream.CONNECTING)
	stream.feed(("event: record\nid: ep-41\ndata: {\"id\":\"ep-41\",\"type\":\"mission.stage\",\"family\":\"v7_mission\",\"retained\":true,\"payload\":{}}\n\n").to_utf8_buffer())
	check(stream.state == Stream.CONNECTING, "Replayed records before ready are not yet live")
	stream.feed(("retry: 3000\nevent: ready\nid: ep-42\ndata: {\"type\":\"ready\",\"heartbeat_seconds\":4,\"cursor\":\"ep-42\"}\n\n").to_utf8_buffer())
	check(stream.state == Stream.LIVE and stream.heartbeat_seconds == 4.0 and stream.retry_seconds == 3.0, "Ready makes the stream live and sets heartbeat/retry")
	check(stream.last_event_id == "ep-42", "Resume id follows the ready cursor")
	stream.feed(("event: record\nid: ep-44\ndata: {\"id\":\"ep-44\",\"type\":\"mission.activity\",\"family\":\"v7_mission\",\"retained\":false,\"payload\":{\"kind\":\"tool_started\"}}\n\n").to_utf8_buffer())
	stream.feed(("event: heartbeat\ndata: {\"type\":\"heartbeat\"}\n\n").to_utf8_buffer())
	check(seen.record.size() == 1 and seen.activity.size() == 1, "Activity notes are routed apart from record events")
	check(stream.last_event_id == "ep-44", "Heartbeat without id keeps the resume position")
	check("Last-Event-ID: ep-44" in stream.request_headers(), "Reconnect sends Last-Event-ID")
	stream.feed(("event: record\ndata: not json\n\n").to_utf8_buffer())
	check(stream.malformed == 1 and seen.record.size() == 1, "Malformed data is counted, not emitted")
	stream.feed(("event: reset\nid: ep-90\ndata: {\"type\":\"reset\",\"reason\":\"buffer_exceeded\"}\n\n").to_utf8_buffer())
	check(seen.reset == ["buffer_exceeded"] and stream.resets == 1 and stream.last_event_id == "ep-90", "Reset reports its reason and moves the cursor")
	# Staleness: a missed heartbeat window (4 × 2 + 1 = 9 s) is stale; three missed is dropped.
	check(is_equal_approx(stream.stale_after_seconds(), 9.0), "Stale window is heartbeat × 2 + 1")
	stream.clock_offset_msec += 8500
	stream.check_staleness()
	check(stream.state == Stream.LIVE, "Within the window the stream stays live")
	stream.clock_offset_msec += 1000
	stream.check_staleness()
	check(stream.state == Stream.STALE and stream.last_event_age_seconds() > 9.0, "Missed heartbeat window becomes stale")
	stream.feed(("event: heartbeat\ndata: {\"type\":\"heartbeat\"}\n\n").to_utf8_buffer())
	check(stream.state == Stream.LIVE, "A heartbeat restores live")
	stream.clock_offset_msec += 14000
	stream.check_staleness()
	check(stream.state == Stream.OFFLINE and stream.phase == "waiting" and stream.backoff_seconds() > 0.0, "Three missed heartbeats drop the connection and schedule a reconnect")
	check(seen.states.has(Stream.STALE) and seen.states[-1] == Stream.OFFLINE, "Connection changes are signalled in order")
	# Backoff grows from the server retry and is capped.
	stream.failures = 0
	var delays: Array = []
	for attempt in 6:
		stream.fail("test")
		delays.append(snappedf(stream.backoff_seconds(), 0.5))
	check(delays[0] == 3.0 and delays[1] == 6.0 and delays[2] == 12.0 and delays[5] == 30.0, "Exponential backoff capped at 30 s: " + str(delays))
	check(Stream.split_origin("http://127.0.0.1:8787") == {"tls": false, "host": "127.0.0.1", "port": 8787}, "Origin parsing")
	check(Stream.split_origin("https://example.test") == {"tls": true, "host": "example.test", "port": 443}, "TLS origin parsing")
	for bad in ["ftp://x", "http://u@h:1", "http://h:99999", "http://h/path", ""]: check(Stream.split_origin(bad).is_empty(), "Rejects " + bad)
	stream.stop()
	check(stream.state == Stream.OFFLINE and not stream.running, "Stop is offline and does not reconnect")
	stream.queue_free()

func freshness() -> void:
	var live := Freshness.evaluate("live", 0.8, 5, true, 1.0)
	check(live.status == "live" and live.text == "[~] LIVE · last event 0.8 s ago" and live.live, "Live badge text: " + live.text)
	var edge := Freshness.evaluate("live", 11.0, 5, true, 1.0)
	check(edge.status == "live", "Exactly at the window is still live")
	var stale := Freshness.evaluate("live", 11.2, 5, true, 1.0)
	check(stale.status == "stale" and stale.text.begins_with("[?] STALE · last event 11 s ago") and not stale.live, "Past the window is stale even before the state flips")
	check(Freshness.evaluate("stale", 30.0, 5, true, 1.0).status == "stale", "Stale state stays stale while the snapshot is fresh")
	var offline := Freshness.evaluate("offline", 40.0, 5, true, 2.0)
	check(offline.status == "offline" and offline.text.contains("snapshot 2.0 s ago") and offline.glyph == "[/]", "Offline stream falls back to snapshot age")
	check(Freshness.evaluate("connecting", -1.0, 5, true, 1.0).status == "connecting", "Connecting with a fresh snapshot")
	check(Freshness.evaluate("connecting", -1.0, 5, false, -1.0).status == "connecting", "First connection attempt")
	var unknown := Freshness.evaluate("", -1.0, 5, false, -1.0)
	check(unknown.status == "unknown" and unknown.glyph == "[?]", "Nothing received is unknown")
	var gone := Freshness.evaluate("offline", 40.0, 5, false, 12.0)
	check(gone.status == "disconnected" and gone.text.contains("last event 40 s ago"), "Core unreachable is disconnected with last-known age")
	check(Freshness.evaluate("live", -1.0, 5, true, 1.0).status != "live", "Live state without any event is never healthy")
	var statuses := {}
	for model in [live, stale, offline, unknown, gone]: statuses[model.status] = model.glyph
	check(statuses.size() == 5 and statuses.values().size() == 5, "Five distinct states")
	check(Freshness.evaluate("live", 1.0, 5, true, 1.0, true).text.ends_with("SYNTHETIC REPLAY"), "Fixture replay is labelled")

func fixture_replay() -> void:
	var stream = Stream.new()
	root.add_child(stream)
	var counts := {"record": 0, "activity": 0}
	stream.record_event.connect(func(_evt): counts.record += 1)
	stream.activity.connect(func(_evt): counts.activity += 1)
	check(stream.start_fixture("res://../../fixtures/world/transparency/stream.jsonl"), "Fixture loads")
	check(str(stream.fixture_header.get("fixture")) == "synthetic", "Fixture is labelled synthetic")
	check(stream.state == Stream.CONNECTING and stream.client == null, "Fixture opens no connection")
	stream.clock_offset_msec += 150
	stream.advance_fixture()
	check(counts.record == 2 and stream.state == Stream.CONNECTING, "Relative timing: only frames due by 0.15 s")
	stream.clock_offset_msec += 10000
	stream.advance_fixture()
	check(stream.fixture_done() and counts.record == 3 and counts.activity == 7, "All frames replayed: %s" % str(counts))
	check(stream.last_event_id.ends_with("-115") and stream.state == Stream.LIVE, "Fixture ends live at the newest id")
	check(stream.parser.comments == 2, "Raw fixture frames go through the parser")
	stream.pause_fixture()
	stream.clock_offset_msec += 12000
	stream.check_staleness()
	check(stream.state == Stream.STALE, "A silent fixture goes stale")
	stream.queue_free()

## A loopback HTTP/1.1 chunked SSE server: two connections. The first sends
## frames in awkward chunks then closes; the client must reconnect with the id.
func native_loopback() -> void:
	var server := TCPServer.new()
	var port := 0
	for candidate in range(38711, 38760):
		if server.listen(candidate, "127.0.0.1") == OK:
			port = candidate
			break
	check(port > 0, "Loopback server listens")
	if port == 0: return
	var stream = Stream.new()
	root.add_child(stream)
	var got: Array = []
	stream.record_event.connect(func(evt): got.append(evt.id))
	stream.retry_seconds = 0.5
	stream.start("http://127.0.0.1:%d" % port)
	var requests: Array = []
	for connection in 2:
		var peer: StreamPeerTCP = null
		var deadline := Time.get_ticks_msec() + 8000
		while peer == null and Time.get_ticks_msec() < deadline:
			await process_frame
			if server.is_connection_available(): peer = server.take_connection()
		check(peer != null, "Client connected (%d)" % connection)
		if peer == null: break
		var request := ""
		while not request.contains("\r\n\r\n") and Time.get_ticks_msec() < deadline:
			await process_frame
			peer.poll()
			if peer.get_available_bytes() > 0: request += peer.get_utf8_string(peer.get_available_bytes())
		requests.append(request)
		peer.put_data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nTransfer-Encoding: chunked\r\n\r\n".to_utf8_buffer())
		var body := ""
		if connection == 0:
			body = "retry: 500\nevent: ready\nid: e-1\ndata: {\"type\":\"ready\",\"heartbeat_seconds\":5}\n\n: keep\nevent: record\nid: e-2\ndata: {\"id\":\"e-2\",\"type\":\"mission.stage\",\n"
			body += "data: \"retained\":true,\"payload\":{}}\n\n"
		else:
			body = "event: ready\nid: e-2\ndata: {\"type\":\"ready\",\"heartbeat_seconds\":5}\n\nevent: record\nid: e-3\ndata: {\"id\":\"e-3\",\"type\":\"mission.stage\",\"retained\":true,\"payload\":{}}\n\n"
		var bytes := body.to_utf8_buffer()
		var offset := 0
		for size in [7, 30, 1, 64, 5000]:
			var piece := bytes.slice(offset, mini(offset + size, bytes.size()))
			offset += piece.size()
			if piece.is_empty(): continue
			peer.put_data(("%x\r\n" % piece.size()).to_utf8_buffer() + piece + "\r\n".to_utf8_buffer())
			for _frame in 3: await process_frame
		for _frame in 20: await process_frame
		if connection == 0:
			check(stream.state == Stream.LIVE and got == ["e-2"], "Native client parsed chunked frames: %s %s" % [stream.state, str(got)])
			peer.put_data("0\r\n\r\n".to_utf8_buffer())
			peer.disconnect_from_host()
			for _frame in 10: await process_frame
			check(stream.state == Stream.OFFLINE, "Server close is offline until reconnect")
		else:
			check(stream.state == Stream.LIVE and got == ["e-2", "e-3"], "Reconnected and resumed: " + str(got))
			peer.disconnect_from_host()
	check(requests.size() == 2 and requests[0].begins_with("GET /v8/events HTTP/1.1") and requests[0].contains("Accept: text/event-stream"), "Native request shape")
	check(requests.size() == 2 and not requests[0].contains("Last-Event-ID") and requests[1].contains("Last-Event-ID: e-2"), "Resume header on reconnect only")
	stream.stop()
	server.stop()
	stream.queue_free()

func run() -> void:
	parsing()
	routing_and_state()
	freshness()
	fixture_replay()
	await native_loopback()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("EVENT_STREAM_PASSED: SSE parsing (multi-line, comments, split chunks, CR/LF/CRLF, BOM, retry), resume id, reset, staleness, backoff, freshness states, fixture replay, native loopback reconnect")
	quit(0 if failures.is_empty() else 1)
