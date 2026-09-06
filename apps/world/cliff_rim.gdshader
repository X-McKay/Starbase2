shader_type spatial;
render_mode cull_disabled, depth_draw_never;
uniform sampler2D stone : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec2 ground;
void vertex() { ground=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz; }
void fragment() {
	vec2 uv=1.0-abs(fract(ground*0.055)*2.0-1.0);
	vec3 paint=texture(stone,uv).rgb;
	float grain=dot(paint,vec3(0.3,0.5,0.2));
	ALBEDO=paint*0.75+vec3(0.09,0.04,0.017);
	ALPHA=smoothstep(0.06,0.84,UV.x+(grain-0.4)*0.7);
	ROUGHNESS=1.0;
}
