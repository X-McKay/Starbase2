extends RefCounted
## Explicit alternating foot adjustments for the two Command chair approaches.
## Holds actual feet while planted; visible lifted steps account for chair alignment.
var owner:Node3D
var skeleton:Skeleton3D
var enabled:=false
var reference:Dictionary={}
var lengths:Dictionary={}
var starts:Dictionary={}
var goals:Dictionary={}
var last:Dictionary={}
var current_pose:=""
var foot_phase:Dictionary={}
var sole_points:Dictionary={}
var sole_clearances:Dictionary={}
var stable_probes:Dictionary={}
var maximum_reach_error:=0.0
var groups:Dictionary={"Left":[],"Right":[]}
func bone(name:String) -> Transform3D:
 return skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(name))
func configure(visual:Node3D,identity:String) -> void:
 owner=visual;skeleton=visual.skeleton;enabled=identity in ["watchkeeper","reviewer"]
 if not enabled:return
 var saved:Array=[];var shapes:Array=[]
 for index in skeleton.get_bone_count():saved.append([skeleton.get_bone_pose_position(index),skeleton.get_bone_pose_rotation(index),skeleton.get_bone_pose_scale(index)])
 for mesh in owner.find_children("*","MeshInstance3D",true,false):
  if mesh.mesh==null:continue
  for index in mesh.get_blend_shape_count():shapes.append([mesh,index,mesh.get_blend_shape_value(index)])
 for pose in ["sit","stand"]:
  skeleton.reset_bone_poses()
  var clip:="social/seated" if pose=="sit" else "social/stand_up"
  owner.animation.play(clip);owner.animation.seek(0 if pose=="sit" else owner.animation.get_animation(clip).length,true)
  reference[pose]={}
  for side in ["Left","Right"]:
   reference[pose][side]=owner.global_transform.affine_inverse()*bone(side+"Foot")
   if pose=="sit":lengths[side]=Vector2(bone(side+"UpLeg").origin.distance_to(bone(side+"Leg").origin),bone(side+"Leg").origin.distance_to(bone(side+"Foot").origin))
  reference[pose].lift=maxf(0,.002-owner.sole_contact.minimum_y(owner))
 owner.animation.play("idle")
 for index in saved.size():
  skeleton.set_bone_pose_position(index,saved[index][0]);skeleton.set_bone_pose_rotation(index,saved[index][1]);skeleton.set_bone_pose_scale(index,saved[index][2])
 for shape in shapes:shape[0].set_blend_shape_value(shape[1],shape[2])
 for probe in owner.sole_contact.probes:
  for side in ["Left","Right"]:
   var weight:=0.0
   for term in probe[1]:
    var index:int=owner.sole_contact.binds[term[0]][0]
    if skeleton.get_bone_name(index).begins_with(side):weight+=term[1]
   if weight>.5:groups[side].append(probe)
 for side in ["Left","Right"]:
  var lowest:=INF
  for probe in groups[side]:
   var foot_weight:=0.0
   for term in probe[1]:
    if skeleton.get_bone_name(owner.sole_contact.binds[term[0]][0])==side+"Foot":foot_weight+=term[1]
   if foot_weight<.95:continue
   var point:=skin_point(probe)
   if point.y<lowest:lowest=point.y;stable_probes[side]=probe
  if not stable_probes.has(side):stable_probes[side]=groups[side][0]
func skin_point(probe:Array) -> Vector3:
 var point:=Vector3.ZERO
 for term in probe[1]:
  var bind:Array=owner.sole_contact.binds[term[0]]
  point+=(skeleton.global_transform*skeleton.get_bone_global_pose(bind[0])*bind[1]*probe[0])*term[1]
 return point
func turn(name:String,rotation:Quaternion) -> void:
 var index:=skeleton.find_bone(name);var parent:=skeleton.get_bone_parent(index)
 var parent_basis:=skeleton.global_basis*skeleton.get_bone_global_pose(parent).basis
 skeleton.set_bone_pose_rotation(index,parent_basis.orthonormalized().get_rotation_quaternion().inverse()*rotation)
 skeleton.force_update_all_bone_transforms()
func solve(side:String,target:Transform3D) -> void:
 var a:=side+"UpLeg";var b:=side+"Leg";var c:=side+"Foot"
 var start:=bone(a).origin;var lens:Vector2=lengths[side];var line:=target.origin-start
 var distance:=clampf(line.length(),absf(lens.x-lens.y)+.0001,lens.x+lens.y-.0001)
 var axis:=line.normalized();var end:=start+axis*distance
 var along:float=(lens.x*lens.x-lens.y*lens.y+distance*distance)/(2*distance)
 var pole:Vector3=owner.global_basis*Vector3(.10 if side=="Left" else -.10,.05,1)
 var bend:Vector3=(pole-axis*pole.dot(axis)).normalized()
 var knee:=start+axis*along+bend*sqrt(maxf(0,lens.x*lens.x-along*along))
 turn(a,Quaternion((bone(b).origin-start).normalized(),(knee-start).normalized())*bone(a).basis.orthonormalized().get_rotation_quaternion())
 var lower:=bone(b)
 turn(b,Quaternion((bone(c).origin-lower.origin).normalized(),(end-lower.origin).normalized())*lower.basis.orthonormalized().get_rotation_quaternion())
 turn(c,target.basis.orthonormalized().get_rotation_quaternion())
 maximum_reach_error=maxf(maximum_reach_error,bone(c).origin.distance_to(target.origin))
func sole(side:String) -> Vector3:
 var transforms:Array[Transform3D]=[]
 for bind in owner.sole_contact.binds:transforms.append(skeleton.global_transform*skeleton.get_bone_global_pose(bind[0])*bind[1])
 var points:Array[Vector3]=[];var minimum:=INF
 for probe in groups[side]:
  var point:=Vector3.ZERO
  for term in probe[1]:point+=(transforms[term[0]]*probe[0])*term[1]
  points.append(point);minimum=minf(minimum,point.y)
 var result:=Vector3.ZERO;var count:=0
 for point in points:
  if point.y<=minimum+.003:result+=point;count+=1
 result/=maxi(count,1);result.y=minimum
 return result
func _ease(value:float) -> float:
 var t:=clampf(value,0,1);return t*t*(3-2*t)
func project(pose:String,reduced:bool,seat_target:Vector3,progress:float) -> void:
 if not enabled:return
 var active:bool=is_instance_valid(owner.seating_station) and pose in ["sit","stand"] and (pose!="sit" or owner.seating_facing_ready)
 if active:
  var data:Dictionary=owner.seating_station.seat()
  var floor_y:float=data.get("floor_y",owner.get_parent().global_position.y)
  if pose!=current_pose:
   starts.clear();goals.clear()
   for side in ["Left","Right"]:
    starts[side]=last.get(side,bone(side+"Foot"))
    var offset:=seat_target if pose=="sit" else Vector3(0,floor_y-owner.get_parent().global_position.y+reference.stand.lift,0)
    goals[side]=owner.get_parent().global_transform*Transform3D(Basis(Vector3.UP,owner.rotation.y),offset)*reference[pose][side]
  for side in ["Left","Right"]:
   var first:bool=(side=="Left") if pose=="sit" else (side=="Right")
   var start:=.04 if first else .36;var end:=.53 if first else .87
   var amount:=clampf((progress-start)/(end-start),0,1)
   if reduced:amount=1
   var target:Transform3D=starts[side].interpolate_with(goals[side],_ease(amount))
   var lift:=sin(PI*amount)*sin(PI*amount)*.055
   target.origin.y+=lift
   solve(side,target)
   # Calibrate against the actual sparse deformed sole, not an ankle-height guess.
   var correction:=-INF
   for probe in groups[side]:
    var point:=skin_point(probe)
    var surface_y:float=owner.support_sample.call(point) if owner.support_sample.is_valid() else floor_y
    correction=maxf(correction,surface_y+.002+lift-point.y)
   target.origin.y+=correction
   solve(side,target)
   var next_phase:="step" if amount>0 and amount<1 else "planted"
   foot_phase[side]=next_phase
   sole_points[side]=skin_point(stable_probes[side])
   sole_clearances[side]=INF
   for probe in groups[side]:
    var point:=skin_point(probe)
    var surface_y:float=owner.support_sample.call(point) if owner.support_sample.is_valid() else floor_y
    sole_clearances[side]=minf(sole_clearances[side],point.y-surface_y)
 else:
  foot_phase.clear();sole_points.clear();sole_clearances.clear()
 current_pose=pose if active else ""
 for side in ["Left","Right"]:last[side]=bone(side+"Foot")
