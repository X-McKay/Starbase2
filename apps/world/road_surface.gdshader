shader_type spatial;
render_mode cull_disabled;
uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform vec4 region;
void fragment() {
	vec3 pigment=texture(atlas,region.xy+UV*region.zw).rgb;
	float detail=clamp(dot(pigment,vec3(0.2126,0.7152,0.0722))*0.45,0.0,0.17);
	ALBEDO=vec3(0.43,0.45,0.47)+detail;
	ROUGHNESS=0.94;
}
