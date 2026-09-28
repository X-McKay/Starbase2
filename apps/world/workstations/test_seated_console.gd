extends SceneTree
class Member extends Node3D:
 var reduced_motion:=false
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
 if not value:failures.append(message)
func _initialize()->void:run.call_deferred()
func run()->void:
 var room=load("res://structures/interiors/review-continuous.tscn").instantiate();root.add_child(room)
 for item in [["reviewer","Prop2",.80],["watchkeeper","Prop4",.90]]:
  var role:String=item[0];var chair=room.get_node(item[1]);var size:Vector3=chair.get_node("Collision").shape.size
  var member:=Member.new();room.add_child(member)
  var station=load("res://workstations/interaction_station.gd").new();room.add_child(station);station.configure(role,member);station.position.y=.184
  var frame:Transform3D=station.seat().frame;var approach:Vector3=station.approach_point();var local_approach:Vector3=room.to_local(approach)
  check(station.uses_seated_work and station.footprint_rect().size==Vector2.ZERO,role+": uses authored collidable chair, no duplicate freestanding terminal")
  check(absf((station.seat().cushion_frame.origin-frame.origin).dot(frame.basis.z)+.14)<.0001,role+": actual cushion top frame records rearward support offset")
  check(is_equal_approx(frame.origin.y-station.seat().floor_y,.48),role+": measured cushion supports authored seated clip at48cm")
  check(frame.basis.z.is_equal_approx(Vector3.FORWARD),role+": chair faces the existing north console")
  check(is_equal_approx(local_approach.z,-7.98),role+": approach remains on the collision-safe navigation datum")
  var chair_rect:=Rect2(Vector2(chair.position.x-size.x/2,chair.position.z-size.z/2),Vector2(size.x,size.z))
  check(not chair_rect.grow(.4).has_point(Vector2(local_approach.x,local_approach.z)),role+": approach clears actual chair proxy plus40cm navigation padding")
  var desk=room.get_node("Prop3" if role=="watchkeeper" else "Prop1");var desk_size:Vector3=desk.get_node("Collision").shape.size
  var desk_rect:=Rect2(Vector2(desk.position.x-desk_size.x/2,desk.position.z-desk_size.z/2),Vector2(desk_size.x,desk_size.z))
  check(not desk_rect.grow(.4).has_point(Vector2(local_approach.x,local_approach.z)),role+": approach clears actual desk proxy plus40cm padding")
  var measured:=0;var cushion_top:=-INF
  for mesh in room.get_node("Furniture").find_children("*","MeshInstance3D",true,false):
   for surface in mesh.mesh.get_surface_count():
    for vertex in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
     var point:Vector3=room.to_local(mesh.to_global(vertex))
     if absf(point.x-chair.position.x)>.65 or absf(point.z-chair.position.z)>.55 or point.y>.185+1.34:continue
     measured+=1
     check(absf(point.x-chair.position.x)<=size.x/2+.0005 and absf(point.z-chair.position.z)<=size.z/2+.0005,role+": imported chair geometry fits retained physical proxy")
     if absf(point.x-chair.position.x)<.30 and absf(point.z-chair.position.z)<.30 and point.y>.55 and point.y<.70:cushion_top=maxf(cushion_top,point.y)
  print(role," measured=",measured," cushion=",cushion_top," frame=",frame.origin.y)
  check(measured>100 and absf(cushion_top-frame.origin.y)<.0005,role+": seat datum matches actual imported cushion vertices")
  var meshes:=0;var triangles:=0;var forward_extent:=-INF
  for mesh in station.find_children("*","MeshInstance3D",true,false):
   meshes+=1
   for surface in mesh.mesh.get_surface_count():
    var arrays:Array=mesh.mesh.surface_get_arrays(surface);triangles+=arrays[Mesh.ARRAY_INDEX].size()/3
    for vertex in arrays[Mesh.ARRAY_VERTEX]:forward_extent=maxf(forward_extent,station.to_local(mesh.to_global(vertex)).z)
  for mesh in station.find_children("*","MultiMeshInstance3D",true,false):
   meshes+=1
   for surface in mesh.multimesh.mesh.get_surface_count():triangles+=mesh.multimesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size()/3*mesh.multimesh.instance_count
  check(meshes<=12 and triangles<=1800,role+": bounded chair-input geometry including30 real key instances")
  check(.76-forward_extent>.28+.1,role+": folded accessory clears approaching torso radius plus10cm")
  print(role," input meshes=",meshes," triangles=",triangles," folded forward extent=",forward_extent)
  check(station.folded_ready() and not station.seated_ready(),role+": tray starts stowed while approaching")
  station.present_contacts({"left_key":1});check(station.active_weights.left_key==0,role+": closed tray cannot display a false key press")
  station.set_seated_amount(1);station.seated_console.advance(.1)
  check(not station.seated_ready(),role+": input unavailable during tray deployment")
  station.seated_console.advance(.1);station.seated_console.advance(.1)
  check(station.seated_ready(),role+": physical deployment completes before hand input")
  var contacts:Dictionary=station.contacts();var local_key:Vector3=station.to_local(contacts.left_key.origin)
  check(absf(local_key.z-.39)<.0001 and absf(local_key.y-float(item[2]))<.0001,role+": exact reachable seated key placement")
  check(contacts.screen.origin.z<contacts.left_key.origin.z-.9,role+": actual large console screen is a separate gaze target")
  var before:float=contacts.left_key.origin.y;station.present_contacts({"left_key":1})
  check(absf(before-station.contacts().left_key.origin.y-.009)<.0001,role+": observed contact depresses real key9mm")
  station.present_contacts({});station.set_seated_amount(0)
  for step in 3:station.seated_console.advance(.1)
  check(station.folded_ready(),role+": tray folds completely before departure")
  member.reduced_motion=true;station.set_seated_amount(1)
  check(station.seated_ready(),role+": reduced motion snaps to usable tray position")
  station.set_seated_amount(NAN);check(station.folded_ready(),role+": nonfinite input safely stows tray")
  station.queue_free();member.queue_free()
 room.queue_free();await process_frame
 for failure in failures:push_error(failure)
 if failures.is_empty():print("SEATED_CONSOLE_PASSED: real cushion, colliders, facing, exact keys, fold sequencing and reduced motion")
 quit(0 if failures.is_empty() else 1)
