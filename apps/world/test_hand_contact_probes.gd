extends SceneTree
## Verify calibrated rigid skin contact probes against the selected imported hand geometry.
## --write explicitly regenerates the owned calibration after an intentional rig change.
var failures:Array[String]=[]
func _initialize():run.call_deferred()
func run():
 var all_probes:Dictionary={}
 for id in ["mender","surveyor","trainer","watchkeeper","reviewer"]:
  var v=preload("res://characters/model_visual.gd").new();root.add_child(v);v.configure_definition(preload("res://characters/catalog.gd").get_definition(id))
  var s:Skeleton3D=v.skeleton;var record:Dictionary={}
  for side in ["Left","Right"]:
   var bone_index:=s.find_bone(side+"Hand");var samples:Array=[];var points:Array[Vector3]=[]
   for mesh in v.find_children("*","MeshInstance3D",true,false):
    if mesh.skin==null:continue
    for surface in mesh.mesh.get_surface_count():
     var arrays:Array=mesh.mesh.surface_get_arrays(surface)
     var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var bones=arrays[Mesh.ARRAY_BONES];var weights=arrays[Mesh.ARRAY_WEIGHTS]
     if bones==null or weights==null:continue
     var count:int=bones.size()/vertices.size()
     for index in vertices.size():
      var weight:=0.0;var hand_bind:=-1
      for j in count:
       var bind:int=bones[index*count+j]
       var bind_name:String=mesh.skin.get_bind_name(bind)
       var target:int=s.find_bone(bind_name) if not bind_name.is_empty() else mesh.skin.get_bind_bone(bind)
       if target==bone_index:weight+=weights[index*count+j];hand_bind=bind
      if weight>.95:
       var local:Vector3=mesh.skin.get_bind_pose(hand_bind)*vertices[index];samples.append(local.y*.01);points.append(local)
   samples.sort()
   if not samples.is_empty():
    var distal:Vector3=points[0];var underside:Vector3=points[0];underside.z=-INF
    var middle:float=samples[int(samples.size()*.75)]*100
    var upper:float=samples[int(samples.size()*.9)]*100
    for point in points:
     if point.y>distal.y:distal=point
     if point.y>=middle and point.y<=upper and absf(point.x)<2.5 and point.z>underside.z:underside=point
    record[side]={"keyboard":[underside.x,underside.y,underside.z],"screen":[distal.x,distal.y,distal.z],"samples":points.size(),"units":"skeleton centimetres; vertices >95% weighted to own hand"}

  all_probes[id]=record
  print(id," ",JSON.stringify(record));v.free()
 if "--write" in OS.get_cmdline_user_args():
  var file:=FileAccess.open("res://characters/hand_contact_probes.json",FileAccess.WRITE);file.store_string(JSON.stringify(all_probes,"  "));file.close()
 else:
  var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://characters/hand_contact_probes.json"))
  for id in all_probes:
   for side in ["Left","Right"]:
    for kind in ["keyboard","screen"]:
     for axis in 3:
      if absf(all_probes[id][side][kind][axis]-expected.get(id,{}).get(side,{}).get(kind,[INF,INF,INF])[axis])>.001:
       failures.append(id+" "+side+" "+kind+": calibrated skin vertex changed")
  for message in failures:printerr(message)
 print("HAND_CONTACT_PROBES_PASSED" if failures.is_empty() else "HAND_CONTACT_PROBES_FAILED")
 quit(0 if failures.is_empty() else 1)
