extends RefCounted
## Local workstation choreography. These are cosmetic gestures, never run phases.
var owner:Node3D
var skeleton:Skeleton3D
var state:="neutral"
var elapsed:=0.0
var blend:=0.0
var contact_errors:Dictionary={}
var contact_weights:Dictionary={}
var lengths:Dictionary={}
var last_rotations:Dictionary={}
var entry_hands:Dictionary={}
var last_hands:Dictionary={}
var hand_probes:Dictionary={}
var character_id:=""
var current_probes:Dictionary={}
var maximum_error:=0.0
var unreachable_targets:Array=[]
var prior_station:Node3D
var returning:=false
var enabled:=true
var action:="neutral"
const SEQUENCES:={
 "operator":[["type",1.5],["read",1.4],["point",1.0],["type",1.4],["compare",1.2]],
 "mender":[["type",1.8],["inspect",1.2],["control",1.1],["type",1.5],["read",1.4]],
 "surveyor":[["type",1.6],["compare",1.4],["annotate",1.1],["read",1.8],["type",1.2]],
 "trainer":[["type",1.2],["demonstrate",1.2],["type",1.2],["scan",1.2],["point",1.0]],
 "watchkeeper":[["scan",1.8],["type",1.2],["control",1.0],["read",2.2],["type",1.0]],
 "reviewer":[["type",1.5],["compare",1.3],["control",1.1],["annotate",1.4],["type",1.3],["read",1.5]]}

func sequence_sample(style:String,time:float) -> Dictionary:
 var sequence:Array=SEQUENCES.get(style,SEQUENCES.operator)
 var total:=0.0
 for item in sequence:total+=float(item[1])
 var cursor:=fposmod(maxf(0,time),total)
 for item in sequence:
  var duration:=float(item[1])
  if cursor<duration:return {"action":str(item[0]),"progress":cursor/duration,"duration":duration,"total":total}
  cursor-=duration
 return {"action":"read","progress":0.0,"duration":1.0,"total":total}

func configure(visual:Node3D,identity:String) -> void:
 owner=visual;skeleton=owner.skeleton;character_id=identity
 enabled=false
 if not FileAccess.file_exists("res://characters/hand_contact_probes.json"):return
 var data=JSON.parse_string(FileAccess.get_file_as_string("res://characters/hand_contact_probes.json"))
 if not data is Dictionary or not data.has(character_id) or not data[character_id] is Dictionary:return
 hand_probes=data
 for side in ["Left","Right"]:
  for suffix in ["Arm","ForeArm","Hand"]:
   if skeleton.find_bone(side+suffix)<0:return
  var hand_data=data[character_id].get(side,{})
  if not hand_data is Dictionary:return
  for kind in ["keyboard","screen"]:
   var point=hand_data.get(kind,[])
   if not point is Array or point.size()!=3:return
   for value in point:
    if not (value is float or value is int) or not is_finite(float(value)):return
 enabled=true
 for side in ["Left","Right"]:
  var a:=bone(side+"Arm");var b:=bone(side+"ForeArm");var c:=bone(side+"Hand")
  lengths[side]=Vector2(a.origin.distance_to(b.origin),b.origin.distance_to(c.origin))

func bone(name:String) -> Transform3D:
 return skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(name))
func turn(name:String,rotation:Quaternion) -> void:
 var index:=skeleton.find_bone(name);var parent:=skeleton.get_bone_parent(index)
 var parent_basis:=skeleton.global_basis*skeleton.get_bone_global_pose(parent).basis
 skeleton.set_bone_pose_rotation(index,parent_basis.orthonormalized().get_rotation_quaternion().inverse()*rotation)
 skeleton.force_update_all_bone_transforms()
func _ease(t:float) -> float:
 var x:=clampf(t,0,1);return x*x*x*(x*(x*6-15)+10)
func probe(side:String,kind:String) -> Vector3:
 var point:Array=hand_probes[character_id][side][kind]
 return Vector3(float(point[0]),float(point[1]),float(point[2]))
func hand_point(side:String) -> Vector3:
 # Calibrated rigid skin point; not independent finger articulation.
 return bone(side+"Hand")*current_probes.get(side,probe(side,"keyboard"))
func solve(side:String,target:Transform3D,amount:float) -> void:
 var a:=side+"Arm";var b:=side+"ForeArm";var c:=side+"Hand"
 var before:Dictionary={}
 for name in [a,b,c]:before[name]=skeleton.get_bone_pose_rotation(skeleton.find_bone(name))
 var start:=bone(a).origin;var lens:Vector2=lengths[side]
 var line:=target.origin-start;var distance:=clampf(line.length(),absf(lens.x-lens.y)+.0001,lens.x+lens.y-.0001)
 var axis:=line.normalized();var end:=start+axis*distance
 var along:float=(lens.x*lens.x-lens.y*lens.y+distance*distance)/(2*distance)
 var pole:Vector3=owner.global_basis*Vector3(1 if side=="Left" else -1,-.4,-.2)
 var bend:Vector3=(pole-axis*pole.dot(axis)).normalized()
 var elbow:=start+axis*along+bend*sqrt(maxf(0,lens.x*lens.x-along*along))
 turn(a,Quaternion((bone(b).origin-start).normalized(),(elbow-start).normalized())*bone(a).basis.orthonormalized().get_rotation_quaternion())
 var fore:=bone(b)
 turn(b,Quaternion((bone(c).origin-fore.origin).normalized(),(end-fore.origin).normalized())*fore.basis.orthonormalized().get_rotation_quaternion())
 turn(c,target.basis.get_rotation_quaternion())
 for name in [a,b,c]:
  var index:=skeleton.find_bone(name)
  skeleton.set_bone_pose_rotation(index,before[name].slerp(skeleton.get_bone_pose_rotation(index),amount))
 skeleton.force_update_all_bone_transforms()

func project(station:Node3D,active:bool,reduced:bool,delta:float) -> void:
 contact_weights.clear();contact_errors.clear();unreachable_targets.clear()
 if not enabled:
  if is_instance_valid(prior_station) and prior_station.has_method("present_contacts"):prior_station.present_contacts({})
  if is_instance_valid(station) and station.has_method("present_contacts"):station.present_contacts({})
  action="neutral";return
 var valid:=enabled and is_instance_valid(station) and station.has_method("contacts")
 var targets:Dictionary=station.contacts() if valid else {}
 for key in ["left_key","right_key","screen","control"]:
  if not targets.has(key) or not targets[key] is Transform3D:valid=false
 active=active and valid and not reduced and delta>0 and delta<=.25
 if active:active=absf(angle_difference(owner.global_rotation.y,station.global_rotation.y))<.12
 if is_instance_valid(prior_station) and prior_station!=station and prior_station.has_method("present_contacts"):prior_station.present_contacts({})
 if reduced or not enabled:
  state="neutral";action="neutral";elapsed=0;blend=0;last_rotations.clear();returning=false
 elif not active:
  elapsed=0
  if not last_rotations.is_empty() and blend>0:
   var return_duration:=.32 if is_instance_valid(owner.seating_station) else .18
   state="return";action="return";blend=maxf(0,blend-delta/return_duration);returning=true
   for name in last_rotations:
    var index:=skeleton.find_bone(name)
    skeleton.set_bone_pose_rotation(index,skeleton.get_bone_pose_rotation(index).slerp(last_rotations[name],_ease(blend)))
  else:state="neutral";action="neutral";returning=false;last_rotations.clear()
 else:
  if elapsed==0 or returning:
   entry_hands.clear()
   for side in ["Left","Right"]:entry_hands[side]=last_hands.get(side,owner.global_transform.affine_inverse()*bone(side+"Hand"))
   if returning:blend=0;returning=false
  elapsed+=delta;blend=minf(1,blend+delta/.46)
  var style:String=owner.motion_profile
  var sample:=sequence_sample(style,maxf(0,elapsed-.46))
  action="prepare" if blend<1 else str(sample.action)
  state="prepare" if blend<1 else "type" if action=="type" else "gesture" if action in ["point","control","demonstrate","annotate"] else "read"
  var progress:float=float(sample.progress)
  var contacts:Dictionary={"Left":"left_key","Right":"right_key"}
  var gesture_edge:=.40 if style=="reviewer" else .28
  var gesture:=_ease(progress/gesture_edge)*(1-_ease((progress-(1.0-gesture_edge))/gesture_edge)) if state=="gesture" or action=="compare" else 0.0
  var screen:Transform3D=targets.screen
  var glance:=(sin(progress*PI)*.075 if action in ["compare","scan"] else .025) if style in ["surveyor","trainer","watchkeeper","reviewer"] else .015
  for side in ["Left","Right"]:
   var key:String=contacts[side];var touch:Transform3D=targets[key]
   # Palms hover between restrained alternating presses; no repeated arm flailing.
   var tap:=fposmod(elapsed*(2.6 if style=="trainer" else 2.0)+(0.5 if side=="Right" else 0.0),1.0)
   var type_blend:=sin(progress*PI) if state=="type" else 0.0
   var lift:=lerpf(.022,.016*(0.5-0.5*cos(TAU*tap)),type_blend)
   if (state=="gesture" or action=="compare") and side=="Right":
    key="control" if action=="control" else "screen"
    var destination:Transform3D=targets[key]
    if key=="screen":
     var trace:=Vector2(-.10+glance*.6,0)
     if action=="demonstrate":trace=Vector2(-.065,.02)
     elif action=="annotate":trace=Vector2(-.10+sin(progress*TAU)*.035,cos(progress*TAU)*.022)
     elif style=="trainer":trace.x=-.065 if int(elapsed/6.0)%2==0 else -.135
     elif style=="reviewer":trace=Vector2(-.10+sin(progress*TAU)*.025,cos(progress*TAU)*.018)
     destination.origin+=station.global_basis.x*trace.x+station.global_basis.y*trace.y
    touch=touch.interpolate_with(destination,gesture);lift=.022*(1-gesture)
   var normal:Vector3=station.global_basis.y.normalized()
   var forward:Vector3=station.global_basis.z.normalized()
   # Hand +Y follows the actual finger direction of these own rigs (cm skeleton).
   var wrist_basis:=Basis(station.global_basis.x.normalized(),forward,-normal).orthonormalized()
   var contact_probe:=probe(side,"keyboard")
   if key=="screen":contact_probe=contact_probe.lerp(probe(side,"screen"),_ease(gesture*2.0))
   current_probes[side]=contact_probe
   var clearance:Vector3=-forward*.003*gesture if key=="screen" else Vector3.ZERO
   var target:=Transform3D(wrist_basis,touch.origin+normal*lift+clearance-wrist_basis*(contact_probe*.01))
   var reachable:bool=bone(side+"Arm").origin.distance_to(target.origin)<lengths[side].x+lengths[side].y-.003
   if not reachable:unreachable_targets.append(key)
   target=(owner.global_transform*entry_hands[side]).interpolate_with(target,_ease(blend))
   solve(side,target,1.0)
   var error:=hand_point(side).distance_to(touch.origin)
   contact_errors[key]=error
   if blend>=1 and error<.009:
    contact_weights[key]=clampf(1-error/.009,0,1);maximum_error=maxf(maximum_error,error)
  # Look toward the real display, with role-specific compare/scan accents.
  var head:=bone("Head");var local:Vector3=owner.global_basis.inverse()*(screen.origin-head.origin)
  var yaw:=clampf(atan2(local.x+glance,local.z),-.18,.18)
  var pitch:=-clampf(atan2(local.y,Vector2(local.x,local.z).length()),-.25,.2)
  var rotation:=Quaternion(owner.global_basis.y,yaw*_ease(blend))*Quaternion(owner.global_basis.x,pitch*_ease(blend))*head.basis.orthonormalized().get_rotation_quaternion()
  turn("Head",rotation)
  last_rotations.clear()
  for name in ["LeftArm","LeftForeArm","LeftHand","RightArm","RightForeArm","RightHand","Head"]:last_rotations[name]=skeleton.get_bone_pose_rotation(skeleton.find_bone(name))
 last_hands.clear()
 for side in ["Left","Right"]:last_hands[side]=owner.global_transform.affine_inverse()*bone(side+"Hand")
 prior_station=station
 if is_instance_valid(station) and station.has_method("present_contacts"):station.present_contacts(contact_weights)

func project_exchange(partner:Node3D,role:String,reduced:bool,delta:float) -> void:
 contact_weights.clear();contact_errors.clear();unreachable_targets.clear()
 if is_instance_valid(prior_station) and prior_station.has_method("present_contacts"):prior_station.present_contacts({})
 prior_station=null
 var valid:=enabled and is_instance_valid(partner) and not reduced and delta>0 and delta<=.25
 if not valid:
  project(null,false,reduced,delta)
  return
 if state!="exchange":
  elapsed=0.0;blend=0.0;entry_hands.clear()
  for side in ["Left","Right"]:entry_hands[side]=owner.global_transform.affine_inverse()*bone(side+"Hand")
 elapsed+=delta;blend=minf(1.0,blend+delta/.52)
 state="exchange";action="handoff_give" if role=="giver" else "handoff_receive"
 var midpoint:Vector3=(owner.get_parent().global_position+partner.global_position)*.5+Vector3(0,1.12,0)
 var side:="Right"
 var forward:Vector3=(partner.global_position-owner.get_parent().global_position).normalized()
 var wrist_basis:=Basis(owner.global_basis.x.normalized(),forward,-Vector3.UP).orthonormalized()
 current_probes[side]=probe(side,"screen")
 var target:=Transform3D(wrist_basis,midpoint-wrist_basis*(current_probes[side]*.01))
 var reach:float=bone(side+"Arm").origin.distance_to(target.origin)
 if reach>=lengths[side].x+lengths[side].y-.003:unreachable_targets.append("handoff")
 target=(owner.global_transform*entry_hands[side]).interpolate_with(target,_ease(blend))
 solve(side,target,1.0)
 contact_errors.handoff=hand_point(side).distance_to(midpoint)
 if blend>=1 and float(contact_errors.handoff)<.014:contact_weights.handoff=1.0-float(contact_errors.handoff)/.014
 var head:=bone("Head")
 var look:Vector3=partner.global_position+Vector3(0,1.35,0)-head.origin
 if look.length()>0.01:
  var yaw:=clampf(atan2((owner.global_basis.inverse()*look).x,(owner.global_basis.inverse()*look).z),-.32,.32)
  turn("Head",Quaternion(owner.global_basis.y,yaw*_ease(blend))*head.basis.orthonormalized().get_rotation_quaternion())
 last_rotations.clear()
 for name in ["RightArm","RightForeArm","RightHand","Head"]:last_rotations[name]=skeleton.get_bone_pose_rotation(skeleton.find_bone(name))
 last_hands.clear()
 for hand_side in ["Left","Right"]:last_hands[hand_side]=owner.global_transform.affine_inverse()*bone(hand_side+"Hand")
