shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// Soft contact darkening where floors meet walls; decorative only.
uniform float strength = 0.42;
void fragment() {
	float base=1.0-UV.y;
	float ends=smoothstep(0.0,0.06,UV.x)*smoothstep(0.0,0.06,1.0-UV.x);
	ALBEDO=vec3(0.02,0.03,0.045);
	ALPHA=base*base*strength*ends;
}
