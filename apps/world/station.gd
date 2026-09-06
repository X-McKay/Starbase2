@tool
extends Node3D
## Shared host for both illustrated PNG exteriors and authored native scenes.
const Definition = preload("res://building_definition.gd")
const Art = preload("res://art.gd")
@export var definition: Definition
## Existing UI context assigned by placement, never inferred from artwork.
@export var interaction_kind := ""

func _ready() -> void:
	if definition==null: return
	var errors := definition.problems()
	if not errors.is_empty():
		push_error("Invalid building %s: %s" % [name,"; ".join(errors)])
		return
	if not definition.exterior_image.is_empty():
		var texture: Texture2D=load(definition.exterior_image)
		var sprite := Sprite3D.new()
		sprite.name="Illustration"
		sprite.texture=texture
		sprite.pixel_size=definition.image_pixel_size
		sprite.offset=Vector2(texture.get_width()*0.5-definition.image_door_pixel.x,definition.image_door_pixel.y-texture.get_height()*0.5)
		sprite.position=definition.threshold
		sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		sprite.alpha_cut=SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.alpha_scissor_threshold=0.5
		sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sprite.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sprite)
	else:
		add_child(load(definition.exterior_scene).instantiate())
	if not definition.yard_scene.is_empty(): add_child(load(definition.yard_scene).instantiate())
	for rect in definition.collision_boxes:
		var shade := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size=rect.size+Vector2(1.8,1.8)
		shade.mesh=plane
		shade.position=Vector3(rect.get_center().x+0.4,0.093,rect.get_center().y+0.3)
		var shadow_material := ShaderMaterial.new()
		shadow_material.shader=preload("res://contact_shadow.gdshader")
		shade.material_override=shadow_material
		shade.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shade)
		Art.collider(self,Vector3(rect.get_center().x,definition.collision_height*0.5,rect.get_center().y),Vector3(rect.size.x,definition.collision_height,rect.size.y))
	if not definition.interior_scene.is_empty():
		# Shared physical sill ties the billboard door to the paved approach.
		var sill:=definition.threshold+Vector3(0,0.12,0.35)
		Art.box(self,sill,Vector3(1.7,0.06,0.75),"263c4a")
		Art.box(self,sill+Vector3(0,0.04,0.30),Vector3(1.6,0.025,0.055),"b9d8d9")
	for pair in [["Threshold",definition.threshold],["Approach",definition.approach],["Return",definition.return_point]]:
		var marker := Marker3D.new()
		marker.name=pair[0]
		marker.position=pair[1]
		add_child(marker)

func entrance() -> Vector3: return to_global(definition.approach)
func return_position() -> Vector3: return to_global(definition.return_point)
