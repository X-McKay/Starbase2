extends Node3D
## All interiors are ordinary authored scenes. This host owns shared traversal.
const Definition = preload("res://building_definition.gd")
const Art = preload("res://art.gd")
const Dressing = preload("res://room_dressing.gd")
var definition: Definition
var reduced_motion := false:
	set(value):
		reduced_motion=value
		if content!=null:
			var motes := content.get_node_or_null("Dressing/Dust")
			if motes: motes.emitting=not value
var blocks: Array[Rect2] = []
var grid := AStarGrid2D.new()
var activity: Label3D
var console_point := Vector3.ZERO
var spawn_point := Vector3.ZERO
var crew_point := Vector3.ZERO
var content: Node3D

func _ready() -> void:
	content=load(definition.interior_scene).instantiate()
	add_child(content)
	# Dressing goes under the authored content so its physical props join the block list.
	Dressing.apply(content,definition,reduced_motion)
	console_point=content.get_node("Console").position
	spawn_point=content.get_node("Spawn").position
	crew_point=content.get_node("Crew").position
	activity=Art.sign(self,"Work unknown",content.get_node("Activity").position,"e6d4a7",14)
	# Physical boxes in authored props own both click and walking collision.
	for shape in content.find_children("*","CollisionShape3D",true,false):
		if shape.disabled: continue
		if not shape.shape is BoxShape3D:
			push_error("Interior navigation requires BoxShape3D: "+str(shape.get_path()))
			continue
		var transform_to_room: Transform3D=global_transform.affine_inverse()*shape.global_transform
		var half: Vector3=shape.shape.size*0.5
		var lo := Vector2(INF,INF)
		var hi := Vector2(-INF,-INF)
		for x in [-1,1]:
			for z in [-1,1]:
				var point: Vector3=transform_to_room*Vector3(x*half.x,0,z*half.z)
				lo=lo.min(Vector2(point.x,point.z))
				hi=hi.max(Vector2(point.x,point.z))
		blocks.append(Rect2(lo,hi-lo))
	var bounds: Rect2=definition.interior_bounds
	# Low physical cutaway edges retain a visible boundary without hiding crew.
	for edge in [Rect2(bounds.position-Vector2(0.2,0.2),Vector2(0.2,bounds.size.y+0.4)),Rect2(Vector2(bounds.end.x,bounds.position.y-0.2),Vector2(0.2,bounds.size.y+0.4)),Rect2(bounds.position-Vector2(0,0.2),Vector2(bounds.size.x,0.2)),Rect2(Vector2(bounds.position.x,bounds.end.y),Vector2(bounds.size.x,0.2))]:
		var center := Vector3(edge.get_center().x,0.17,edge.get_center().y)
		Art.box(self,center,Vector3(edge.size.x,0.34,edge.size.y),"738e98")
		Art.collider(self,Vector3(center.x,1.5,center.z),Vector3(edge.size.x,3,edge.size.y))
	Art.sign(self,"F / COLONY",Vector3(0,0.7,bounds.end.y),"edcf95",16)
	var first := Vector2i((bounds.position*2).ceil())
	var last := Vector2i((bounds.end*2).floor())
	grid.region=Rect2i(first,last-first+Vector2i.ONE)
	grid.cell_size=Vector2(0.5,0.5)
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for x in range(first.x,last.x+1):
		for z in range(first.y,last.y+1):
			if not clear(Vector2(x,z)*0.5): grid.set_point_solid(Vector2i(x,z))
func clear(point: Vector2) -> bool:
	if not definition.interior_bounds.has_point(point): return false
	for rect in blocks:
		if rect.grow(0.36).has_point(point): return false
	return true
func route(from: Vector3,to: Vector3) -> PackedVector3Array:
	var start := Vector2(from.x-position.x,from.z-position.z)
	var end := Vector2(to.x-position.x,to.z-position.z)
	var a := Vector2i((start*2).round())
	var b := Vector2i((end*2).round())
	if not clear(end) or not grid.is_in_boundsv(a) or not grid.is_in_boundsv(b) or grid.is_point_solid(b): return PackedVector3Array()
	if grid.is_point_solid(a):
		var best := INF
		var origin := a
		for dx in range(-1,2):
			for dz in range(-1,2):
				var next := origin+Vector2i(dx,dz)
				if not grid.is_in_boundsv(next) or grid.is_point_solid(next): continue
				var point := Vector2(next)*0.5
				var safe := true
				for rect in blocks:
					for i in range(9):
						if rect.grow(0.29).has_point(start.lerp(point,i/8.0)): safe=false
				if safe and start.distance_squared_to(point)<best:
					best=start.distance_squared_to(point)
					a=next
	if grid.is_point_solid(a): return PackedVector3Array()
	var path := PackedVector3Array()
	for point in grid.get_point_path(a,b): path.append(position+Vector3(point.x,0,point.y))
	return path
