extends SceneTree
const StateView = preload("res://state.gd")
func _initialize() -> void:
	assert(StateView.describe({}, true).begins_with("Disconnected"))
	assert(StateView.describe({}, false).begins_with("Idle"))
	assert(StateView.describe({"state":"running", "stale":true}, false).begins_with("Stale"))
	assert(StateView.describe({"state":"completed", "stale":false}, false).begins_with("Unknown"))
	for state in ["failed", "cancelled", "cancel_requested", "queued", "running", "blocked", "no_change"]:
		assert(StateView.describe({"state":state, "stale":false}, false) == state.capitalize().replace("_", " "))
	var projected = StateView.project({"schema_version":2, "worker":{"available":false}, "recent":[{"input":{"request":{"id":"review-one"}},"state":"running","report":null}]})
	assert(projected.size() == 1)
	assert(StateView.describe(projected[0], false).begins_with("Stale"))
	assert(StateView.project({"schema_version":99}).is_empty())
	assert(StateView.project({"schema_version":2,"recent":[],"active":null}).is_empty())
	assert(StateView.input_label({"synthetic_task":true}) == "synthetic fixture")
	assert(StateView.input_label({"simulation":true}) == "synthetic fixture")
	var repairs = StateView.project({"schema_version":2,"recent":[],"worker":{"available":false},"repairs":[{"input":{"id":"repair-one","scenario":"clamp-v1"},"state":"executing","summary":null}]})
	assert(repairs.size() == 1 and repairs[0]["input"]["kind"] == "repair")
	assert(StateView.describe(repairs[0],false).begins_with("Stale"))
	assert(StateView.crew_activity([],"repair",true).begins_with("Unknown"))
	assert(StateView.crew_activity([],"repair",false)=="No recorded work")
	assert(StateView.crew_activity(repairs,"repair",false).begins_with("Stale"))
	var record := {"input":{"id":"one","kind":"repair"},"state":"completed","stale":false,"evidence":{"summary":{"outcome":"inconclusive"}}}
	assert(StateView.crew_activity([record],"repair",false)=="Inconclusive")
	record["evidence"]["summary"]["outcome"]="no_change"
	assert(StateView.crew_activity([record],"repair",false)=="Verified no change")
	record["evidence"]=null
	assert(StateView.crew_activity([record],"repair",false).begins_with("Unknown"))
	var a := {"input":{"id":"two","kind":"repair"},"state":"executing","stale":false}
	assert(StateView.crew_activity([record,a,a],"repair",false)=="2 open runs")
	var ordered = StateView.project({"schema_version":2,"recent":[],"worker":{"available":true},"repairs":[{"input":{"id":"newest"},"state":"failed"},{"input":{"id":"older"},"state":"failed"}]})
	assert(ordered[0]["input"]["id"]=="newest","Preserve core order; latest crew state must not come from the oldest run")
	var old := {"input":{"request":{"id":"old","kind":"review"}},"state":"running","updated_at":1.0}
	var recent: Array=[]
	for i in range(20): recent.append({"input":{"request":{"id":"new-"+str(i),"kind":"review"}},"state":"completed","updated_at":2.0+i})
	var union=StateView.project({"schema_version":2,"recent":recent,"active":[old],"worker":{"available":true}})
	assert(union.size()==21,"Active review must survive twenty newer records")
	var evaluation={"input":{"request":{"id":"trial","kind":"evaluation"},"build":{"id":"build-1"}},"state":"running","created_at":10.0,"updated_at":12.0}
	var trials=StateView.project({"schema_version":2,"recent":[evaluation],"active":[evaluation],"worker":{"available":true}})
	assert(trials.size()==1,"Union must deduplicate shared active/recent records")
	assert(trials[0].input.kind=="evaluation","Keep backend request kind")
	assert(StateView.crew_activity(trials,"gym",false)=="Running","Evaluation belongs to Trainer")
	assert(trials[0].context=="gym" and StateView.kind(trials[0])=="evaluation")
	assert(trials[0].build.id=="build-1" and trials[0].created_at==10.0 and trials[0].updated_at==12.0)
	var newer=evaluation.duplicate(true);newer.state="completed";newer.updated_at=15.0;newer.report={"summary":{"outcome":"equivalent"}}
	var merged=StateView.project({"schema_version":2,"recent":[evaluation],"active":[newer],"worker":{"available":true}})
	assert(merged.size()==1 and merged[0].state=="completed" and merged[0].evidence.summary.outcome=="equivalent")
	merged[0].input.kind="mutated"
	assert(evaluation.input.request.kind=="evaluation" and newer.input.request.kind=="evaluation","Projection must not mutate source request")
	var scalar_build=evaluation.duplicate(true);scalar_build.input.build="retained-build-id"
	var scalar=StateView.project({"schema_version":2,"recent":[scalar_build],"worker":null})
	assert(scalar.size()==1 and scalar[0].build=="retained-build-id" and scalar[0].stale)
	var field={"input":{"id":"field-freshness","agent":"watchkeeper"},"state":"completed","summary":{"source_observed_at":123.0,"outcome":"no_findings"}}
	var fields=StateView.project({"schema_version":2,"recent":[],"field_runs":[field]})
	assert(fields[0].source_observed_at==123.0 and fields[0].evidence.summary.source_observed_at==123.0)
	var invalid: Array=[null,{}, {"input":null}, {"input":{"request":null}}, {"input":{"request":{"id":{}}}}]
	for bad_field in ["report","summary","snapshot"]:
		var bad=evaluation.duplicate(true);bad[bad_field]="malformed";invalid.append(bad)
	var bad_report=evaluation.duplicate(true);bad_report.report={"findings":null};invalid.append(bad_report)
	var bad_source=evaluation.duplicate(true);bad_source.snapshot={"data":null};invalid.append(bad_source)
	assert(StateView.project({"schema_version":2,"recent":invalid,"active":invalid,"repairs":invalid,"field_runs":invalid,"worker":null}).is_empty(),"Malformed nested records are skipped without crashing")
	print("Godot state checks passed: disconnected, empty, stale, missing evidence, terminal and pending states")
	quit()
