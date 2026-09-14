shader_type spatial;
render_mode cull_disabled;
// The commons uses folded, two-sided leaves. Hull cutaways retain their own culling.
uniform vec4 color : source_color = vec4(0.15, 0.3, 0.08, 1.0);
uniform float roughness = 0.7;
uniform float metallic = 0.0;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap;
uniform bool use_albedo = false;
uniform float breeze_strength = 0.025;
uniform bool motion_enabled = true;

void vertex() {
 if (motion_enabled) {
  VERTEX.x += sin(TIME * 1.1 + VERTEX.z * 2.0 + VERTEX.y)
   * breeze_strength * clamp(VERTEX.y, 0.0, 1.0);
 }
}

void fragment() {
 ALBEDO = color.rgb * (use_albedo ? texture(albedo_map, UV).rgb : vec3(1.0));
 ROUGHNESS = roughness;
 METALLIC = metallic;
 if (!FRONT_FACING) NORMAL = -NORMAL;
}
