shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.08,0.55,1.0,1.0);
void fragment() {
	float edge=min(min(UV.x,1.0-UV.x),min(UV.y,1.0-UV.y));
	ALBEDO=tint.rgb;
	ALPHA=smoothstep(0.0,0.35,edge)*0.14;
}
