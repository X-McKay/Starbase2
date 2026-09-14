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

static func kind(mission: Dictionary) -> String:
	return str(mission.get("input",{}).get("kind","review"))

static func context(mission: Dictionary) -> String:
	var backend_kind := kind(mission)
	return "gym" if backend_kind=="evaluation" else backend_kind

static func metadata(projected: Dictionary, run: Dictionary) -> Dictionary:
	# Keep durable identifiers/timestamps separate from visual crew context.
	for key in ["created_at","updated_at","events","build","summary","snapshot","workflow_id","source_observed_at"]:
		if run.has(key): projected[key]=run[key].duplicate(true) if run[key] is Dictionary or run[key] is Array else run[key]
	if run.get("input",{}).has("build"):
		var build=run.input.build
		projected["build"]=build.duplicate(true) if build is Dictionary or build is Array else build
	if run.get("summary") is Dictionary and run.summary.has("source_observed_at"):
		projected["source_observed_at"]=run.summary.source_observed_at
	projected["context"]=context(projected)
	return projected

static func valid_record(run: Variant) -> bool:
	if not run is Dictionary or not run.get("input") is Dictionary: return false
	var request=run.input.get("request",run.input)
	if not request is Dictionary or not request.get("id") is String or request.id.is_empty(): return false
	for key in ["kind","agent"]:
		if request.has(key) and not request[key] is String: return false
	for key in ["created_at","updated_at","source_observed_at"]:
		if run.has(key) and run[key]!=null and not (run[key] is float or run[key] is int): return false
	for key in ["report","summary","snapshot"]:
		if run.get(key)!=null and not run[key] is Dictionary: return false
	var report: Dictionary=run.get("report") if run.get("report") is Dictionary else {}
	if report.get("summary")!=null and not report.summary is Dictionary: return false
	for key in ["findings","coverage"]:
		if report.has(key) and not report[key] is Array: return false
	if report.has("memory") and not report.memory is Dictionary: return false
	var source: Dictionary=run.get("snapshot") if run.get("snapshot") is Dictionary else {}
	if source.has("data") and not source.data is Dictionary: return false
	return true

static func operation_records(snapshot: Dictionary) -> Array:
	var records: Array=[]
	var indices: Dictionary={}
	# Retain recent order, adding active records that have aged out of that window.
	for run in snapshot.get("recent",[])+snapshot.get("active",[]):
		if not valid_record(run): continue
		var request=run.input.get("request",{})
		if not request is Dictionary or not request.get("id") is String: continue
		var id:=str(request.get("id",""))
		if id.is_empty(): continue
		if indices.has(id):
			var index:int=indices[id]
			if float(run.get("updated_at",0))>float(records[index].get("updated_at",0)): records[index]=run
		else:
			indices[id]=records.size()
			records.append(run)
	return records

static func project(snapshot: Dictionary) -> Array:
	if snapshot.get("schema_version") != 2 or not snapshot.get("recent") is Array or not snapshot.get("active",[]) is Array or not snapshot.get("repairs",[]) is Array or not snapshot.get("field_runs",[]) is Array:
		return []
	var worker: Dictionary=snapshot.get("worker") if snapshot.get("worker") is Dictionary else {}
	var result: Array = []
	for run in operation_records(snapshot):
		if not valid_record(run):
			continue
		var request: Dictionary = run["input"].get("request", {})
		var report = run.get("report")
		result.append(metadata({"input": request.duplicate(true), "state": run.get("state", "unknown"),
			"detail": run.get("detail", ""), "evidence": report,
			"stale": not worker.get("available", false) and run.get("state") not in ["completed", "failed", "cancelled"]},run))
	var repair_records: Array = []
	for run in snapshot.get("repairs", []):
		if not valid_record(run):
			continue
		var request: Dictionary = run["input"].duplicate()
		request["kind"] = "repair"
		request["target"] = request.get("scenario", "synthetic")
		request["profile"] = "mender-v1"
		repair_records.append(metadata({"input": request, "state": run.get("state", "unknown"),
			"detail": run.get("detail", ""), "evidence": {"summary":run["summary"]} if run.get("summary") != null else null,
			"stale": not worker.get("available", false) and run.get("state") not in ["completed", "failed", "cancelled"]},run))
	var field_records: Array=[]
	for run in snapshot.get("field_runs",[]):
		if not valid_record(run): continue
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
			evidence={"summary":{"outcome":outcome,"finding_count":count,"simulation":(run.snapshot.get("data",{}).get("simulation",false) if run.get("snapshot") is Dictionary else false),"source_kind":"field","qualification":"Read-only advisory. Memory: "+str(report.get("memory",{}).get("status","unknown"))}}
		field_records.append(metadata({"input":request,"state":run.get("state","unknown"),"detail":run.get("detail",""),"evidence":evidence,"stale":not worker.get("available",false) and run.get("state") not in ["completed","failed","cancelled"]},run))
	return field_records + repair_records + result

static func input_label(summary: Dictionary) -> String:
	if summary.get("simulation", false) or summary.get("synthetic_task", false):
		return "synthetic fixture"
	return "live provider snapshot" if summary.get("source_kind")=="field" else "real local repository"

static func crew_activity(missions: Array, kind: String, disconnected: bool) -> String:
	if disconnected:
		return "Unknown · offline"
	var own: Array = missions.filter(func(m): return context(m) == kind)
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
