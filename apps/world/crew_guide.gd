extends RefCounted
## Plain-language crew reference.  This is a projection of policy and builds;
## it never grants a crew member authority or infers proficiency.

const ROLE_DATA := {
	"mender": {"id":"rivet", "name":"Rivet", "title":"Repair", "purpose":"Tests AI-proposed fixes on small Python exercises and shows which checks pass.", "actions":[{"label":"Try a repair exercise", "route":"work.repair"}], "skills":[{"key":"repair", "label":"Synthetic repair", "explanation":"Proposes a Python fix, runs it in isolation, and saves the test results for review.", "source":"typical"}], "limits":["Practice exercises only. Your repositories and production systems are not changed."]},
	"surveyor": {"id":"moss-cartographer", "name":"Moss Bombadil", "title":"Review", "purpose":"Finds issues in Python code changes and points you to the affected lines.", "actions":[{"label":"Review Python changes", "route":"work.review"}], "skills":[{"key":"review", "label":"Python review", "explanation":"Scans added Python lines with the registered Ruff rule set and retains source and coverage details.", "source":"typical"}], "limits":["Reviews supported Python changes. Findings are advisory; publishing and merging remain your decision."]},
	"trainer": {"id":"stillpoint", "name":"Mae Jin", "title":"Gym / evaluation", "purpose":"Compares two agent versions on the same test cases so you can judge what improved.", "actions":[{"label":"Compare agent versions", "route":"work.evaluation"}], "skills":[{"key":"evaluation", "label":"Build comparison", "explanation":"Runs the deterministic comparison suite against paired baseline and candidate builds.", "source":"typical"}], "limits":["Results apply to these test cases. A higher score does not automatically promote an agent or grant permissions."]},
	"watchkeeper": {"id":"night-shift", "name":"Wes Walker", "title":"Watchkeeper", "purpose":"Checks configured Kubernetes workloads for readiness and startup problems.", "actions":[{"label":"Check system health", "route":"field.watchkeeper"}], "skills":[{"key":"field", "label":"Workload observation", "explanation":"Reads configured Kubernetes pods and deployments, or the matching fixture, and identifies visible readiness and startup problems.", "source":"typical"}], "limits":["Observes configured workloads without changing them. This is not a complete cluster health check."]},
	"reviewer": {"id":"prism", "name":"Prism", "title":"Reviewer", "purpose":"Reviews a configured GitHub pull request and prepares findings for you to inspect.", "actions":[{"label":"Review a pull request", "route":"field.reviewer"}], "skills":[{"key":"field", "label":"Pull request review", "explanation":"Verifies the configured PR head and base, checks changed Python lines, and retains findings and coverage.", "source":"typical"}], "limits":["Python changes in one configured pull request. Drafts stay local; comments, approvals, and merges are not published."]}
}

const BUILD_PROFILES := {
	"mender-v1":"mender", "surveyor-v1":"surveyor", "surveyor-v2":"surveyor", "surveyor-regressed":"surveyor"
}

static func catalog() -> Array:
	var result:Array=[]
	for role in ["mender","surveyor","trainer","watchkeeper","reviewer"]:
		result.append(_copy_role(role))
	return result

static func _copy_role(role:String) -> Dictionary:
	return ROLE_DATA.get(role, {}).duplicate(true)

static func profile(snapshot:Dictionary, role:String, offline:bool=false) -> Dictionary:
	var result:=_copy_role(role)
	if result.is_empty(): return {"role":role, "title":"Unknown", "purpose":"Crew profile unavailable.", "availability":"unknown", "skills":[], "actions":[], "limits":[]}
	result["role"]=role
	var matches:=_matching_builds(snapshot, role)
	result["builds"]=matches
	result["build_status"]="registered" if not matches.is_empty() else "unknown"
	var worker:Dictionary=snapshot.get("worker") if snapshot.get("worker") is Dictionary else {}
	var worker_ready:bool=worker.get("available",false)==true
	result["availability"]="offline" if offline else ("available" if worker_ready else "worker_unavailable")
	for skill in result.skills:
		var capability:String=str(skill.get("key", ""))
		# Build identity alone does not prove a skill is installed. Runtime build
		# manifests currently carry no skills field, so this stays explicitly unknown.
		skill["registered"]=_skill_registered(matches, role, capability)
		skill["policy"]=_capability(snapshot, capability)
		skill["availability"]=_skill_availability(snapshot, offline, worker_ready, skill.registered, capability)
	return result

static func project(snapshot:Dictionary, offline:bool=false) -> Array:
	var result:Array=[]
	for role in ["mender","surveyor","trainer","watchkeeper","reviewer"]:
		result.append(profile(snapshot, role, offline))
	return result

static func _matching_builds(snapshot:Dictionary, role:String) -> Array:
	var result:Array=[]
	for entry in snapshot.get("builds",[]):
		if not entry is Dictionary: continue
		var manifest:Dictionary=entry.get("manifest") if entry.get("manifest") is Dictionary else {}
		var build_role:=str(manifest.get("agent", ""))
		var profile_name:=str(manifest.get("profile", ""))
		if build_role==role or BUILD_PROFILES.get(profile_name, "") == role:
			result.append({"digest":entry.get("digest", ""), "profile":profile_name, "agent":build_role, "skills":manifest.get("skills", []).duplicate(true) if manifest.get("skills") is Array else []})
	return result

static func _skill_registered(builds:Array, role:String, capability:String) -> bool:
	for build in builds:
		var agent:=str(build.get("agent", ""))
		if agent==role and build.get("skills") is Array and capability in build.skills:
			return true
	return false

static func _capability(snapshot:Dictionary, key:String) -> Dictionary:
	var installation:Dictionary=snapshot.get("installation") if snapshot.get("installation") is Dictionary else {}
	var caps:Dictionary=installation.get("capabilities") if installation.get("capabilities") is Dictionary else {}
	var value:Dictionary=caps.get(key) if caps.get(key) is Dictionary else {}
	return value.duplicate(true)

static func _skill_availability(snapshot:Dictionary, offline:bool, worker_ready:bool, registered:bool, key:String) -> String:
	if offline: return "offline"
	if not registered: return "unknown"
	if not worker_ready: return "worker_unavailable"
	var policy:=_capability(snapshot,key)
	if policy.is_empty(): return "unknown"
	return "available" if policy.get("enabled",false)==true else "disabled"
