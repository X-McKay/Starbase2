extends "res://capture_new_cast_contacts.gd"
## Dense independent skin check after engine frames, including blended transitions.
func run() -> void:
	var roles=["operator","mender","surveyor","trainer","watchkeeper","reviewer","cybercat"]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--contact-role="):roles=[argument.trim_prefix("--contact-role=")]
	var failures:Array=[]
	var results:Array=[]
	for role in roles:
		visual=Visual.new();root.add_child(visual)
		visual.configure_definition(preload("res://characters/catalog.gd").get_definition(role))
		var worst:=INF
		for mode in ["idle","walk","run","stop","reduced"]:
			for frame in 33:
				var moving:bool=mode in ["walk","run"]
				visual.project(Vector3(0,0,.2 if mode=="run" else .1) if moving else Vector3.ZERO,moving,float(frame)/33.0,mode=="reduced",1.0/30.0)
				await process_frame
				var measured:Dictionary=points()
				worst=minf(worst,measured.floor_skin_min)
				if measured.floor_skin_min < -.003:
					failures.append("%s %s phase %d: %.5f" % [role,mode,frame,measured.floor_skin_min])
		results.append({"role":role,"minimum_skin_y":worst,"probes":visual.sole_contact.probes.size()})
		visual.queue_free();await process_frame
	var file=FileAccess.open("/tmp/starbase-sole-results-"+str(roles[0])+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"results":results,"failures":failures},"  "));file.close()
	for failure in failures:push_error(failure)
	print("SOLE_CONTACT_CHECK failures=",failures.size());quit(0 if failures.is_empty() else 1)
