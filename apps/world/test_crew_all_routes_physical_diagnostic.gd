extends SceneTree
## Exhaustive authored home/work pairs using current world bodies and doors.
var failures:Array=[]
var records:Array=[]
func _initialize()->void:run.call_deferred()
func run()->void:
	var world=load("res://main.tscn").instantiate();world.fixture_path="res://../../fixtures/world/stale.json";world.board_fixture="__empty_visual_fixture__"
	root.add_child(world);await process_frame
	for i in range(5):await physics_frame
	var anchors:Array=world.collect_home_anchors()
	var stations:Dictionary={}
	for kind in world.crew_motions:stations[kind]=world.crew_motions[kind].workstation
	for anchor in anchors:
		for direction in ["work-to-home","home-to-work"]:
			var samples:Dictionary={}
			for kind in world.crew_motions:
				var m=world.crew_motions[kind]
				m.project({"goal":"hold"});m.release_anchor()
				# Isolate each route case at its authored start; no teleport after dispatch.
				var start:Vector3=stations[kind] if direction=="work-to-home" else anchor.position
				var target:Vector3=anchor.position if direction=="work-to-home" else stations[kind]
				m.actor.position=start;m.actor.last_position=start;m.previous=start
				m.workstation=target;m.project({"goal":"workstation","pose":"console"})
				samples[kind]={"previous":start,"distance":0.0,"max_step":0.0,"arrived":false,"target":target,"blocked":false,"ticks":0}
			for tick in range(9000):
				await physics_frame
				var done:=true
				for kind in world.crew_motions:
					var m=world.crew_motions[kind];var s:Dictionary=samples[kind]
					var step:float=m.actor.position.distance_to(s.previous)
					s.distance+=step;s.max_step=maxf(s.max_step,step);s.previous=m.actor.position
					if not s.arrived and not s.blocked:
						s.ticks=tick+1
						if m.route_blocked:s.blocked=true
						elif m.path.is_empty() and m.actor.motion.is_zero_approx() and m.actor.position.distance_to(s.target)<.15:s.arrived=true
						else:done=false
				if done:break
			for kind in world.crew_motions:
				var s:Dictionary=samples[kind];var m=world.crew_motions[kind]
				var result={"anchor":anchor.id,"direction":direction,"kind":kind,"arrived_stopped":s.arrived,"blocked":s.blocked,"distance":s.distance,"max_frame_step":s.max_step,"end_error":m.actor.position.distance_to(s.target),"ticks":s.ticks}
				records.append(result)
				if not s.arrived or s.blocked or s.max_step>1.3/60.0+.015:failures.append(result)
			print("PHYSICAL_PAIR_BATCH ",anchor.id," ",direction," total=",records.size()," failures=",failures.size())
	check_no_effects(world)
	FileAccess.open("res://../../evidence/crew-motion-validation/travel/all-routes-physical.json",FileAccess.WRITE).store_string(JSON.stringify({"records":records,"failures":failures,"setup":"Each test case places bodies at authored start, then moves entirely through physics; collision/door handling unchanged. Actors do not collide with each other in production."},"  "))
	print("ALL_ROUTES_PHYSICAL: routes=",records.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
func check_no_effects(world)->void:
	if not world.commands.payload.is_empty() or world.http.get_http_client_status()!=HTTPClient.STATUS_DISCONNECTED:failures.append("Unexpected dispatch or connection")
