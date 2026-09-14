extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var window:Window=root
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json"
	world.board_fixture="__empty_visual_fixture__"
	root.add_child(world)
	for frame in 8: await process_frame
	print("NATIVE_WINDOW_INITIAL window=%s root=%s content_scale=%s viewport=%s" % [window.size,root.size,root.content_scale_size,window.get_viewport().get_visible_rect().size])
	window.size=Vector2i(800,640)
	for frame in 8: await process_frame
	print("NATIVE_WINDOW_COMPACT window=%s root=%s content_scale=%s viewport=%s" % [window.size,root.size,root.content_scale_size,window.get_viewport().get_visible_rect().size])
	if window.get_viewport().get_visible_rect().size!=Vector2(800,640):
		push_error("Compact viewport must reflow rather than scale the fixed canvas"); quit(1); return
	window.size=Vector2i(1280,800)
	for frame in 8: await process_frame
	print("NATIVE_WINDOW_WIDE window=%s root=%s content_scale=%s viewport=%s" % [window.size,root.size,root.content_scale_size,window.get_viewport().get_visible_rect().size])
	if window.get_viewport().get_visible_rect().size!=Vector2(1280,800):
		push_error("Wide viewport must match actual window size"); quit(1); return
	print("NATIVE_WINDOW_SIZE_PASSED")
	world.queue_free(); await process_frame; quit()
