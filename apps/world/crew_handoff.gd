extends RefCounted
## A short physical presentation of a newly observed retained SDLC handoff.
## It cannot create work, mutate records, or replay retained history on startup.
const ROLE_CREW:={"lead":"review","implementer":"repair","reviewer":"reviewer"}
const WEST:=Vector3(-7.36,0,24.85)
const EAST:=Vector3(-6.64,0,24.85)
var last_signature:=""
var initialized:=false
var current:Dictionary={}
var travel_elapsed:=0.0
var dwell_elapsed:=0.0

func selected_mission(snapshot:Dictionary) -> Dictionary:
	if snapshot.get("schema_version")!=7:return {}
	var best:Dictionary={};var best_key:=""
	for value in snapshot.get("missions",[]):
		if not value is Dictionary:continue
		var mission:Dictionary=value
		var key:="%s:%s"%[str(mission.get("updated_at","")),str(mission.get("id",mission.get("input",{}).get("id","")))]
		if best.is_empty() or key>best_key:best=mission;best_key=key
	return best

func signature(snapshot:Dictionary) -> String:
	var mission:=selected_mission(snapshot)
	if mission.is_empty():return ""
	var events:Array=recent(mission)
	if events.size()<2:return ""
	var latest:Dictionary=events[-1]
	return "%s:%d:%s:%s:%s"%[str(mission.get("id",mission.get("input",{}).get("id",""))),int(mission.get("event_count",events.size())),str(latest.get("role","")),str(latest.get("state",latest.get("stage",""))),str(mission.get("updated_at",""))]

## V7 summaries carry the newest events as `recent_events` (oldest first);
## full records and fixtures carry `events`.
static func recent(mission:Dictionary) -> Array:
	var events=mission.get("recent_events",mission.get("events",[]))
	return events if events is Array else []

func observe(snapshot:Dictionary,fresh:bool,reduced:bool) -> bool:
	var next_signature:=signature(snapshot)
	if not initialized:
		var missions:Array=snapshot.get("missions",[]) if snapshot.get("schema_version")==7 else []
		if missions.is_empty():return false
		initialized=true
		last_signature=next_signature
		return false
	if next_signature.is_empty():return false
	if next_signature==last_signature:return false
	last_signature=next_signature
	if not fresh or reduced:return false
	var mission:Dictionary=selected_mission(snapshot)
	var events:Array=recent(mission)
	var before:Dictionary=events[-2];var after:Dictionary=events[-1]
	var giver:=str(before.get("role",""));var receiver:=str(after.get("role",""))
	if giver==receiver or not ROLE_CREW.has(giver) or not ROLE_CREW.has(receiver):return false
	current={"giver":ROLE_CREW[giver],"receiver":ROLE_CREW[receiver],"mission_id":str(mission.get("id",mission.get("input",{}).get("id",""))),"from_role":giver,"to_role":receiver,"event_signature":next_signature}
	travel_elapsed=0.0;dwell_elapsed=0.0
	return true

func active() -> bool:return not current.is_empty()

func advance(delta:float,arrived:bool,reduced:bool) -> bool:
	if current.is_empty():return false
	if reduced:
		current.clear();return true
	travel_elapsed+=maxf(delta,0)
	if arrived:dwell_elapsed+=maxf(delta,0)
	if dwell_elapsed>=6.0 or travel_elapsed>=75.0:
		current.clear();return true
	return false

func override(kind:String,base:Dictionary,reduced:bool) -> Dictionary:
	if current.is_empty() or reduced or kind not in [current.giver,current.receiver]:return base
	var result:Dictionary=base.duplicate(true)
	var giver:bool=kind==current.giver
	result.goal="handoff";result.pose="handoff";result.moving_allowed=true
	result.target=WEST if giver else EAST
	result.facing=EAST if giver else WEST
	result.exchange_role="giver" if giver else "receiver"
	result.exchange_partner=current.receiver if giver else current.giver
	result.presentation_event=current.event_signature
	return result
