extends SceneTree
const Slate=preload("res://characters/work_slate.gd")
var failures:Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,message:String) -> void:
 if not ok and message not in failures:failures.append(message);printerr(message)
func run() -> void:
 var hands:=Skeleton3D.new();root.add_child(hands)
 hands.add_bone("LeftHand");hands.add_bone("RightHand")
 hands.set_bone_pose_position(0,Vector3(.2,1,0));hands.set_bone_pose_position(1,Vector3(-.2,1,0))
 var slate=Slate.new();root.add_child(slate);slate.configure(hands)
 slate.project(hands,true)
 var initial_span:float=slate.contact_span
 for bone in [0,1]:hands.set_bone_pose_rotation(bone,Quaternion(Vector3.RIGHT,.1))
 slate.project(hands,true)
 check(slate.global_basis.y.normalized().is_equal_approx(Vector3.UP.rotated(Vector3.RIGHT,.1)),"Equipment follows actual wrist rotation")
 check(is_equal_approx(slate.contact_span,initial_span),"Wrist rotation retains grip spacing")
 for bone in [0,1]:hands.set_bone_pose_rotation(bone,Quaternion(Vector3.RIGHT,.8))
 slate.project(hands,true)
 check(is_equal_approx(slate.wrist_tilt,Slate.MAX_WRIST_TILT),"Extreme wrist motion stays inside the equipment envelope")
 slate.project(hands,false);check(not slate.visible and slate.palm_normals.is_empty(),"Leaving pose clears visibility and wrist calibration")
 slate.project(hands,true);check(is_zero_approx(slate.wrist_tilt),"Reentry adopts current authored grip without stale recoil")
 hands.set_bone_pose_position(0,Vector3(-.2,1,0));slate.project(hands,true)
 check(not slate.visible and slate.global_transform.is_finite(),"Coincident hands cannot render a singular slate")
 hands.set_bone_pose_position(0,Vector3(-.2,2,0));slate.project(hands,true)
 check(not slate.visible,"Vertical degenerate grip is hidden")
 slate.queue_free();hands.queue_free();await process_frame
 var peaks:={}
 for role in ["operator","mender","surveyor","trainer","watchkeeper","reviewer","cybercat"]:
  var visual=preload("res://characters/model_visual.gd").new();root.add_child(visual);visual.configure_definition(preload("res://characters/catalog.gd").get_definition(role))
  await process_frame
  var peak:=0.0
  for frame in range(240):
   visual.project(Vector3.ZERO,false,0,false,1.0/60.0,"console",0)
   if visual.transition<=0:
    check(visual.work_slate.visible,role+": valid work grip remains visible")
    check(visual.work_slate.global_transform.is_finite(),role+": finite attachment")
    peak=maxf(peak,absf(visual.work_slate.wrist_tilt))
  peaks[role]=rad_to_deg(peak)
  visual.project(Vector3.ZERO,false,0,true,1.0/60.0,"console",0)
  check((visual.slate_choreography!=null and visual.slate_choreography.state=="docked") or (not visual.work_slate.visible and visual.work_slate.palm_normals.is_empty()),role+": reduced motion clears handling or retains static docked equipment")
  visual.project(Vector3(.05,0,0),true,.25,false)
  check(visual.slate_choreography!=null or not visual.work_slate.visible,role+": travel uses dock/stow or hides unsupported equipment")
  visual.queue_free();await process_frame
 print("Wrist tilt peaks (degrees): ",JSON.stringify(peaks))
 print("CREW_SLATE_CHECKS_PASSED" if failures.is_empty() else "CREW_SLATE_CHECKS_FAILED")
 quit(0 if failures.is_empty() else 1)
