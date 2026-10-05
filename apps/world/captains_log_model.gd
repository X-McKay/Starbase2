extends RefCounted
## Captain's Log projection (page 4). Pure functions only: the view renders what
## this returns. Every event comes from an authoritative record:
##   * the full mission record from GET /v7/missions/{id} (events[], created_at,
##     publication claim, effect claims, PR observation),
##   * the bounded /v7/snapshot summary (recent_events) while the full record is
##     loading or unavailable,
##   * /v8 stream frames already received (stage records not yet in the fetched
##     record, and transient tool/sandbox notes), marked as observations.
## Nothing is inferred beyond what those records hold. Model reasoning and tool
## arguments are not stored by Core, so they are reported as "not recorded".
const LiveActivity = preload("res://live_activity.gd")
const LANES := ["lead", "implementer", "reviewer", "core"]
const LANE_ROLES := {"lead":"lead", "implementer":"implementer", "reviewer":"reviewer", "core":"grader and gate"}
const DEFAULT_CREW := {"lead":"moss", "implementer":"rivet", "reviewer":"prism"}
const TONES := {"working":"6fe3f0", "waiting":"f3c26b", "passed":"8fdc8a", "failed":"ff8a70", "muted":"aebccc", "observed":"c6a6ff"}
const TERMINAL := ["awaiting_review", "failed", "blocked", "cancelled", "completed"]
## A gap longer than this and four times the median gap is collapsed.
const MIN_COLLAPSE_SECONDS := 240.0
const NOT_RECORDED_REASONING := "Model reasoning · not recorded (Core keeps only the returned output)"
const NOT_RECORDED_TOOL_ARGS := "Tool arguments · not recorded"
const NOTE_TOOLS := ["tool_started", "tool_finished", "sandbox_boot", "sandbox_finished"]

static func number(value: Variant) -> bool:
	return value is float or value is int

static func clock(at: Variant) -> String:
	return Time.get_time_string_from_unix_time(int(at)) if number(at) else "--:--:--"

static func stamp(at: Variant) -> String:
	return Time.get_datetime_string_from_unix_time(int(at)).replace("T", " ") + " UTC" if number(at) else "time not recorded"

static func short(value: Variant, length: int = 12) -> String:
	return str(value).left(length) if value is String and not value.is_empty() else "not recorded"

static func duration(seconds: float) -> String:
	if seconds < 90.0: return "%d s" % int(round(seconds))
	if seconds < 5400.0: return "%d m" % int(round(seconds / 60.0))
	var hours := int(seconds / 3600.0)
	var minutes := int(round((seconds - hours * 3600.0) / 60.0))
	return "%d h %d m" % [hours, minutes] if minutes > 0 else "%d h" % hours

static func dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

static func crew_for(record: Dictionary, summary: Dictionary) -> Dictionary:
	var crew := {}
	var assigned = summary.get("assigned_crew")
	if assigned is Dictionary:
		for role in assigned: crew[str(role)] = str(assigned[role])
	var plan := dict(record.get("coordination"))
	if plan.get("assignments") is Array:
		for task in plan.assignments:
			if task is Dictionary and task.get("role") is String and task.get("crew") is String: crew[task.role] = task.crew
	return crew

static func lane_name(lane: String, crew: Dictionary) -> String:
	if lane == "core": return "Core"
	return str(crew.get(lane, DEFAULT_CREW.get(lane, lane))).capitalize()

static func lane_for(role: Variant) -> String:
	return str(role) if role is String and str(role) in ["lead", "implementer", "reviewer"] else "core"

## Tokens and model requests retained in member results ({"usage": {...}}).
static func add_usage(totals: Dictionary, lane: String, member: Dictionary) -> void:
	if not member.has("usage") and not member.has("elapsed_ms"): return
	var bucket: Dictionary = totals.get(lane, {"requests":0, "tokens":0, "unknown":0})
	bucket.requests += 1
	var used := dict(member.get("usage"))
	var counted := false
	for field in ["input_tokens", "output_tokens"]:
		if number(used.get(field)):
			bucket.tokens += int(used[field])
			counted = true
	if not counted: bucket.unknown += 1
	totals[lane] = bucket

static func usage_text(member: Dictionary) -> String:
	var used := dict(member.get("usage"))
	if used.is_empty(): return "Model usage · not recorded"
	var tokens := 0
	for field in ["input_tokens", "output_tokens"]:
		if number(used.get(field)): tokens += int(used[field])
	var elapsed := LiveActivity.seconds_text(member.get("elapsed_ms"))
	return "Model usage · %s tokens (%s in, %s out)%s" % [LiveActivity.short_tokens(tokens), LiveActivity.num(used.get("input_tokens")), LiveActivity.num(used.get("output_tokens")), " · " + elapsed if not elapsed.is_empty() else ""]

static func diff_stats(diff: Variant) -> Dictionary:
	if not diff is String: return {}
	var stats := {"files":0, "additions":0, "deletions":0}
	for line in str(diff).split("\n"):
		if line.begins_with("+++ "): stats.files += 1
		elif line.begins_with("--- "): pass
		elif line.begins_with("+"): stats.additions += 1
		elif line.begins_with("-"): stats.deletions += 1
	return stats

static func cases_text(run: Variant) -> String:
	var data := dict(run)
	if data.is_empty(): return "not recorded"
	if data.get("not_executed", false) or not number(data.get("exit_code")): return "not executed"
	var count: int = data.cases.size() if data.get("cases") is Array else 0
	return "%d case%s observed · exit code %s" % [count, "" if count == 1 else "s", LiveActivity.num(data.get("exit_code"))]

static func make(at: Variant, lane: String, stage: String, key: String, title: String, glyph: String, tone: String) -> Dictionary:
	return {"at":float(at) if number(at) else -1.0, "lane":lane, "stage":stage, "key":key, "title":title, "glyph":glyph,
		"tone":tone, "body":"", "evidence":[], "not_recorded":[], "source":"", "kind":"record", "order":0}

## One retained events[] entry becomes one or two timeline events.
static func describe_event(item: Dictionary, index: int, crew: Dictionary, latest_testing: int, summary: Dictionary, mission_id: String) -> Array:
	var event := dict(item.get("event"))
	var data := dict(event.get("data"))
	var stage := str(event.get("stage", "unknown"))
	var key := str(item.get("key", event.get("key", "")))
	var at = item.get("at")
	var role = data.get("role")
	var lane := lane_for(role)
	var source := "/v7/missions/%s · events[%d] · key %s" % [mission_id, index, key]
	var result: Array = []
	var e: Dictionary
	match stage:
		"investigating":
			var sources := dict(data.get("sources"))
			e = make(at, "core", stage, key, "Sources captured · %d file%s" % [sources.size(), "" if sources.size() == 1 else "s"], "[/]", "working")
			e.body = "The pinned source and a baseline sandbox observation were retained before any model request."
			e.evidence = ["Source digest · " + short(data.get("source_digest")), "Baseline · " + cases_text(data.get("baseline")), "Scope · " + str(data.get("scope", "not recorded"))]
			var paths: Array = sources.keys()
			paths.sort()
			if not paths.is_empty(): e.evidence.append("Files · " + ", ".join(paths.slice(0, 4)) + (" …" if paths.size() > 4 else ""))
		"implementing":
			var output := dict(data.get("output"))
			if role == "lead" and output.get("decision") is String:
				e = make(at, "lead", stage, key, "Plan handed to " + lane_name("implementer", crew), "[>]", "working")
				e.body = str(output.get("task", "Task not recorded"))
				e.evidence = ["Decision · " + str(output.decision), "Stated rationale · " + str(output.get("rationale", "not recorded")), usage_text(data)]
				e.not_recorded = [NOT_RECORDED_REASONING]
			elif role == "reviewer":
				var feedback := dict(data.get("feedback"))
				e = make(at, "reviewer", stage, key, "Sent back for revision", "[x]", "waiting")
				e.body = "The reviewer returned its findings to the implementer for another round."
				e.evidence = ["Review status · " + str(feedback.get("status", "not recorded")), "Core verdict then · " + str(data.get("verdict", "not recorded"))]
			elif role == "patch-validator":
				e = make(at, "core", stage, key, "Patch returned · not executed", "[x]", "failed")
				e.body = "The proposed edits could not be applied, so nothing ran. The implementer was asked to try again."
				e.evidence = ["Validation error · " + str(data.get("validation_error", "not recorded"))]
			else:
				e = make(at, lane, stage, key, "Implementing", "[>]", "working")
				e.body = "Stage record without a recognised handoff."
		"testing":
			var patch := dict(data.get("patch"))
			var stats := diff_stats(data.get("diff"))
			var invalid = data.get("validation_error")
			var round_number := int(key.get_slice("-", 1)) if key.get_slice_count("-") > 1 and key.get_slice("-", 1).is_valid_int() else 1
			if invalid is String:
				e = make(at, "implementer", stage, key + ":patch", "Patch round %d rejected · not executed" % round_number, "[x]", "failed")
				e.body = "The proposed edits did not apply to the pinned source. No candidate was run."
			elif stats.is_empty():
				e = make(at, "implementer", stage, key + ":patch", "Patch round %d · diff not recorded" % round_number, "[?]", "muted")
				e.body = "A candidate was tested but no diff was retained."
			elif stats.additions == 0 and stats.deletions == 0:
				e = make(at, "implementer", stage, key + ":patch", "Patch round %d · no change" % round_number, "[-]", "muted")
				e.body = "The retained diff is empty: the candidate equals the pinned source."
			else:
				e = make(at, "implementer", stage, key + ":patch", "Patch round %d · +%d −%d" % [round_number, stats.additions, stats.deletions], "[/]", "working")
				e.body = "Candidate patch to %d file%s, run in a disposable sandbox." % [stats.files, "" if stats.files == 1 else "s"]
			e.evidence = ["Diff · %s" % ("%d file · +%d −%d" % [stats.files, stats.additions, stats.deletions] if not stats.is_empty() else "not recorded"),
				"Candidate run · " + cases_text(data.get("candidate")), "Artifact digest · " + short(data.get("artifact_digest")),
				"Stated rationale · " + str(dict(patch.get("output")).get("rationale", "not recorded")), usage_text(patch)]
			if invalid is String: e.evidence.push_front("Validation error · " + str(invalid))
			e.not_recorded = [NOT_RECORDED_REASONING, NOT_RECORDED_TOOL_ARGS]
			e.source = source
			result.append(e)
			var grading := dict(data.get("grading"))
			var verdict = data.get("verdict", grading.get("verdict"))
			var title := "Graded round %d · %s" % [round_number, str(verdict).replace("_", " ")] if verdict is String else "Round %d grade · not recorded" % round_number
			var tone := "passed" if verdict == "improved" else ("muted" if not verdict is String else "failed")
			e = make(at, "core", stage, key + ":grade", title, "[=]" if verdict == "improved" else ("[?]" if not verdict is String else "[x]"), tone)
			e.body = "Core graded the baseline and candidate against its own oracle, outside the candidate's sandbox."
			e.evidence = ["Verdict · " + (str(verdict) if verdict is String else "not recorded"),
				"Baseline passes · " + (str(grading.baseline_pass) if grading.get("baseline_pass") is bool else "not graded"),
				"Candidate passes · " + (str(grading.candidate_pass) if grading.get("candidate_pass") is bool else "not graded")]
			var testing := dict(dict(summary.get("stage_evidence")).get("testing"))
			if index == latest_testing and not testing.is_empty():
				var candidate := LiveActivity.case_ratio(testing.get("candidate_cases"))
				var baseline := LiveActivity.case_ratio(testing.get("baseline_cases"))
				e.evidence.append("Cases · candidate %s · baseline %s" % [candidate if not candidate.is_empty() else "not recorded", baseline if not baseline.is_empty() else "not recorded"])
				var failed: Array = dict(testing.get("candidate_cases")).get("failed", []) if dict(testing.get("candidate_cases")).get("failed") is Array else []
				if not failed.is_empty(): e.evidence.append("Candidate failed · " + ", ".join(failed))
			else:
				e.evidence.append("Per-case results · retained only for the current round")
		"reviewing":
			var status := str(data.get("status", dict(data.get("output")).get("status", "")))
			var findings = data.get("findings")
			var count_text := ("%d finding%s" % [findings.size(), "" if findings.size() == 1 else "s"]) if findings is Array else "findings not reported"
			if role == "patch-validator":
				e = make(at, "core", stage, key, "Validator · revise · nothing ran", "[x]", "failed")
				e.body = str(data.get("rationale", "No candidate was executed."))
				e.evidence = ["Validation error · " + str(data.get("validation_error", "not recorded"))]
			else:
				match status:
					"accept":
						e = make(at, "reviewer", stage, key, "Review accepted · " + count_text, "[=]", "passed")
					"revise":
						e = make(at, "reviewer", stage, key, "Changes requested · " + count_text, "[x]", "waiting")
					"abstain":
						e = make(at, "reviewer", stage, key, "Reviewer abstained", "[?]", "muted")
					_:
						e = make(at, "reviewer", stage, key, "Review · status not recorded", "[?]", "muted")
				e.body = str(data.get("rationale", "Rationale not recorded"))
				e.evidence = []
				if findings is Array:
					for finding in findings.slice(0, 8):
						var f := dict(finding)
						e.evidence.append("Finding · %s:%s · %s%s" % [str(f.get("path", "path not recorded")), LiveActivity.num(f.get("line")), str(f.get("problem", "problem not recorded")), " · evidence: " + str(f.evidence) if f.get("evidence") is String else ""])
					if findings.is_empty(): e.evidence.append("Findings · none reported")
				else: e.evidence.append("Findings · not reported")
				e.evidence.append("Missing evidence · " + (str(data.missing_evidence) if data.get("missing_evidence") is String else "none noted"))
				e.evidence.append(usage_text(data))
				e.not_recorded = [NOT_RECORDED_REASONING]
		"ready_to_publish":
			e = make(at, "core", stage, key, "Gates passed · ready to publish", "[=]", "passed")
			e.body = "Core accepted the stage only after an improved verdict and an accepting review."
		"publishing":
			var kind := key.trim_prefix("published-")
			var titles := {"branch":"Branch pushed", "pr":"PR opened", "review":"Review comment posted"}
			e = make(at, "core", stage, key, str(titles.get(kind, "Publication receipt · " + kind)) + (" #" + LiveActivity.num(data.get("number")) if number(data.get("number")) else ""), "[/]", "working")
			e.body = "Provider receipt retained after a one-shot effect claim."
			for field in ["branch", "number", "url", "head", "review_id"]:
				if data.has(field): e.evidence.append(field.capitalize() + " · " + (LiveActivity.num(data[field]) if number(data[field]) else str(data[field])))
		"submitted":
			e = make(at, "core", stage, key, "PR #%s submitted" % LiveActivity.num(data.get("number")), "[=]", "passed")
			e.body = "The pull request exists. This is not a merge, a production verification or an XP award."
			e.evidence = ["URL · " + str(data.get("url", "not recorded")), "Head · " + short(data.get("head"))]
		"awaiting_review":
			var ci := dict(data.get("ci"))
			e = make(at, "core", stage, key, "Awaiting human review", "[-]", "waiting")
			e.body = str(data.get("status", "Human merge decision remains."))
			e.evidence = ["CI · " + str(ci.get("status", "not recorded")) + (" · coverage " + str(ci.coverage) if ci.has("coverage") else ""), "Verified merge · " + str(data.get("verified_merge", "not recorded")), "XP awarded · " + LiveActivity.num(data.get("xp_awarded"), "not recorded")]
		"blocked", "failed", "cancelled":
			var output := dict(data.get("output"))
			var title := stage.capitalize()
			if output.get("decision") == "abstain": title = "Lead abstained · mission blocked"
			elif output.get("status") == "abstain": title = "Implementer abstained · mission blocked"
			elif data.get("error_type") is String: title = "Model request failed · " + str(data.error_type)
			elif data.get("status") is String: title = stage.capitalize() + " · review " + str(data.status)
			elif data.get("reason") is String: title = stage.capitalize() + " · bounded activity ended"
			e = make(at, lane, stage, key, title, "[x]" if stage != "cancelled" else "[_]", "failed")
			e.body = str(data.get("reason", output.get("rationale", data.get("rationale", "Reason not recorded"))))
			if data.has("external_effect_may_have_started"): e.evidence.append("External effect may have started · " + str(data.external_effect_may_have_started))
			if data.has("usage") or data.has("elapsed_ms"): e.evidence.append(usage_text(data))
			if data.get("response_excerpt") is String: e.evidence.append("Response excerpt · retained in the full record (" + str(str(data.response_excerpt).length()) + " characters)")
		_:
			e = make(at, lane, stage, key, stage.replace("_", " ").capitalize(), "[/]", "muted")
			e.body = "Stage record."
	e.source = source
	result.append(e)
	return result

## Record-level facts with their own retained timestamps.
static func record_facts(record: Dictionary, mission_id: String) -> Array:
	var facts: Array = []
	var input := dict(record.get("input"))
	if number(record.get("created_at")):
		var e := make(record.created_at, "core", "queued", "admission", "Mission admitted", "[/]", "passed")
		e.body = "Core admitted the mission and froze its source, build and policy generation."
		e.evidence = ["Repository · " + str(input.get("repository", "not recorded")), "Opportunity · " + str(input.get("opportunity", "not recorded")),
			"Pinned revision · " + short(input.get("revision")), "Policy generation · " + LiveActivity.num(record.get("policy_generation"), "not recorded"),
			"Retry of · " + (str(record.retry_of) if record.get("retry_of") is String else "none")]
		e.source = "/v7/missions/%s · created_at" % mission_id
		facts.append(e)
	var claim := dict(record.get("publication"))
	if number(claim.get("claimed_at")):
		var e := make(claim.claimed_at, "core", "publishing", "publication-claim", "Publication authority claimed", "[>]", "working")
		e.body = str(claim.get("authority", "Authority not recorded"))
		e.evidence = ["Branch · " + str(claim.get("branch", "not recorded")), "Policy generation · " + LiveActivity.num(claim.get("policy_generation"), "not recorded")]
		var kinds: Array = []
		for effect in (record.effects if record.get("effects") is Array else []):
			kinds.append(str(dict(dict(effect).get("input")).get("kind", "?")))
		e.evidence.append("Effect claims · " + (", ".join(kinds) if not kinds.is_empty() else "none"))
		e.source = "/v7/missions/%s · publication.claimed_at" % mission_id
		facts.append(e)
	var observed := dict(record.get("pr_observation"))
	if number(observed.get("observed_at")):
		var e := make(observed.observed_at, "core", "awaiting_review", "pr-observation", "PR #%s observed · %s" % [LiveActivity.num(observed.get("number")), str(observed.get("state", "unknown"))], "[/]", "working")
		e.body = "Read-only provider checkpoint. It does not mean Starbase merged anything."
		e.evidence = ["Head · " + short(observed.get("head"))]
		e.source = "/v7/missions/%s · pr_observation" % mission_id
		facts.append(e)
	return facts

## Stream frames already received for this mission that the fetched record
## does not hold yet, and transient tool/sandbox notes.
static func stream_events(entries: Array, mission_id: String, record_keys: Dictionary, record: Dictionary) -> Array:
	var shown: Array = []
	for entry in entries:
		if not entry is Dictionary: continue
		var evt := dict(entry.get("evt"))
		if str(evt.get("record_id", "")) != mission_id: continue
		var payload := dict(evt.get("payload"))
		var type := str(evt.get("type", ""))
		var at = evt.get("at")
		if entry.get("kind") == "note":
			if not str(payload.get("kind", "")) in NOTE_TOOLS: continue
			var line := LiveActivity.describe_note(payload)
			var e := make(at, lane_for(payload.get("role")), str(payload.get("state", "")), "note:" + str(entry.get("key", "")), str(line.text), str(line.glyph), "observed")
			e.kind = "observation"
			e.body = "Live activity note from the /v8 stream. Notes are observations, not evidence: Core does not retain them and they are not replayed after a reconnect."
			e.evidence = ["Note · " + str(payload.get("kind", "")).replace("_", " ") + (" · " + str(payload.tool) if payload.get("tool") is String else "") + (" · " + str(payload.label) if payload.get("label") is String else ""),
				"Outcome · " + ("ok" if payload.get("ok") == true else ("failed" + (" · " + str(payload.error) if payload.get("error") is String else "") if payload.get("ok") == false else "in progress"))]
			var elapsed := LiveActivity.seconds_text(payload.get("elapsed_ms"))
			if not elapsed.is_empty(): e.evidence.append("Elapsed · " + elapsed)
			e.not_recorded = [NOT_RECORDED_TOOL_ARGS, "Tool output · not recorded in notes"]
			e.source = "/v8 stream · mission.activity (transient)"
			shown.append(e)
		elif type == "mission.stage" and not record_keys.has(str(payload.get("key", ""))):
			var e := make(at, lane_for(payload.get("role")), str(payload.get("stage", "")), "stream:" + str(payload.get("key", "")), str(payload.get("label", payload.get("stage", "stage"))).capitalize(), "[~]", "observed")
			e.kind = "provisional"
			e.body = "Announced on the /v8 stream. The full record has not been reread yet, so its evidence is not shown."
			e.evidence = ["Stream id · " + str(evt.get("id", "")), "Record key · " + str(payload.get("key", ""))]
			e.source = "/v8 stream · mission.stage · awaiting /v7/missions/" + mission_id
			shown.append(e)
		elif type == "mission.publication" and dict(record.get("publication")).is_empty():
			var e := make(at, "core", "publishing", "stream:publication", "Publication claimed", "[~]", "observed")
			e.kind = "provisional"
			e.body = "Announced on the /v8 stream; awaiting the full record."
			e.evidence = ["Branch · " + str(payload.get("branch", "not reported"))]
			e.source = "/v8 stream · mission.publication"
			shown.append(e)
		elif type == "mission.cancel_requested":
			var e := make(at, "core", "cancel_requested", "stream:cancel", "Stop requested", "[_]", "waiting")
			e.kind = "observation"
			e.body = "Core keeps the stop flag but not its time; this time comes from the stream. Already-started effects may still complete."
			e.source = "/v8 stream · mission.cancel_requested"
			shown.append(e)
	return shown

## Bounded fallback: the last three events from the /v7 snapshot summary.
static func summary_events(summary: Dictionary, mission_id: String) -> Array:
	var shown: Array = []
	if number(summary.get("created_at")):
		var e := make(summary.created_at, "core", "queued", "admission", "Mission admitted", "[/]", "passed")
		e.body = "From the bounded /v7 snapshot summary."
		e.source = "/v7/snapshot · " + mission_id + " · created_at"
		shown.append(e)
	var recent: Array = summary.get("recent_events", []) if summary.get("recent_events") is Array else []
	for item in recent:
		var event := dict(item)
		var e := make(event.get("at"), lane_for(event.get("role")), str(event.get("stage", "")), str(event.get("key", "")), str(event.get("label", event.get("stage", ""))).capitalize(), "[/]", "muted")
		e.kind = "summary"
		e.body = "Summary only. The full evidence for this event is on /v7/missions/%s, which has not been read." % mission_id
		e.source = "/v7/snapshot · recent_events · key " + str(event.get("key", ""))
		shown.append(e)
	return shown

static func median(values: Array) -> float:
	if values.is_empty(): return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])

## Piecewise time axis: quiet gaps longer than the threshold get a fixed width.
static func build_axis(times: Array, start: float, end: float) -> Dictionary:
	var points: Array = [start]
	for t in times:
		if t >= start and t <= end: points.append(t)
	points.append(end)
	points.sort()
	var unique: Array = []
	for t in points:
		if unique.is_empty() or t - float(unique[-1]) > 0.001: unique.append(t)
	if unique.size() < 2: unique = [start, start + 60.0]
	var gaps: Array = []
	for i in unique.size() - 1: gaps.append(float(unique[i + 1]) - float(unique[i]))
	var threshold := maxf(MIN_COLLAPSE_SECONDS, median(gaps) * 4.0)
	var active := 0.0
	for g in gaps:
		if g <= threshold: active += g
	var collapsed_weight := maxf(active * 0.07, 1.0)
	var weights: Array = []
	var total := 0.0
	for g in gaps:
		var w: float = collapsed_weight if g > threshold else g
		weights.append(w)
		total += w
	var pad := total * 0.035
	total += pad * 2.0
	var segments: Array = []
	var cursor := pad
	for i in gaps.size():
		segments.append({"t0":float(unique[i]), "t1":float(unique[i + 1]), "collapsed":gaps[i] > threshold,
			"f0":cursor / total, "f1":(cursor + weights[i]) / total})
		cursor += weights[i]
	return {"start":float(unique[0]), "end":float(unique[-1]), "segments":segments, "threshold":threshold, "pad":pad / total}

static func position(axis: Dictionary, t: float) -> float:
	var segments: Array = axis.get("segments", [])
	if segments.is_empty(): return 0.5
	if t <= segments[0].t0: return segments[0].f0
	for s in segments:
		if t <= s.t1:
			if s.collapsed:
				# Inside a collapsed gap only the ends are meaningful.
				return s.f0 if t - s.t0 < s.t1 - t else s.f1
			var span: float = s.t1 - s.t0
			return s.f0 + (s.f1 - s.f0) * ((t - s.t0) / span if span > 0.0 else 0.0)
	return segments[-1].f1

static func ticks(axis: Dictionary) -> Array:
	var result: Array = []
	var active := 0.0
	for s in axis.segments:
		if not s.collapsed: active += s.t1 - s.t0
	var step := 60.0
	for candidate in [60.0, 120.0, 300.0, 600.0, 900.0, 1800.0, 3600.0, 7200.0, 21600.0, 43200.0, 86400.0]:
		step = candidate
		if active / candidate <= 6.0: break
	for s in axis.segments:
		if s.collapsed:
			result.append({"f":(s.f0 + s.f1) * 0.5, "label":"≈ " + duration(s.t1 - s.t0) + " quiet", "gap":true, "f0":s.f0, "f1":s.f1})
			continue
		var t := ceilf(s.t0 / step) * step
		while t <= s.t1:
			result.append({"f":position(axis, t), "label":Time.get_time_string_from_unix_time(int(t)).left(5), "gap":false})
			t += step
	return result

static func state_bands(record_events: Array, created_at: Variant, end: float) -> Array:
	var bands: Array = []
	var marks: Array = []
	if number(created_at): marks.append({"at":float(created_at), "state":"queued"})
	for item in record_events:
		var event := dict(dict(item).get("event"))
		if number(dict(item).get("at")) and event.get("stage") is String: marks.append({"at":float(item.at), "state":str(event.stage)})
	for i in marks.size():
		var t1: float = float(marks[i + 1].at) if i + 1 < marks.size() else end
		if t1 > float(marks[i].at): bands.append({"t0":float(marks[i].at), "t1":t1, "state":str(marks[i].state)})
	return bands

## options: now (unix seconds), record_state, freshness_text, coordination, snapshot_known
static func build(record: Dictionary, summary: Dictionary, entries: Array, options: Dictionary) -> Dictionary:
	var now: float = float(options.get("now", Time.get_unix_time_from_system()))
	var mission_id := str(summary.get("id", record.get("id", "")))
	var full := not record.is_empty() and str(record.get("id", "")) == mission_id and record.get("events") is Array
	var source: Dictionary = record if full else summary
	var crew := crew_for(record if full else {}, summary)
	var events: Array = []
	var record_keys := {}
	var totals := {}
	if full:
		var latest_testing := -1
		for i in record.events.size():
			if dict(dict(record.events[i]).get("event")).get("stage") == "testing": latest_testing = i
		for i in record.events.size():
			var item := dict(record.events[i])
			record_keys[str(item.get("key", ""))] = true
			for e in describe_event(item, i, crew, latest_testing, summary, mission_id):
				e.order = i * 2 + (1 if str(e.key).ends_with(":grade") else 0)
				events.append(e)
			var data := dict(dict(item.get("event")).get("data"))
			var lane := lane_for(data.get("role"))
			if data.has("usage") or (data.has("elapsed_ms") and data.has("role")): add_usage(totals, lane, data)
			if dict(data.get("patch")).has("usage"): add_usage(totals, "implementer", dict(data.patch))
		for fact in record_facts(record, mission_id):
			fact.order = -1
			events.append(fact)
	elif not summary.is_empty():
		events = summary_events(summary, mission_id)
		for e in events:
			if e.key != "admission": record_keys[str(e.key)] = true
	if not mission_id.is_empty():
		for e in stream_events(entries, mission_id, record_keys, record if full else {}):
			e.order = 100000
			events.append(e)
	events = events.filter(func(e): return float(e.at) >= 0.0)
	events.sort_custom(func(a, b): return a.at < b.at if a.at != b.at else a.order < b.order)
	for i in events.size():
		events[i].n = i + 1
		events[i].who = lane_name(events[i].lane, crew) + " · " + str(LANE_ROLES[events[i].lane])
	var state := str(source.get("state", "unknown"))
	var terminal := state in TERMINAL
	var times: Array = events.map(func(e): return float(e.at))
	var created = source.get("created_at")
	var start: float = float(created) if number(created) else (float(times.min()) if not times.is_empty() else now - 60.0)
	if not times.is_empty(): start = minf(start, float(times.min()))
	var last: float = float(times.max()) if not times.is_empty() else start
	var end: float = last if terminal else maxf(last, now)
	var axis := build_axis(times, start, end)
	var bands: Array = state_bands(record.events if full else [], created, end) if full else []
	for e in events: e.f = position(axis, float(e.at))
	for band in bands:
		band.f0 = position(axis, band.t0)
		band.f1 = position(axis, band.t1)
	var lanes: Array = []
	var token_total := 0
	var unknown_total := 0
	var max_tokens := 1
	for lane in LANES:
		var bucket: Dictionary = totals.get(lane, {"requests":0, "tokens":0, "unknown":0})
		max_tokens = maxi(max_tokens, int(bucket.tokens))
	for lane in LANES:
		var bucket: Dictionary = totals.get(lane, {"requests":0, "tokens":0, "unknown":0})
		token_total += int(bucket.tokens)
		unknown_total += int(bucket.unknown)
		var text := ""
		if lane == "core": text = "no model use · grades and gates"
		elif not full: text = "unknown · full record not read"
		elif int(bucket.requests) == 0: text = "no model requests recorded"
		else:
			text = "%s tokens · %d request%s" % [LiveActivity.short_tokens(int(bucket.tokens)), int(bucket.requests), "" if int(bucket.requests) == 1 else "s"]
			if int(bucket.unknown) > 0: text = "≥" + text + " · %d usage not recorded" % int(bucket.unknown)
		lanes.append({"id":lane, "name":lane_name(lane, crew), "role":str(LANE_ROLES[lane]), "tokens":int(bucket.tokens), "fraction":float(bucket.tokens) / float(max_tokens), "tokens_text":text})
	var input := dict(source.get("input"))
	var objective = summary.get("objective", dict(record.get("capability")).get("objective") if full else null)
	var round_value = summary.get("revision_count", record.get("revision_loops") if full else null)
	var meta: Array = [str(input.get("repository", summary.get("repository", "repository not recorded"))),
		"admitted " + (clock(created).left(5) + " UTC" if number(created) else "time not recorded"),
		"now " + state.replace("_", " ") + (" round %d" % (int(round_value) + 1) if number(round_value) else ""),
		(("≥" if unknown_total > 0 else "") + LiveActivity.short_tokens(token_total) + " tokens retained") if full else "tokens unknown",
		"cost not recorded"]
	return {"mission_id":mission_id, "full":full, "state":state, "terminal":terminal,
		"title":("Mission " + mission_id.trim_prefix("sdlc-") + " · " + (str(objective) if objective is String else "objective not recorded")) if not mission_id.is_empty() else "No mission",
		"meta":" · ".join(meta), "events":events, "lanes":lanes, "axis":axis, "ticks":ticks(axis), "bands":bands,
		"now_f":position(axis, now) if not terminal and now <= end + 0.001 else -1.0, "now":now,
		"status":status_lines(full, summary, record, options)}

## Header status lines. Unknown, loading, stale, failed and no-change stay distinct.
static func status_lines(full: bool, summary: Dictionary, record: Dictionary, options: Dictionary) -> Array:
	var lines: Array = []
	var freshness := str(options.get("freshness_text", ""))
	if not freshness.is_empty(): lines.append({"glyph":"", "text":freshness, "tone":str(options.get("freshness_tone", "muted"))})
	var state := str(options.get("record_state", "unknown"))
	var age = options.get("record_age")
	var age_text := (" · read " + preload("res://freshness.gd").age_text(float(age)) + " ago") if number(age) and float(age) >= 0.0 else ""
	if summary.is_empty():
		if options.get("snapshot_known", false): lines.append({"glyph":"[-]", "text":"No V7 mission recorded · nothing to show", "tone":"muted"})
		else: lines.append({"glyph":"[?]", "text":"UNKNOWN · no /v7 snapshot received", "tone":"failed"})
		return lines
	match state:
		"live": lines.append({"glyph":"[=]", "text":"Full record%s · %d retained events" % [age_text, dict(record).get("events", []).size()], "tone":"passed"})
		"fixture": lines.append({"glyph":"[=]", "text":"Synthetic fixture record · %d retained events" % dict(record).get("events", []).size(), "tone":"muted"})
		"stale": lines.append({"glyph":"[?]", "text":"LAST KNOWN · /v7 snapshot older than 15 s" + age_text, "tone":"failed"})
		"failed": lines.append({"glyph":"[x]", "text":("Record read failed · showing last known record" + age_text) if full else "Record read failed · showing the bounded summary", "tone":"failed"})
		"loading": lines.append({"glyph":"[-]", "text":"Reading full record · showing the bounded summary", "tone":"waiting"})
		_: lines.append({"glyph":"[?]", "text":"Record state unknown", "tone":"muted"})
	if full and number(summary.get("event_count")) and int(summary.event_count) != dict(record).get("events", []).size():
		lines.append({"glyph":"[?]", "text":"Summary reports %d events; record holds %d · rereading" % [int(summary.event_count), dict(record).get("events", []).size()], "tone":"waiting"})
	var coordination := dict(options.get("coordination"))
	if coordination.get("admission") is String:
		var admission := str(coordination.admission)
		lines.append({"glyph":"[=]" if admission == "ready" else "[-]", "text":"Admission now · " + admission.replace("_", " ") + " (current Core state, not a timeline event)", "tone":"passed" if admission == "ready" else "waiting"})
	return lines

## Neighbour selection for keyboard travel between lanes: the event in the
## adjacent lane nearest in time to the current one.
static func neighbour_in_lane(events: Array, current: int, direction: int) -> int:
	if current < 0 or current >= events.size(): return 0 if not events.is_empty() else -1
	var lane_index := LANES.find(str(events[current].lane))
	var target := lane_index + direction
	while target >= 0 and target < LANES.size():
		var best := -1
		var best_gap := INF
		for i in events.size():
			if events[i].lane != LANES[target]: continue
			var gap := absf(float(events[i].f) - float(events[current].f))
			if gap < best_gap:
				best_gap = gap
				best = i
		if best >= 0: return best
		target += direction
	return current

## One line per event for the chronological list (the non-spatial equivalent).
static func list_line(e: Dictionary) -> String:
	var tag := " · observed, not retained" if e.kind == "observation" else (" · streamed, awaiting record" if e.kind == "provisional" else (" · summary only" if e.kind == "summary" else ""))
	return "%d. %s UTC · %s · %s %s%s" % [int(e.n), clock(e.at), str(e.who).get_slice(" · ", 0), str(e.glyph), str(e.title), tag]
