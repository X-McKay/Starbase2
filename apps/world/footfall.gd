extends Node
## Original synthesized foley. Movement feedback only; never an operational alert.
const Paving = preload("res://colony_paving.gd")
var enabled := false
var actor: Node3D
var interior := false
var reduced := false
var previous := Vector3.ZERO
var player := AudioStreamPlayer.new()
var ambience := AudioStreamPlayer.new()
var samples: Dictionary = {}
var dust := CPUParticles3D.new()

static func sound(kind: String) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate=22050
	var seconds := 0.22 if kind in ["soil","metal"] else 0.65
	var bytes := PackedByteArray(); bytes.resize(int(seconds*22050)*2)
	var rng := RandomNumberGenerator.new(); rng.seed=53
	var smooth := 0.0
	for i in range(bytes.size()/2):
		var t := float(i)/22050.0
		smooth=lerpf(smooth,rng.randf_range(-1,1),0.28)
		var value := smooth*exp(-t*25)*0.5
		if kind=="metal": value+=sin(t*TAU*180)*exp(-t*38)*0.25
		if kind=="door": value=(smooth*0.18+sin(t*TAU*(280-t*140))*0.04)*sin(t/seconds*PI)
		bytes.encode_s16(i*2,int(clampf(value,-1,1)*32767))
	stream.data=bytes
	return stream

func _ready() -> void:
	for kind in ["soil","metal","door"]: samples[kind]=sound(kind)
	player.volume_db=-16; add_child(player)
	ambience.volume_db=-22; add_child(ambience)
	dust.amount=16; dust.lifetime=0.65; dust.emitting=false
	dust.local_coords=false; dust.gravity=Vector3(0,0.15,0); dust.direction=Vector3.UP
	dust.initial_velocity_min=0.15; dust.initial_velocity_max=0.5; dust.spread=70
	dust.scale_amount_min=0.06; dust.scale_amount_max=0.18
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
	var paved:=interior or Paving.contains(Vector2(point.x,point.z))
	dust.position=point+Vector3(0,0.08,0)
	dust.emitting=moving and not paved and not reduced
	if not enabled:
		player.stop(); ambience.stop()

func _on_contact() -> void:
	if enabled:
		var point:=actor.global_position
		var paved:=interior or Paving.contains(Vector2(point.x,point.z))
		player.stream=samples.metal if paved else samples.soil
		player.play()
