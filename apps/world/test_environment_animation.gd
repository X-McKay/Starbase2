extends SceneTree
const Visual=preload("res://characters/model_visual.gd")
const Station=preload("res://workstations/interaction_station.gd")
const CAST={"mender":"repair","surveyor":"review","trainer":"gym"}
var failures:Array[String]=[]
func _initialize():run.call_deferred()
func check(ok:bool,message:String):
 if not ok and message not in failures:failures.append(message);printerr(message)
func run():
 create_timer(300).timeout.connect(func():push_error("Environment animation watchdog");quit(1))
 var records:Array=[]
 for id in CAST:
  for hz in [30,60,120]:
   var v=Visual.new();root.add_child(v);v.configure_definition(preload("res://characters/catalog.gd").get_definition(id));v.set_motion_profile(id)
   var station=Station.new();root.add_child(station);station.configure(CAST[id],v);station.rotation.y=.37
   v.rotation.y=.37;v.heading=.37
   for settle in range(hz):v.project(Vector3.ZERO,false,0,false,1.0/hz,"",.37)
   v.interaction_station=station
   var driver=v.environment_interaction;var contacts_seen:Dictionary={};var states:Array=[];var maximum_contact:=0.0;var maximum_step:=0.0;var last:Dictionary={};var worst:Dictionary={};var dt:float=1.0/hz
   for frame in range(hz*9):
    v.project(Vector3.ZERO,false,0,false,dt,"console",.37)
    await process_frame
    if driver.state not in states:states.append(driver.state)
    for key in driver.contact_weights:
     contacts_seen[key]=true;maximum_contact=maxf(maximum_contact,driver.contact_errors[key]);check(driver.contact_errors[key]<.0091,id+": pressure requires actual palm contact")
    for side in ["Left","Right"]:
     var hand:Vector3=driver.hand_point(side)
     check(hand.is_finite(),id+": finite rigid hand skin probe")
     if last.has(side) and last[side].distance_to(hand)>maximum_step:
      maximum_step=last[side].distance_to(hand);worst={"side":side,"frame":frame,"state":driver.state}
     last[side]=hand
    check(not v.work_slate.visible,id+": station hands suppress handheld slate")
   check(contacts_seen.has("left_key") and contacts_seen.has("right_key"),id+": both actual keys contacted")
   check(contacts_seen.has("control" if id in ["mender","watchkeeper"] else "screen"),id+": role gesture meets physical target")
   check(maximum_step<.08,id+": continuous prepared/use/gesture motion")
   for interrupted in [.08,.22,.62,5.7]:
    for frame in range(int(interrupted*hz)):v.project(Vector3.ZERO,false,0,false,dt,"console",.37)
    v.interaction_station=null
    for frame in range(int(hz*.4)):
     v.position.x+=dt
     v.project(Vector3(dt,0,0),true,0,false,dt,"",PI/2)
     await process_frame
     check(driver.contact_weights.is_empty(),id+": move/cancel immediately clears contact")
    check(driver.state=="neutral",id+": bounded return")
    check(float(station.active_weights.get("left_key",0))==0,id+": previous station feedback cleared")
    v.position=Vector3.ZERO;v.rotation.y=.37;v.heading=.37
   for settle in range(hz):v.project(Vector3.ZERO,false,0,false,1.0/hz,"",.37)
   v.interaction_station=station
   v.project(Vector3.ZERO,false,0,true,dt,"console",.37);await process_frame
   var neutral:Transform3D=driver.bone("LeftHand")
   for frame in 10:v.project(Vector3.ZERO,false,0,true,dt,"console",.37);await process_frame
   check(driver.state=="neutral" and driver.contact_weights.is_empty(),id+": reduced motion neutral")
   check(neutral.is_equal_approx(driver.bone("LeftHand")),id+": reduced motion static")
   v.interaction_station=null
   for frame in range(hz*2):v.project(Vector3.ZERO,false,0,false,dt,"console",.37)
   check(v.work_slate.visible,id+": legacy field equipment fallback restored")
   records.append({"id":id,"hz":hz,"states":states,"contacts":contacts_seen.keys(),"max_contact_m":maximum_contact,"max_rigid_contact_step_m":maximum_step,"worst":worst})
   station.free();v.free();await process_frame
 print("Environment animation: ",JSON.stringify(records))
 print("ENVIRONMENT_ANIMATION_PASSED" if failures.is_empty() else "ENVIRONMENT_ANIMATION_FAILED")
 quit(0 if failures.is_empty() else 1)
