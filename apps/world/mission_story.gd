extends RefCounted
## Reads one retained V7 mission record (GET /v7/missions/{id}) as a story of
## rounds: the lead plan, each implementation's diff, tests, receipts and spend,
## each review's findings and the implementer's recorded reply. Pure projection;
## missing values stay missing. Model reasoning and tool arguments are not part
## of the record (ADR 0015 is proposed, not implemented), so nothing here can
## produce them.
const CREW_NAMES := {"moss":"Moss", "rivet":"Rivet", "prism":"Prism", "mae":"Mae", "wes":"Wes"}
const ROLE_CREW := {"lead":"moss", "implementer":"rivet", "reviewer":"prism"}
const DIFF_LIMIT := 60

static func dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

static func arr(value: Variant) -> Array:
	return value if value is Array else []

static func is_number(value: Variant) -> bool:
	return value is float or value is int

static func full(record: Dictionary) -> bool:
	return record.get("events") is Array and record.get("evidence") is Dictionary

## Rounds follow Core: a reviewing -> implementing transition starts the next round.
static func parse(record: Dictionary) -> Dictionary:
	var story := {"full":full(record), "events":[], "rounds":{}, "lead":{}, "state":str(record.get("state", "unknown")),
		"max_rounds":0, "revision_loops":int(record.get("revision_loops", 0)) if is_number(record.get("revision_loops")) else 0,
		"assignments":{}, "reassignments":arr(dict(record.get("coordination")).get("reassignments"))}
	var coordination := dict(record.get("coordination"))
	if is_number(coordination.get("max_rounds")): story.max_rounds = int(coordination.max_rounds)
	elif is_number(dict(dict(record.get("capability")).get("limits")).get("max_rounds")): story.max_rounds = int(record.capability.limits.max_rounds)
	for task in arr(coordination.get("assignments")):
		if task is Dictionary and task.get("role") is String: story.assignments[task.role] = task
	if not story.full: return story
	var round := 1
	var previous := ""
	for item in record.events:
		if not item is Dictionary: continue
		var event := dict(item.get("event"))
		var stage := str(event.get("stage", ""))
		var data := dict(event.get("data"))
		if stage == "implementing" and previous == "reviewing": round += 1
		previous = stage
		var entry := {"key":str(item.get("key", event.get("key", ""))), "stage":stage, "at":item.get("at"), "data":data, "round":round}
		story.events.append(entry)
		var slot: Dictionary = story.rounds.get(round, {"round":round})
		match stage:
			"implementing":
				if str(data.get("role", "")) == "lead" and dict(data.get("output")).has("decision"): story.lead = entry
				elif round > 1 and not slot.has("revise"): slot.revise = entry
			"testing": slot.testing = entry
			"reviewing": slot.review = entry
			"blocked", "failed", "cancelled": slot.stop = entry
			"ready_to_publish": slot.ready = entry
		story.rounds[round] = slot
	return story

static func current_round(story: Dictionary, summary: Dictionary) -> int:
	if is_number(summary.get("revision_count")): return int(summary.revision_count) + 1
	return int(story.get("revision_loops", 0)) + 1

## Crew for a role from the retained plan (reassignments already applied by Core).
static func crew_for(story: Dictionary, summary: Dictionary, role: String) -> String:
	var task := dict(dict(story.get("assignments")).get(role))
	if task.get("crew") is String: return str(task.crew)
	var crew := dict(summary.get("assigned_crew"))
	if crew.get(role) is String: return str(crew[role])
	return str(ROLE_CREW.get(role, ""))

static func crew_name(crew: String) -> String:
	return str(CREW_NAMES.get(crew, crew.capitalize() if not crew.is_empty() else "Unassigned"))

static func latest(story: Dictionary, slot_key: String, at_or_before: int = 1000) -> Dictionary:
	var rounds: Dictionary = story.get("rounds", {})
	var keys := rounds.keys()
	keys.sort()
	keys.reverse()
	for round in keys:
		if int(round) <= at_or_before and dict(rounds[round]).has(slot_key): return rounds[round][slot_key]
	return {}

## The member result a role recorded in a round: lead output, implementer patch, reviewer review.
static func member_entry(story: Dictionary, role: String, round: int) -> Dictionary:
	match role:
		"lead": return dict(story.get("lead"))
		"implementer":
			var testing := dict(dict(dict(story.get("rounds")).get(round)).get("testing"))
			if testing.is_empty(): return {}
			return {"key":testing.key, "at":testing.at, "round":round, "data":dict(testing.data.get("patch"))}
		"reviewer": return dict(dict(dict(story.get("rounds")).get(round)).get("review"))
	return {}

static func receipts(member: Dictionary) -> Array:
	var shown: Array = []
	for item in arr(member.get("tools")):
		if not item is Dictionary: continue
		shown.append({"tool":str(item.get("tool", "unknown tool")), "ok":item.get("ok"), "seconds":item.get("elapsed_seconds"),
			"sequence":item.get("sequence"), "cached":item.get("cached") == true, "digest":str(item.get("input_digest", ""))})
	return shown

## Recorded spend for one member result. Unknown stays unknown (null), never zero.
static func spend(member: Dictionary) -> Dictionary:
	if member.is_empty(): return {}
	var usage := dict(member.get("usage"))
	var requests: Variant = null
	if member.get("model_requests") is Array: requests = member.model_requests.size()
	elif is_number(member.get("model_requests")): requests = int(member.model_requests)
	return {"requests":requests, "input":usage.get("input_tokens") if is_number(usage.get("input_tokens")) else null,
		"output":usage.get("output_tokens") if is_number(usage.get("output_tokens")) else null,
		"complete":member.get("usage_complete") == true, "elapsed_ms":member.get("elapsed_ms") if is_number(member.get("elapsed_ms")) else null}

## Unified diff -> display rows. An empty string is a recorded no-change diff.
static func diff_rows(diff: String, limit: int = DIFF_LIMIT) -> Dictionary:
	var rows: Array = []
	var files: Array = []
	var additions := 0
	var deletions := 0
	var lines := diff.split("\n")
	if lines.size() > 0 and lines[lines.size() - 1].is_empty(): lines.remove_at(lines.size() - 1)
	for line in lines:
		var kind := "context"
		if line.begins_with("+++ "):
			files.append(line.trim_prefix("+++ ").strip_edges())
			continue
		if line.begins_with("--- "): continue
		if line.begins_with("@@"): kind = "hunk"
		elif line.begins_with("+"):
			kind = "add"; additions += 1
		elif line.begins_with("-"):
			kind = "delete"; deletions += 1
		rows.append({"text":line, "kind":kind})
	var hidden := maxi(0, rows.size() - limit)
	return {"rows":rows.slice(0, limit), "hidden":hidden, "files":files, "additions":additions, "deletions":deletions}

static func short_digest(value: String) -> String:
	return value.left(8) if value.length() >= 8 else (value if not value.is_empty() else "none")

static func findings(review: Dictionary) -> Variant:
	var data := dict(review.get("data"))
	var listed: Variant = data.get("findings", dict(data.get("output")).get("findings"))
	return listed if listed is Array else null

static func review_status(review: Dictionary) -> String:
	var data := dict(review.get("data"))
	if str(data.get("role", "")) == "patch-validator": return "rejected"
	var status: Variant = data.get("status", dict(data.get("output")).get("status"))
	return str(status) if status is String else ""

## One stage track: plan -> implement -> test -> review -> revise loop -> accept/PR.
## status: done | current | changes | failed | blocked | pending | unknown.
## verdicts maps a testing event key to a Core verdict seen on the stream.
static func track(story: Dictionary, summary: Dictionary, verdicts: Dictionary = {}) -> Array:
	var state := str(summary.get("state", story.get("state", "unknown")))
	var round := current_round(story, summary)
	var items: Array = []
	var stopped := state in ["blocked", "failed", "cancelled", "cancel_requested"]
	var plan_done := state not in ["queued", "investigating", "unknown"]
	items.append({"text":"plan", "status":"done" if plan_done else ("current" if state in ["queued", "investigating"] else "unknown"), "round":0})
	var testing_now := dict(dict(summary.get("stage_evidence")).get("testing"))
	for r in range(1, round + 1):
		var slot := dict(dict(story.get("rounds")).get(r))
		var known: bool = bool(story.get("full", false)) or r == round
		if not known:
			if r == 1: items.append({"text":"rounds 1–%d · full record not loaded" % (round - 1), "status":"unknown", "round":r})
			continue
		var last := r == round
		var implement := "done" if slot.has("testing") else ("current" if last and state == "implementing" else ("pending" if last else "unknown"))
		if last and not story.get("full", false): implement = "done" if state in ["testing", "reviewing", "ready_to_publish", "publishing", "submitted", "awaiting_review"] else implement
		items.append({"text":"implement r%d" % r, "status":implement, "round":r})
		var verdict: Variant = null
		if last and testing_now.get("verdict") is String: verdict = testing_now.verdict
		elif slot.has("testing") and verdicts.get(str(slot.testing.key)) is String: verdict = verdicts[str(slot.testing.key)]
		var tested: bool = slot.has("testing") or (last and not bool(story.get("full", false)) and implement == "done")
		var test_text := "test r%d" % r
		var test_status := "pending"
		if tested:
			if verdict is String:
				test_text += " · " + str(verdict).replace("_", " ")
				test_status = "done" if verdict == "improved" else "failed"
			else:
				test_text += " · verdict not retained"
				test_status = "unknown"
		items.append({"text":test_text, "status":test_status, "round":r})
		var rstatus := ""
		if slot.has("review"): rstatus = review_status(slot.review)
		elif last and dict(dict(summary.get("stage_evidence")).get("reviewing")).get("status") is String: rstatus = str(summary.stage_evidence.reviewing.status)
		var review := {"text":"review r%d" % r, "status":"pending", "round":r}
		match rstatus:
			"accept": review = {"text":"review r%d · accepted" % r, "status":"done", "round":r}
			"revise": review = {"text":"review r%d · changes" % r, "status":"changes", "round":r}
			"rejected": review = {"text":"review r%d · patch rejected" % r, "status":"changes", "round":r}
			"abstain": review = {"text":"review r%d · abstained" % r, "status":"unknown", "round":r}
			_:
				if last and state == "testing": review.status = "current"
		items.append(review)
		if r < round: items.append({"text":"↺ round %d → %d" % [r, r + 1], "status":"loop", "round":r})
	var ahead := {"ready_to_publish":1, "publishing":2, "submitted":3, "awaiting_review":3}
	var at: int = ahead.get(state, 0)
	for step in [["ready to publish", 1], ["Reality Gate · branch + PR", 2], ["awaiting human review", 3]]:
		var status := "pending"
		if at > step[1]: status = "done"
		elif at == step[1]: status = "current"
		items.append({"text":step[0], "status":status, "round":0})
	if stopped: items.append({"text":state.replace("_", " "), "status":"blocked" if state != "failed" else "failed", "round":round})
	return items
