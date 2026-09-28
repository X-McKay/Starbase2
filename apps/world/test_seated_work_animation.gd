extends SceneTree
class Chair:
 extends Node3D
 var height:=.90
 var weights:Dictionary={}
 func seat()->Dictionary:return {"frame":Transform3D(Basis.IDENTITY,Vector3(0,.625,-.76)),"floor_y":.145}
 func contacts()->Dictionary:
  return {"left_key":Transform3D(Basis.IDENTITY,Vector3(.15,height+.145,-.37)),"right_key":Transform3D(Basis.IDENTITY,Vector3(-.15,height+.145,-.37)),"control":Transform3D(Basis.IDENTITY,Vector3(-.23,height+.17,-.33)),"screen":Transform3D(Basis.IDENTITY,Vector3(0,1.65,.8))}
 func present_contacts(value:Dictionary):weights=value.duplicate()
 func set_seated_amount(_value:float):pass
 func seated_ready()->bool:return true
var failures:Array[String]=[]
func _initialize():run.call_deferred()
func check(ok:bool,message:String):
 if not ok and message not in failures:failures.append(message);printerr(message)
func run():
 create_timer(290).timeout.connect(func():push_error("Seated work test timeout");quit(1))
 var records:Array=[]
 for id in ["watchkeeper","reviewer"]:
  for hz in [30,60,120]:
   var actor:=Node3D.new();root.add_child(actor)
   var v=preload("res://characters/model_visual.gd").new();actor.add_child(v);v.configure_definition(preload("res://characters/catalog.gd").get_definition(id));v.set_motion_profile(id);v.support_sample=func(_point):return .145
   var station:=Chair.new();station.height=.90 if id=="watchkeeper" else .80;root.add_child(station)
   var dt:float=1.0/hz
   for frame in hz:v.project(Vector3.ZERO,false,0,false,dt,"",0)
   v.rotation.y=-.9;v.heading=-.9
   for frame in hz:v.project(Vector3.ZERO,false,0,false,dt,"",-.9)
   v.seating_station=station;v.interaction_station=station
   var contacts:Dictionary={};var max_slide:=0.0;var min_sole:=INF;var prior:Dictionary={};var prior_phase:Dictionary={};var max_alignment:=0.0;var max_hand_step:=0.0;var max_contact:=0.0;var prior_hands:Dictionary={};var worst_hand:Dictionary={};var worst_foot:Dictionary={}
   for segment in ["sit","hold","sit","stand"]:
    for frame in range(hz*(10 if segment=="sit" else 2)):
     v.interaction_station=station if segment=="sit" else null
     v.project(Vector3.ZERO,false,0,false,dt,"sit" if segment!="stand" else "stand",0)
     if frame%10==0 or "--fast" not in OS.get_cmdline_user_args():await process_frame
     var feet=v.seated_footwork
     for side in feet.sole_points:
      var point:Vector3=feet.sole_points[side];min_sole=minf(min_sole,feet.sole_clearances[side])
      if prior.has(side) and feet.foot_phase[side]=="planted" and prior_phase.get(side)=="planted":
       var slide:=Vector2(point.x-prior[side].x,point.z-prior[side].z).length()
       if slide>max_slide:max_slide=slide;worst_foot={"side":side,"frame":frame,"segment":segment,"point":str(point),"prior":str(prior[side])}
      prior[side]=point;prior_phase[side]=feet.foot_phase[side]
     max_alignment=maxf(max_alignment,Vector2(v.seat_alignment_offset.x,v.seat_alignment_offset.z).length())
     if not v.social_transition_finished or segment!="sit":check(v.environment_interaction.contact_weights.is_empty(),id+": no contact before settled or afterinvalidated")
     for key in v.environment_interaction.contact_weights:
      contacts[key]=true;max_contact=maxf(max_contact,v.environment_interaction.contact_errors[key])
      check(v.environment_interaction.contact_errors[key]<.0091,id+": actual rigid hand contact within9mm")
     for side in ["Left","Right"]:
      var point:Vector3=v.environment_interaction.hand_point(side)
      check(point.is_finite(),id+": finite rigid hand skin probe")
      if prior_hands.has(side) and point.distance_to(prior_hands[side])>max_hand_step:
       max_hand_step=point.distance_to(prior_hands[side]);worst_hand={"side":side,"frame":frame,"segment":segment,"state":v.environment_interaction.state,"clip":v.clip}
      prior_hands[side]=point
     if segment in ["sit","hold"] and v.social_transition_finished:check(v.seat_reference_error<.001,id+": actual authoredseat reference aligned")
    if segment=="stand":check(v.seat_alignment_offset.length()<.25 and Vector2(v.position.x,v.position.z).length()<.001,id+": returns to physicalapproach beforewalking")
   check(contacts.has("left_key") and contacts.has("right_key") and contacts.has("control"),id+": both keys and reachablecontrol")
   check(max_hand_step<.08,id+": continuous seated hand motion")
   check(max_alignment<=.4501,id+": bounded cosmeticchairalignment")
   check(min_sole>=-.004,id+": actualsole stays abovefloor")
   check(max_slide<.005,id+": planted sole horizontaldrift below5mm/frame")
   check(v.seated_footwork.maximum_reach_error<.025,id+": ownleg reach remains bounded")
   # Reduced motion adopted partway through entry stays seated when restored.
   v.seating_station=null
   for frame in hz:v.project(Vector3.ZERO,false,0,false,dt,"",0)
   v.seating_station=station
   for frame in range(hz/3):v.project(Vector3.ZERO,false,0,false,dt,"sit",0)
   v.project(Vector3.ZERO,false,0,true,dt,"sit",0);await process_frame
   var seated:Vector3=v.environment_interaction.bone("Hips").origin
   v.project(Vector3.ZERO,false,0,false,dt,"sit",0);await process_frame
   check(seated.distance_to(v.environment_interaction.bone("Hips").origin)<.015,id+": restoringmotion doesnotreplaysit")
   records.append({"id":id,"hz":hz,"worst_foot":worst_foot,"worst_hand":worst_hand,"max_rigid_contact_step_m":max_hand_step,"max_contact_m":max_contact,"max_planted_slide_m":max_slide,"minimum_sole_clearance_m":min_sole,"max_own_leg_error_m":v.seated_footwork.maximum_reach_error,"contacts":contacts.keys(),"max_alignment_m":max_alignment})
   actor.free();station.free();await process_frame
 print("SEATED_WORK_MEASUREMENTS ",JSON.stringify(records))
 print("SEATED_WORK_ANIMATION_PASSED" if failures.is_empty() else "SEATED_WORK_ANIMATION_FAILED");quit(0 if failures.is_empty() else 1)
