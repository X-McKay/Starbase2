extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json"
	world.board_fixture="__empty_visual_fixture__"
	root.add_child(world)
	await process_frame
	world.missions=[
		{"input":{"id":"shared-id","kind":"reviewer"},"state":"completed","stale":false,"evidence":{"summary":{"outcome":"field-result"}}},
		{"input":{"id":"shared-id","kind":"repair"},"state":"completed","stale":false,"evidence":{"summary":{"outcome":"repair-result"}}}]
	world.inspect_morning_record("shared-id","repair")
	var correct:bool=world.selected_mission().input.kind=="repair" and world.hud.evidence.text.contains("repair-result")
	if not correct: push_error("Exact station record selection must preserve context when different services share a run ID")
	var idle:bool=world.commands.payload.is_empty()
	world.queue_free(); await process_frame
	if correct and idle: print("EXACT_RECORD_SELECTION_PASSED: context+ID selects repair evidence independently of colliding field ID")
	quit(0 if correct and idle else 1)
