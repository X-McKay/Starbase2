extends Node3D
## Decorative spring surface. The existing navigation/physics footprint owns access.
var reduced_motion := false
var water_time := 0.0
var water := ShaderMaterial.new()

func edge(angle: float) -> Vector2:
	var erosion := 0.93+sin(angle*3.0+0.7)*0.035+sin(angle*7.0)*0.025
	return Vector2(cos(angle)*5.9,sin(angle)*4.9)*erosion

func _ready() -> void:
	var surface := SurfaceTool.new()
	var bank := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	bank.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(80):
		var a := edge(TAU*i/80.0)
		var b := edge(TAU*(i+1)/80.0)
		for pair in [[Vector2.ZERO,Vector2.ZERO],[b*0.92,Vector2(cos(TAU*(i+1)/80.0),sin(TAU*(i+1)/80.0))],[a*0.92,Vector2(cos(TAU*i/80.0),sin(TAU*i/80.0))]]:
			surface.set_uv(pair[1]*0.5+Vector2.ONE*0.5)
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(pair[0].x,0.11,pair[0].y))
		var inner_a := Vector3(a.x*0.90,0.095,a.y*0.90)
		var inner_b := Vector3(b.x*0.90,0.095,b.y*0.90)
		var outer_a := Vector3(a.x,0.035,a.y)
		var outer_b := Vector3(b.x,0.035,b.y)
		for p in [inner_a,outer_b,inner_b,inner_a,outer_a,outer_b]: bank.add_vertex(p)
	var pool := MeshInstance3D.new()
	pool.name="WaterSurface"
	pool.mesh=surface.commit()
	water.shader=preload("res://mineral_pool.gdshader")
	pool.material_override=water
	pool.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pool)
	bank.generate_normals()
	var shore := MeshInstance3D.new()
	shore.name="MineralBank"
	shore.mesh=bank.commit()
	var sediment := ShaderMaterial.new()
	sediment.shader=preload("res://strata.gdshader")
	sediment.set_shader_parameter("stone",preload("res://art/geology/sandstone-v1.png"))
	sediment.set_shader_parameter("rock_color",Color("a79973"))
	shore.material_override=sediment
	add_child(shore)

func _process(delta: float) -> void:
	if reduced_motion or not is_visible_in_tree(): return
	water_time+=delta
	water.set_shader_parameter("water_time",water_time)
