extends Node3D
## Decorative machinery and local audio only. Never projects operational success.
var world: Node
var rotor := Node3D.new()
var hum := AudioStreamPlayer3D.new()
var phase := 0.0
var core_light: OmniLight3D

func _ready() -> void:
 world=get_parent()
 while world!=null and not world.has_method("apply_settings"): world=world.get_parent()
 var roof := MeshInstance3D.new()
 var roof_mesh := BoxMesh.new()
 roof_mesh.size=Vector3(10.7,0.18,8.3)
 roof.mesh=roof_mesh
 roof.position=Vector3(-1.95,4.15,-2.6)
 roof.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
 add_child(roof)
 for mesh in get_node("Reactor").find_children("*","MeshInstance3D",true,false):
  for i in mesh.mesh.get_surface_count():
   var material := preload("res://buildings/materials.gd").cutaway(mesh.get_active_material(i))
   material.set_shader_parameter("reactor_glow",true)
   mesh.set_surface_override_material(i,material)
 rotor.position=Vector3(-1.95,3.45,-2.6)
 add_child(rotor)
 var material := StandardMaterial3D.new()
 material.albedo_color=Color(0.04,0.5,0.65)
 material.emission_enabled=true
 material.emission=Color(0.03,0.48,0.65)
 material.emission_energy_multiplier=1.5
 for i in range(3):
  var blade := MeshInstance3D.new()
  var box := BoxMesh.new()
  box.size=Vector3(0.08,0.035,0.6)
  blade.mesh=box
  blade.material_override=material
  var angle := i*TAU/3
  blade.position=Vector3(sin(angle)*0.55,0,cos(angle)*0.55)
  blade.rotation.y=angle
  rotor.add_child(blade)
 for spec in [[Vector3(-1.95,2.3,-2.6),Color(0.15,0.65,0.85),1.6,4.8],[Vector3(-5.6,2.8,-5.5),Color(1,0.62,0.28),1.8,5.0],[Vector3(1.5,2.8,-5.5),Color(1,0.62,0.28),1.8,5.0]]:
  var light := OmniLight3D.new()
  light.position=spec[0]
  light.light_color=spec[1]
  light.light_energy=spec[2]
  light.omni_range=spec[3]
  light.omni_attenuation=1.4
  add_child(light)
  if core_light==null: core_light=light
 var sound := AudioStreamWAV.new()
 sound.format=AudioStreamWAV.FORMAT_16_BITS
 sound.mix_rate=22050
 var data := PackedByteArray()
 data.resize(22050*2*2)
 for i in range(22050*2):
  var t := float(i)/22050.0
  var value := (sin(t*TAU*70)*0.07+sin(t*TAU*140)*0.018+sin(t*TAU*210)*0.009)
  data.encode_s16(i*2,int(value*32767))
 sound.data=data
 sound.loop_mode=AudioStreamWAV.LOOP_FORWARD
 sound.loop_end=44100
 hum.stream=sound
 hum.position=Vector3(-1.95,1.5,-2.6)
 hum.volume_db=-15
 hum.unit_size=3
 hum.max_distance=16
 add_child(hum)

func _process(delta: float) -> void:
 if world==null or world.hud==null: return
 var enabled: bool=world.hud.sound_enabled
 if enabled and not hum.playing: hum.play()
 if not enabled and hum.playing: hum.stop()
 if world.hud.reduced: return
 phase+=delta
 rotor.rotation.y=phase*0.35
 core_light.light_energy=1.6+sin(phase*1.2)*0.06
