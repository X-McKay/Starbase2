extends Node3D
## Authored contact furniture. Inputs animate only from the crew hand-contact driver.
## Origin is the sampled room support at the crew feet anchor; local +Z faces the controls, +X is actor left.
const PROFILES:={
 "repair":{"yaw":PI,"height":.90,"mounted":true,"caption":"ENGINEERING"},
 "review":{"yaw":-PI/2,"height":1.13,"mounted":true,"caption":"ANALYSIS"},
 "gym":{"yaw":PI/2,"height":1.08,"mounted":false,"caption":"SIMULATION"},
 "watchkeeper":{"yaw":PI,"height":1.30,"mounted":false,"caption":"OBSERVATION"},
 "reviewer":{"yaw":PI,"height":1.12,"mounted":false,"caption":"VERIFICATION"}}
const COLORS:={"shell":"b5b9ad","edge":"536772","body":"26343d","key":"778e8e","screen":"10232c","ink":"5a9d9d","accent":"c78a50"}
var seated_console:Node3D
var uses_seated_work:=false
var role:=""
var actor:Node3D
var height:=1.1
var mounted:=false
var surfaces:Dictionary={}
var markers:Dictionary={}
var keys:Dictionary={}
var key_rest:Dictionary={}
var control:MeshInstance3D
var cue:MeshInstance3D
var active_weights:Dictionary={}
func configure(value:String,member:Node3D) -> void:
 assert(PROFILES.has(value),"Unknown contact-station role")
 assert(get_child_count()==0,"Configure a contact station once")
 role=value;actor=member
 var profile:Dictionary=PROFILES[role]
 rotation.y=profile.yaw;height=profile.height;mounted=profile.mounted
 uses_seated_work=role in ["watchkeeper","reviewer"]
 if uses_seated_work:
  mounted=true
  var room:Node3D=get_parent()
  global_position=room.to_global(Vector3(3.2 if role=="watchkeeper" else -3.2,0,-7.22))
  seated_console=preload("res://workstations/seated_console.gd").new();add_child(seated_console);seated_console.configure(self,member,role)
 else:build_geometry(str(profile.caption));flush_surfaces();present_contacts({})
func append_box(at:Vector3,size:Vector3,color:String) -> void:
 var mesh:=BoxMesh.new();mesh.size=size
 if not surfaces.has(color):
  var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES);surfaces[color]=surface
 surfaces[color].append_from(mesh,0,Transform3D(Basis.IDENTITY,at))
func append_beveled(at:Vector3,size:Vector3,color:String,radius:float) -> void:
 surfaces[color].append_from(beveled_mesh(size,radius),0,Transform3D(Basis.IDENTITY,at))
func beveled_mesh(size:Vector3,radius:float) -> ArrayMesh:
 var half:=size*.5;var inner:=half-Vector3.ONE*radius
 var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
 # Six inset faces, twelve bevel strips and eight triangular corner facets.
 for axis in 3:
  var u:=(axis+1)%3;var v:=(axis+2)%3
  for sign_value in [-1.0,1.0]:
   var normal:=Vector3.ZERO;normal[axis]=sign_value
   var points:Array[Vector3]=[]
   for pair in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
    var point:=Vector3.ZERO;point[axis]=half[axis]*sign_value;point[u]=inner[u]*pair.x;point[v]=inner[v]*pair.y;points.append(point)
   triangle(surface,points[0],points[1],points[2],normal);triangle(surface,points[0],points[2],points[3],normal)
 for along in 3:
  var a:=(along+1)%3;var b:=(along+2)%3
  for sa in [-1.0,1.0]:
   for sb in [-1.0,1.0]:
    var normal:=Vector3.ZERO;normal[a]=sa;normal[b]=sb;normal=normal.normalized()
    var points:Array[Vector3]=[]
    for end in [-1.0,1.0]:
     var p:=Vector3.ZERO;p[along]=inner[along]*end;p[a]=half[a]*sa;p[b]=inner[b]*sb;points.append(p)
     p[a]=inner[a]*sa;p[b]=half[b]*sb;points.append(p)
    triangle(surface,points[0],points[1],points[3],normal);triangle(surface,points[0],points[3],points[2],normal)
 for sx in [-1.0,1.0]:
  for sy in [-1.0,1.0]:
   for sz in [-1.0,1.0]:
    var sign_vector:=Vector3(sx,sy,sz);var points:Array[Vector3]=[]
    for axis in 3:
     var p:=inner*sign_vector;p[axis]=half[axis]*sign_vector[axis];points.append(p)
    triangle(surface,points[0],points[1],points[2],sign_vector.normalized())
 surface.index()
 return surface.commit()
func triangle(surface:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,normal:Vector3) -> void:
 surface.set_normal(normal)
 # Match the native primitive orientation; outward faces remain visible under backface culling.
 for point in ([a,c,b] if (b-a).cross(c-a).dot(normal)>0 else [a,b,c]):surface.add_vertex(point)
func fastener(at:Vector3,front:bool=false) -> void:
 var mesh:=CylinderMesh.new();mesh.top_radius=.008;mesh.bottom_radius=.008;mesh.height=.005;mesh.radial_segments=8;mesh.rings=1
 surfaces.body.append_from(mesh,0,Transform3D(Basis(Vector3.RIGHT,PI/2) if front else Basis.IDENTITY,at))
func flush_surfaces() -> void:
 for color in surfaces:
  var mesh:=MeshInstance3D.new();mesh.name="Authored_"+color;mesh.mesh=surfaces[color].commit()
  var material:=StandardMaterial3D.new();material.albedo_color=Color(COLORS[color]);material.roughness=.68;material.metallic=.12 if color=="edge" else 0.0
  mesh.material_override=material;add_child(mesh)
 surfaces.clear()
func box(at:Vector3,size:Vector3,color:String) -> MeshInstance3D:
 var node:=preload("res://art.gd").box(self,at,size,COLORS[color]);return node
func marker(key:String,point:Vector3) -> void:
 var node:=Marker3D.new();node.name=key;node.position=point;add_child(node);markers[key]=node
func build_geometry(caption:String) -> void:
 # Folded lower tray, supported either by the existing console or a grounded stand.
 append_box(Vector3(0,height-.085,.43),Vector3(.68,.02,.25),"shell")
 append_beveled(Vector3(0,height-.065,.405),Vector3(.80,.065,.34),"shell",.015)
 append_box(Vector3(0,height-.026,.405),Vector3(.75,.015,.30),"body")
 append_box(Vector3(0,height-.018,.255),Vector3(.75,.016,.026),"edge")
 append_box(Vector3(0,height-.075,.57),Vector3(.44,.05,.20),"edge")
 if mounted:
  # Visible C-brackets penetrate the existing desk side, not the actor's space.
  for x in [-.27,.27]:
   append_box(Vector3(x,height-.17,.67),Vector3(.05,.28,.07),"edge")
   append_box(Vector3(x,height-.29,.77),Vector3(.05,.05,.25),"edge")
 else:
  append_box(Vector3(0,.0325,.60),Vector3(.60,.065,.25),"body")
  append_box(Vector3(0,(height-.08)/2+.055,.63),Vector3(.13,height-.08,.12),"edge")
  append_box(Vector3(0,height-.22,.63),Vector3(.18,.17,.17),"body")
  append_box(Vector3(0,.0695,.60),Vector3(.48,.012,.17),"shell")
 # Static key grid is backed by a physical keyboard plate; two key clusters travel.
 for row in 3:
  for col in 10:
   append_box(Vector3(-.245+col*.045,height-.011,.28+row*.045),Vector3(.036,.014,.03),"key")
 for key in ["left_key","right_key"]:
  var x:=.15 if key=="left_key" else -.15
  var node:=box(Vector3(x,height,.30),Vector3(.085,.025,.065),"shell")
  keys[key]=node;key_rest[key]=node.position;marker(key,Vector3(x,height+.015,.30))
 control=box(Vector3(-.23,height+.01,.34),Vector3(.095,.045,.11),"accent")
 marker("control",Vector3(-.23,height+.035,.34))
 # Raised display on an articulated arm meeting the supported tray.
 append_box(Vector3(0,height+.035,.51),Vector3(.055,.16,.055),"edge")
 append_box(Vector3(0,height+.105,.455),Vector3(.055,.045,.17),"edge")
 append_beveled(Vector3(0,height+.22,.385),Vector3(.52,.26,.055),"shell",.012)
 append_box(Vector3(0,height+.22,.352),Vector3(.47,.21,.012),"screen")
 # Authored wiring schematic: no percentages, fabricated activity or outcomes.
 for x in [-.15,0.0,.15]:
  append_box(Vector3(x,height+.235,.342),Vector3(.075,.045,.005),"ink")
 append_box(Vector3(0,height+.17,.342),Vector3(.31,.007,.005),"ink")
 for x in [-.15,0.0,.15]:append_box(Vector3(x,height+.19,.342),Vector3(.007,.045,.005),"ink")
 marker("screen",Vector3(0,height+.22,.335))
 # Quiet manufactured detail: countersunk fixings and a recessed vented rear cover.
 for x in [-.34,.34]:
  for z in [.285,.515]:fastener(Vector3(x,height-.01,z))
 append_box(Vector3(0,height+.22,.416),Vector3(.43,.18,.008),"body")
 for row in 5:append_box(Vector3(0,height+.17+row*.025,.422),Vector3(.32,.008,.007),"edge")
 for x in [-.245,.245]:
  for y in [-.105,.105]:fastener(Vector3(x,height+.22+y,.352),true)
 cue=box(Vector3(.29,height+.005,.44),Vector3(.025,.014,.045),"ink")
 var label:=Label3D.new();label.text=caption;label.font_size=24;label.pixel_size=.0015;label.position=Vector3(0,height-.065,.226);label.rotation.y=PI;label.modulate=Color("d8d7c9");label.outline_size=0;add_child(label)
func contacts() -> Dictionary:
 if uses_seated_work:return seated_console.contacts()
 var result:Dictionary={}
 for key in markers:result[key]=markers[key].global_transform
 return result
func facing_point() -> Vector3:return to_global(Vector3(0,0,1))
func footprint_rect() -> Rect2:
 # Desk brackets remain within old furniture bounds; only independent stands add a blocker.
 if mounted:return Rect2()
 var a:=to_global(Vector3(-.30,0,.475));var b:=to_global(Vector3(.30,0,.725))
 return Rect2(Vector2(minf(a.x,b.x),minf(a.z,b.z)),Vector2(absf(b.x-a.x),absf(b.z-a.z)))
func present_contacts(weights:Dictionary) -> void:
 if uses_seated_work:
  seated_console.present_contacts(weights);active_weights=seated_console.active_weights;return
 active_weights={}
 for key in ["left_key","right_key","screen","control"]:
  var value:float=clampf(float(weights.get(key,0.0)),0.0,1.0)
  if not is_finite(value):value=0.0
  active_weights[key]=value
 for key in keys:
  keys[key].position=key_rest[key]-Vector3.UP*(.009*active_weights[key])
  markers[key].position.y=keys[key].position.y+.015
 if is_instance_valid(control):control.rotation.z=-.10*active_weights.control
 if is_instance_valid(cue):cue.scale.y=1.0+.25*active_weights.screen

func seat() -> Dictionary:return seated_console.seat() if uses_seated_work else {}
func seat_frame() -> Transform3D:return seat().frame if uses_seated_work else global_transform
func approach_point() -> Vector3:return seated_console.approach_point() if uses_seated_work else global_position
func set_seated_amount(value:float) -> void:
 if uses_seated_work:seated_console.set_seated_amount(value)
func seated_ready() -> bool:return uses_seated_work and seated_console.seated_ready()
func folded_ready() -> bool:return not uses_seated_work or seated_console.folded_ready()
