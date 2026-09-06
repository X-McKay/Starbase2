extends SceneTree
const Commands = preload("res://commands.gd")
var messages: Array[String] = []
var accepted: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	assert(Commands.local_origin("http://127.0.0.1:8787"))
	for url in ["https://example.org", "http://127.0.0.1:8787@evil.test", "http://127.0.0.1:8787/path", "http://127.0.0.1:99999"]:
		assert(not Commands.local_origin(url))
	var client := Commands.new()
	client.api = OS.get_cmdline_user_args()[0]
	root.add_child(client)
	client.accepted.connect(func(id): accepted.append(id))
	client.feedback.connect(func(message,pending):
		if not pending: messages.append(message))
	for id in ["normal","forbidden","lost-response","uncertain"]:
		messages.clear()
		client.submit("/v3/repairs",{"id":id,"scenario":"clamp-v1","mode":"control-good"},id)
		# Duplicate input while pending must never dispatch a second request.
		client.submit("/v3/repairs",{"id":"duplicate"},"duplicate")
		while messages.is_empty(): await process_frame
		if id=="uncertain":
			assert(client.uncertain)
			messages.clear()
			client.submit("/v3/repairs",{"id":"must-not-dispatch"},"must-not-dispatch")
			while messages.is_empty(): await process_frame
			assert(not client.uncertain)
	for action in [
		["/v4/repositories",{"repository":"fixture/command","generation":0},"repo-change","/v4/repositories"],
		["/v4/memory/review",{"id":"memory-change","revision":0,"decision":"approve"},"memory-change","/v4/snapshot"]
	]:
		messages.clear()
		client.submit(action[0],action[1],action[2],action[3])
		while messages.is_empty(): await process_frame
		assert(not client.uncertain)
	assert(accepted==["normal","lost-response","uncertain","repo-change","memory-change"])
	print("Native command checks passed: local origin, session, denial, pending deduplication, lost response, reconciliation without redispatch")
	client.queue_free()
	await process_frame
	quit()
