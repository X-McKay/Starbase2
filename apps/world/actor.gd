extends CharacterBody3D
## Animation is decorative; authoritative activity labels are supplied separately.
const Art = preload("res://art.gd")
const Catalog = preload("res://characters/catalog.gd")
const Gait = preload("res://characters/gait.gd")
const ModelVisual = preload("res://characters/model_visual.gd")
var model_visual: Node3D
var presentation_pose := ""
var presentation_facing := Vector3(INF,0,0)
signal foot_contact
@export var character_definition: Resource
var gait := Gait.new()
var last_position := Vector3.ZERO
@export var appearance := "operator"
@export var display_name := "YOU"
@export var suit_tint := Color.WHITE
var sprite: AnimatedSprite3D
var label: Label3D
var target := Vector3.ZERO
var motion := Vector3.ZERO
var phase := 0.0
var reduced_motion := false
var home := Vector3.ZERO
var facing := 0

func _ready() -> void:
	home = position
	target = position
	if character_definition==null:
		character_definition=Catalog.get_definition(appearance,"--character-pilot" in OS.get_cmdline_user_args())
	sprite = AnimatedSprite3D.new()
	sprite.sprite_frames=character_definition.frames()
	sprite.animation="idle_front"
	_apply_layout()
	last_position=global_position
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.modulate=suit_tint
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.5
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(sprite)
	if character_definition.model_scene:
		model_visual = ModelVisual.new()
		add_child(model_visual)
		model_visual.configure(character_definition.model_scene, character_definition.model_scale, character_definition.model_floor_offset)
		model_visual.apply_role(character_definition.model_tint*suit_tint)
		sprite.visible = false
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.6
	shape.shape = capsule
	shape.position.y = 0.8
	add_child(shape)
	collision_layer = 2
	collision_mask = 1
	label = Art.sign(self, display_name, Vector3(0, character_definition.label_height, 0), "e8e6d4", 18)
	label.no_depth_test = true
	label.pixel_size = 0.021
	# Grounding shadow complements the real directional sprite shadow.
	var shadow := Art.cylinder(self, Vector3(0, 0.015, 0), 0.36, 0.015, "456169")
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _physics_process(_delta: float) -> void:
	var teleported:=global_position.distance_to(last_position)>0.5
	var before:=global_position
	velocity = motion
	move_and_slide()
	var traveled:=global_position-before
	traveled.y=0
	last_position=global_position
	var stride: float = character_definition.model_stride if model_visual else character_definition.stride
	if model_visual and model_visual.animation.has_animation("run") and traveled.length()/maxf(_delta,0.001)>5.0:
		stride=character_definition.model_run_stride
	gait.advance(traveled.length(),stride,teleported)
	if model_visual:
		var face_delta:=presentation_facing-global_position
		var face_heading:=atan2(face_delta.x,face_delta.z) if is_finite(presentation_facing.x) else INF
		model_visual.project(traveled,gait.moving,gait.phase,reduced_motion,_delta,presentation_pose,face_heading)
	if gait.moving:
		if absf(traveled.x)>absf(traveled.z):
			facing=3 if traveled.x>0 else 2
		else:
			facing=0 if traveled.z>0 else 1
	var clip: String=character_definition.animation_for(gait.moving and not reduced_motion,facing)
	if sprite.animation!=clip:
		sprite.animation=clip
		_apply_layout()
	sprite.set_frame_and_progress(character_definition.frame_for_phase(clip,gait.phase),0.0)
	# Frames already contain the authored rise/fall. No additional procedural bob.
	for _contact in range(gait.contacts): foot_contact.emit()

func _apply_layout() -> void:
	var layout:Dictionary=character_definition.layout_for(sprite.animation)
	if layout.is_empty():
		sprite.pixel_size=2.8/sprite.sprite_frames.get_frame_texture(sprite.animation,0).get_height()
		sprite.position.y=1.36; sprite.offset=Vector2.ZERO; sprite.shaded=true
	else:
		var size:Vector2=Vector2(layout.canvas)
		var anchor:Vector2=Vector2(layout.pivot)
		sprite.pixel_size=layout.pixel_size
		sprite.offset=Vector2(size.x*.5-anchor.x,anchor.y-size.y*.5)
		sprite.position.y=0; sprite.shaded=layout.get("shaded",false)

# Static, color-independent assignment cues. Structured inspectors own full run IDs.
# This changes only the existing label: no timers, movement, or command dispatch.
func project_assignment(intent: Dictionary, large_text: bool = false) -> void:
	if label==null: return
	var markers: Array=intent.get("task_markers",[])
	var summary:=str(intent.get("label","No recorded work"))
	if not markers.is_empty():
		summary="%s %s" % [markers[0].get("icon","?"),markers[0].get("text","Unknown")]
		if int(intent.get("active_count",0))>1: summary+=" · %d tasks" % int(intent.active_count)
	label.text=display_name+"\n"+summary
	label.set_meta("retained_count",markers.size()+int(intent.get("marker_overflow",0)))
	label.font_size=22 if large_text else 18
	label.modulate=Color(markers[0].get("color","e8e6d4")) if not markers.is_empty() else Color("e8e6d4")
