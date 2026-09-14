extends Node3D
## Decorative morning dressing. No backend inputs, dispatch, health or progress.
const DOORWAY=preload("res://assets/environment/morning-atmosphere/doorway.glb")
const LINEN=preload("res://morning_linen.gdshader")
const STEAM=preload("res://morning_steam.gdshader")
var breeze_time:=0.0
var reduced_motion:=false
var textiles:Array[ShaderMaterial]=[]
var vapors:Array[MeshInstance3D]=[]
var entrances:Array[Dictionary]=[]
var leaves:Array[Dictionary]=[]

func install(world:Node3D) -> void:
	for station in world.get_node("Structures").get_children():
		if str(station.definition.id) not in ["habitat","review"]: continue
		var threshold:Vector3=station.to_global(station.definition.threshold)
		var art:Node3D=DOORWAY.instantiate()
		add_child(art); art.global_position=threshold
		for mesh in art.find_children("MorningLinen*","MeshInstance3D",true,false):
			var material:=ShaderMaterial.new(); material.shader=LINEN
			material.set_shader_parameter("linen_color",Color("b46b44") if str(station.definition.id)=="habitat" else Color("519b98"))
			mesh.material_override=material; textiles.append(material)
		var lamp:=OmniLight3D.new()
		lamp.name="WelcomeLight"; lamp.position=threshold+Vector3(0,2.5,0.65)
		lamp.light_color=Color("ffd3a0"); lamp.omni_range=3.4; lamp.light_energy=0.18
		lamp.shadow_enabled=false; add_child(lamp)
		entrances.append({"point":threshold,"lamp":lamp,"warmth":0.0})
		if str(station.definition.id)=="habitat":
			var wall:Node3D=preload("res://assets/environment/morning-atmosphere/habitat-wall.glb").instantiate()
			add_child(wall); wall.global_position=station.global_position
			var accents:Node3D=preload("res://assets/kits/habitat-accents/habitat-accents.glb").instantiate()
			add_child(accents); accents.global_transform=station.global_transform
			for leaf in wall.find_children("Sage*","MeshInstance3D",true,false):
				leaves.append({"node":leaf,"rest":leaf.rotation,"phase":float(leaves.size())*0.73})
			for point in [Vector3(-4.7,1.063,-2.7),Vector3(-2.8,1.063,-2.5),Vector3(-7.75,1.353,-3.7)]:
				add_steam(station.to_global(point))
	for point in [Vector3(-0.36,1.073,-0.35),Vector3(0.34,1.073,0.42)]:
		add_steam(world.get_node("LivingCommons").to_global(point))

func add_steam(point:Vector3) -> void:
	var mesh:=MeshInstance3D.new(); mesh.name="DecorativeTeaSteam"
	var quad:=QuadMesh.new(); quad.size=Vector2(0.21,0.46); mesh.mesh=quad
	mesh.position=point+Vector3(0,0.23,0)
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material:=ShaderMaterial.new(); material.shader=STEAM
	material.set_shader_parameter("phase",float(vapors.size())*1.7)
	mesh.material_override=material; add_child(mesh); vapors.append(mesh)

func set_reduced_motion(value:bool) -> void:
	reduced_motion=value
	for mesh in vapors: mesh.visible=not value

func update_presentation(points:Array,delta:float,reduced:bool) -> void:
	set_reduced_motion(reduced)
	if not reduced: breeze_time+=clampf(delta,0.0,0.1)
	for leaf in leaves:
		leaf.node.rotation=leaf.rest+Vector3(0.0,0.0,sin(breeze_time*0.9+float(leaf.phase))*0.045)
	for material in textiles: material.set_shader_parameter("breeze_time",breeze_time)
	for mesh in vapors: mesh.material_override.set_shader_parameter("steam_time",breeze_time)
	for entry in entrances:
		var nearest:=INF
		for point in points:
			nearest=minf(nearest,Vector2(point.x-entry.point.x,point.z-entry.point.z).length())
		var target:=1.0-smoothstep(1.4,4.0,nearest)
		entry.warmth=target if reduced else move_toward(float(entry.warmth),target,delta*1.5)
		entry.lamp.light_energy=0.18+float(entry.warmth)*0.65
