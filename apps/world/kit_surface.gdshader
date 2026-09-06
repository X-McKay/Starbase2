shader_type spatial;
render_mode cull_disabled;
uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform vec4 region;
uniform float emission_strength = 0.0;
void fragment() {
	vec3 pigment=texture(atlas,region.xy+UV*region.zw).rgb;
	ALBEDO=pigment;
	ROUGHNESS=0.86;
	EMISSION=pigment*emission_strength;
}
