shader_type spatial;
render_mode unshaded, cull_disabled;
uniform bool motion_enabled = true;
void fragment() {
	// One slow, soft pulse every 2.4 seconds; reduced motion stays fully lit.
	float wave=0.5+0.5*cos(TIME*2.617993878);
	float pulse=motion_enabled ? mix(0.20,1.0,smoothstep(0.3,0.8,wave)) : 1.0;
	ALBEDO=vec3(1.0,0.72,0.075)*pulse;
}
