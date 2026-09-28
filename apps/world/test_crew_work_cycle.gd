extends SceneTree
## Pose timing/contact checks; authoritative projection and physical routes stay separate.
const Visual=preload("res://characters/model_visual.gd")
const Catalog=preload("res://characters/catalog.gd")
var failures:Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,message:String) -> void:
 if not ok and message not in failures:failures.append(message);printerr(message)
func run() -> void:
 var measurements:Array=[]
 for role in ["mender","surveyor","trainer","watchkeeper","reviewer"]:
  for treatment in ["precise","deliberate"]:
   var pair:Array=[]
   for warmup in [30,177]:
    var v=Visual.new();root.add_child(v);v.configure_definition(Catalog.get_definition(role));v.set_motion_profile(role);v.set_work_treatment(treatment)
    for frame in range(warmup):v.project(Vector3.ZERO,false,0,false,1.0/60.0,"",0)
    pair.append(v)
   var first_equipment:=-1;var first_attention:=-1;var prior:Vector3;var max_step:=0.0
   for frame in range(120):
    for v in pair:v.project(Vector3.ZERO,false,0,false,1.0/60.0,"console",0)
    if frame%15==0:await process_frame
    var v=pair[0]
    check(is_equal_approx(pair[0].animation.current_animation_position,pair[1].animation.current_animation_position),role+": work cadence independent of earlier idle clock")
    var hand:Vector3=v.skeleton.to_global(v.skeleton.get_bone_global_pose(v.skeleton.find_bone("LeftHand")).origin)
    if frame>0:max_step=maxf(max_step,hand.distance_to(prior))
    prior=hand
    if v.work_slate.visible and first_equipment<0:first_equipment=frame
    if v.work_attention.envelope>0 and first_attention<0:first_attention=frame
    check(v.skeleton.global_transform.is_finite() and hand.is_finite(),role+": finite incoming pose")
    if v.transition>0 and v.slate_choreography==null:check(not v.work_slate.visible,role+": do not stretch equipment over an unfinished grip")
   check(first_equipment>=0 and first_attention>first_equipment,role+": reach/grip settles before attention starts")
   check(first_equipment<45,role+": bounded entry cannot become a long local wait")
   check(max_step<0.10,role+": controlled hand displacement at 60 Hz")
   measurements.append({"role":role,"treatment":treatment,"equipment_frame":first_equipment,"attention_frame":first_attention,"max_hand_step_m":max_step})
   var v=pair[0]
   var old_position:Vector3=v.position
   v.project(Vector3(.03,0,0),true,.2,false,1.0/60.0,"",PI/2)
   check(v.clip=="walk" and (v.slate_choreography!=null or not v.work_slate.visible) and v.work_attention.envelope==0,role+": interruption immediately returns to travel projection")
   check(is_equal_approx(v.position.x,old_position.x) and is_equal_approx(v.position.z,old_position.z),role+": work clock cannot move actor")
   v.project(Vector3.ZERO,false,0,true,1.0/60.0,"console",0)
   check(v.clip=="idle" and (v.slate_choreography!=null or not v.work_slate.visible) and v.work_attention.envelope==0,role+": reduced motion restores still pose")
   for item in pair:item.free()
   await process_frame
 print("Work cycle measurements: ",JSON.stringify(measurements))
 print("CREW_WORK_CYCLE_PASSED" if failures.is_empty() else "CREW_WORK_CYCLE_FAILED")
 quit(0 if failures.is_empty() else 1)
