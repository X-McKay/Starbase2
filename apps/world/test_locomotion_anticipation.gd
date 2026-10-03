extends SceneTree
## A measured corner, stop and reduced-motion check on imported crew rigs.
const Catalog=preload("res://characters/catalog.gd")
const Visual=preload("res://characters/model_visual.gd")
const Gait=preload("res://characters/gait.gd")
var failures:Array[String]=[]

func _initialize() -> void:
	run.call_deferred()

func check(value:bool,message:String) -> void:
	if not value:failures.append(message)

func step(visual:Node3D,gait:RefCounted,travel:Vector3,dt:float,reduced:=false) -> void:
	gait.advance(travel.length(),2.0)
	visual.project(travel,gait.moving,gait.phase,reduced,dt)

func run() -> void:
	for role in ["mender","trainer","watchkeeper"]:
		for hz in [30,60,120]:
			var visual=Visual.new();root.add_child(visual)
			visual.configure_definition(Catalog.get_definition(role))
			visual.set_motion_profile(role)
			var gait=Gait.new()
			var dt:=1.0/float(hz)
			for frame in hz:step(visual,gait,Vector3(0,0,2.0*dt),dt)
			var before:Quaternion=visual.skeleton.get_bone_pose_rotation(visual.spine_bone)
			step(visual,gait,Vector3(2.0*dt,0,0),dt)
			var change:float=before.angle_to(visual.skeleton.get_bone_pose_rotation(visual.spine_bone))
			check(visual.turn_anticipation>0.02,"%s %d Hz: torso does not anticipate a right corner" % [role,hz])
			check(change>0.01,"%s %d Hz: imported torso has no visible corner response" % [role,hz])
			check(visual.rotation.y<0.20,"%s %d Hz: root snaps toward the new heading" % [role,hz])
			step(visual,gait,Vector3.ZERO,dt)
			check(visual.stop_recovery<0.0,"%s %d Hz: no stopping response" % [role,hz])
			for frame in hz:step(visual,gait,Vector3.ZERO,dt)
			check(absf(visual.turn_anticipation)<0.003,"%s %d Hz: anticipation remains after stopping" % [role,hz])
			check(absf(visual.stop_recovery)<0.001,"%s %d Hz: stopping response remains after rest" % [role,hz])
			step(visual,gait,Vector3(2.0*dt,0,0),dt,true)
			check(visual.turn_anticipation==0.0,"%s %d Hz: reduced motion retains turn overlay" % [role,hz])
			visual.queue_free();await process_frame
	for failure in failures:push_error(failure)
	if failures.is_empty():print("LOCOMOTION_ANTICIPATION_PASSED: 3 imported rigs at 30/60/120 Hz, corner, stop and reduced motion")
	quit(0 if failures.is_empty() else 1)
