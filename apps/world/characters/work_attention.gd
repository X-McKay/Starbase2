extends RefCounted
## Cosmetic attention during an authoritative working pose. Never task progress.
## Head-only offsets preserve authored hands, Equipment contact, hips and feet.
const PROFILES:={
 "operator":Vector4(12.0,0.0,4.0,3.0),
 "mender":Vector4(11.0,1.1,7.0,4.0),
 "surveyor":Vector4(14.0,3.4,9.0,5.0),
 "trainer":Vector4(10.0,5.8,10.0,4.0),
 "watchkeeper":Vector4(16.0,8.1,6.0,3.0),
 "reviewer":Vector4(13.0,10.3,8.0,5.0)}
var enabled:=true
var strength:=1.0
var tempo:=1.0
var elapsed:=0.0
var envelope:=0.0
var offset:=Vector2.ZERO
var head:=-1

func configure(skeleton:Skeleton3D) -> void:
 head=skeleton.find_bone("Head")

func project(skeleton:Skeleton3D,profile:String,active:bool,delta:float) -> void:
 if not enabled or not active or head<0 or not is_finite(delta) or delta<=0.0 or delta>0.25:
  elapsed=0.0;envelope=0.0;offset=Vector2.ZERO
  return
 elapsed+=delta*clampf(tempo,0.5,1.5)
 envelope=smoothstep(0.0,0.8,elapsed)
 var style:Vector4=PROFILES.get(profile,PROFILES.operator)
 var phase:=fposmod(elapsed+style.y,style.x)/style.x
 # A short, smooth side glance within a longer settled reading interval.
 # Cosmetic timing cannot represent subtask execution or an evidence handoff.
 var glance:=sin(PI*clampf((phase-0.55)/0.35,0.0,1.0))
 var reading:=0.5-0.5*cos(TAU*phase)
 offset=Vector2(deg_to_rad(style.w)*reading,deg_to_rad(style.z)*glance)*envelope*clampf(strength,0.0,1.0)
 var parent:=skeleton.get_bone_parent(head)
 var parent_basis:=skeleton.get_bone_global_pose(parent).basis if parent>=0 else Basis.IDENTITY
 var parent_rotation:=parent_basis.orthonormalized().get_rotation_quaternion()
 var desired:=Quaternion(Vector3.UP,offset.y)*Quaternion(Vector3.RIGHT,offset.x)
 var local_delta:=parent_rotation.inverse()*desired*parent_rotation
 skeleton.set_bone_pose_rotation(head,local_delta*skeleton.get_bone_pose_rotation(head))
