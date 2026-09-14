extends Node
## Runs the actual command state machine through the Web bridge against isolated Core.
var client: Node
var notices: Array[String] = []
var accepted: Array[String] = []
var damage_write := false

func _ready() -> void:
	client = load("res://commands.gd").new()
	add_child(client)
	client.accepted.connect(func(id: String): accepted.append(id))
	client.feedback.connect(func(message: String, pending: bool):
		if pending and damage_write and message.begins_with("Request pending"):
			client.http.body_size_limit = 1
		if not pending: notices.append(message))
	if not OS.has_feature("web"):
		client.api = OS.get_cmdline_user_args()[0]
	call_deferred("run_checks")

func report(message: String) -> void:
	print(message)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("var result=document.getElementById('command-result'); if(!result){result=document.createElement('pre');result.id='command-result';result.style.cssText='position:fixed;z-index:9999;inset:12px;background:white;color:black;white-space:pre-wrap';document.body.append(result);}result.textContent=" + JSON.stringify(message), true)

func settle() -> void:
	var deadline := Time.get_ticks_msec() + 12000
	while client.phase != "" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if client.phase != "":
		report("FAIL: command did not settle before deadline")
		client.http.cancel_request()

func run_checks() -> void:
	var id := "godot-web-controlled"
	var data := {"id": id, "kind": "review", "target": "sample", "profile": "surveyor-v1", "inference": false}
	client.submit("/v2/runs", data, id)
	client.submit("/v2/runs", {"id": "must-not-dispatch"}, "must-not-dispatch")
	await settle()
	if accepted != [id]: report("FAIL: actual Godot command session/write/duplicate fencing"); return
	report("Godot command accepted through browser-managed session")
	damage_write = true
	id = "godot-web-uncertain"
	data.id = id
	client.submit("/v2/runs", data, id)
	await settle()
	if not client.uncertain: report("FAIL: unreadable write/reconciliation did not preserve uncertainty"); return
	damage_write = false
	client.http.body_size_limit = 2097152
	client.submit("/v2/runs", data, id)
	await settle()
	if client.uncertain or accepted != ["godot-web-controlled", id]: report("FAIL: uncertain write did not reconcile exactly"); return
	client.submit("/v2/runs/godot-web-controlled/cancel", {}, "godot-web-controlled")
	await settle()
	if accepted.size() != 3: report("FAIL: stop request"); return
	report("PASS: actual Godot Web adapter, browser session, controlled command, pending duplicate fence, uncertain-write GET reconciliation, stop dispatch")
	if not OS.has_feature("web"): get_tree().quit()
