extends RefCounted
## Human-readable projection of stream record events and transient activity notes.
## Notes are observations, not evidence: they drive verbs and the activity log but
## never a success claim. Record text is rendered against the latest /v7 snapshot
## so details (finding counts, case counts) come from retained evidence.
const CREW := {"lead":"Moss", "implementer":"Rivet", "reviewer":"Prism"}
const KIND_ROLE := {"review":"lead", "repair":"implementer", "reviewer":"reviewer"}
const LIMIT := 50
const VERB_FRESH_MSEC := 120000
const TOOLS := {
	"run_public_tests":{"running":"Running tests", "ran":"ran tests", "start":"started running tests", "noun":"Tests"},
	"apply_patch":{"running":"Patching code", "ran":"applied a patch", "start":"started a patch", "noun":"Patch"},
	"replace_symbol":{"running":"Rewriting a symbol", "ran":"rewrote a symbol", "start":"started rewriting a symbol", "noun":"Rewrite"},
	"inspect_symbol":{"running":"Reading code", "ran":"read a symbol", "start":"started reading code", "noun":"Read"},
	"search_source":{"running":"Searching source", "ran":"searched source", "start":"started searching source", "noun":"Search"},
	"inspect_diff":{"running":"Inspecting the diff", "ran":"inspected the diff", "start":"started inspecting the diff", "noun":"Diff check"},
	"check_candidate":{"running":"Checking the candidate", "ran":"checked the candidate", "start":"started checking the candidate", "noun":"Candidate check"}}
const COLORS := {"working":"6fe3f0", "waiting":"f3c26b", "passed":"8fdc8a", "failed":"ff8a70", "muted":"aebccc"}

var entries: Array = []
var latest: Dictionary = {}
var usage: Dictionary = {}

## JSON numbers arrive as floats; show integral ids and counts without ".0".
static func num(value: Variant, fallback: String = "?") -> String:
	return str(int(value)) if value is float or value is int else (str(value) if value is String and not value.is_empty() else fallback)

static func crew_name(role: String) -> String:
	return CREW.get(role, "Core" if role == "core" else ("Worker" if role.is_empty() else role.capitalize()))

static func clock(at: Variant) -> String:
	return Time.get_time_string_from_unix_time(int(at)) if at is float or at is int else "--:--:--"

static func short_tokens(count: int) -> String:
	return str(count) if count < 1000 else "%.1fk" % (count / 1000.0)

static func seconds_text(ms: Variant) -> String:
	if not (ms is float or ms is int): return ""
	return "%.1f s" % (float(ms) / 1000.0) if float(ms) < 60000.0 else "%d s" % int(float(ms) / 1000.0)

func ingest(evt: Dictionary, now_msec: int) -> void:
	if not evt.get("payload") is Dictionary: evt = evt.duplicate(); evt.payload = {}
	if str(evt.get("type", "")) == "mission.activity" or evt.get("retained", true) == false: ingest_note(evt, now_msec)
	else: append({"kind":"record", "evt":evt, "at":evt.get("at"), "msec":now_msec, "key":str(evt.get("id", ""))})

func note_reset(reason: String, at: float, now_msec: int) -> void:
	append({"kind":"reset", "reason":reason, "at":at, "msec":now_msec, "key":"reset-"+str(now_msec)})

func append(entry: Dictionary) -> void:
	entries.append(entry)
	while entries.size() > LIMIT: entries.pop_front()

static func note_role(payload: Dictionary) -> String:
	return str(payload.get("role", ""))

static func note_subject(payload: Dictionary) -> String:
	var kind := str(payload.get("kind", ""))
	if kind.begins_with("model_request"): return "model:" + num(payload.get("request"))
	if kind.begins_with("tool"): return "tool:" + str(payload.get("tool", "?"))
	if kind.begins_with("sandbox"): return "sandbox:" + str(payload.get("label", "?"))
	return kind

func ingest_note(evt: Dictionary, now_msec: int) -> void:
	var payload: Dictionary = evt.payload
	var mission := str(evt.get("record_id", ""))
	var role := note_role(payload)
	var scope := mission + "|" + role + "|" + str(payload.get("verification_id", ""))
	var key := scope + "|" + note_subject(payload)
	# A finished note replaces its started note so the log reads as one action.
	if str(payload.get("kind", "")).ends_with("_finished"):
		for index in range(entries.size() - 1, -1, -1):
			if entries[index].get("key") == key and entries[index].get("open", false):
				entries.remove_at(index)
				break
	var open := str(payload.get("kind", "")) in ["model_request_started", "tool_started", "sandbox_boot"]
	append({"kind":"note", "evt":evt, "at":evt.get("at"), "msec":now_msec, "key":key, "open":open})
	latest[mission + "|" + role] = {"payload":payload, "msec":now_msec, "at":evt.get("at"), "state":str(payload.get("state", ""))}
	if str(payload.get("kind", "")) == "model_request_finished":
		var bucket: Dictionary = usage.get(mission + "|" + role, {"requests":{}, "input_tokens":0, "output_tokens":0})
		var request := num(payload.get("request"))
		if not bucket.requests.has(request):
			bucket.requests[request] = true
			bucket.input_tokens += int(payload.get("input_tokens", 0)) if payload.get("input_tokens") is float or payload.get("input_tokens") is int else 0
			bucket.output_tokens += int(payload.get("output_tokens", 0)) if payload.get("output_tokens") is float or payload.get("output_tokens") is int else 0
		usage[mission + "|" + role] = bucket

## Activity verb for one crew role, from the latest note on that mission.
static func verb(payload: Dictionary) -> Dictionary:
	var kind := str(payload.get("kind", ""))
	var tool: Dictionary = TOOLS.get(str(payload.get("tool", "")), {})
	var ok = payload.get("ok")
	match kind:
		"model_request_started": return {"glyph":"[>]", "text":"Waiting on model · request " + num(payload.get("request")), "tone":"working"}
		"model_request_finished":
			if ok == false: return {"glyph":"[x]", "text":"Model request " + num(payload.get("request")) + " failed", "tone":"failed"}
			return {"glyph":"[>]", "text":"Model reply received", "tone":"working"}
		"tool_started": return {"glyph":"[>]", "text":str(tool.get("running", "Using " + str(payload.get("tool", "a tool")))), "tone":"working"}
		"tool_finished":
			var noun := str(tool.get("noun", str(payload.get("tool", "Tool")).capitalize()))
			if ok == false: return {"glyph":"[x]", "text":noun + " failed", "tone":"failed"}
			return {"glyph":"[/]", "text":noun + " finished", "tone":"working"}
		"sandbox_boot": return {"glyph":"[>]", "text":"Booting sandbox", "tone":"working"}
		"sandbox_finished":
			if ok == false: return {"glyph":"[x]", "text":"Sandbox run failed", "tone":"failed"}
			return {"glyph":"[/]", "text":"Sandbox run finished", "tone":"working"}
	return {"glyph":"[?]", "text":"Activity unknown", "tone":"muted"}

## Current activity is fresh only while the stream is live, the note is recent,
## and the note belongs to the mission the crew member is assigned to.
func current(mission: String, role: String, now_msec: int, stream_live: bool) -> Dictionary:
	var item: Dictionary = latest.get(mission + "|" + role, {})
	if item.is_empty(): return {"fresh":false, "observed":false, "glyph":"[-]", "text":"No activity observed yet", "tone":"muted"}
	if not stream_live: return {"fresh":false, "observed":true, "glyph":"[?]", "text":"Activity unknown · stream not live", "tone":"failed"}
	if now_msec - int(item.msec) > VERB_FRESH_MSEC: return {"fresh":false, "observed":true, "glyph":"[-]", "text":"No recent activity note", "tone":"muted"}
	var result := verb(item.payload)
	result.fresh = true
	result.observed = true
	return result

func usage_for(mission: String, role: String) -> Dictionary:
	var bucket: Dictionary = usage.get(mission + "|" + role, {})
	if bucket.is_empty(): return {"requests":0, "tokens":0}
	return {"requests":bucket.requests.size(), "tokens":int(bucket.input_tokens) + int(bucket.output_tokens)}

static func mission_summary(snapshot: Dictionary, id: String) -> Dictionary:
	for mission in snapshot.get("missions", []):
		if mission is Dictionary and str(mission.get("id", mission.get("input", {}).get("id", ""))) == id: return mission
	return {}

static func case_ratio(cases: Variant) -> String:
	if not cases is Dictionary or not cases.get("passed") is Array or not cases.get("failed") is Array: return ""
	return "%d/%d" % [cases.passed.size(), cases.passed.size() + cases.failed.size()]

func latest_testing_key(mission: String) -> String:
	for index in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[index]
		if entry.kind == "record" and str(entry.evt.get("record_id", "")) == mission and str(entry.evt.payload.get("stage", "")) == "testing": return str(entry.key)
	return ""

func describe_record(entry: Dictionary, snapshot: Dictionary) -> Dictionary:
	var evt: Dictionary = entry.evt
	var payload: Dictionary = evt.payload
	var mission := str(evt.get("record_id", ""))
	var type := str(evt.get("type", ""))
	var summary := mission_summary(snapshot, mission)
	var evidence: Dictionary = summary.get("stage_evidence", {}) if summary.get("stage_evidence") is Dictionary else {}
	match type:
		"mission.stage":
			var stage := str(payload.get("stage", ""))
			var role := str(payload.get("role", "")) if payload.get("role") is String else ""
			var round := int(payload.get("revision_count", 0)) + 1 if payload.get("revision_count") is float or payload.get("revision_count") is int else 0
			var label := str(payload.get("label", "")) if payload.get("label") is String else ""
			if role == "lead" and stage == "implementing": return {"glyph":"[>]", "text":"Moss handed the plan to Rivet", "tone":"working"}
			if stage == "testing":
				var verdict = payload.get("verdict")
				var text := "Core graded round %d · %s" % [round, str(verdict).replace("_", " ")] if verdict is String else "Core recorded round %d tests · verdict not recorded" % round
				var testing: Dictionary = evidence.get("testing", {}) if evidence.get("testing") is Dictionary else {}
				if latest_testing_key(mission) == str(entry.key) and not testing.is_empty():
					var candidate := case_ratio(testing.get("candidate_cases"))
					var baseline := case_ratio(testing.get("baseline_cases"))
					if not candidate.is_empty() and not baseline.is_empty(): text += " (%s vs %s)" % [candidate, baseline]
				return {"glyph":"[=]" if verdict == "improved" else ("[?]" if not verdict is String else "[x]"), "text":text, "tone":"passed" if verdict == "improved" else ("muted" if not verdict is String else "failed")}
			if stage == "reviewing" or role == "reviewer":
				var status := label.get_slice(" · ", 2) if label.get_slice_count(" · ") >= 3 else ""
				var review: Dictionary = evidence.get("reviewing", {}) if evidence.get("reviewing") is Dictionary else {}
				if status.is_empty(): status = str(review.get("status", ""))
				var findings := ""
				if review.get("findings") is Array and str(review.get("status", "")) == status:
					findings = " · %d finding%s" % [review.findings.size(), "" if review.findings.size() == 1 else "s"]
				match status:
					"revise": return {"glyph":"[x]", "text":"Prism requested changes" + findings, "tone":"waiting"}
					"accept": return {"glyph":"[=]", "text":"Prism accepted round %d" % round + findings, "tone":"passed"}
					"abstain": return {"glyph":"[?]", "text":"Prism abstained · evidence missing", "tone":"muted"}
				return {"glyph":"[?]", "text":"Prism recorded a review · status not recorded", "tone":"muted"}
			var who := crew_name(role) if not role.is_empty() else "Core"
			return {"glyph":"[>]", "text":who + " · " + (label if not label.is_empty() else stage.replace("_", " ")), "tone":"working"}
		"mission.admitted": return {"glyph":"[>]", "text":"Core admitted mission " + mission, "tone":"working"}
		"mission.cancel_requested": return {"glyph":"[_]", "text":"Stop requested · effects may still be in flight", "tone":"waiting"}
		"mission.publication": return {"glyph":"[>]", "text":"Core claimed publication · " + str(payload.get("branch", "branch not reported")), "tone":"working"}
		"mission.effect": return {"glyph":"[/]", "text":"Core recorded effect · " + str(payload.get("kind", "unknown")), "tone":"working"}
		"mission.pr_observation": return {"glyph":"[/]", "text":"Core observed the PR · " + str(payload.get("pr_state", "unknown")), "tone":"working"}
		"mission.feedback": return {"glyph":"[/]", "text":"Core recorded PR feedback", "tone":"waiting"}
		"policy.changed": return {"glyph":"[/]", "text":"Policy changed · gen " + str(payload.get("generation", "?")), "tone":"waiting"}
		"discovery.observed": return {"glyph":"[/]", "text":"Core observed an opportunity · " + str(payload.get("outcome", "unknown")), "tone":"working"}
	if type.begins_with("verification."):
		return {"glyph":"[>]", "text":"Verifier · " + type.trim_prefix("verification.").replace("_", " ") + " · " + str(payload.get("stage", payload.get("state", payload.get("kind", "")))).replace("_", " "), "tone":"working"}
	return {"glyph":"[/]", "text":"Core recorded " + type, "tone":"muted"}

static func describe_note(payload: Dictionary) -> Dictionary:
	var who := crew_name(note_role(payload))
	if not str(payload.get("verification_id", "")).is_empty(): who = "Verifier " + who.to_lower()
	var kind := str(payload.get("kind", ""))
	var tool: Dictionary = TOOLS.get(str(payload.get("tool", "")), {})
	var ok = payload.get("ok")
	var elapsed := seconds_text(payload.get("elapsed_ms"))
	var error := str(payload.get("error", "")) if payload.get("error") is String else ""
	match kind:
		"model_request_started": return {"glyph":"[>]", "text":"%s sent model request %s" % [who, num(payload.get("request"))], "tone":"working"}
		"model_request_finished":
			if ok == false: return {"glyph":"[x]", "text":"%s model request %s failed%s" % [who, num(payload.get("request")), " · " + error if not error.is_empty() else ""], "tone":"failed"}
			var tokens := 0
			for field in ["input_tokens", "output_tokens"]:
				if payload.get(field) is float or payload.get(field) is int: tokens += int(payload[field])
			return {"glyph":"[/]", "text":"%s model request %s · %s tokens%s" % [who, num(payload.get("request")), short_tokens(tokens), " · " + elapsed if not elapsed.is_empty() else ""], "tone":"working"}
		"tool_started": return {"glyph":"[>]", "text":"%s %s" % [who, str(tool.get("start", "started " + str(payload.get("tool", "a tool"))))], "tone":"working"}
		"tool_finished":
			var action := str(tool.get("ran", "ran " + str(payload.get("tool", "a tool"))))
			if ok == false: return {"glyph":"[x]", "text":"%s %s · failed" % [who, action], "tone":"failed"}
			return {"glyph":"[/]", "text":"%s %s · ok" % [who, action], "tone":"working"}
		"sandbox_boot": return {"glyph":"[>]", "text":"%s booted sandbox %s" % [who, str(payload.get("label", ""))], "tone":"working"}
		"sandbox_finished":
			return {"glyph":"[x]" if ok == false else "[/]", "text":"%s sandbox run %s%s" % [who, "failed" if ok == false else "finished", " · " + elapsed if not elapsed.is_empty() else ""], "tone":"failed" if ok == false else "working"}
	return {"glyph":"[?]", "text":who + " · unrecognized note", "tone":"muted"}

## The newest `count` entries, oldest first, as {time, glyph, text, color}.
func visible_entries(snapshot: Dictionary, count: int = 6) -> Array:
	var shown: Array = []
	for entry in entries.slice(maxi(0, entries.size() - count)):
		var line: Dictionary
		if entry.kind == "record": line = describe_record(entry, snapshot)
		elif entry.kind == "reset": line = {"glyph":"[?]", "text":"Stream reset · " + str(entry.reason).replace("_", " ") + " · records refetched", "tone":"waiting"}
		else: line = describe_note(entry.evt.payload)
		line.time = clock(entry.get("at"))
		line.color = COLORS.get(line.tone, COLORS.muted)
		shown.append(line)
	return shown

## Follow-card text for one crew member. Activity is a note-derived observation;
## round and mission come from the authoritative /v7 summary.
static func follow_card(name: String, role: String, intent: Dictionary, summary: Dictionary, act: Dictionary, spent: Dictionary) -> Dictionary:
	var mission := str(intent.get("sdlc_mission_id", ""))
	var lines: Array = []
	lines.append({"text":(name + " · " + (role if not role.is_empty() else "crew")).to_upper(), "tone":"title"})
	if mission.is_empty():
		lines.append({"text":"No V7 mission assigned · " + str(intent.get("label", "status unknown")), "tone":"muted"})
		return {"lines":lines, "mission":""}
	var round := "round " + str(int(summary.revision_count) + 1) if summary.get("revision_count") is float or summary.get("revision_count") is int else "round unknown"
	lines.append({"text":"Mission " + mission + " · " + round, "tone":"muted"})
	if bool(intent.get("unknown", false)): lines.append({"text":"[?] Last known · " + str(intent.get("label", "state unknown")), "tone":"failed"})
	else: lines.append({"text":str(act.get("glyph", "[?]")) + " " + str(act.get("text", "Activity unknown")), "tone":str(act.get("tone", "muted"))})
	var requests := int(spent.get("requests", 0))
	lines.append({"text":("%d model request%s · %s tokens · observed" % [requests, "" if requests == 1 else "s", short_tokens(int(spent.get("tokens", 0)))]) if requests > 0 else "Model requests · none observed", "tone":"muted"})
	return {"lines":lines, "mission":mission}
