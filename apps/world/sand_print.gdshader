shader_type spatial;
render_mode cull_disabled, depth_draw_never;
uniform float clock = 0.0;
uniform float lifetime = 24.0;
varying float born;
void vertex() { born = INSTANCE_CUSTOM.r; }
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// Broad toe, narrowed arch and separate heel; no square decal boundary.
	float toe = length((p - vec2(0.0, -0.27)) / vec2(0.72, 0.61)) - 1.0;
	float heel = length((p - vec2(0.0, 0.52)) / vec2(0.55, 0.30)) - 1.0;
	float shape = min(toe, heel);
	float aa = max(fwidth(shape), 0.035);
	float body = 1.0 - smoothstep(-aa, aa, shape);
	float rim = (1.0 - smoothstep(0.04, 0.18 + aa, abs(shape))) * 0.18;
	float grooves = smoothstep(0.28, 0.48, abs(sin(p.y * 18.0 + p.x * 2.0)));
	float age = max(clock - born, 0.0);
	float fade = 1.0 - smoothstep(lifetime * 0.35, lifetime, age);
	ALBEDO = mix(vec3(0.19, 0.075, 0.036), vec3(0.64, 0.34, 0.17), rim);
	ROUGHNESS = 1.0;
	ALPHA = (body * mix(0.13, 0.29, grooves) + rim * 0.15) * fade;
}
