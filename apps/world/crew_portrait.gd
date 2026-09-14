extends TextureRect
## Actual colony character, rendered only when identity changes or the panel opens.
## Cosmetic portrait owns no task state, world movement or command authority.
const Catalog=preload("res://characters/catalog.gd")
const Visual=preload("res://characters/model_visual.gd")
const IDENTITIES={"repair":"mender","review":"surveyor","gym":"trainer","watchkeeper":"watchkeeper","reviewer":"reviewer"}
var viewport:SubViewport
var stage:Node3D
var model:Node3D
var camera:Camera3D
var crew_kind:=""

func _ready() -> void:
	expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	viewport=SubViewport.new(); viewport.size=Vector2i(480,720)
	viewport.own_world_3d=true
	viewport.msaa_3d=Viewport.MSAA_4X
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(viewport)
	stage=Node3D.new(); viewport.add_child(stage)
	var environment:=WorldEnvironment.new()
	var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR; settings.background_color=Color("141312")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("ddd9d4"); settings.ambient_light_energy=0.55
	environment.environment=settings; stage.add_child(environment)
	camera=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=1.7; stage.add_child(camera)
	for spec in [[Vector3(-2,3,4),Color("fff0df"),1.5],[Vector3(3,1,2),Color("e8e7e4"),0.6],[Vector3(-2,2,-2),Color("ff764f"),1.0]]:
		var light:=DirectionalLight3D.new(); stage.add_child(light)
		light.position=spec[0]; light.look_at(Vector3(0,1,0))
		light.light_color=spec[1]; light.light_energy=spec[2]
	texture=viewport.get_texture()
	visibility_changed.connect(refresh)
	set_crew("repair" if crew_kind.is_empty() else crew_kind)

func set_crew(kind:String) -> void:
	if viewport==null: crew_kind=kind; return
	if crew_kind==kind and is_instance_valid(model): refresh(); return
	crew_kind=kind
	if is_instance_valid(model): stage.remove_child(model); model.queue_free()
	var definition:Resource=Catalog.get_definition(IDENTITIES.get(kind,"operator"))
	model=Visual.new(); stage.add_child(model)
	model.configure_definition(definition)
	model.set_motion_profile(definition.motion_profile)
	model.apply_role(definition.model_tint)
	model.project(Vector3.ZERO,false,0,true)
	model.rotation.y=-0.12
	var head:int=model.skeleton.find_bone("Head")
	var height:=2.0
	if head>=0: height=(model.skeleton.global_transform*model.skeleton.get_bone_global_pose(head).origin).y
	var target:=Vector3(0,height-0.35,0)
	camera.position=target+Vector3(0,0.02,4)
	camera.look_at(target)
	refresh.call_deferred()

func refresh() -> void:
	if viewport==null: return
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
