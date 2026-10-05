extends RefCounted
## One freshness rule for the world masthead. The live event stream is preferred;
## the polled snapshot age is the fallback. Unknown, connecting, stale, offline
## and disconnected stay distinct, and nothing reads as live without evidence.
## Stale is a missed heartbeat window: heartbeat_seconds × 2 + 1.
const SNAPSHOT_FRESH_SECONDS := 5.0
const COLORS := {"live":"6fe3f0", "connecting":"aebccc", "offline":"f3c26b", "stale":"ff8a70", "disconnected":"ff8a70", "unknown":"c6bdd6"}

static func age_text(seconds: float) -> String:
	if seconds < 10.0: return "%.1f s" % seconds
	if seconds < 60.0: return "%d s" % int(seconds)
	if seconds < 3600.0: return "%d m" % int(seconds / 60.0)
	return "%d h" % int(seconds / 3600.0)

static func stale_window(heartbeat_seconds: float) -> float:
	return heartbeat_seconds * 2.0 + 1.0

static func result(status: String, glyph: String, text: String, fixture: bool) -> Dictionary:
	return {"status":status, "glyph":glyph, "text":glyph + " " + text + (" · SYNTHETIC REPLAY" if fixture else ""),
		"color":COLORS[status], "live":status == "live"}

## stream_state: connecting | live | stale | offline (or "" when no stream exists).
## Ages are seconds, or a negative value when nothing has been received.
static func evaluate(stream_state: String, stream_age: float, heartbeat_seconds: float, snapshot_connected: bool, snapshot_age: float, fixture: bool = false) -> Dictionary:
	var window := stale_window(heartbeat_seconds)
	if stream_state == "live" and stream_age >= 0.0 and stream_age <= window:
		return result("live", "[~]", "LIVE · last event " + age_text(stream_age) + " ago", fixture)
	if stream_state in ["live", "stale"] and stream_age >= 0.0:
		return result("stale", "[?]", "STALE · last event " + age_text(stream_age) + " ago · heartbeat missed", fixture)
	var snapshot_fresh := snapshot_connected and snapshot_age >= 0.0 and snapshot_age <= SNAPSHOT_FRESH_SECONDS
	if snapshot_fresh:
		if stream_state == "connecting": return result("connecting", "[-]", "CONNECTING STREAM · snapshot " + age_text(snapshot_age) + " ago", fixture)
		return result("offline", "[/]", "STREAM OFFLINE · snapshot " + age_text(snapshot_age) + " ago", fixture)
	if stream_age < 0.0 and snapshot_age < 0.0:
		if stream_state == "connecting": return result("connecting", "[-]", "CONNECTING · no events yet", fixture)
		return result("unknown", "[?]", "UNKNOWN · nothing received from Core", fixture)
	var last := ""
	if stream_age >= 0.0: last = " · last event " + age_text(stream_age) + " ago"
	elif snapshot_age >= 0.0: last = " · snapshot " + age_text(snapshot_age) + " ago"
	return result("disconnected", "[x]", "DISCONNECTED · last-known records only" + last, fixture)
