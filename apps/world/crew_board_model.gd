extends RefCounted
## Page 5 (crew board) projection. Every line is derived from authoritative
## records: the /v7 snapshot, its missions and recent_events, the /v2 world
## snapshot and /v8 stream entries. Nothing here dispatches work or invents
## state. Unknown, stale, silent, blocked, failed and idle stay distinct.
const StateView = preload("res://state.gd")
const SdlcCrew = preload("res://sdlc_crew.gd")
const LiveActivity = preload("res://live_activity.gd")
const RealityGate = preload("res://reality_gate.gd")
const SafeLink = preload("res://sdlc_missions.gd")

## Board order: duty officer first, then the SDLC pair, then the other crew.
const CREW := [
	{"kind":"review", "name":"Moss", "init":"Mo", "role":"lead", "where":"Command"},
	{"kind":"repair", "name":"Rivet", "init":"Ri", "role":"implementer", "where":"Workshop"},
	{"kind":"reviewer", "name":"Prism", "init":"Pr", "role":"reviewer", "where":"Command"},
	{"kind":"watchkeeper", "name":"Wes", "init":"We", "role":"watchkeeper", "where":"Cluster watch"},
	{"kind":"gym", "name":"Mae", "init":"Ma", "role":"trainer", "where":"Trial Hall"}]
const ROLE_KIND := {"lead":"review", "implementer":"repair", "reviewer":"reviewer"}
const V2_TERMINAL := ["completed", "failed", "cancelled"]
const V7_PROBLEM := ["blocked", "failed"]
## An open record with no update for this long is "silent": an observation that
## the record stopped changing, never a claim that the work failed.
const SILENT_SECONDS := 300.0
const DAY_SECONDS := 86400.0
const POLICY_WARN_SECONDS := 3.0 * 86400.0
const FEED_LIMIT := 14
const TONES := {"working":"6fe3f0", "waiting":"f3c26b", "passed":"8fdc8a", "failed":"ff8a70", "muted":"aebccc", "need":"ffc861"}
const STATUS := {
	"working":{"glyph":"[>]", "tone":"working"}, "waiting":{"glyph":"[||]", "tone":"waiting"},
	"queued":{"glyph":"[...]", "tone":"muted"}, "idle":{"glyph":"[-]", "tone":"muted"},
	"silent":{"glyph":"[/]", "tone":"failed"}, "stale":{"glyph":"[/]", "tone":"failed"},
	"unknown":{"glyph":"[?]", "tone":"failed"}}

static func number(value: Variant) -> bool:
	return value is float or value is int

static func clock(at: Variant) -> String:
	return Time.get_time_string_from_unix_time(int(at)).left(5) if number(at) else "--:--"

static func ago(seconds: float) -> String:
	var s := maxf(seconds, 0.0)
	if s < 60.0: return "%d s" % int(s)
	if s < 3600.0: return "%d m" % int(s / 60.0)
	if s < DAY_SECONDS: return "%d h" % int(s / 3600.0)
	return "%d d" % int(s / DAY_SECONDS)

static func member(kind: String) -> Dictionary:
	for item in CREW:
		if item.kind == kind: return item
	return {}

static func name_of(kind: String) -> String:
	return str(member(kind).get("name", "Core" if kind == "core" else kind.capitalize()))

static func short_id(id: String) -> String:
	return id.trim_prefix("sdlc-")

static func repo_name(repository: String) -> String:
	return repository.get_slice("/", 1) if repository.contains("/") else repository

static func mission_id(mission: Dictionary) -> String:
	return str(mission.get("id", mission.get("input", {}).get("id", "")))

static func v7_missions(v7: Dictionary) -> Array:
	return v7.get("missions", []).filter(func(m): return m is Dictionary) if v7.get("missions") is Array else []

static func active_v7(v7: Dictionary) -> Dictionary:
	var found := {}
	for mission in v7_missions(v7):
		if str(mission.get("state", "")) in SdlcCrew.TERMINAL: continue
		if found.is_empty() or float(mission.get("updated_at", 0)) > float(found.get("updated_at", 0)): found = mission
	return found

static func round_of(mission: Dictionary) -> int:
	return int(mission.revision_count) + 1 if number(mission.get("revision_count")) else 0

static func v2_own(ctx: Dictionary, kind: String) -> Array:
	var own: Array = ctx.get("v2_missions", []).filter(func(m): return m is Dictionary and StateView.context(m) == kind)
	own.sort_custom(func(a, b): return float(a.get("updated_at", 0)) > float(b.get("updated_at", 0)))
	return own

static func v2_target(record: Dictionary) -> String:
	var input: Dictionary = record.get("input", {})
	return str(input.get("target", input.get("scenario", "target not reported")))

## What a v2 record was doing, in plain words. Field agent kinds read as checks.
static func v2_activity(record: Dictionary) -> String:
	var kind := StateView.kind(record)
	var noun: String = {"watchkeeper":"workload check", "reviewer":"review pass", "review":"repository review", "repair":"repair", "evaluation":"evaluation"}.get(kind, "run")
	return noun + " on " + v2_target(record)

## Upper-case the first letter only; record text keeps its own spelling.
static func sentence(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)

static func v2_outcome(record: Dictionary) -> String:
	var state := str(record.get("state", "unknown"))
	if state == "completed":
		var evidence = record.get("evidence")
		if evidence is Dictionary and evidence.get("summary") is Dictionary:
			var outcome := str(evidence.summary.get("outcome", ""))
			var count = evidence.summary.get("finding_count")
			if number(count): return "%d finding%s" % [int(count), "" if int(count) == 1 else "s"]
			if not outcome.is_empty(): return outcome.replace("_", " ")
		return "completed · evidence missing" if evidence == null else "completed"
	return state.replace("_", " ")

# --- per-member day ----------------------------------------------------------

static func member_day(ctx: Dictionary, kind: String) -> Dictionary:
	var info: Dictionary = member(kind)
	var now: float = float(ctx.get("now", 0.0))
	var observed: float = float(ctx.get("v2_observed_at", now)) if number(ctx.get("v2_observed_at")) and float(ctx.get("v2_observed_at")) > 0.0 else now
	var v7: Dictionary = ctx.get("v7", {})
	var v7_current: bool = bool(ctx.get("v7_current", false))
	var disconnected: bool = bool(ctx.get("v2_disconnected", true))
	var role: String = SdlcCrew.ROLES.get(kind, "")
	var own := v2_own(ctx, kind)
	var open: Array = own.filter(func(m): return str(m.get("state", "unknown")) not in V2_TERMINAL)
	var status := "idle"
	var now_text := "Nothing recorded right now"
	var next_text := "Nothing queued in the records"
	var sources: Array = []
	var silent_for := -1.0
	var last_known := false
	var mission := active_v7(v7) if not role.is_empty() else {}
	var id := mission_id(mission)
	var state := str(mission.get("state", ""))
	# V2 records first: an open record that is stale or has stopped changing wins,
	# because it is the one thing the operator must not read as healthy.
	for record in open:
		var age := observed - float(record.get("updated_at", observed)) if number(record.get("updated_at")) else -1.0
		var run_id := str(record.get("input", {}).get("id", "record"))
		if bool(record.get("stale", true)):
			status = "stale"; last_known = true
			now_text = "Last known: " + v2_activity(record) + " · " + str(record.get("state", "unknown")).replace("_", " ") + " (unconfirmed)"
			sources.append("record " + run_id + " stale · worker unavailable")
			break
		if age >= SILENT_SECONDS:
			status = "silent"; last_known = true; silent_for = age
			now_text = "Last known: " + v2_activity(record) + " (unconfirmed)"
			sources.append("record " + run_id + " " + str(record.get("state", "")) + " · last update " + clock(record.get("updated_at")) + " UTC")
			break
		if str(record.get("state", "")) == "queued":
			if status == "idle": status = "queued"
			next_text = "Queued: " + v2_activity(record)
			sources.append("record " + run_id + " queued")
			continue
		status = "working"
		now_text = sentence(v2_activity(record)) + " · " + str(record.get("state", "")).replace("_", " ")
		sources.append("record " + run_id + " " + str(record.get("state", "")))
	if status in ["idle", "queued"] and not mission.is_empty():
		var round := round_of(mission)
		var round_text := "round %d" % round if round > 0 else "round unknown"
		var assigned_role: String = SdlcCrew.ASSIGNED.get(state, "")
		sources.append("mission " + id + " " + state)
		if not v7_current:
			status = "unknown"; last_known = true
			now_text = "Last known: mission %s · %s, %s" % [short_id(id), state.replace("_", " "), round_text]
		elif assigned_role == role:
			status = "working"
			now_text = "Mission %s · %s, %s" % [short_id(id), state.replace("_", " "), round_text]
			var activity = ctx.get("activity")
			if activity != null:
				var act: Dictionary = activity.current(id, role, int(ctx.get("now_msec", 0)), bool(ctx.get("stream_live", false)))
				if bool(act.get("fresh", false)):
					now_text = "%s %s · mission %s, %s" % [act.glyph, act.text, short_id(id), round_text]
					sources.append("activity note (stream live)")
		else:
			status = "waiting"
			var holder := name_of(ROLE_KIND.get(assigned_role, "core")) if not assigned_role.is_empty() else "Core"
			now_text = "Holding mission %s while %s is %s" % [short_id(id), holder, state.replace("_", " ")]
		next_text = up_next(role, state, short_id(id), round)
	# Without a current /v2 snapshot (and, for the SDLC trio, a current /v7 one)
	# nothing here can be confirmed: say "last known" or "unknown", never idle.
	if disconnected and not (not role.is_empty() and v7_current) and status not in ["stale", "silent", "unknown"]:
		now_text = ("Last known: " + now_text) if status != "idle" else "Unknown · Core disconnected"
		status = "unknown"; last_known = true
		sources.append("/v2 snapshot not current")
	# Done in the last 24 h: terminal v2 records and SDLC missions this role served.
	var done: Array = []
	var runs := 0
	for record in own:
		var created := float(record.get("created_at", record.get("updated_at", 0))) if number(record.get("created_at", record.get("updated_at"))) else 0.0
		if created > 0.0 and now - created <= DAY_SECONDS: runs += 1
		if str(record.get("state", "")) in V2_TERMINAL and number(record.get("updated_at")) and now - float(record.updated_at) <= DAY_SECONDS:
			done.append({"at":float(record.updated_at), "text":sentence(v2_activity(record)) + " · " + v2_outcome(record)})
	if not role.is_empty():
		for item in v7_missions(v7):
			var crew: Dictionary = item.get("assigned_crew", {}) if item.get("assigned_crew") is Dictionary else {}
			if not crew.has(role): continue
			var created := float(item.get("created_at", 0)) if number(item.get("created_at")) else 0.0
			if created > 0.0 and now - created <= DAY_SECONDS: runs += 1
			var item_state := str(item.get("state", ""))
			if item_state in SdlcCrew.TERMINAL and number(item.get("updated_at")) and now - float(item.updated_at) <= DAY_SECONDS:
				done.append({"at":float(item.updated_at), "text":mission_outcome(item)})
	done.sort_custom(func(a, b): return a.at > b.at)
	var tokens := "tokens not recorded"
	if not role.is_empty():
		var activity = ctx.get("activity")
		var spent: Dictionary = activity.usage_for(id, role) if activity != null and not id.is_empty() else {}
		tokens = ("%s tokens observed this session" % LiveActivity.short_tokens(int(spent.tokens))) if int(spent.get("requests", 0)) > 0 else "no tokens observed this session"
	var shape: Dictionary = STATUS[status]
	var status_text: String = {"working":"working", "waiting":"waiting", "queued":"queued", "idle":"idle", "unknown":"unknown · last known",
		"stale":"stale · last known", "silent":"silent %s · last known" % ago(silent_for)}[status]
	return {"kind":kind, "name":info.get("name", kind), "init":info.get("init", "?"), "role":info.get("role", ""),
		"where":info.get("where", "") + (" · last known" if last_known else ""), "status":status, "glyph":shape.glyph,
		"tone":shape.tone, "color":TONES[shape.tone], "state_text":status_text, "now":now_text, "next":next_text,
		"done":done, "done_count":done.size(), "runs":runs, "tokens":tokens, "last_known":last_known,
		"silent_for":silent_for, "sources":sources, "mission":id}

static func up_next(role: String, state: String, id: String, round: int) -> String:
	var r := "round %d" % round if round > 0 else "the next round"
	match role:
		"lead":
			if state in ["queued", "investigating"]: return "Hand the mission %s plan to Rivet" % id
			return "Wait for mission %s %s to finish" % [id, r]
		"implementer":
			if state in ["queued", "investigating"]: return "Implement mission %s once Moss plans it" % id
			if state == "implementing": return "Hand %s to Core for testing" % r
			return "Revise mission %s if Prism requests changes" % id
		"reviewer":
			if state == "testing": return "Review mission %s %s" % [id, r]
			if state == "reviewing": return "Record the mission %s review" % id
			return "Review mission %s %s after Core's tests" % [id, r]
	return "Nothing queued in the records"

static func mission_outcome(mission: Dictionary) -> String:
	var id := short_id(mission_id(mission))
	var state := str(mission.get("state", "unknown"))
	var publication: Dictionary = mission.get("publication", {}) if mission.get("publication") is Dictionary else {}
	if state in ["awaiting_review", "submitted"] and number(publication.get("pr_number")):
		return "Mission %s accepted · PR #%d opened for your review" % [id, int(publication.pr_number)]
	return "Mission %s · %s" % [id, state.replace("_", " ")]

# --- needs, alerts and feed --------------------------------------------------

static func needs(ctx: Dictionary) -> Array:
	var now: float = float(ctx.get("now", 0.0))
	var v7: Dictionary = ctx.get("v7", {})
	var items: Array = []
	for mission in v7_missions(v7):
		var state := str(mission.get("state", ""))
		var id := mission_id(mission)
		var publication: Dictionary = mission.get("publication", {}) if mission.get("publication") is Dictionary else {}
		var repository := str(mission.get("repository", mission.get("input", {}).get("repository", "")))
		if state in ["awaiting_review", "submitted"] and number(publication.get("pr_number")):
			var at := float(publication.get("pr_observed_at", mission.get("updated_at", 0))) if number(publication.get("pr_observed_at", mission.get("updated_at"))) else 0.0
			var url := str(publication.get("pr_url", "")) if publication.get("pr_url") is String else ""
			var action := {"label":"Open PR", "kind":"open_url", "url":url}
			if not SafeLink.safe_pr_url(url, repository):
				action = {"label":"Open PR", "kind":"unavailable", "reason":"Not available here · no safe PR link is recorded for mission " + short_id(id)}
			items.append({"id":"pr-" + id, "at":at, "glyph":"[!]", "tone":"need", "title":"Review PR #%d on %s" % [int(publication.pr_number), repo_name(repository)],
				"detail":"Mission %s passed the gate · crew never merge%s" % [short_id(id), (" · " + ago(now - at)) if at > 0.0 else ""],
				"action":action, "source":"mission %s %s · PR #%d" % [id, state, int(publication.pr_number)],
				"say":"Mission %s opened PR #%d on %s and is waiting for your review." % [short_id(id), int(publication.pr_number), repo_name(repository)]})
		elif state in V7_PROBLEM and number(mission.get("updated_at")) and now - float(mission.updated_at) <= DAY_SECONDS:
			items.append({"id":"problem-" + id, "at":float(mission.updated_at), "glyph":"[x]", "tone":"failed", "title":"Mission %s %s" % [short_id(id), state],
				"detail":"Retry is explicit and needs a new build · " + ago(now - float(mission.updated_at)),
				"action":{"label":"Inspect", "kind":"inspect_mission", "mission":id}, "source":"mission %s %s" % [id, state],
				"say":"Mission %s is %s; a retry is explicit and needs a new build." % [short_id(id), state]})
	items.sort_custom(func(a, b): return a.at < b.at)
	var policy: Dictionary = v7.get("policy", {}) if v7.get("policy") is Dictionary else {}
	var extend := {"label":"Extend", "kind":"unavailable", "reason":"Not available here · an operator renews the policy with a new generation through POST /v7/policy (see the repository SDLC pilot guide)"}
	if number(policy.get("expires_at")):
		var left := float(policy.expires_at) - now
		var generation := " gen %d" % int(policy.generation) if number(policy.get("generation")) else ""
		if left <= 0.0:
			items.append({"id":"policy", "at":0.0, "glyph":"[x]", "tone":"failed", "title":"Publish policy%s expired" % generation,
				"detail":"Nothing new is admitted or published until it is renewed", "action":extend, "source":"policy%s expires_at" % generation,
				"say":"Our publish policy has expired, so nothing new is admitted or published."})
		elif left <= POLICY_WARN_SECONDS:
			items.append({"id":"policy", "at":0.0, "glyph":"[!]", "tone":"need", "title":"Publish policy ends in " + RealityGate.duration(left),
				"detail":"Then nothing new is admitted or published", "action":extend, "source":"policy%s expires_at" % generation,
				"say":"Our publish policy ends in %s." % RealityGate.duration(left)})
	# The memory review queue lives in /v4, which this board does not read. Say
	# so instead of showing a count that could be wrong.
	items.append({"id":"memory", "at":0.0, "glyph":"[?]", "tone":"muted", "title":"Memory notes · not in these records",
		"detail":"The review queue is in Field ops, which this board does not read", "unknown":true,
		"action":{"label":"Review in Field ops", "kind":"open_memory"}, "source":"memory review queue not read (/v4)",
		"say":"I can't see the memory review queue from these records; Field ops has it."})
	return items

static func admission(ctx: Dictionary) -> Dictionary:
	var v7: Dictionary = ctx.get("v7", {})
	var coordination: Dictionary = v7.get("coordination", {}) if v7.get("coordination") is Dictionary else {}
	var code := str(coordination.get("admission", "")) if coordination.get("admission") is String else ""
	var mission := active_v7(v7)
	return {"code":code, "known":not code.is_empty(), "current":bool(ctx.get("v7_current", false)),
		"blocked":not code.is_empty() and code != "ready", "resolution":str(coordination.get("resolution", "")) if coordination.get("resolution") is String else "",
		"mission":mission_id(mission), "state":str(mission.get("state", "")), "round":round_of(mission) if not mission.is_empty() else 0}

static func chips(ctx: Dictionary, crew: Array) -> Array:
	var result: Array = []
	var gate := admission(ctx)
	var suffix := "" if gate.current else " · last known"
	if not gate.known: result.append({"id":"admission", "glyph":"[?]", "tone":"muted", "text":"[?] Admission unknown", "question":"why_blocked"})
	elif gate.blocked: result.append({"id":"admission", "glyph":"[x]", "tone":"failed", "text":"[x] Next mission blocked: " + gate.code + suffix, "question":"why_blocked"})
	for person in crew:
		if person.status == "silent": result.append({"id":"silent-" + person.kind, "kind":person.kind, "glyph":"[/]", "tone":"failed", "text":"[/] %s silent %s" % [person.name, ago(person.silent_for)], "question":"accounted"})
		elif person.status == "stale": result.append({"id":"stale-" + person.kind, "kind":person.kind, "glyph":"[/]", "tone":"failed", "text":"[/] %s stale · worker unavailable" % person.name, "question":"accounted"})
	if bool(ctx.get("v2_disconnected", true)) and not bool(ctx.get("fixture_only", false)):
		result.append({"id":"disconnected", "glyph":"[x]", "tone":"failed", "text":"[x] Core disconnected · last known", "question":"accounted"})
	return result

static func feed(ctx: Dictionary) -> Array:
	var items: Array = []
	var seen: Dictionary = {}
	var v7: Dictionary = ctx.get("v7", {})
	var activity = ctx.get("activity")
	if activity != null:
		for entry in activity.entries:
			var line: Dictionary
			var kind := "core"
			if entry.kind == "record":
				line = activity.describe_record(entry, v7)
				var payload: Dictionary = entry.evt.get("payload", {})
				var role := str(payload.get("role", "")) if payload.get("role") is String else ""
				if str(payload.get("stage", "")) != "testing": kind = ROLE_KIND.get(role, "core")
				seen[str(entry.evt.get("record_id", "")) + "|" + str(payload.get("key", ""))] = true
			elif entry.kind == "reset":
				line = {"glyph":"[?]", "text":"Stream reset · " + str(entry.reason).replace("_", " ") + " · records refetched", "tone":"waiting"}
			else:
				line = LiveActivity.describe_note(entry.evt.payload)
				kind = ROLE_KIND.get(LiveActivity.note_role(entry.evt.payload), "core")
			items.append({"at":float(entry.at) if number(entry.get("at")) else 0.0, "kind":kind, "glyph":line.glyph, "text":strip_name(str(line.text), kind), "tone":line.tone, "source":"stream"})
	for mission in v7_missions(v7):
		var id := mission_id(mission)
		for event in mission.get("recent_events", []) if mission.get("recent_events") is Array else []:
			if not event is Dictionary or seen.has(id + "|" + str(event.get("key", ""))): continue
			var label := str(event.get("label", "")) if event.get("label") is String else ""
			var role := str(event.get("role", "")) if event.get("role") is String else ""
			var stage := str(event.get("stage", ""))
			var kind: String = "core" if stage == "testing" else ROLE_KIND.get(role, "core")
			var outcome := label.get_slice(" · ", 2) if label.get_slice_count(" · ") >= 3 else ""
			var text := stage.replace("_", " ") + (" · " + outcome if not outcome.is_empty() else "") + " · mission " + short_id(id)
			if role == "lead" and stage == "implementing": text = "handed the mission %s plan to Rivet" % short_id(id)
			elif stage == "testing": text = "graded mission %s · %s" % [short_id(id), outcome if not outcome.is_empty() else "verdict not recorded"]
			elif stage == "reviewing" and outcome == "revise": text = "requested changes on mission " + short_id(id)
			elif stage == "reviewing" and outcome == "accept": text = "accepted mission " + short_id(id)
			var tone := "failed" if outcome in ["revise", "failed", "regressed"] else ("passed" if outcome in ["accept", "improved"] else "working")
			items.append({"at":float(event.get("at", 0)) if number(event.get("at")) else 0.0, "kind":kind, "glyph":"[=]" if tone == "passed" else ("[x]" if tone == "failed" else "[/]"), "text":text, "tone":tone, "source":"recent_events"})
		if number(mission.get("created_at")):
			items.append({"at":float(mission.created_at), "kind":"core", "glyph":"[/]", "text":"admitted mission %s%s" % [short_id(id), (" under policy gen %d" % int(mission.policy_generation)) if number(mission.get("policy_generation")) else ""], "tone":"working", "source":"mission"})
		var publication: Dictionary = mission.get("publication", {}) if mission.get("publication") is Dictionary else {}
		if number(publication.get("pr_number")) and number(publication.get("pr_observed_at")):
			items.append({"at":float(publication.pr_observed_at), "kind":"core", "glyph":"[!]", "text":"opened PR #%d for mission %s · waiting for your review" % [int(publication.pr_number), short_id(id)], "tone":"waiting", "source":"publication"})
	for record in ctx.get("v2_missions", []):
		if not record is Dictionary or not number(record.get("updated_at")): continue
		var kind := StateView.context(record)
		if member(kind).is_empty(): continue
		var state := str(record.get("state", "unknown"))
		var text := (v2_activity(record) + " · " + v2_outcome(record)) if state in V2_TERMINAL else ("last record: " + v2_activity(record) + " · " + state.replace("_", " "))
		var tone := "failed" if state == "failed" else ("passed" if state == "completed" else "working")
		items.append({"at":float(record.updated_at), "kind":kind, "glyph":"[=]" if tone == "passed" else ("[x]" if tone == "failed" else "[/]"), "text":text, "tone":tone, "source":"v2 record"})
	items.sort_custom(func(a, b): return a.at > b.at)
	for item in items:
		item.time = clock(item.at)
		item.who = name_of(item.kind)
		item.color = TONES.get(item.tone, TONES.muted)
	return items

## Stream text starts with the actor's name; the feed shows the name in its own column.
static func strip_name(text: String, kind: String) -> String:
	var who := name_of(kind)
	if text.begins_with(who + " "): return text.substr(who.length() + 1)
	if kind == "core" and text.begins_with("Core "): return text.substr(5)
	return text

static func build(ctx: Dictionary) -> Dictionary:
	var crew: Array = CREW.map(func(item): return member_day(ctx, item.kind))
	var need_list := needs(ctx)
	var known := need_list.filter(func(n): return not n.get("unknown", false)).size()
	var stale := crew.filter(func(p): return p.status in ["silent", "stale", "unknown"]).size()
	var gate := admission(ctx)
	return {"crew":crew, "needs":need_list, "needs_known":known, "needs_unknown":need_list.size() - known,
		"chips":chips(ctx, crew), "feed":feed(ctx), "admission":gate, "stale_count":stale,
		"blocked_count":1 if gate.blocked else 0, "v7_current":bool(ctx.get("v7_current", false)),
		"v7_age":float(ctx.get("v7_age", -1.0)), "v2_disconnected":bool(ctx.get("v2_disconnected", true)),
		"now":float(ctx.get("now", 0.0)), "freshness":str(ctx.get("freshness", "[?] UNKNOWN"))}

static func filtered_feed(model: Dictionary, kind: String, limit: int = FEED_LIMIT) -> Array:
	var items: Array = model.get("feed", [])
	if not kind.is_empty(): items = items.filter(func(item): return item.kind == kind)
	return items.slice(0, limit)

static func person(model: Dictionary, kind: String) -> Dictionary:
	for item in model.get("crew", []):
		if item.kind == kind: return item
	return {}
