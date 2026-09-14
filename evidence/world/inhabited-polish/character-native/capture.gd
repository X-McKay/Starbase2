extends SceneTree
const OUT := "/Users/al/git/Starbase2/evidence/world/inhabited-polish/character-native/"
var actor: CharacterBody3D
var camera: Camera3D
var foley: Node
var records: Array[Dictionary] = []
func _initialize() -> void:
	run.call_deferred()
func capture(label:String,wide:bool=false) -> void:
	camera.size=3.5 if wide else 1.45
	camera.position=actor.position+Vector3(.35,1.7,3.3)
	camera.look_at(actor.position+Vector3(-.12,1.12 if wide else 1.55,0))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+label+".png")
	records.append({"capture":label,"position":[actor.position.x,actor.position.y,actor.position.z],"clip":actor.model_visual.clip,"hair_angle":[actor.model_visual.secondary.angles.x,actor.model_visual.secondary.angles.y],"foot_contacts":foley.contact_count,"surface":foley.last_surface,"dust_emitting":foley.dust.emitting,"audio_enabled":foley.enabled})
func _process(_delta:float) -> bool:
	if camera and actor:
		camera.position=actor.position+Vector3(.35,1.7,3.3)
		camera.look_at(actor.position+Vector3(-.12,1.12 if camera.size>2 else 1.55,0))
	return false
func run() -> void:
	root.size=Vector2i(1200,900)
	var world:=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(.095,.12,.14)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color(.72,.80,.85)
	environment.environment.ambient_light_energy=.8
	world.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-25,0);light.light_energy=1.4;world.add_child(light)
	var floor_mesh:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(100,100);floor_mesh.mesh=plane
	var material:=StandardMaterial3D.new();material.albedo_color=Color(.22,.14,.09);material.roughness=1;floor_mesh.material_override=material
	floor_mesh.position=Vector3(-25,-.02,-25);world.add_child(floor_mesh)
	actor=load("res://actor.gd").new();actor.position=Vector3(-29,0,-32);actor.display_name="";world.add_child(actor)
	foley=load("res://footfall.gd").new();foley.actor=actor;world.add_child(foley)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.current=true;world.add_child(camera)
	for i in range(15): await physics_frame
	await capture("01-idle")
	actor.motion=Vector3(0,0,6)
	for i in range(35): await physics_frame
	await capture("02-running")
	actor.motion=Vector3(6,0,0)
	for i in range(5): await physics_frame
	await capture("03-turning")
	for i in range(20): await physics_frame
	await capture("04-soil-footfall",true)
	actor.motion=Vector3.ZERO
	for i in range(20): await physics_frame
	await capture("05-stopped")
	actor.reduced_motion=true;foley.reduced=true
	actor.motion=Vector3(0,0,6)
	for i in range(15): await physics_frame
	await capture("06-reduced-motion",true)
	var file:=FileAccess.open(OUT+"capture-record.json",FileAccess.WRITE);file.store_string(JSON.stringify(records,"\t"));file.close()
	print("CHARACTER_NATIVE_CAPTURE_COMPLETE")
	world.queue_free();await process_frame
	quit()
