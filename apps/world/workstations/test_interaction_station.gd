extends SceneTree
var failures:Array[String]=[]
func check(value:bool,message:String) -> void:
 if not value:failures.append(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
 for role in ["repair","review","gym"]:
  var actor:=Node3D.new();root.add_child(actor)
  var station=load("res://workstations/interaction_station.gd").new();station.position=Vector3(4,0,-3);root.add_child(station);station.configure(role,actor)
  var bevel:Mesh=station.beveled_mesh(Vector3(.80,.065,.34),.015)
  var bevel_arrays:=bevel.surface_get_arrays(0)
  var vertices:PackedVector3Array=bevel_arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=bevel_arrays[Mesh.ARRAY_NORMAL];var indices:PackedInt32Array=bevel_arrays[Mesh.ARRAY_INDEX]
  check(indices.size()==132,role+": all44 bevel triangles are indexed before joining indexed primitive batches")
  for index in range(0,indices.size(),3):
   var a:int=indices[index];var b:int=indices[index+1];var c:int=indices[index+2]
   var normal:Vector3=normals[a];var center:Vector3=(vertices[a]+vertices[b]+vertices[c])/3
   check(center.dot(normal)>0,role+": every convex bevel face normal points outside the casing")
   check((vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).dot(normal)<0,role+": bevel winding matches native BoxMesh clockwise front faces")
  var shell:Mesh=station.get_node("Authored_shell").mesh
  check(shell.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()/3>=100,role+": both bevel casings survive joining the actual rendered shell batch")
  var contacts:Dictionary=station.contacts()
  check(contacts.size()==4,role+": all four named world contact frames")
  var reach:Vector3=station.to_local(contacts.left_key.origin)
  check(is_equal_approx(reach.z,.30) and is_equal_approx(reach.x,.15),role+": physical key is reachable in the explicit local basis")
  for key in contacts:
   check(contacts[key].origin.is_finite(),role+": finite world contact")
   check(contacts[key].basis.is_equal_approx(station.global_basis),role+": target frame follows station role yaw")
  var forward:Vector3=(station.facing_point()-station.global_position).normalized()
  var expected:Vector3={"review":Vector3.LEFT,"gym":Vector3.RIGHT}.get(role,Vector3.FORWARD)
  check(forward.is_equal_approx(expected),role+": contacts face the actual assigned furniture")
  var idle:Vector3=station.keys.left_key.position
  station.present_contacts({"left_key":1.0,"right_key":.5,"control":3.0,"screen":-2.0})
  check(is_equal_approx(idle.y-station.keys.left_key.position.y,.009),role+": observed hand contact depresses physical key by9mm")
  check(is_equal_approx(station.to_local(station.contacts().left_key.origin).y,station.keys.left_key.position.y+.015),role+": contact frame follows physical key travel")
  check(is_equal_approx(station.control.rotation.z,-.1),role+": out-of-range input is clamped")
  station.present_contacts({"left_key":NAN})
  check(station.keys.left_key.position==idle,role+": malformed contact cannot poison geometry")
  station.present_contacts({})
  check(station.keys.left_key.position==idle and station.control.rotation.z==0,role+": inactive/reduced contact reset restores neutral geometry")
  var foot:Rect2=station.footprint_rect()
  if station.mounted:check(foot.size==Vector2.ZERO,role+": existing desk support does not create an invented ground collider")
  else:
   check(not foot.grow(.40).has_point(Vector2(station.position.x,station.position.z)),role+": grounded stand clears padded actor body")
   var base:Vector3=station.to_global(Vector3(0,0,.60))
   check(foot.has_point(Vector2(base.x,base.z)),role+": support footprint bounds the actual grounded base")
  var triangles:=0;var meshes:=0;var minimum_y:=INF
  for mesh in station.find_children("*","MeshInstance3D",true,false):
   meshes+=1
   for surface in mesh.mesh.get_surface_count():
    var arrays: Array=mesh.mesh.surface_get_arrays(surface)
    triangles+=arrays[Mesh.ARRAY_INDEX].size()/3
    for point in arrays[Mesh.ARRAY_VERTEX]:minimum_y=minf(minimum_y,(mesh.transform*point).y)
  if not station.mounted:check(absf(minimum_y)<.00001,role+": actual rendered stand base rests exactly at sampled support origin")
  check(meshes<=12 and triangles<=1400,role+": geometry/material batch budget")
  station.queue_free();actor.queue_free()
 await process_frame
 for failure in failures:push_error(failure)
 if failures.is_empty():print("INTERACTION_STATIONS_PASSED: frames, facing, physical key travel, safe resets, support clearance and bounded geometry")
 quit(0 if failures.is_empty() else 1)
