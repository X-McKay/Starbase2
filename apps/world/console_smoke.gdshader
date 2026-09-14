shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
// Neutral smoked glass: readable backing without blue tint or animated noise.
void fragment() {
	vec4 paint = COLOR;
	if (paint.a > 0.7 && max(paint.r, max(paint.g, paint.b)) < 0.16) {
		vec3 behind = textureLod(screen_texture, SCREEN_UV, 3.0).rgb;
		float luminance = dot(behind, vec3(0.2126, 0.7152, 0.0722));
		vec3 neutral = mix(behind, vec3(luminance), 0.85);
		COLOR = vec4(mix(vec3(0.028), neutral, 0.10), 0.97);
	}
}
