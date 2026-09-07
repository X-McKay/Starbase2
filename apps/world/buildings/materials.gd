extends RefCounted
## Preserve imported PBR channels when adding a cutaway or reactor emission.
static func cutaway(source: Material) -> ShaderMaterial:
 var material := ShaderMaterial.new()
 material.shader=preload("res://buildings/cutaway.gdshader")
 if source is StandardMaterial3D:
  material.set_shader_parameter("color",source.albedo_color)
  material.set_shader_parameter("glow",source.emission if source.emission_enabled else Color.BLACK)
  material.set_shader_parameter("roughness",source.roughness)
  material.set_shader_parameter("metallic",source.metallic)
  material.set_shader_parameter("normal_strength",source.normal_scale)
  material.set_shader_parameter("emission_strength",source.emission_energy_multiplier)
  for spec in [["albedo",source.albedo_texture],["surface",source.roughness_texture],["normal",source.normal_texture],["emission",source.emission_texture]]:
   if spec[1]!=null:
    material.set_shader_parameter(spec[0]+"_map",spec[1])
    material.set_shader_parameter("use_"+spec[0],true)
 return material
