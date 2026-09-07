shader_type spatial;
uniform vec4 color : source_color = vec4(0.6,0.7,0.7,1.0);
uniform vec4 glow : source_color = vec4(0.0);
uniform sampler2D albedo_map : source_color, filter_linear_mipmap;
uniform sampler2D surface_map : filter_linear_mipmap;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap;
uniform sampler2D emission_map : source_color, filter_linear_mipmap;
uniform bool use_albedo = false;
uniform bool use_surface = false;
uniform bool use_normal = false;
uniform bool use_emission = false;
uniform float roughness = 0.6;
uniform float metallic = 0.15;
uniform float normal_strength = 1.0;
uniform float emission_strength = 1.0;
uniform bool reactor_glow = false;
uniform float visibility : hint_range(0.0,1.0) = 1.0;
void fragment() {
 float noise=fract(sin(dot(floor(FRAGCOORD.xy),vec2(12.9898,78.233)))*43758.5453);
 if (visibility <= noise) discard;
 ALBEDO=color.rgb*(use_albedo ? texture(albedo_map,UV).rgb : vec3(1.0));
 ROUGHNESS=roughness*(use_surface ? texture(surface_map,UV).g : 1.0);
 METALLIC=metallic*(use_surface ? texture(surface_map,UV).b : 1.0);
 EMISSION=glow.rgb*emission_strength*(use_emission ? texture(emission_map,UV).rgb : vec3(1.0));
 if (reactor_glow) {
  float cyan=smoothstep(0.04,0.20,ALBEDO.b-ALBEDO.r)*smoothstep(0.02,0.18,ALBEDO.g-ALBEDO.r);
  EMISSION+=ALBEDO*cyan*1.8;
 }
 if (use_normal) { NORMAL_MAP=texture(normal_map,UV).rgb; NORMAL_MAP_DEPTH=normal_strength; }
}
