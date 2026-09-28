shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// A faint sole-contact cue, not a solid selection marker or a second sun shadow.
void fragment() {
	float radius=length((UV-vec2(0.5))*2.0);
	float contact=1.0-smoothstep(0.18,1.0,radius);
	ALBEDO=vec3(0.018,0.022,0.028);
	ALPHA=contact*0.24;
}
