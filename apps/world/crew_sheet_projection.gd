extends RefCounted
## View of the existing Core snapshot, not a progression or qualification engine.
const Guide=preload("res://crew_guide.gd")
const STATS := [
	["Agility", "Recover from encountered faults"],
	["Speed", "Verified completion latency"],
	["Constitution", "Endurance on longer missions"],
	["Efficiency", "Resources per verified outcome"],
	["Perception", "Detect and localize real issues"],
	["Wisdom", "Know when to abstain or escalate"],
	["Precision", "Correct changes within scope"],
	["Cooperation", "Useful handoffs and team outcomes"]
]

static func project(snapshot:Dictionary, role:String, offline:bool=false, fixture:bool=false) -> Dictionary:
	var guide:=Guide.profile(snapshot,role,offline)
	var observed:float=float(snapshot.get("observed_at",0)) if snapshot.get("observed_at") is float or snapshot.get("observed_at") is int else 0.0
	var freshness:="Observation time not reported"
	if observed>0:
		freshness="Observed %s UTC" % Time.get_datetime_string_from_unix_time(int(observed)).replace("T"," ")
	if offline: freshness="Disconnected · last-known records\n"+freshness
	if fixture: freshness="VISUAL FIXTURE · synthetic records\n"+freshness
	var progression:Dictionary=snapshot.get("progression") if snapshot.get("progression") is Dictionary else {}
	# This endpoint owns Mender's ledger only. Neither role names nor array order
	# can transfer its XP to another persistent identity.
	if role!="mender" or progression.get("id","")!="mender": progression={}
	var level:="Level not reported · XP not reported"
	if progression.get("level") is float or progression.get("level") is int:
		level="Level %d" % int(progression.level)
		level+=" · %d lifetime XP" % int(progression.xp) if progression.get("xp") is float or progression.get("xp") is int else " · XP not reported"
	var builds:Array=guide.get("builds",[])
	var equipment:PackedStringArray=[]
	for build in builds:
		equipment.append("%s\nBuild  %s\nManifest skills  %s" % [str(build.get("profile","")) if not str(build.get("profile","")).is_empty() else "Registered build",str(build.get("digest","Not reported")),", ".join(build.get("skills",[])) if not build.get("skills",[]).is_empty() else "Not reported"])
	var history:PackedStringArray=[]
	var qualifications:Array=progression.get("qualifications") if progression.get("qualifications") is Array else []
	for item in qualifications:
		if not item is Dictionary: continue
		history.append("%s\nBuild  %s\nRun  %s" % [str(item.get("scenario","Scenario not reported")),str(item.get("build","Not reported")),str(item.get("run_id","Not reported"))])
	var skills:PackedStringArray=[]
	for skill in guide.get("skills",[]):
		skills.append("%s · Rank unassessed\n%s" % [str(skill.label),"Listed in a registered build manifest; active equipment is not reported." if skill.get("registered",false) else "Role workflow; no installed skill record is reported."])
	return {
		"freshness":freshness,"level":level,"class":"Class not reported · Subclass not reported",
		"progression_note":"Synthetic practice ledger · provisional Level rules. Current capability is assessed separately." if not progression.is_empty() else "No lifetime progression ledger is reported for this crew member.",
		"current":"Current build not reported · qualifications unassessed",
		"equipment":"\n\n".join(equipment) if not equipment.is_empty() else "No registered build is reported for this crew member.",
		"skills":"\n\n".join(skills) if not skills.is_empty() else "Skills not reported.",
		"history":"\n\n".join(history) if not history.is_empty() else "No historical qualification is reported for this crew member.",
		"authority":str(progression.get("authority","No crew-specific operational clearance is reported. Inspect the task workspace for target and action policy."))
	}
