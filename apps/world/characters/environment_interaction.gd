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
  return
 var valid:=enabled and is_instance_valid(station) and station.has_method("contacts")
 var targets:Dictionary=station.contacts() if valid else {}
 for key in ["left_key","right_key","screen","control"]:
  if not targets.has(key) or not targets[key] is Transform3D:valid=false
 active=active and valid and not reduced and delta>0 and delta<=.25
 if active:active=absf(angle_difference(owner.global_rotation.y,station.global_rotation.y))<.12
 if is_instance_valid(prior_station) and prior_station!=station and prior_station.has_method("present_contacts"):prior_station.present_contacts({})
 if reduced or not enabled:
  state="neutral";elapsed=0;blend=0;last_rotations.clear();returning=false
 elif not active:
  elapsed=0
  if not last_rotations.is_empty() and blend>0:
   var return_duration:=.32 if is_instance_valid(owner.seating_station) else .18
   state="return";blend=maxf(0,blend-delta/return_duration);returning=true
   for name in last_rotations:
    var index:=skeleton.find_bone(name)
    skeleton.set_bone_pose_rotation(index,skeleton.get_bone_pose_rotation(index).slerp(last_rotations[name],_ease(blend)))
  else:state="neutral";returning=false;last_rotations.clear()
 else:
  if elapsed==0 or returning:
   entry_hands.clear()
   for side in ["Left","Right"]:entry_hands[side]=last_hands.get(side,owner.global_transform.affine_inverse()*bone(side+"Hand"))
   if returning:blend=0;returning=false
  elapsed+=delta;blend=minf(1,blend+delta/.46)
  var cycle:=fposmod(maxf(0,elapsed-.46),8.4)
  state="prepare" if blend<1 else "type" if cycle<3.2 else "read" if cycle<5.0 else "gesture" if cycle<6.5 else "read"
  var style:String=owner.motion_profile
  var contacts:Dictionary={"Left":"left_key","Right":"right_key"}
  var gesture:=_ease((cycle-5.0)/.38)*(1-_ease((cycle-6.12)/.38)) if state=="gesture" else 0.0
  var screen:Transform3D=targets.screen
  var glance:=sin(cycle*1.2)*.055 if style in ["surveyor","trainer","watchkeeper"] else .015
  for side in ["Left","Right"]:
   var key:String=contacts[side];var touch:Transform3D=targets[key]
   # Palms hover between restrained alternating presses; no repeated arm flailing.
   var tap:=fposmod(cycle*(2.6 if style=="trainer" else 2.0)+(0.5 if side=="Right" else 0.0),1.0)
   var type_blend:=smoothstep(0,.18,cycle)*(1-smoothstep(3.02,3.2,cycle)) if state=="type" else 0.0
   var lift:=lerpf(.022,.016*(0.5-0.5*cos(TAU*tap)),type_blend)
   if state=="gesture" and side=="Right":
    key="control" if style in ["mender","watchkeeper"] or (owner.social_pose=="sit" and is_instance_valid(owner.seating_station)) else "screen"
    var destination:Transform3D=targets[key]
    if key=="screen":
     var trace:=Vector2(-.10+glance*.6,0)
     if style=="trainer":trace.x=-.065 if int(elapsed/8.4)%2==0 else -.135
     elif style=="reviewer":trace=Vector2(-.10+sin(cycle*3.0)*.025,cos(cycle*3.0)*.018)
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
