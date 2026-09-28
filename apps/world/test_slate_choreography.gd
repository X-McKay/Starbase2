extends SceneTree
const Visual=preload("res://characters/model_visual.gd")
var failures:Array[String]=[]
func _initialize():run.call_deferred()
func check(ok:bool,message:String):
 if not ok and message not in failures:failures.append(message);printerr(message)
func run():
 var records:Array=[]
 for treatment in ["precise","deliberate"]:
  for hz in [30,60,120]:
   var v=Visual.new();root.add_child(v);v.configure_definition(preload("res://characters/catalog.gd").get_definition("mender"));v.set_work_treatment(treatment);v.set_motion_profile("mender")
   var dt:float=1.0/hz;var states:Array=[];var prior:=Transform3D.IDENTITY;var max_step:=0.0;var max_transfer:=0.0;var previous_state:="";var largest_transfer:={}
   for segment in ["idle","work","walk_stow","work","cancel","work","reduced"]:
    for frame in range(hz*2):
     var moving:bool=segment=="walk_stow"
     if moving:v.position.x+=dt*1.3
     v.project(Vector3(dt*1.3,0,0) if moving else Vector3.ZERO,moving,float(frame%hz)/hz,segment=="reduced",dt,"console" if segment in ["work","reduced"] else "",0)
     if frame%10==0:await process_frame
     var c=v.slate_choreography;var local:Transform3D=v.global_transform.affine_inverse()*v.work_slate.global_transform
     check(v.work_slate.visible,"Rivet equipment cannot pop out of existence")
     if not previous_state.is_empty() and segment!="reduced":
      var distance:float=prior.origin.distance_to(local.origin)
      max_step=maxf(max_step,distance)
      if previous_state!=c.state and distance>max_transfer:
       max_transfer=distance;largest_transfer={"segment":segment,"frame":frame,"from":previous_state,"to":c.state}
     if c.state not in states:states.append(c.state)
     if c.state in ["lift","stow"]:
      var hand:Transform3D=c._hand("Left")*c.attachment
      check(hand.origin.distance_to(v.work_slate.global_position)<.001,"Rigid hand attachment must match actual joint")
      check(c.contact_error<.006,"Hand must reach authored trajectory without an unreachable stretch")
     if c.state=="docked":check(v.work_slate.global_position.distance_to(c._dock().origin)<.001,"Docked slate stays on its actual mount")
     check(local.is_finite(),"Finite equipment transformation")
     prior=local;previous_state=c.state
    if segment=="work":check(v.slate_choreography.state=="use","Work gesture reaches stable use in bounded time")
    if segment in ["walk_stow","cancel","reduced"]:check(v.slate_choreography.state=="docked","Interruption and motion return equipment to dock")
   for interruption in [.10,.50,.80]:
    for frame in range(int(hz*interruption)):v.project(Vector3.ZERO,false,0,false,dt,"console",0)
    for frame in range(hz*2):v.project(Vector3.ZERO,false,0,false,dt,"",0)
    check(v.slate_choreography.state=="docked","Fast completion must coalesce unfinished pickup back to dock")
   # Interruption while stowing must reverse from current attachment, without a jump.
   for frame in range(hz*2):v.project(Vector3.ZERO,false,0,false,dt,"console",0)
   for frame in range(int(hz*.25)):v.project(Vector3.ZERO,false,0,false,dt,"",0)
   var interrupted:Transform3D=v.work_slate.global_transform
   v.project(Vector3.ZERO,false,0,false,dt,"console",0)
   check(v.work_slate.global_position.distance_to(interrupted.origin)<.02,"New work coalesces a partial stow continuously")
   for frame in range(hz*2):v.project(Vector3.ZERO,false,0,false,dt,"console",0)
   check(v.slate_choreography.state=="use","Reentry reaches use without queued obsolete gestures")
   check(v.slate_choreography.maximum_transfer_error<.005,"Rigid attachment transfer must occur within 5 mm of actual contact")
   check(max_step<.065,"Handling must stay continuous at 30 Hz")
   check(v.slate_choreography.maximum_contact_error<.006,"All authored arm targets must remain inside the own-rig reach envelope")
   records.append({"treatment":treatment,"hz":hz,"states":states,"maximum_contact_error_m":v.slate_choreography.maximum_contact_error,"worst_contact":v.slate_choreography.worst_contact,"attachment_transfer_error_m":v.slate_choreography.maximum_transfer_error,"maximum_step_m":max_step,"transfer_step_m":max_transfer,"largest_transfer":largest_transfer})
   v.free();await process_frame
 print("Slate choreography: ",JSON.stringify(records))
 print("SLATE_CHOREOGRAPHY_PASSED" if failures.is_empty() else "SLATE_CHOREOGRAPHY_FAILED")
 quit(0 if failures.is_empty() else 1)
