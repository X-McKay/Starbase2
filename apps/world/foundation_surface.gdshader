shader_type spatial;
render_mode cull_disabled;
uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform vec4 region;
void fragment() {
	vec3 pigment = texture(atlas, region.xy + UV * region.zw).rgb;
	// Retain the authored surface while subordinating repeated panel detail.
	float value = dot(pigment, vec3(0.2126, 0.7152, 0.0722));
	ALBEDO = vec3(0.24, 0.265, 0.27) + vec3(value * 0.19);
	ROUGHNESS = 0.94;
}
