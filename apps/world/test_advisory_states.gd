extends SceneTree
const Board=preload("res://command_board.gd")
func _initialize() -> void:
	var run={"input":{"inference":true},"state":"completed","report":{"advisory":{"status":"unavailable","reason":"Provider unavailable","calls":1}}}
	assert(Board.advisory_description(run).contains("UNAVAILABLE"))
	run.report.advisory={"status":"skipped","reason":"Daily inference admission limit reached","calls":0}
	assert(Board.advisory_description(run).contains("SKIPPED") and Board.advisory_description(run).contains("Daily inference"))
	run.report.advisory={"status":"unverified","advice":{"summary":"Advisory text","recommendation":"Inspect source"}}
	assert(Board.advisory_description(run).contains("UNVERIFIED") and Board.advisory_description(run).contains("Advisory text"))
	assert(not Board.advisory_description(run,false).contains("Advisory text"))
	run.report.advisory=null; run.state="failed"
	assert(Board.advisory_description(run).contains("observation failed"))
	run.input.inference=false
	assert(Board.advisory_description(run).contains("NOT REQUESTED"))
	run.input.inference=true; run.summary={"advisory_status":"unavailable","advisory_reason":"Model timeout"}
	assert(Board.advisory_description(run).contains("Model timeout"))
	run.summary={}; run.inference_budget={"status":"skipped","reason":"Inference cooldown active","used":1,"limit":8,"next_eligible_at":1000}
	assert(Board.advisory_description(run).contains("cooldown") and Board.advisory_description(run).contains("Next eligible"))
	print("ADVISORY_STATES_PASSED: unavailable, skipped, unverified, failed and not-requested remain distinct")
	quit()
