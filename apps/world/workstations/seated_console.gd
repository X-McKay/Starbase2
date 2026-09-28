extends Node3D
## Chair-mounted input tray for the existing large Command consoles.
## Origin is chair center on the sampled platform; local +Z points north.
const CHAIR_Z:=-7.22
const APPROACH_DISTANCE:=.76
const CUSHION_Y:=.664
const CUSHION_SIZE:=Vector3(.68,.18,.40)
const FOLD_SECONDS:=.28
var host:Node3D
var actor:Node3D
var role:=""
var height:=.90
var chair_x:=3.2
var tray:Node3D
var markers:Dictionary={}
var keys:Dictionary={}
var rests:Dictionary={}
var control:MeshInstance3D
var active_weights:Dictionary={}
var amount:=0.0
var target:=0.0
func configure(parent_station:Node3D,member:Node3D,value:String) -> void:
 host=parent_station;actor=member;role=value
 height=.90 if role=="watchkeeper" else .80
 chair_x=3.2 if role=="watchkeeper" else -3.2
 tray=Node3D.new();tray.name="ChairMountedKeyboard";tray.position=Vector3(0,height-.03,.22);add_child(tray)
 var casing:=MeshInstance3D.new();casing.mesh=host.beveled_mesh(Vector3(.76,.045,.28),.012)
 casing.position=Vector3(0,-.032,.14);casing.material_override=preload("res://art.gd").mat("b5b9ad");tray.add_child(casing)
 box(tray,Vector3(0,-.006,.14),Vector3(.71,.013,.235),"26343d")
 # Two pivots are directly supported by the authored chair armrest ends.
 for side in [-1,1]:
  box(self,Vector3(side*.395,height-.09,.22),Vector3(.07,.12,.09),"536772")
  var hinge:=preload("res://art.gd").cylinder(self,Vector3(side*.395,height-.03,.22),.035,.075,"26343d");hinge.rotation.z=PI/2
 var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D
 var mesh:=BoxMesh.new();mesh.size=Vector3(.035,.014,.028);mesh.material=preload("res://art.gd").mat("778e8e")
 multi.mesh=mesh;multi.instance_count=30
 for index in 30:
  multi.set_instance_transform(index,Transform3D(Basis.IDENTITY,Vector3(-.24+(index%10)*.047,.007,.082+(index/10)*.043)))
 var key_grid:=MultiMeshInstance3D.new();key_grid.name="PhysicalKeyboard";key_grid.multimesh=multi;tray.add_child(key_grid)
 for key in ["left_key","right_key"]:
  var x:=.15 if key=="left_key" else -.15
  keys[key]=box(tray,Vector3(x,.015,.17),Vector3(.082,.024,.06),"b5b9ad");rests[key]=keys[key].position
  marker(key,Vector3(x,.03,.17))
 control=box(tray,Vector3(-.29,.02,.145),Vector3(.09,.042,.10),"c78a50")
 marker("control",Vector3(-.29,.045,.145))
 set_seated_amount(0.0);apply_fold();present_contacts({})
func box(parent:Node3D,point:Vector3,size:Vector3,color:String) -> MeshInstance3D:
 return preload("res://art.gd").box(parent,point,size,color)
func marker(key:String,point:Vector3) -> void:
 var node:=Marker3D.new();node.name=key;node.position=point;tray.add_child(node);markers[key]=node
func seat() -> Dictionary:
 var room:Node3D=host.get_parent()
 var frame:=Transform3D(host.global_basis,room.to_global(Vector3(chair_x,CUSHION_Y,CHAIR_Z)))
 return {"frame":frame,"floor_y":host.global_position.y,"cushion_size":CUSHION_SIZE,"cushion_frame":Transform3D(frame.basis,frame.origin-frame.basis.z*.14),"back_frame":Transform3D(host.global_basis,room.to_global(Vector3(chair_x,.944,CHAIR_Z+.27))),"approach":approach_point()}
func approach_point() -> Vector3:
 var point:Vector3=host.to_global(Vector3(0,0,APPROACH_DISTANCE))
 # Navigation remains on its authored datum; floor_y carries the physical support.
 point.y=host.get_parent().global_position.y
 return point
func contacts() -> Dictionary:
 var result:Dictionary={}
 for key in markers:result[key]=markers[key].global_transform
 var room:Node3D=host.get_parent()
 # Main display is a gaze target; hands use reachable keyboard/selector controls.
 result.screen=Transform3D(host.global_basis,room.to_global(Vector3(chair_x,1.95,-8.93)))
 return result
func set_seated_amount(value:float) -> void:
 target=clampf(value,0,1) if is_finite(value) else 0.0
 if is_instance_valid(actor) and actor.get("reduced_motion")==true:
  amount=target;apply_fold()
func _process(delta:float) -> void:advance(delta)
func advance(delta:float) -> void:
 if not is_finite(delta) or delta<0:return
 amount=move_toward(amount,target,minf(delta,.1)/FOLD_SECONDS);apply_fold()
func apply_fold() -> void:
 if is_instance_valid(tray):tray.rotation.x=lerpf(-PI/2,0,smoothstep(0,1,amount))
func seated_ready() -> bool:return amount>=.999
func folded_ready() -> bool:return amount<=.001
func present_contacts(weights:Dictionary) -> void:
 active_weights={}
 for key in ["left_key","right_key","screen","control"]:
  var value:=clampf(float(weights.get(key,0.0)),0,1)
  active_weights[key]=value if is_finite(value) and seated_ready() else 0.0
 for key in keys:
  keys[key].position=rests[key]-Vector3.UP*.009*active_weights[key]
  markers[key].position.y=keys[key].position.y+.015
 if is_instance_valid(control):control.rotation.z=-.10*active_weights.control
