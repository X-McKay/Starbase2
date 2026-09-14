shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Cosmetic suit treatment for the three selected opaque suits. Source UVs and
// skin remain unchanged. No state input and no emission or animated parameters.
uniform sampler2D suit_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 role_color : source_color = vec4(0.6, 0.84, 1.0, 1.0);
uniform bool use_identity_mask = false;
uniform float palette_strength = 0.30;

void fragment() {
	vec4 source = texture(suit_texture, UV);
	float value = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	// Baked near-black contrast was hiding entire limbs in ordinary room light.
	// Lift the darkest cloth, compress tiny details, retain broad plate separation.
	vec3 cloth = mix(source.rgb, vec3(value), 0.45) * 0.60 + vec3(0.10, 0.12, 0.13);
	float plate = smoothstep(0.12, 0.52, value);
	vec3 ceramic = mix(vec3(0.76, 0.80, 0.77), role_color.rgb, palette_strength);
	ALBEDO = mix(cloth, ceramic, plate * 0.68);
	// Retain strongly colored source accents, especially Engineering's gold visor.
	float chroma = max(source.r, max(source.g, source.b)) - min(source.r, min(source.g, source.b));
	ALBEDO = mix(ALBEDO, source.rgb * 0.8 + vec3(0.04), smoothstep(0.35, 0.65, chroma) * 0.8);
	// Blender-authored full-head protection keeps skin, hair and helmet art intact.
	if (use_identity_mask) {
		ALBEDO = mix(ALBEDO, source.rgb, clamp(COLOR.r, 0.0, 1.0));
	}
	ROUGHNESS = 0.72;
	METALLIC = 0.0;
	SPECULAR = 0.25;
}
