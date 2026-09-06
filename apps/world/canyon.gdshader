shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float water_time = 0.0;
// Shared with the visible sea-stack placement; x/z centers, elliptical waterline radii.
uniform vec4 sea_stacks[4];
varying vec2 basin;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void vertex() { basin=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz; }
void fragment() {
	vec2 p=basin;
	float t=water_time;
	vec2 drift=vec2(t*0.065,-t*0.04);
	float broad=noise(p*0.052+drift*0.15);
	float warp=noise(p*0.19+drift);
	float swell=sin(p.y*0.80+p.x*0.19+warp*4.0-t*0.48);
	float chop=sin(p.y*2.7-p.x*0.37+noise(p*0.42-drift)*5.0-t*0.72);
	float fine=sin(p.y*6.3+p.x*0.85+warp*7.0-t*0.95);
	float aa=max(fwidth(chop),0.035);
	float crests=smoothstep(0.68-aa,0.99+aa,chop);
	crests*=smoothstep(0.25,0.73,noise(p*vec2(0.45,0.7)+drift));
	float glints=smoothstep(0.88,1.0,fine)*smoothstep(0.55,0.8,noise(p*0.85-drift));
	vec3 water=mix(vec3(0.075,0.19,0.245),vec3(0.13,0.32,0.365),broad);
	water+=swell*vec3(0.012,0.028,0.031);
	water+=crests*vec3(0.06,0.12,0.13)+glints*vec3(0.04,0.07,0.08);
	// Broken waterline rings suggest gentle breakers at the four distant stacks.
	float foam=0.0;
	for(int i=0;i<4;i++) {
		vec2 offset=(p-sea_stacks[i].xy)/sea_stacks[i].zw;
		float shore=length(offset);
		float wave=sin(shore*15.0-t*0.75+warp*2.0)*0.5+0.5;
		float band=(1.0-smoothstep(1.05,1.65,shore))*smoothstep(0.80,1.02,shore);
		foam=max(foam,band*wave*(0.3+noise(p*1.7+drift)*0.7));
	}
	water=mix(water,vec3(0.43,0.62,0.60),foam*0.65);
	float mist=noise(p*vec2(0.035,0.09))*0.65+noise(p*0.08)*0.35;
	ALBEDO=mix(water,vec3(0.39,0.49,0.53),smoothstep(0.52,0.87,mist)*0.24);
}
