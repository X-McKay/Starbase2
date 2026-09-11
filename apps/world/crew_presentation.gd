extends RefCounted
## Cosmetic intent only. World navigation resolves destinations; this never dispatches work.
const StateView = preload("res://state.gd")
const TERMINAL := ["completed","failed","cancelled"]
const WORKING := ["running","executing","analyzing","evaluating","verifying"]
var last_observed_at := -1.0
var retained: Array = []
var selected_run_id := ""

func update(missions: Array, crew_context: String, disconnected: bool, reduced: bool, observed_at: float = 0.0, duty_state: Dictionary = {}) -> Dictionary:
	# Pass the core snapshot observed_at timestamp, not a local animation clock.
	# A reconnect replaces current intent; there is no queue of obsolete trips.
	if not disconnected and observed_at >= last_observed_at:
		retained=missions.filter(func(m): return StateView.context(m)==crew_context).duplicate(true)
		retained.sort_custom(func(a,b): return float(a.get("updated_at",0))>float(b.get("updated_at",0)))
		last_observed_at=observed_at
	var active: Array=retained.filter(func(m): return m.get("state","unknown") not in TERMINAL)
	var selected: Dictionary=active[0] if not active.is_empty() else (retained[0] if not retained.is_empty() else {})
	# Concurrent progress timestamps must not bounce one crew member between assignments.
	for run in active:
		if str(run.get("input",{}).get("id",""))==selected_run_id:
			selected=run
			break
	selected_run_id=str(selected.get("input",{}).get("id",""))
	var state:=str(selected.get("state","unknown"))
	var stale: bool=not active.is_empty() and active.any(func(m): return m.get("stale",true))
	var unknown: bool=disconnected or stale or (state=="completed" and selected.get("evidence")==null) or (not selected.is_empty() and state=="unknown")
	var evidence_ready: bool=not unknown and state=="completed" and selected.get("evidence")!=null
	var goal:="home" if not unknown and selected.is_empty() else "hold"
	var pose:=""
	if not unknown and not selected.is_empty():
		if state in WORKING:
			goal="workstation"
			pose="console"
		elif state=="queued": goal="workstation"
		elif state in TERMINAL: goal="home"
	# Reduced motion leaves semantic status/evidence intact, removing cosmetic travel/pose.
	if reduced or unknown:
		goal="hold"
		pose=""
	return {"run_id":str(selected.get("input",{}).get("id","")),
		"backend_state":state,"goal":goal,"pose":pose,
		"duty_label":("On duty · waiting" if duty_state.get("enabled",false) else "Duty paused") if duty_state.get("known",false) and active.is_empty() and not unknown else "",
		"moving_allowed":goal!="hold","active_count":active.size(),
		"label":StateView.crew_activity(retained,crew_context,disconnected),
		"evidence_ready":evidence_ready,"unknown":unknown,
		"observed_at":last_observed_at,
		"task_markers":task_markers(retained,selected_run_id,disconnected),
		"marker_overflow":maxi(0,retained.size()-3)}

# Markers retain run identity and describe records, never a claim of success or authority.
# Keep the assigned run first, followed by recent retained records. No animation queue.
static func task_markers(records: Array, assigned_id: String, disconnected: bool) -> Array:
	var ordered: Array=records.duplicate()
	for i in range(ordered.size()):
		if str(ordered[i].get("input",{}).get("id",""))==assigned_id:
			var assigned=ordered.pop_at(i)
			ordered.push_front(assigned)
			break
	var markers: Array=[]
	for run in ordered.slice(0,3):
		var state:=str(run.get("state","unknown"))
		var unknown: bool=disconnected or bool(run.get("stale",true)) and state not in TERMINAL
		var status:="unknown"
		if not unknown:
			if state=="queued": status="queued"
			elif state in WORKING: status="active"
			elif state=="completed" and run.get("evidence")!=null: status="evidence"
			elif state=="failed": status="failed"
			elif state=="cancel_requested": status="cancel_pending"
			elif state=="cancelled": status="cancelled"
		var style: Dictionary={
			"queued":{"icon":"...","text":"Queued","color":"c6d3e0"},
			"active":{"icon":">","text":"Active","color":"82d8ee"},
			"evidence":{"icon":"[=]","text":"Evidence ready","color":"b4ddac"},
			"failed":{"icon":"!","text":"Failed","color":"f1b08e"},
			"cancel_pending":{"icon":"||","text":"Cancel pending","color":"e8ce8e"},
			"cancelled":{"icon":"x","text":"Cancelled","color":"c6d3e0"},
			"unknown":{"icon":"?","text":"Unknown","color":"c6bdd6"}}[status]
		var marker:=style.duplicate()
		marker["status"]=status
		marker["run_id"]=str(run.get("input",{}).get("id",""))
		marker["backend_state"]=state
		markers.append(marker)
	return markers
