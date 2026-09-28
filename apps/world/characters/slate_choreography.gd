extends RefCounted
## Rivet's authored equipment handling. Cosmetic only; motion/mission never waits.
## Own-rig arm IK and rigid attachment, calibrated from this rig's existing clip.
var owner:Node3D
var skeleton:Skeleton3D
var slate:Node3D
var state:="docked"
var elapsed:=0.0
var contact_error:=0.0
var maximum_contact_error:=0.0
var maximum_transfer_error:=0.0
var worst_contact:={}
var attachment:=Transform3D.IDENTITY
var dock_local:=Transform3D.IDENTITY
var hips:=-1
var work_target:=Transform3D.IDENTITY
var hand_start:={}
var slate_start:=Transform3D.IDENTITY
var last_slate:=Transform3D.IDENTITY
var lengths:={}
var enabled:=true
var dock_mount:MeshInstance3D

func configure(visual:Node3D) -> void:
 owner=visual;skeleton=visual.skeleton;slate=visual.work_slate
 hips=skeleton.find_bone("Hips")
 skeleton.reset_bone_poses();owner.animation.play("work/field_slate");owner.animation.seek(0,true)
 slate.project(skeleton,true)
 attachment=_hand("Left").affine_inverse()*slate.global_transform
 work_target=owner.global_transform.affine_inverse()*slate.global_transform
 var dock:=work_target
 dock.basis=Basis(Vector3.BACK,-PI/2.0)*dock.basis
 dock.origin=Vector3(.35,.85,.10)
 dock_local=_bone(hips).affine_inverse()*owner.global_transform*dock
 dock_mount=MeshInstance3D.new();dock_mount.name="RivetSlateMount";dock_mount.mesh=BoxMesh.new();dock_mount.mesh.size=Vector3(.16,.022,.035)
 var metal:=StandardMaterial3D.new();metal.albedo_color=Color("282d2c");metal.metallic=.6;metal.roughness=.45;dock_mount.mesh.material=metal;owner.add_child(dock_mount)
 for side in ["Left","Right"]:
  var a:=skeleton.find_bone(side+"Arm");var b:=skeleton.find_bone(side+"ForeArm");var c:=skeleton.find_bone(side+"Hand")
  lengths[side]=Vector2(_bone(a).origin.distance_to(_bone(b).origin),_bone(b).origin.distance_to(_bone(c).origin))
 owner.animation.play("idle");owner.animation.seek(0,true)
 slate.global_transform=_dock();last_slate=owner.global_transform.affine_inverse()*slate.global_transform;slate.visible=true

func _bone(index:int) -> Transform3D:
 return skeleton.global_transform*skeleton.get_bone_global_pose(index)
func _hand(side:String) -> Transform3D:
 return _bone(skeleton.find_bone(side+"Hand"))
func _dock() -> Transform3D:
 return _bone(hips)*dock_local
func _ease(t:float) -> float:
 var x:=clampf(t,0,1)
 return x*x*x*(x*(x*6-15)+10)
func _begin(next:String) -> void:
 state=next;elapsed=0
 hand_start={"Left":owner.global_transform.affine_inverse()*_hand("Left"),"Right":owner.global_transform.affine_inverse()*_hand("Right")}
 slate_start=last_slate
func _turn(index:int,rotation:Quaternion) -> void:
 var parent:=skeleton.get_bone_parent(index)
 var parent_rotation:Quaternion=(_bone(parent).basis if parent>=0 else skeleton.global_basis).orthonormalized().get_rotation_quaternion()
 skeleton.set_bone_pose_rotation(index,parent_rotation.inverse()*rotation)
 skeleton.force_update_all_bone_transforms()
func _arm(side:String,target:Transform3D) -> void:
 var a:=skeleton.find_bone(side+"Arm");var b:=skeleton.find_bone(side+"ForeArm");var c:=skeleton.find_bone(side+"Hand")
 var start:=_bone(a).origin;var end:=target.origin;var lens:Vector2=lengths[side]
 var line:=end-start;var distance:=clampf(line.length(),.001,lens.x+lens.y-.0001);var axis:=line.normalized()
 end=start+axis*distance
 var along:float=(lens.x*lens.x-lens.y*lens.y+distance*distance)/(2*distance)
 var pole:Vector3=owner.global_basis*Vector3(1 if side=="Left" else -1,-.15,-.15)
 var bend:Vector3=(pole-axis*pole.dot(axis)).normalized()
 var elbow:=start+axis*along+bend*sqrt(maxf(0,lens.x*lens.x-along*along))
 var before:=_bone(a)
 _turn(a,Quaternion((_bone(b).origin-start).normalized(),(elbow-start).normalized())*before.basis.orthonormalized().get_rotation_quaternion())
 before=_bone(b)
 _turn(b,Quaternion((_bone(c).origin-before.origin).normalized(),(end-before.origin).normalized())*before.basis.orthonormalized().get_rotation_quaternion())
 _turn(c,target.basis.orthonormalized().get_rotation_quaternion())
 var error:=_hand(side).origin.distance_to(target.origin)
 if side=="Left":contact_error=error
 if error>maximum_contact_error:
  maximum_contact_error=error;worst_contact={"state":state,"side":side,"requested_distance":line.length(),"reach":lens.x+lens.y,"error":error}

func _carried(desired:Transform3D) -> void:
 _arm("Left",desired*attachment.affine_inverse())
 # Rigid equipment follows the actual hand, never a visually unrelated target.
 slate.global_transform=_hand("Left")*attachment

func project(active:bool,reduced:bool,delta:float,treatment:String) -> void:
 if not enabled:return
 slate.visible=true
 var mount:=_dock();mount.basis=owner.global_basis;mount.origin-=owner.global_basis.x*.08;dock_mount.global_transform=mount
 if reduced or not is_finite(delta) or delta<=0 or delta>.25:
  state="docked";elapsed=0;slate.global_transform=_dock();last_slate=owner.global_transform.affine_inverse()*slate.global_transform;return
 var precise:=treatment=="precise"
 var reach:=.30 if precise else .45
 var lift:=.60 if precise else .80
 var stow:=.60 if precise else .80
 if active and state in ["docked","release"]:_begin("prepare")
 elif active and state=="stow":_begin("lift")
 elif not active and state in ["lift","use"]:_begin("stow")
 elif not active and state=="prepare":_begin("release")
 elapsed+=delta
 var dock:=_dock()
 if state=="docked":slate.global_transform=dock
 elif state=="prepare":
  var amount:=_ease(elapsed/reach)
  _arm("Left",(owner.global_transform*hand_start.Left).interpolate_with(dock*attachment.affine_inverse(),amount))
  slate.global_transform=dock
  if amount>=1 and contact_error<.005:
   maximum_transfer_error=maxf(maximum_transfer_error,(_hand("Left")*attachment).origin.distance_to(slate.global_position));_begin("lift")
 elif state=="lift":
  var amount:=_ease(elapsed/lift)
  var target:=owner.global_transform*work_target
  var start:=owner.global_transform*slate_start
  var desired:=start.interpolate_with(target,amount)
  var control:=owner.to_global(Vector3(.32,1.03,.36))
  desired.origin=(1-amount)*(1-amount)*start.origin+2*(1-amount)*amount*control+amount*amount*target.origin
  _carried(desired)
  var right_goal:=_hand("Right")
  # The authored final hand position is sampled by the base work clip each frame.
  _arm("Right",(owner.global_transform*hand_start.Right).interpolate_with(right_goal,_ease((elapsed/lift-.2)/.8)))
  if amount>=1:state="use";elapsed=0
 elif state=="use":
  slate.project(skeleton,true)
  attachment=_hand("Left").affine_inverse()*slate.global_transform
 elif state=="stow":
  var amount:=_ease(elapsed/stow)
  var start:=owner.global_transform*slate_start
  var desired:=start.interpolate_with(dock,amount)
  var control:=owner.to_global(Vector3(.32,1.03,.36))
  desired.origin=(1-amount)*(1-amount)*start.origin+2*(1-amount)*amount*control+amount*amount*dock.origin
  _carried(desired)
  _arm("Right",(owner.global_transform*hand_start.Right).interpolate_with(_hand("Right"),_ease(elapsed/.25)))
  if amount>=1 and contact_error<.005:
   maximum_transfer_error=maxf(maximum_transfer_error,slate.global_position.distance_to(dock.origin));_begin("release")
 elif state=="release":
  var target:=_hand("Left")
  _arm("Left",(owner.global_transform*hand_start.Left).interpolate_with(target,_ease(elapsed/.22)))
  slate.global_transform=dock
  if elapsed>=.22:state="docked";elapsed=0
 last_slate=owner.global_transform.affine_inverse()*slate.global_transform
