extends Node3D
## Bounded, cosmetic regolith impressions. No route or operational state changes.
const Foley = preload("res://footfall.gd")
const Geography = preload("res://geography.gd")
const SOIL_HEIGHT:float = preload("res://cliff_landform.gd").CAP_HEIGHT
const CAPACITY := 128
const LIFETIME := 24.0
const SIZE := Vector2(0.27, 0.43)
var reduced := false:
	set(value):
		reduced=value
		visible=not value
var surface: Callable
var clock := 0.0
var next_slot := 0
var emitted := 0
var last_contacts: Dictionary = {}
var entries: Array[Dictionary] = []
var marks := MultiMeshInstance3D.new()
var material := ShaderMaterial.new()

func _ready() -> void:
	material.shader=preload("res://sand_print.gdshader")
	material.set_shader_parameter("lifetime",LIFETIME)
	var plane:=PlaneMesh.new();plane.size=SIZE;plane.material=material
	var batch:=MultiMesh.new()
	batch.transform_format=MultiMesh.TRANSFORM_3D;batch.use_custom_data=true
	batch.mesh=plane;batch.instance_count=CAPACITY
	for index in CAPACITY:batch.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO))
	marks.multimesh=batch;marks.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marks)

func watch(actor: Node3D) -> void:
	actor.foot_contact.connect(_contact.bind(actor))

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	clock+=maxf(delta,0.0)
	material.set_shader_parameter("clock",clock)
	while not entries.is_empty() and clock-float(entries[0].born)>=LIFETIME:entries.pop_front()

func accepts(point: Vector3, heading: float) -> bool:
	if not surface.is_valid() or not point.is_finite():return false
	# Check the complete imprint, including transitions onto floors and paving.
	var basis:=Basis(Vector3.UP,heading)
	for corner in [Vector3.ZERO,Vector3(-SIZE.x/2,0,-SIZE.y/2),Vector3(SIZE.x/2,0,-SIZE.y/2),Vector3(-SIZE.x/2,0,SIZE.y/2),Vector3(SIZE.x/2,0,SIZE.y/2)]:
		var sample:Vector3=point+basis*corner
		if not Geography.contains(Vector2(sample.x,sample.z),0.05):return false
		if Foley.surface_at(sample)!="soil" or absf(float(surface.call(sample)))>0.005:return false
	return absf(point.y-float(surface.call(point)))<0.055

func _contact(actor: Node3D) -> void:
	if reduced or not actor.visible or not actor.gait.moving or actor.model_visual==null:return
	var visual:Node3D=actor.model_visual
	var point:Vector3=visual.sole_contact.ground_contact(visual)
	if not accepts(point,visual.rotation.y):return
	var id:=actor.get_instance_id()
	if last_contacts.has(id) and point.distance_to(last_contacts[id])<0.13:return
	last_contacts[id]=point
	stamp(point,visual.rotation.y)

func stamp(point: Vector3, heading: float) -> void:
	# The rendered soil lies below the navigation/support datum. Place the
	# impression just above that mesh, not hovering at the actor's root height.
	var transform:=Transform3D(Basis(Vector3.UP,heading),Vector3(point.x,SOIL_HEIGHT+0.004+next_slot*0.000002,point.z))
	marks.multimesh.set_instance_transform(next_slot,global_transform.affine_inverse()*transform)
	marks.multimesh.set_instance_custom_data(next_slot,Color(clock,0,0,1))
	entries.append({"point":point,"heading":heading,"born":clock,"slot":next_slot})
	if entries.size()>CAPACITY:entries.pop_front()
	next_slot=(next_slot+1)%CAPACITY
	emitted+=1
