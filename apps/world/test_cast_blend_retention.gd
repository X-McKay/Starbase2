extends SceneTree
## Frame processing must retain the blended pose written by project().
const Catalog=preload("res://characters/catalog.gd")
const Visual=preload("res://characters/model_visual.gd")
var failures:Array[String]=[]
var samples:Array=[]
var output:=""
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	run.call_deferred()
func snapshot(v:Node3D) -> Array:
	var result:Array=[]
	for bone in v.skeleton.get_bone_count():result.append([v.skeleton.get_bone_pose_rotation(bone),v.skeleton.get_bone_pose_position(bone)])
	return result
func run() -> void:
	for id in ["operator","mender","surveyor","trainer","watchkeeper","reviewer"]:
		var v=Visual.new();root.add_child(v);v.configure_definition(Catalog.get_definition(id));v.set_motion_profile(id)
		for frame in 30:v.project(Vector3.ZERO,false,0,false,1.0/60.0)
		for transition in ["idle_to_walk","walk_to_run"]:
			if transition=="walk_to_run":
				for frame in 30:v.project(Vector3(0,0,2.0/60),true,.25,false,1.0/60.0)
			v.project(Vector3(0,0,(2.0 if transition=="idle_to_walk" else 6.0)/60),true,.25,false,1.0/60.0)
			var before:=snapshot(v)
			await process_frame
			await process_frame
			var after:=snapshot(v)
			var max_angle:=0.0;var max_position:=0.0;var worst_bone:=""
			for bone in before.size():
				var angle:float=before[bone][0].angle_to(after[bone][0])
				if angle>max_angle:max_angle=angle;worst_bone=v.skeleton.get_bone_name(bone)
				max_position=maxf(max_position,before[bone][1].distance_to(after[bone][1]))
			samples.append({"id":id,"transition":transition,"max_rotation_change_rad":max_angle,"max_position_change_m":max_position,"worst_bone":worst_bone})
			if max_angle>.005 or max_position>.0001:failures.append(id+" "+transition+": frame processing replaced blended pose on "+worst_bone+" ("+str(max_angle)+" rad)")
		v.queue_free();await process_frame
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"samples":samples,"failures":failures},"  "));file.close()
	for failure in failures:push_error(failure)
	if failures.is_empty():print("CAST_BLEND_RETENTION_PASSED: engine frame processing retains all six rendered transition poses")
	quit(0 if failures.is_empty() else 1)
