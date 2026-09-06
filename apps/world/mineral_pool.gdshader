shader_type spatial;
render_mode cull_disabled;
uniform float water_time = 0.0;
varying vec2 basin;
varying vec2 ground;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void vertex() { basin=UV*2.0-1.0; ground=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz; }
void fragment() {
	float r=length(basin);
	float t=water_time;
	vec2 p=ground;
	float a=dot(p,vec2(2.2,1.1))+t*0.65;
	float b=dot(p,vec2(-1.3,2.8))-t*0.48;
	float c=dot(p,vec2(4.8,2.5))+sin(a)*0.6+t*0.24;
	vec2 slope=vec2(2.2,1.1)*cos(a)*0.009+vec2(-1.3,2.8)*cos(b)*0.006;
	slope+=vec2(4.8,2.5)*cos(c)*0.003;
	NORMAL=normalize((VIEW_MATRIX*vec4(-slope.x,1.0,-slope.y,0)).xyz);
	float shallow=smoothstep(0.36,0.97,r);
	vec3 col=mix(vec3(0.025,0.23,0.275),vec3(0.16,0.51,0.47),shallow);
	float warp=noise(p*1.1+vec2(t*0.06,-t*0.04));
	col+=(noise(p*0.65+vec2(t*0.025))-0.5)*vec3(0.012,0.045,0.045);
	float lattice=abs(sin(p.x*3.6+warp*3.0+t*0.16)*sin(p.y*4.2-warp*2.0-t*0.12));
	float caustic=1.0-smoothstep(0.015,0.10,lattice);
	col+=vec3(0.10,0.22,0.17)*caustic*shallow*0.40;
	float ripple=pow(0.5+0.5*sin(c),12.0);
	col+=vec3(0.10,0.16,0.16)*ripple*0.18;
	float foam=smoothstep(0.90,0.99,r)*(0.4+noise(p*4.0)*0.6);
	col=mix(col,vec3(0.65,0.78,0.65),foam*0.64);
	float fresnel=pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),3.0);
	ALBEDO=mix(col,vec3(0.35,0.55,0.62),fresnel*0.4);
	ROUGHNESS=0.25+foam*0.4;
	METALLIC=0.0;
	SPECULAR=0.45;
}
