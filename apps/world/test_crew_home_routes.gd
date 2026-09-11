extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	world.fixture_path="res://../../fixtures/world/stale.json";world.board_fixture="__empty_visual_fixture__"
	root.add_child(world);await process_frame;await physics_frame
	var anchors:Array=load("res://shift_change_anchors.gd").collect(world)
	var failures:Array=[];var pairs:=0
	if anchors.size()<7: failures.append("At least seven authored home anchors required")
	for anchor in anchors:
		for kind in world.crew_motions:
			var station:Vector3=world.crew_motions[kind].workstation
			for endpoints in [[station,anchor.position],[anchor.position,station]]:
				var route:PackedVector3Array=world.navigator.route(endpoints[0],endpoints[1])
				if route.is_empty(): failures.append(str(anchor.id)+" unreachable for "+kind+" from "+str(endpoints[0])+" to "+str(endpoints[1]))
				elif not world.navigator.clear_start_segment(Vector2(route[-1].x,route[-1].z),Vector2(endpoints[1].x,endpoints[1].z)):
					failures.append(str(anchor.id)+" final authored segment blocked for "+kind)
				pairs+=1
	world.queue_free();await process_frame
	for failure in failures: push_error(failure)
	print("CREW_HOME_ROUTES: anchors=",anchors.size()," directed_routes=",pairs," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
