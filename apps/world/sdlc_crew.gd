extends RefCounted
## Presentation of retained V7 assignments, never an assertion of an in-flight model call.
const ROLES := {"review":"lead","repair":"implementer","reviewer":"reviewer"}
const ASSIGNED := {"queued":"lead","investigating":"lead","implementing":"implementer","testing":"reviewer"}
const TERMINAL := ["awaiting_review","failed","blocked","cancelled","completed"]
const VERIFY_ASSIGNED := {"queued":"reviewer","verifying":"reviewer","repairing":"implementer","testing":"reviewer"}

static func assignment(mission:Dictionary) -> Dictionary:
	var children:Array=mission.get("verifications",[]).filter(func(item): return item is Dictionary and item.get("input") is Dictionary)
	children.sort_custom(func(a,b):
		var a_active:bool=a.get("state","") not in TERMINAL
		var b_active:bool=b.get("state","") not in TERMINAL
		if a_active!=b_active: return a_active
		return float(a.get("updated_at",0))>float(b.get("updated_at",0)))
	var nested:bool=not children.is_empty() and (children[0].get("state","") not in TERMINAL or mission.get("state","") in TERMINAL)
	return {"record":children[0] if nested else mission,"mission_id":str(mission.get("id",mission.get("input",{}).get("id",""))),"verification":nested,"parent_cancelled":mission.get("cancel_requested",false)}

static func project(data:Dictionary,kind:String,fresh:bool,reduced:bool,existing:Dictionary) -> Dictionary:
	if not ROLES.has(kind) or data.get("schema_version")!=7: return existing
	var records:Array=data.get("missions",[]).filter(func(item): return item is Dictionary and item.get("input") is Dictionary).map(assignment)
	if records.is_empty(): return existing
	records.sort_custom(func(a,b):
		var a_active:bool=a.record.get("state","") not in TERMINAL
		var b_active:bool=b.record.get("state","") not in TERMINAL
		if a_active!=b_active: return a_active
		return float(a.record.get("updated_at",0))>float(b.record.get("updated_at",0)))
	var chosen:Dictionary=records[0]
	var record:Dictionary=chosen.record
	var state:=str(record.get("state","unknown"))
	if record.get("cancel_requested",false) or chosen.parent_cancelled: state="cancel_requested"
	var policy:Dictionary=data.get("policy",{}) if data.get("policy",{}) is Dictionary else {}
	var authorized:bool=data.get("enabled",false) and policy.get("enabled",false) and float(policy.get("expires_at",0))>Time.get_unix_time_from_system() and policy.get("generation",-1)==record.get("policy_generation",-2)
	if chosen.verification: authorized=authorized and data.get("verification_enabled",false)
	var authority_hold:bool=not authorized and state not in TERMINAL and state!="cancel_requested"
	var assignments:Dictionary=VERIFY_ASSIGNED if chosen.verification else ASSIGNED
	var assigned:bool=assignments.get(state,"")==ROLES[kind] and not authority_hold
	var working:bool=assigned and state!="queued" and fresh
	# Existing concurrent work remains visible. A waiting SDLC teammate must not
	# stop an independently active observation or repair assignment.
	var result:Dictionary=existing.duplicate(true)
	var id:=str(record.get("id",record.input.get("id","")))
	var prefix:String="Verifier "+ROLES[kind] if chosen.verification else "SDLC "+ROLES[kind]
	var text:String=prefix+" · "+state.replace("_"," ")
	if not assigned and state not in TERMINAL: text=prefix+" · waiting ("+state.replace("_"," ")+")"
	if authority_hold: text=prefix+" · authority hold"
	if not fresh: text=prefix+" · last known "+state.replace("_"," ")
	var marker:={"run_id":id,"backend_state":state,"status":"active" if working else ("unknown" if not fresh else "queued"),"icon":">" if working else "||","text":text,"color":"82d8ee" if working else "c6d3e0"}
	var markers:Array=existing.get("task_markers",[]).duplicate(true)
	var primary:bool=(assigned and fresh) or int(existing.get("active_count",0))==0
	if primary: markers.push_front(marker)
	else: markers.append(marker)
	result.task_markers=markers.slice(0,3)
	result.marker_overflow=maxi(0,markers.size()-3)+int(existing.get("marker_overflow",0))
	if primary:
		result.run_id=id
		result.sdlc_mission_id=chosen.mission_id
		if chosen.verification: result.sdlc_verification_id=id
		result.backend_state=state
		result.goal="workstation" if assigned and fresh and not reduced else "hold"
		result.pose="console" if working and not reduced else ""
		result.moving_allowed=result.goal!="hold"
		result.active_count=(1 if assigned else 0)+int(existing.get("active_count",0))
		result.label=text
		result.sdlc_label=text
		result.duty_label="V7 stage assignment; movement is cosmetic"
		result.evidence_ready=false
		result.unknown=not fresh
	return result
