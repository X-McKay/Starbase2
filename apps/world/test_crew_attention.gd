extends SceneTree
var failures:Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,message:String) -> void:
 if not ok and message not in failures:failures.append(message);printerr(message)
func run() -> void:
 var report:={}
 for role in ["mender","surveyor","trainer","watchkeeper","reviewer"]:
  var visual=preload("res://characters/model_visual.gd").new();root.add_child(visual)
  visual.configure_definition(preload("res://characters/catalog.gd").get_definition(role));visual.set_motion_profile(role)
  var reference=preload("res://characters/model_visual.gd").new();root.add_child(reference)
  reference.configure_definition(preload("res://characters/catalog.gd").get_definition(role));reference.set_motion_profile(role)
  reference.work_attention.enabled=false
  var head:int=visual.skeleton.find_bone("Head")
  check(head>=0,role+": requires known Head joint")
  var peak:=0.0
  for frame in range(1080):
   visual.project(Vector3.ZERO,false,0,false,1.0/60.0,"console",0)
   reference.project(Vector3.ZERO,false,0,false,1.0/60.0,"console",0)
   if frame%120==0:await process_frame
   var rotation:Quaternion=visual.skeleton.get_bone_pose_rotation(head)
   peak=maxf(peak,rotation.angle_to(reference.skeleton.get_bone_pose_rotation(head)))
   for bone_name in ["LeftHand","RightHand","Hips","LeftFoot","RightFoot"]:
    var bone:int=visual.skeleton.find_bone(bone_name)
    if bone>=0:check(visual.skeleton.get_bone_global_pose(bone).is_equal_approx(reference.skeleton.get_bone_global_pose(bone)),role+": preserve authored "+bone_name+" contact")
   check(rotation.is_finite(),role+": finite head pose")
   check(visual.work_attention.offset.length()<deg_to_rad(12),role+": restrained focus envelope")
  check(peak>deg_to_rad(4.0),role+": observable distinct attention motion")
  report[role]={"peak_degrees":rad_to_deg(peak),"offset":str(visual.work_attention.offset)}
  for state in ["reduced","travel","hold","cancel"]:
   var travel:bool=state=="travel"
   visual.project(Vector3(.03,0,0) if travel else Vector3.ZERO,travel,.25,state=="reduced",1.0/60.0,"console" if state in ["travel","reduced"] else "",0)
   check(visual.work_attention.offset==Vector2.ZERO and visual.work_attention.elapsed==0,role+": "+state+" suppresses attention immediately")
  visual.free();reference.free();await process_frame
 # Authority projection must never grant the visual permission for stale or queued work.
 var presentation=preload("res://crew_presentation.gd").new()
 var run_record:={"input":{"id":"attention-run","candidate":"fixture"},"state":"running","stale":false,"updated_at":1}
 var context:String=preload("res://state.gd").context(run_record)
 check(presentation.update([run_record],context,false,false,1).pose=="console","Fresh actual work grants console pose")
 run_record.stale=true
 check(presentation.update([run_record],context,false,false,2).pose=="","Stale data suppresses detailed work")
 run_record.stale=false;run_record.state="cancel_requested"
 check(presentation.update([run_record],context,false,false,3).pose=="","Cancellation pending suppresses detailed work")
 run_record.state="queued"
 check(presentation.update([run_record],context,false,false,4).pose=="","Queued work does not imitate execution")
 print("Attention measurements: ",JSON.stringify(report))
 print("CREW_ATTENTION_CHECKS_PASSED" if failures.is_empty() else "CREW_ATTENTION_CHECKS_FAILED")
 quit(0 if failures.is_empty() else 1)
