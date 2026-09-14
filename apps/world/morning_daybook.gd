extends Node3D
## Physical entrance to retained history. Model art never supplies operational facts.
var caption:=Label3D.new()
var body:Node3D
var count:=0

func _ready() -> void:
	body=load("res://assets/props/daybook/daybook.glb").instantiate()
	add_child(body)
	caption.text="DAYBOOK · K\nWaiting for records"
	caption.font_size=30; caption.outline_size=5; caption.pixel_size=0.009
	caption.modulate=Color("e3eadc")
	caption.position=Vector3(0,0.65,0)
	caption.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	caption.no_depth_test=false
	add_child(caption)

func update_records(model:Dictionary) -> void:
	count=int(model.get("retained_count",0))
	var state:="Waiting for records" if model.is_empty() else "%d recent reports"%count
	if model.get("disconnected",true) and not model.is_empty(): state="Last known · %d reports"%count
	caption.text="DAYBOOK · K\n"+state

func hit(camera:Camera3D,point:Vector2) -> bool:
	if not is_visible_in_tree() or camera.is_position_behind(global_position): return false
	var center:=camera.unproject_position(global_position+Vector3(0,0.24,0))
	var edge:=camera.unproject_position(global_position+camera.global_basis.x*0.55)
	var radius:=maxf(18,center.distance_to(edge))
	if not Rect2(center-Vector2(radius,radius),Vector2(radius*2,radius*2)).has_point(point): return false
	var target:=global_position+Vector3(0,0.24,0)
	var origin:=camera.project_ray_origin(center)
	var ray:=PhysicsRayQueryParameters3D.create(origin,target)
	ray.collide_with_areas=false
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
