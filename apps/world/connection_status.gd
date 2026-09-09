extends RefCounted
## Presentation of Core policy; never grants authority or substitutes for admission.
static func installation(snapshot:Dictionary) -> Dictionary:
	var value=snapshot.get("installation")
	return value if value is Dictionary else {}

static func capability(snapshot:Dictionary,key:String) -> Dictionary:
	var caps=installation(snapshot).get("capabilities",{})
	if not caps is Dictionary: return {}
	var value=caps.get(key)
	return value if value is Dictionary else {}

static func enabled(snapshot:Dictionary,key:String) -> bool:
	return capability(snapshot,key).get("enabled",false)==true

static func reason(snapshot:Dictionary,key:String) -> String:
	return str(capability(snapshot,key).get("reason","Capability not reported by this Core. Update the backend or use its journal."))

static func worker_available(snapshot:Dictionary) -> bool:
	var worker=snapshot.get("worker")
	return worker is Dictionary and worker.get("available",false)==true

static func valid(snapshot:Variant) -> bool:
	if not snapshot is Dictionary or snapshot.get("schema_version")!=2: return false
	if not snapshot.get("recent") is Array or not snapshot.get("worker") is Dictionary: return false
	for name in ["active","repairs","field_runs"]:
		if snapshot.has(name) and not snapshot[name] is Array: return false
	return true

static func headline(snapshot:Dictionary,offline:bool,fixture:bool) -> String:
	if fixture: return "VISUAL TEST FIXTURE · not live operational activity"
	if offline: return "DISCONNECTED · last-known records only"
	var info:=installation(snapshot)
	var identity:=str(info.get("id","local Core"))
	if info.is_empty(): return "LIVE CORE · capability information unavailable"
	if not enabled(snapshot,"accept_work"): return identity+" · STOPPED · new work disabled"
	if not worker_available(snapshot): return identity+" · WORKER UNAVAILABLE"
	return identity+" · LIVE CORE"
