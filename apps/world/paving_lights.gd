extends Node3D
## Decorative navigation accents. Never connected to operational health.
## Geometry follows the shared paving field; lights add no collision.
const Paving=preload("res://colony_paving.gd")
const HEIGHT := Paving.HEIGHT+0.02
var beacon_material: ShaderMaterial
var reduced_motion := false:
	set(value):
		reduced_motion=value
		if beacon_material: beacon_material.set_shader_parameter("motion_enabled",not value)

static func pad_edges() -> Array[Rect2]:
	var result: Array[Rect2]=[]
	for cells in Paving.foundation_cells():
		var rect := Rect2(Vector2(cells.position)*Paving.TILE,Vector2(cells.size)*Paving.TILE).grow(-0.18)
		result.append(Rect2(rect.position,Vector2(rect.size.x,0.07)))
		result.append(Rect2(Vector2(rect.position.x,rect.end.y-0.07),Vector2(rect.size.x,0.07)))
		result.append(Rect2(rect.position,Vector2(0.07,rect.size.y)))
		result.append(Rect2(Vector2(rect.end.x-0.07,rect.position.y),Vector2(0.07,rect.size.y)))
	return result

static func road_edges() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for cell in Paving.road_tiles():
		for normal in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			# Only the outside boundary: no lines across junctions or pad entries.
			if Paving.cells().has(cell+normal): continue
			var at := Paving.center(cell)+Vector2(normal)*(Paving.TILE*0.5-0.15)
			var size := Vector2(0.055,Paving.TILE) if normal.x!=0 else Vector2(Paving.TILE,0.055)
			result.append({"rect":Rect2(at-size*0.5,size),"at":at,"cell":cell,"normal":normal})
	return result

static func beacons() -> Array[Vector2]:
	var result: Array[Vector2]=[]
	for edge in road_edges():
		# Three metres apart along a straight edge; paired across the road.
		var along: int=edge.cell.y if edge.normal.x!=0 else edge.cell.x
		if posmod(along,2)==0: result.append(edge.at)
	return result

static func steady(color: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color=Color(color)
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func mesh_part(label: String, rectangles: Array[Rect2], material: Material, height: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rect in rectangles: Paving.quad(surface,rect,height)
	var instance := MeshInstance3D.new()
	instance.name=label
	instance.mesh=surface.commit()
	instance.material_override=material
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _ready() -> void:
	var cores := pad_edges()
	var halos: Array[Rect2]=[]
	for rect in cores: halos.append(rect.grow(0.12))
	var blue := ShaderMaterial.new()
	blue.shader=preload("res://paving_glow.gdshader")
	blue.set_shader_parameter("tint",Color("168dff"))
	mesh_part("PadHalo",halos,blue,HEIGHT)
	mesh_part("PadNeon",cores,steady("71dfff"),HEIGHT+0.006)
	var edges: Array[Rect2]=[]
	for edge in road_edges(): edges.append(edge.rect)
	mesh_part("RoadOutline",edges,steady("b4ab78"),HEIGHT)
	var fixtures: Array[Rect2]=[]
	var lenses: Array[Rect2]=[]
	for at in beacons():
		# Flush inset fittings preserve the complete two-tile walking width.
		fixtures.append(Rect2(at-Vector2.ONE*0.14,Vector2.ONE*0.28))
		lenses.append(Rect2(at-Vector2.ONE*0.10,Vector2.ONE*0.20))
	mesh_part("BeaconHousing",fixtures,steady("283848"),HEIGHT+0.006)
	beacon_material=ShaderMaterial.new()
	beacon_material.shader=preload("res://runway_beacon.gdshader")
	beacon_material.set_shader_parameter("motion_enabled",not reduced_motion)
	mesh_part("RunwayLights",lenses,beacon_material,HEIGHT+0.012)
