extends Node
## Original synthesized foley. Movement feedback only; never an operational alert.
const Paving = preload("res://colony_paving.gd")
const Structures = preload("res://structure_catalog.gd")
const Commons = preload("res://living_commons.gd")
var enabled := false:
	set(value):
		enabled=value
		if not value:
			player.stop()
			ambience.stop()
var actor: Node3D
var interior := false
var reduced := false:
	set(value):
		reduced=value
		dust.visible=not value
		if value: dust.emitting=false
var previous := Vector3.ZERO
var player := AudioStreamPlayer.new()
var ambience := AudioStreamPlayer.new()
var samples: Dictionary = {}
var dust := CPUParticles3D.new()
var last_surface := "soil"
var contact_count := 0

static func surface_at(point: Vector3, inside: bool = false) -> String:
	var flat := Vector2(point.x,point.z)
	if Commons.FOOTPRINT.has_point(flat): return "wood"
	# Match the authored Habitat plank strip in build_remaining_structures.py.
	# Use the catalog's actual room placement/footprint rather than world offsets.
	for placement in Structures.placements():
		if str(placement.definition.id)!="habitat": continue
		var footprint: Rect2=placement.definition.collision_boxes[0]
		var center := footprint.get_center()
		var origin := Vector2(placement.position.x,placement.position.z)
		var width := footprint.size.x-3.4
		var wood := Rect2(origin+Vector2(center.x-1.0-width/2.0,center.y-0.065),Vector2(width,4.48))
		if wood.has_point(flat): return "wood"
	return "metal" if inside or Paving.contains(flat) else "soil"

static func sound(kind: String) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate=22050
	var seconds := 0.22 if kind in ["soil","metal","wood"] else 0.65
	var bytes := PackedByteArray(); bytes.resize(int(seconds*22050)*2)
	var rng := RandomNumberGenerator.new(); rng.seed=53
	var smooth := 0.0
	for i in range(bytes.size()/2):
		var t := float(i)/22050.0
		smooth=lerpf(smooth,rng.randf_range(-1,1),0.28)
		var value := smooth*exp(-t*25)*0.5
		if kind=="metal": value+=sin(t*TAU*180)*exp(-t*38)*0.25
		if kind=="wood": value=smooth*exp(-t*32)*0.26+(sin(t*TAU*95)*0.32+sin(t*TAU*210)*0.08)*exp(-t*30)
		if kind=="door": value=(smooth*0.18+sin(t*TAU*(280-t*140))*0.04)*sin(t/seconds*PI)
		value*=minf(1.0,t/0.002)*minf(1.0,(seconds-t)/0.012)
		bytes.encode_s16(i*2,int(clampf(value,-1,1)*32767))
	stream.data=bytes
	return stream

func _ready() -> void:
	for kind in ["soil","metal","wood","door"]: samples[kind]=sound(kind)
	player.volume_db=-19; add_child(player)
	ambience.volume_db=-22; add_child(ambience)
	dust.amount=6; dust.lifetime=0.30; dust.emitting=false; dust.one_shot=true
	dust.explosiveness=0.9
	dust.local_coords=false; dust.gravity=Vector3(0,0.07,0); dust.direction=Vector3.UP
	dust.initial_velocity_min=0.06; dust.initial_velocity_max=0.18; dust.spread=70
	dust.scale_amount_min=0.025; dust.scale_amount_max=0.07
	var mesh := SphereMesh.new(); mesh.radius=0.5; mesh.height=0.6; mesh.radial_segments=4; mesh.rings=2
	var material := StandardMaterial3D.new()
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color=Color(0.68,0.42,0.3,0.22)
	mesh.material=material; dust.mesh=mesh
	add_child(dust)
	if actor:
		previous=actor.global_position
		actor.foot_contact.connect(_on_contact)

func doorway() -> void:
	if actor:
		previous=actor.global_position
		actor.gait.reset()
	if enabled: ambience.stream=samples.door; ambience.play()

func _physics_process(_delta: float) -> void:
	if not actor: return
	var point:=actor.global_position
	var traveled:=point.distance_to(previous); previous=point
	var moving:=traveled>0.005 and traveled<0.5
	last_surface=surface_at(point,interior)
	dust.position=point+Vector3(0,0.08,0)
	if not moving or last_surface!="soil" or reduced: dust.emitting=false
	if not enabled:
		player.stop(); ambience.stop()

func _on_contact() -> void:
	if not actor or not actor.gait.moving: return
	contact_count+=1
	var point:=actor.global_position
	last_surface=surface_at(point,interior)
	if last_surface=="soil" and not reduced:
		dust.position=point+Vector3(0,0.04,0)
		dust.restart()
		dust.emitting=true
	if enabled:
		player.stream=samples[last_surface]
		player.play()

func _exit_tree() -> void:
	player.stop(); ambience.stop()
	player.stream=null; ambience.stream=null
	samples.clear()
	dust.emitting=false
