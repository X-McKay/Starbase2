extends SceneTree
## Offline probe selection. Never runs in the playable world; no external calls.
const IDS=["operator","mender","surveyor","trainer","watchkeeper","reviewer","cybercat"]
func _initialize():run.call_deferred()
func run():
 var result:={}
 for id in IDS:
  var v=preload("res://characters/model_visual.gd").new();root.add_child(v)
  var definition=preload("res://characters/catalog.gd").get_definition(id)
  # Generation must not depend on stale probe indices from a replaced mesh.
  v.configure(definition.model_scene,definition.model_scale,definition.model_floor_offset,definition.animation_family)
  var meshes:Array=[]
  for m in v.find_children("*","MeshInstance3D",true,false):
   if m.skin==null:continue
   var binds:Array=[]
   for i in m.skin.get_bind_count():
    var b=m.skin.get_bind_bone(i)
    if b<0:b=v.skeleton.find_bone(m.skin.get_bind_name(i))
    binds.append([b,m.skin.get_bind_pose(i)])
   for s in m.mesh.get_surface_count():
    var a=m.mesh.surface_get_arrays(s);var vs=a[Mesh.ARRAY_VERTEX];var bs=a[Mesh.ARRAY_BONES];var ws=a[Mesh.ARRAY_WEIGHTS]
    if bs==null or bs.is_empty():continue
    var n:int=bs.size()/vs.size();var points:Array=[]
    for i in vs.size():
     var weight:=0.0;var terms:Array=[]
     for j in n:
      var bind:int=bs[i*n+j];var w:float=ws[i*n+j]
      if w<=0:continue
      if v.skeleton.get_bone_name(binds[bind][0]) in ["LeftFoot","RightFoot","LeftToeBase","RightToeBase"]:weight+=w
      terms.append([bind,w])
     if weight>.05:points.append([i,vs[i],terms])
    meshes.append({"path":str(v.get_path_to(m)),"surface":str(s),"binds":binds,"points":points,"selected":{}})
  for clip in ["idle","walk","run"]:
   v.animation.play(clip)
   for frame in 96:
    v.animation.seek(v.animation.get_animation(clip).length*frame/96.0,true)
    v.skeleton.force_update_all_bone_transforms()
    for mesh in meshes:
     var transforms:Array=[]
     for bind in mesh.binds:transforms.append(v.skeleton.get_bone_global_pose(bind[0])*bind[1])
     var best:={}
     # Directional extrema retain the foot envelope through turns and blends.
     for p in mesh.points:
      var point:=Vector3.ZERO
      for term in p[2]:point+=(transforms[term[0]]*p[1])*term[1]
      for d in [Vector3.DOWN,Vector3(-.3,-1,0),Vector3(.3,-1,0),Vector3(0,-1,-.3),Vector3(0,-1,.3)]:
       var score:float=point.dot(d)
       if not best.has(d) or score>best[d][0]:best[d]=[score,p[0]]
     for value in best.values():mesh.selected[value[1]]=true
  var entry:={};var count:=0
  for mesh in meshes:
   if mesh.selected.is_empty():continue
   if not entry.has(mesh.path):entry[mesh.path]={}
   var selected:Array=mesh.selected.keys();selected.sort()
   entry[mesh.path][mesh.surface]=selected;count+=selected.size()
  result[id]=entry;print(id," support probes ",count)
  v.queue_free();await process_frame
 var output_path:="res://characters/sole_probes.json"
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--output="):output_path=argument.trim_prefix("--output=")
 var out:=FileAccess.open(output_path,FileAccess.WRITE);out.store_string(JSON.stringify(result,"  "));out.close()
 print("SOLE_PROBES_GENERATED");quit()
