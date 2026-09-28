extends RefCounted
## Dense native imported skin/morph inspection used only by focused QA helpers.
static func measure(visual:Node3D,seat:Dictionary,support:Callable)->Dictionary:
 var skeleton:Skeleton3D=visual.skeleton
 var frame:Transform3D=seat.frame;var half:Vector3=seat.get("cushion_size",Vector3(.68,.18,.68))*.5
 var minimum_sole:={"Left":INF,"Right":INF};var penetration:=0.0;var penetrating:=0;var seat_gap:=INF
 skeleton.force_update_all_bone_transforms()
 for mesh in visual.find_children("*","MeshInstance3D",true,false):
  if mesh.skin==null:continue
  var transforms:Array[Transform3D]=[];var names:Array[String]=[]
  for bind in mesh.skin.get_bind_count():
   var bone:int=mesh.skin.get_bind_bone(bind)
   if bone<0:bone=skeleton.find_bone(mesh.skin.get_bind_name(bind))
   transforms.append(skeleton.global_transform*skeleton.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(bind));names.append(skeleton.get_bone_name(bone))
  for surface in mesh.mesh.get_surface_count():
   var a:Array=mesh.mesh.surface_get_arrays(surface);var vertices:PackedVector3Array=a[Mesh.ARRAY_VERTEX];var bones=a[Mesh.ARRAY_BONES];var weights=a[Mesh.ARRAY_WEIGHTS]
   if bones==null or weights==null:continue
   var influences:int=bones.size()/vertices.size();var shapes:Array=mesh.mesh.surface_get_blend_shape_arrays(surface);var active:Array=[];var total:=0.0
   for index in shapes.size():
    var weight:float=mesh.get_blend_shape_value(index)
    if absf(weight)>.000001:active.append([weight,shapes[index][Mesh.ARRAY_VERTEX]]);total+=weight
   for index in vertices.size():
    var source:Vector3=vertices[index]
    if mesh.mesh.blend_shape_mode==Mesh.BLEND_SHAPE_MODE_NORMALIZED:source*=1-total
    for shape in active:source+=shape[0]*shape[1][index]
    var point:=Vector3.ZERO;var feet:={"Left":0.0,"Right":0.0};var pelvis:=0.0
    for j in influences:
     var weight:float=weights[index*influences+j]
     if weight<=0:continue
     var bind:int=bones[index*influences+j];point+=(transforms[bind]*source)*weight
     if names[bind] in ["Hips","LeftUpLeg","RightUpLeg"]:pelvis+=weight
     for side in ["Left","Right"]:
      if names[bind] in [side+"Foot",side+"ToeBase"]:feet[side]+=weight
    for side in ["Left","Right"]:
     if feet[side]>.5:minimum_sole[side]=minf(minimum_sole[side],point.y-float(support.call(point)))
    var volume:Transform3D=seat.get("cushion_frame",frame)
    var local:Vector3=volume.affine_inverse()*point
    if absf(local.x)<half.x-.008 and absf(local.z)<half.z-.008 and local.y<0 and local.y>-half.y*2:
     penetrating+=1;penetration=maxf(penetration,-local.y)
    if pelvis>.5 and absf(local.x)<half.x-.008 and absf(local.z)<half.z-.008 and local.y>-.18 and local.y<.4:seat_gap=minf(seat_gap,local.y)
 return {"dense_sole_clearance_m":minimum_sole,"cushion_penetrating_vertices":penetrating,"maximum_cushion_penetration_m":penetration,"pelvis_support_gap_m":seat_gap if is_finite(seat_gap) else null}
