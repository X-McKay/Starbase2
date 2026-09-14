extends SceneTree

const Guide=preload("res://crew_guide.gd")
var failures:Array[String]=[]

func check(value:bool, message:String) -> void:
	if not value: failures.append(message)

func _initialize() -> void:
	var snapshot:Dictionary={
		"worker":{"available":true},
		"builds":[
			{"digest":"repair-digest","manifest":{"agent":"mender","profile":"mender-v1","skills":["repair"]}},
			{"digest":"review-digest","manifest":{"profile":"surveyor-v2"}},
			{"digest":"field-digest","manifest":{"agent":"watchkeeper","skills":["field"],"target":{"id":"cluster-fixture"}}}
		],
		"installation":{"capabilities":{"repair":{"enabled":true},"review":{"enabled":true},"field":{"enabled":true}}}
	}
	var all:=Guide.catalog()
	check(all.size()==5,"Catalog contains the five operational roles")
	check(all[0].title=="Repair" and all[1].title=="Review" and all[2].title=="Gym / evaluation","Catalog uses plain-language role titles")
	var rivet:=Guide.profile(snapshot,"mender")
	check(rivet.name=="Rivet" and rivet.actions[0].route=="work.repair","Repair profile has identity and route")
	check(rivet.skills[0].source=="typical" and rivet.skills[0].registered and rivet.skills[0].availability=="available","Exact mender build skill is attributable")
	var moss:=Guide.profile(snapshot,"surveyor")
	check(moss.builds.size()==1 and not moss.skills[0].registered and moss.skills[0].availability=="unknown","Build profile does not invent an installed skill")
	var wes:=Guide.profile(snapshot,"watchkeeper")
	check(wes.skills[0].registered and wes.skills[0].availability=="available","Field build maps to Watchkeeper field skill")
	var prism:=Guide.profile(snapshot,"reviewer")
	check(not prism.skills[0].registered and prism.skills[0].availability=="unknown","A watchkeeper build cannot be attributed to Prism")
	snapshot.installation.capabilities.field.enabled=false
	check(Guide.profile(snapshot,"watchkeeper").skills[0].availability=="disabled","Installation policy disables field skill explicitly")
	snapshot.worker.available=false
	check(Guide.profile(snapshot,"mender").skills[0].availability=="worker_unavailable","Worker availability remains separate from policy")
	check(Guide.profile(snapshot,"mender",true).skills[0].availability=="offline","Offline state remains explicit")
	var unknown:=Guide.profile({},"missing")
	check(unknown.availability=="unknown" and unknown.skills.is_empty(),"Unknown role does not invent skills")
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("CREW_GUIDE_PASSED: role purpose/actions/limits, exact build mapping, policy and worker/offline truth")
	quit(0 if failures.is_empty() else 1)
