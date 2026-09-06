shader_type spatial;
render_mode cull_disabled, depth_draw_never;
uniform float trail_length=1.0;
varying vec2 ground;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void vertex() { ground=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz; }
void fragment() {
	float edge=abs(UV.x-0.5)*2.0;
	float grit=noise(ground*6.0);
	float wear=noise(ground*0.9);
	vec3 soil=mix(vec3(0.42,0.265,0.17),vec3(0.60,0.405,0.255),wear*0.6+grit*0.4);
	float track=(1.0-smoothstep(0.045,0.13,abs(edge-0.48)))*(0.6+noise(ground*2.0)*0.4);
	soil-=track*vec3(0.055,0.034,0.02);
	float shoulder=smoothstep(0.68,0.87,edge)*(1.0-smoothstep(0.87,0.98,edge));
	soil+=shoulder*vec3(0.075,0.049,0.022);
	ALBEDO=soil;
	ALPHA=(1.0-smoothstep(0.77+grit*0.08,1.0,edge))*smoothstep(0.0,0.8,UV.y)*(1.0-smoothstep(trail_length-0.8,trail_length,UV.y));
	ROUGHNESS=1.0;
}
