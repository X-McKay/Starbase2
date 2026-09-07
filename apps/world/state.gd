extends RefCounted
## Shared interpretation: operational state never comes from an animation.
static func describe(mission: Dictionary, disconnected: bool) -> String:
	if disconnected:
		return "Disconnected · last known " + str(mission.get("state", "unknown"))
	if mission.is_empty():
		return "Idle · no mission recorded"
	if mission.get("stale", true):
		return "Stale · last known " + str(mission.get("state", "unknown"))
	var current := str(mission.get("state", "unknown"))
	if current == "completed" and mission.get("evidence") == null:
		return "Unknown · completion evidence missing"
	return current.capitalize().replace("_", " ")

## Tone is a presentation category derived only from the record. Shapes and
## colors in the UI follow it; it never adds information the record lacks.
static func tone(mission: Dictionary, disconnected: bool) -> String:
	if disconnected: return "offline"
	if mission.is_empty(): return "idle"
	if mission.get("stale", true): return "stale"
	var current := str(mission.get("state", "unknown"))
	if current == "completed":
		if mission.get("evidence") == null: return "unknown"
		var outcome := str(mission["evidence"].get("summary", {}).get("outcome", "unknown"))
		if outcome in ["regressed"]: return "failed"
		if outcome in ["inconclusive", "partial", "unknown", "invalid", "ineligible"]: return "unknown"
		if outcome == "no_change": return "no_change"
		return "verified"
	if current == "failed": return "failed"
	if current == "cancelled": return "idle"
	if current in ["unknown", "blocked"]: return "unknown"
	return "pending"

static func crew_tone(missions: Array, kind: String, disconnected: bool) -> String:
	if disconnected: return "offline"
	var own: Array = missions.filter(func(m): return m.get("input",{}).get("kind","review") == kind)
	if own.is_empty(): return "idle"
	var active: Array = own.filter(func(m): return m.get("state") not in ["completed","failed","cancelled"])
	if not active.is_empty():
		if active.any(func(m): return m.get("stale",true)): return "stale"
		return "pending"
	return tone(own[0], false)

static func project(snapshot: Dictionary) -> Array:
	if snapshot.get("schema_version") != 2 or not snapshot.get("recent") is Array:
		return []
	var result: Array = []
	for run in snapshot["recent"]:
		if not run is Dictionary or not run.get("input") is Dictionary:
			continue
		var request: Dictionary = run["input"].get("request", {})
		var report = run.get("report")
		result.append({"input": request, "state": run.get("state", "unknown"),
			"detail": run.get("detail", ""), "evidence": report,
			"stale": not snapshot.get("worker", {}).get("available", false) and run.get("state") not in ["completed", "failed", "cancelled"]})
	var repair_records: Array = []
	for run in snapshot.get("repairs", []):
		if not run is Dictionary or not run.get("input") is Dictionary:
			continue
		var request: Dictionary = run["input"].duplicate()
		request["kind"] = "repair"
		request["target"] = request.get("scenario", "synthetic")
		request["profile"] = "mender-v1"
		repair_records.append({"input": request, "state": run.get("state", "unknown"),
			"detail": run.get("detail", ""), "evidence": {"summary":run["summary"]} if run.get("summary") != null else null,
			"stale": not snapshot.get("worker", {}).get("available", false) and run.get("state") not in ["completed", "failed", "cancelled"]})
	var field_records: Array=[]
	for run in snapshot.get("field_runs",[]):
		if not run is Dictionary or not run.get("input") is Dictionary: continue
		var request: Dictionary=run["input"].duplicate()
		request["kind"]=request.get("agent","unknown")
		var report=run.get("report")
		var evidence=null
		if run.get("summary") is Dictionary:
			var summary: Dictionary=run["summary"].duplicate()
			summary["qualification"]="Read-only advisory. Memory: "+str(summary.get("memory_status","unknown"))
			evidence={"summary":summary}
		elif report is Dictionary:
			var count: int=report.get("findings",[]).size()
			var outcome := "partial" if not report.get("coverage",[]).is_empty() else ("findings" if count>0 else "no_findings")
			evidence={"summary":{"outcome":outcome,"finding_count":count,"simulation":run.get("snapshot",{}).get("data",{}).get("simulation",false),"source_kind":"field","qualification":"Read-only advisory. Memory: "+str(report.get("memory",{}).get("status","unknown"))}}
		field_records.append({"input":request,"state":run.get("state","unknown"),"detail":run.get("detail",""),"evidence":evidence,"stale":not snapshot.get("worker",{}).get("available",false) and run.get("state") not in ["completed","failed","cancelled"]})
	return field_records + repair_records + result

static func input_label(summary: Dictionary) -> String:
	if summary.get("simulation", false) or summary.get("synthetic_task", false):
		return "synthetic fixture"
	return "live provider snapshot" if summary.get("source_kind")=="field" else "real local repository"

static func crew_activity(missions: Array, kind: String, disconnected: bool) -> String:
	if disconnected:
		return "Unknown · offline"
	var own: Array = missions.filter(func(m): return m.get("input",{}).get("kind","review") == kind)
	if own.is_empty():
		return "No recorded work"
	var active: Array = own.filter(func(m): return m.get("state") not in ["completed","failed","cancelled"])
	if not active.is_empty():
		if active.any(func(m): return m.get("stale",true)):
			return "Stale · work unknown"
		if active.size() > 1:
			return "%d open runs" % active.size()
		return describe(active[0],false)
	var latest: Dictionary = own[0]
	if latest.get("state") == "completed" and latest.get("evidence") != null:
		var outcome := str(latest["evidence"].get("summary",{}).get("outcome","unknown"))
		return {"improved":"Verified improvement","no_change":"Verified no change","regressed":"Regression recorded","inconclusive":"Inconclusive","equivalent":"Equivalent"}.get(outcome,outcome.capitalize().replace("_"," "))
	return describe(latest,false)
