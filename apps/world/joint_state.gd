extends RefCounted
## Read-only projection of the V5 diagnostic ledger. No simulated recovery claims.
const ROLES := {"lead":"Mission lead", "workload":"Workload specialist", "service":"Service specialist"}

static func number(value:Variant) -> String:
	return str(int(value)) if value is float or value is int else "not reported"

static func stamp(value:Variant) -> String:
	return Time.get_datetime_string_from_unix_time(int(value)).replace("T"," ")+" UTC" if (value is float or value is int) and value>0 else "not reported"

static func valid_snapshot(value:Variant) -> bool:
	return value is Dictionary and value.get("schema_version")==5 and value.get("simulation")==true and value.get("missions") is Array and (value.get("observed_at") is float or value.get("observed_at") is int)

static func valid_record(value:Variant) -> bool:
	return value is Dictionary and value.get("input") is Dictionary and value.input.get("id") is String and not value.input.id.is_empty() and value.get("state") is String and value.get("tasks") is Array and value.get("simulation")==true

static func records(snapshot:Dictionary) -> Array:
	var result:Array=[]
	var seen:Dictionary={}
	for record in snapshot.get("missions",[]):
		if valid_record(record) and not seen.has(record.input.id):
			seen[record.input.id]=true
			result.append(record)
	return result

static func stale(snapshot:Dictionary, now:float) -> bool:
	var observed:float=float(snapshot.get("observed_at",0))
	return observed<=0 or observed>now+30 or now-observed>30

static func state_label(record:Dictionary) -> String:
	var state:=str(record.get("state","unknown"))
	return {"queued":"Queued", "running":"Running", "completed":"Completed", "failed":"Failed", "cancelled":"Cancelled", "blocked":"Blocked"}.get(state,"Unknown state · "+state)

static func outcome_label(record:Dictionary) -> String:
	var outcome=record.get("outcome")
	if outcome==null: return "No final diagnostic outcome recorded"
	return {"diagnostic-pass":"Diagnostic pass · simulated diagnosis only", "diagnostic-fail":"Diagnostic fail", "unresolved":"Unresolved · no verified diagnostic outcome"}.get(str(outcome),"Unknown outcome · "+str(outcome))

static func summary(record:Dictionary) -> String:
	if record.is_empty(): return "No mission selected."
	var input:Dictionary=record.input
	return "%s\n%s\n\nScenario  %s\nMission  %s\nOpportunity  %s\nBuild  %s\nCreated  %s\nUpdated  %s\nDeadline  %s\n\n%s" % [state_label(record),outcome_label(record),str(input.get("scenario","not reported")),str(input.id),str(input.get("opportunity","not reported")),str(input.get("build","not reported")),stamp(record.get("created_at")),stamp(record.get("updated_at")),stamp(record.get("deadline")),str(record.get("reason")) if record.get("reason")!=null else "No final reason recorded."]

static func budget(record:Dictionary) -> String:
	var value:Dictionary=record.get("budget") if record.get("budget") is Dictionary else {}
	return "Requests reserved  %s / %s\nTokens reserved  %s / %s\nTokens accounted  %s\nReservations bound dispatch. Accounted usage can include a full grant when actual usage is unknown." % [number(value.get("requests_reserved")),number(value.get("requests_limit")),number(value.get("tokens_reserved")),number(value.get("tokens_limit")),number(value.get("tokens_accounted"))]

static func members(record:Dictionary) -> String:
	var output:PackedStringArray=[]
	for task in record.get("tasks",[]):
		if not task is Dictionary: continue
		var result:Dictionary=task.get("result") if task.get("result") is Dictionary else {}
		var status:="No reply recorded · outcome unknown" if result.is_empty() else "Reply status  "+str(result.get("status","unknown"))
		var lines:PackedStringArray=["ROUND %s · %s" % [number(task.get("round")),ROLES.get(str(task.get("role","")),"Unknown member role")],"Task  "+str(task.get("id","not reported")),"State  "+str(task.get("state","unknown"))+" · Focus  "+str(task.get("focus","not reported")),str(task.get("question","Question not reported")),"Grant  %s tokens · Accounted  %s" % [number(task.get("tokens")),number(task.get("accounted_tokens"))],status]
		if not result.is_empty():
			lines.append("Accepted for diagnostic grading" if task.get("eligible")==true else "Not eligible for diagnostic grading")
			if result.get("error")!=null: lines.append("Error  "+str(result.error))
			if result.get("output")!=null: lines.append("Recorded reply\n"+reply(result.output))
		output.append("\n".join(lines))
	return "\n\n".join(output) if not output.is_empty() else "No member dispatch recorded. The mission lead and specialists appear here only after Core records their tasks."

static func reply(value:Variant) -> String:
	if not value is Dictionary:return "Reply retained; inspect the exact record for its contents."
	var lines:PackedStringArray=[]
	for key in ["diagnosis","summary","rationale","uncertainty","next_question"]:
		if value.get(key)!=null:lines.append(key.replace("_"," ").capitalize()+"  "+str(value[key]))
	if value.get("evidence_ids") is Array:
		lines.append("Evidence  "+", ".join(value.evidence_ids))
	if value.get("tasks") is Array:
		for task in value.tasks:
			if task is Dictionary:
				lines.append("Delegated  %s · %s" % [ROLES.get(str(task.get("role","")),"Unknown role"),str(task.get("focus","not reported"))])
				if task.get("question")!=null:lines.append("Question  "+str(task.question))
	if value.get("decision") is Dictionary:
		lines.append("Proposed decision  "+str(value.decision.get("action","not reported")))
	return "\n".join(lines) if not lines.is_empty() else "Reply retained; inspect the exact record for its contents."

const OPPORTUNITY_CATEGORIES := {
	"diagnostic-fail":"Diagnostic failure", "malformed-response":"Malformed response",
	"unknown-usage-or-dispatch":"Unknown usage or dispatch", "repeated-no-progress":"Repeated lack of progress",
	"budget-stop":"Budget stop", "incomplete":"Incomplete investigation"
}

static func valid_opportunity(value:Variant) -> bool:
	return value is Dictionary and value.get("id") is String and not value.id.is_empty() and value.get("status")=="proposed-review" and value.get("scope")=="public-simulation-review" and value.get("category") in OPPORTUNITY_CATEGORIES and value.get("sources") is Array

static func opportunities(snapshot:Dictionary) -> Array:
	var result:Array=[];var seen:Dictionary={}
	if not snapshot.get("opportunities") is Array:return result
	for value in snapshot.opportunities:
		if valid_opportunity(value) and not seen.has(value.id):
			seen[value.id]=true;result.append(value)
	return result

static func opportunity_note(snapshot:Dictionary) -> String:
	if not snapshot.has("opportunities"):return "Trainer opportunities are not reported by this Core."
	if not snapshot.opportunities is Array:return "Trainer opportunities are unknown · unsupported response."
	var count:=opportunities(snapshot).size()
	var excluded:int=snapshot.opportunities.size()-count
	var text:="%d proposed reviews in this snapshot · stable identity order, not priority ranking." % count if count>0 else "No proposed Trainer reviews in this snapshot."
	if excluded>0:text+=" %d unsupported reviews omitted; coverage is incomplete." % excluded
	return text

static func opportunity_summary(value:Dictionary) -> String:
	if value.is_empty():return "No proposed review selected."
	var tokens:="Accounted tokens  "+number(value.get("tokens_accounted"))
	if value.get("accounting_overflow")==true:tokens="Accounted tokens unavailable · aggregate overflow; exact source amounts remain below."
	var usage:="Includes uncertain usage; accounting may charge full task grants." if value.get("usage_unknown")==true else "No unknown usage reported in this group." if value.get("usage_unknown")==false else "Usage status not reported."
	return "PROPOSED REVIEW · TRAINING NOT STARTED\nNo qualification, XP or adoption.\n\nCategory  %s\nObservations  %s failed or unresolved missions\nScenario  %s\nBuild  %s\nReview  %s\nMost recent source  %s\n\n%s\n%s" % [OPPORTUNITY_CATEGORIES.get(str(value.get("category","")),"Unknown"),number(value.get("observed_count")),str(value.get("scenario","not reported")),str(value.get("build","not reported")),str(value.get("id","not reported")),stamp(value.get("most_recent_at")),tokens,usage]

static func opportunity_sources(value:Dictionary) -> String:
	var lines:PackedStringArray=[]
	for source in value.get("sources",[]):
		if not source is Dictionary:continue
		var tasks:Array=source.get("task_ids") if source.get("task_ids") is Array else []
		lines.append("Mission  %s\nTasks  %s\nAccounted tokens  %s · %s" % [str(source.get("mission_id","not reported")),", ".join(tasks) if not tasks.is_empty() else "No member task IDs reported",number(source.get("tokens_accounted")),"usage uncertain" if source.get("usage_unknown")==true else "no unknown usage reported" if source.get("usage_unknown")==false else "usage status not reported"])
	return "\n\n".join(lines) if not lines.is_empty() else "No source details reported."
