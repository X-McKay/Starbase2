extends SceneTree
## Imported six-cast continuity diagnostic. Synthetic displacement, not collision QA.
const Catalog=preload("res://characters/catalog.gd")
const Visual=preload("res://characters/model_visual.gd")
const Gait=preload("res://characters/gait.gd")
const IDS=["operator","mender","surveyor","trainer","watchkeeper","reviewer"]
var failures:Array[String]=[]
var records:Array=[]
var seams:Array=[]
var output:=""
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	run.call_deferred()
func check(value:bool,message:String) -> void:
	if not value and message not in failures:failures.append(message)
func snapshot(v:Node3D) -> Array:
	v.skeleton.force_update_all_bone_transforms()
	var result:Array=[]
	for bone in v.skeleton.get_bone_count():
		result.append([v.skeleton.get_bone_pose_rotation(bone),v.skeleton.to_global(v.skeleton.get_bone_global_pose(bone).origin)])
	return result
func difference(a:Array,b:Array,v:Node3D) -> Dictionary:
	var angle:=0.0;var distance:=0.0;var angular_bone:="";var positional_bone:=""
	for i in a.size():
		var delta_angle:float=a[i][0].angle_to(b[i][0])
		var delta_distance:float=a[i][1].distance_to(b[i][1])
		if delta_angle>angle:angle=delta_angle;angular_bone=v.skeleton.get_bone_name(i)
		if delta_distance>distance:distance=delta_distance;positional_bone=v.skeleton.get_bone_name(i)
	return {"angle_rad":angle,"distance_m":distance,"angular_bone":angular_bone,"positional_bone":positional_bone}
func run() -> void:
	var selected:Array=Array(IDS)
	if "--cybercat-only" in OS.get_cmdline_user_args():selected=["cybercat"]
	for id in selected:
		var definition=Catalog.get_definition(id)
		var seam_visual=Visual.new();root.add_child(seam_visual);seam_visual.configure_definition(definition)
		for clip in ["idle","walk","run","work/field_slate","social/seated"]:
			var animation:Animation=seam_visual.animation.get_animation(clip)
			seam_visual.skeleton.reset_bone_poses();seam_visual.animation.play(clip)
			seam_visual.animation.seek(animation.length-0.00001,true)
			var before:=snapshot(seam_visual)
			seam_visual.animation.seek(0.00001,true)
			var d:=difference(before,snapshot(seam_visual),seam_visual)
			# Sub-millisecond loop sampling must not expose a perceptible pose jump.
			# Quaternion angle_to has a small single-precision numerical floor.
			check(d.distance_m<0.001,id+": loop position discontinuity in "+clip)
			check(d.angle_rad<0.005,id+": loop rotation discontinuity in "+clip)
			d.merge({"id":id,"clip":clip,"length_s":animation.length})
			seams.append(d)
		seam_visual.queue_free();await process_frame
		for hz in [30,60,120]:
			var v=Visual.new();root.add_child(v);v.configure_definition(definition);v.set_motion_profile(id)
			var gait=Gait.new()
			var dt:=1.0/float(hz)
			var previous:Array=[]
			for segment in [
				["idle",1.0,0.0,Vector3.BACK,"",false],
				["walk",3.0,2.0,Vector3.BACK,"",false],
				["run",3.0,6.0,Vector3.BACK,"",false],
				["turn90",1.5,6.0,Vector3.RIGHT,"",false],
				["reverse",1.5,6.0,Vector3.LEFT,"",false],
				["stop",3.0,0.0,Vector3.ZERO,"",false],
				["work",4.0,0.0,Vector3.ZERO,"console",false],
				["sit",3.0,0.0,Vector3.ZERO,"sit",false],
				["stand",3.0,0.0,Vector3.ZERO,"stand",false],
				["resume",2.0,2.0,Vector3.BACK,"",false],
				["reduced",1.0,6.0,Vector3.RIGHT,"",true]]:
				var maximum_angle:=0.0;var maximum_distance:=0.0;var angle_bone:="";var distance_bone:="";var max_heading_step:=0.0;var max_hair:=0.0
				var last_heading:float=v.rotation.y
				var first_sample:Dictionary={}
				for frame in int(round(segment[1]*hz)):
					var step:Vector3=segment[3]*segment[2]*dt
					var stride:float=definition.model_run_stride if segment[2]>5.2 else definition.model_stride
					gait.advance(step.length(),stride)
					v.project(step,gait.moving,gait.phase,segment[5],dt,segment[4])
					var current:=snapshot(v)
					for pose in current:check(pose[1].is_finite() and pose[0].is_finite(),id+": nonfinite pose at "+segment[0])
					if not previous.is_empty():
						var delta:=difference(previous,current,v)
						if frame==0:first_sample=delta
						if delta.angle_rad>maximum_angle:maximum_angle=delta.angle_rad;angle_bone=delta.angular_bone
						if delta.distance_m>maximum_distance:maximum_distance=delta.distance_m;distance_bone=delta.positional_bone
					previous=current
					max_heading_step=maxf(max_heading_step,absf(angle_difference(last_heading,v.rotation.y)));last_heading=v.rotation.y
					for bone in v.secondary_bones:
						var driver=v.secondary_bones[bone]
						max_hair=maxf(max_hair,driver.angles.length())
						check(driver.angles.length()<=definition.secondary_motion_limit+0.00001,id+": hair exceeds configured bound")
				if segment[0]=="stop":
					check(v.clip=="idle",id+": stopped clip is idle")
					for bone in v.secondary_bones:check(v.secondary_bones[bone].angles.length()<0.001,id+": hair settles after stopping")
				if segment[0]=="reduced":
					check(v.clip=="idle" and v.locomotion_lean==Vector2.ZERO,id+": reduced motion clears gait and lean")
					for bone in v.secondary_bones:check(v.secondary_bones[bone].angles==Vector2.ZERO,id+": reduced motion clears secondary driver")
				records.append({"id":id,"hz":hz,"segment":segment[0],"max_local_rotation_step_rad":maximum_angle,"angular_bone":angle_bone,"max_joint_world_step_m":maximum_distance,"positional_bone":distance_bone,"max_heading_step_rad":max_heading_step,"max_hair_angle_rad":max_hair,"entry_step":first_sample,"final_clip":v.clip})
			v.queue_free();await process_frame
	var report:={"scope":"synthetic displacement through actual imported rigs; no collision, mesh contact, frame-time benchmark or visual certification","hz":[30,60,120],"loop_seam_epsilon_seconds":0.00001,"loop_seams":seams,"segments":records,"failures":failures}
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	for failure in failures:push_error(failure)
	if failures.is_empty():print("CAST_MOTION_CONTINUITY_PASSED: ",selected.size()," selected rigs, 3 update rates, 11 segments; inspect numerical report and native video for smoothness")
	quit(0 if failures.is_empty() else 1)
