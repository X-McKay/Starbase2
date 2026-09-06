shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
uniform sampler2D stone : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec2 ground;
void vertex() { ground=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz; }
void fragment() {
	vec2 p=UV*2.0-1.0;
	float r=length(p);
	vec2 uv=1.0-abs(fract(ground*0.13)*2.0-1.0);
	vec3 paint=texture(stone,uv).rgb;
	float grain=dot(paint,vec3(0.3,0.5,0.2));
	float lip=exp(-pow((r-0.70)*10.0,2.0));
	float basin=1.0-smoothstep(0.30,0.64,r);
	vec3 soil=mix(vec3(0.48,0.235,0.13),vec3(0.64,0.335,0.18),grain);
	soil*=1.0-basin*0.17;
	soil+=lip*vec3(0.07,0.045,0.025)*(0.7+p.y*0.3);
	ALBEDO=soil;
	ALPHA=1.0-smoothstep(0.86,1.0,r);
	ROUGHNESS=1.0;
}
