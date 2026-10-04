extends RefCounted
## Reality Gate: what Core requires before an SDLC mission may publish, projected
## from the /v7 snapshot policy, coordination and the mission's stage evidence.
## Presentation only. Core re-checks authority before every effect; missing
## evidence is never shown as passed.
const NOTE := "Opens only for: create branch and pull request. Never merges."
const GLYPHS := {"passed":"[=]", "missing":"[?]", "failed":"[x]"}
const COLORS := {"passed":"8fdc8a", "missing":"f3c26b", "failed":"ff8a70"}

static func duration(seconds: float) -> String:
	var total := int(seconds)
	if total >= 86400: return "%dd %dh" % [total / 86400, (total % 86400) / 3600]
	if total >= 3600: return "%dh %dm" % [total / 3600, (total % 3600) / 60]
	if total >= 60: return "%dm" % (total / 60)
	return "%ds" % maxi(total, 0)

static func number(value: Variant) -> bool:
	return value is float or value is int

static func check(label: String, status: String, detail: String) -> Dictionary:
	return {"label":label, "status":status, "glyph":GLYPHS[status], "color":COLORS[status], "detail":detail,
		"text":GLYPHS[status] + " " + label + " · " + detail}

static func cases(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("passed") is Array or not value.get("failed") is Array: return {}
	return {"passed":value.passed.size(), "total":value.passed.size() + value.failed.size()}

static func policy_check(snapshot: Dictionary, now: float) -> Dictionary:
	var policy = snapshot.get("policy")
	if not policy is Dictionary or not policy.get("enabled") is bool or not policy.get("publish") is bool:
		return check("Policy enabled + publish", "missing", "not reported")
	if snapshot.get("enabled") == false or not policy.enabled: return check("Policy enabled + publish", "failed", "policy disabled")
	if not policy.publish: return check("Policy enabled + publish", "failed", "publish not authorized")
	if not number(policy.get("expires_at")): return check("Policy enabled + publish", "missing", "expiry not reported")
	if float(policy.expires_at) <= now: return check("Policy enabled + publish", "failed", "policy expired")
	return check("Policy enabled + publish", "passed", "allowed")

static func test_check(mission: Dictionary) -> Dictionary:
	if mission.is_empty(): return check("Test verdict", "missing", "no mission selected")
	var stages = mission.get("stage_evidence")
	var testing = stages.get("testing") if stages is Dictionary else null
	if not testing is Dictionary: return check("Test verdict", "missing", "not recorded")
	var verdict = testing.get("verdict")
	if not verdict is String or verdict.is_empty(): return check("Test verdict", "missing", "verdict not recorded")
	var candidate := cases(testing.get("candidate_cases"))
	var baseline := cases(testing.get("baseline_cases"))
	var counts := ""
	if not candidate.is_empty() and not baseline.is_empty():
		counts = " · %d/%d vs %d/%d" % [candidate.passed, candidate.total, baseline.passed, baseline.total]
	var diff = testing.get("diff")
	if diff is Dictionary and number(diff.get("additions")) and number(diff.get("deletions")):
		counts += " · +%d −%d" % [int(diff.additions), int(diff.deletions)]
	if verdict == "improved": return check("Test verdict", "passed", "improved" + counts)
	return check("Test verdict", "failed", verdict.replace("_", " ") + counts)

static func review_check(mission: Dictionary) -> Dictionary:
	if mission.is_empty(): return check("Reviewer", "missing", "no mission selected")
	var stages = mission.get("stage_evidence")
	var review = stages.get("reviewing") if stages is Dictionary else null
	if not review is Dictionary: return check("Reviewer", "missing", "not recorded")
	var status := str(review.get("status", "")) if review.get("status") is String else ""
	var count := ""
	if review.get("findings") is Array:
		count = " · %d finding%s" % [review.findings.size(), "" if review.findings.size() == 1 else "s"]
		if review.get("findings_truncated", false): count += " (truncated)"
	match status:
		"accept": return check("Reviewer", "passed", "accepted" + count)
		"revise": return check("Reviewer", "failed", "changes requested" + count)
		"": return check("Reviewer", "missing", "status not recorded")
	return check("Reviewer", "missing", status.replace("_", " ") + count)

static func evaluate(snapshot: Dictionary, mission: Dictionary, now: float, current: bool) -> Dictionary:
	var policy: Dictionary = snapshot.get("policy", {}) if snapshot.get("policy") is Dictionary else {}
	var generation := "gen " + str(int(policy.generation)) if number(policy.get("generation")) else "gen unknown"
	var expiry := "expiry not reported"
	if number(policy.get("expires_at")):
		var left := float(policy.expires_at) - now
		expiry = "expires in " + duration(left) if left > 0 else "expired"
	var budget := "missions used unknown"
	if number(policy.get("max_missions")) and number(policy.get("generation")) and snapshot.get("missions") is Array:
		var used := 0
		for item in snapshot.missions:
			if item is Dictionary and number(item.get("policy_generation")) and int(item.policy_generation) == int(policy.generation): used += 1
		var page = snapshot.get("page")
		# A bounded page may omit older missions; the count is then a lower bound.
		var partial: bool = page is Dictionary and number(page.get("total")) and number(page.get("returned")) and int(page.total) > int(page.returned)
		budget = "%s%d / %d missions used" % ["≥" if partial else "", used, int(policy.max_missions)]
	var coordination: Dictionary = snapshot.get("coordination", {}) if snapshot.get("coordination") is Dictionary else {}
	var admission := str(coordination.get("admission", "unknown")).replace("_", " ")
	var checks: Array = [policy_check(snapshot, now), test_check(mission), review_check(mission)]
	var failed := checks.filter(func(c): return c.status == "failed").size()
	var missing := checks.filter(func(c): return c.status == "missing").size()
	var summary := {"glyph":"[=]", "text":"CONDITIONS MET", "color":COLORS.passed}
	if failed > 0: summary = {"glyph":"[x]", "text":"CLOSED · %d failing" % failed, "color":COLORS.failed}
	elif missing > 0: summary = {"glyph":"[?]", "text":"CLOSED · evidence missing", "color":COLORS.missing}
	if not current: summary = {"glyph":"[?]", "text":"LAST KNOWN", "color":COLORS.missing}
	var mission_id := str(mission.get("id", "")) if not mission.is_empty() else ""
	return {"summary":summary, "policy_line":"Policy " + generation + " · " + expiry,
		"budget_line":budget + " · admission " + admission, "checks":checks, "note":NOTE,
		"mission_line":("Mission " + mission_id + (" · " + str(mission.objective) if mission.get("objective") is String else "")) if not mission_id.is_empty() else "No mission selected",
		"current":current}
