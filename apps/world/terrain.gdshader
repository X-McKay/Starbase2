shader_type spatial;
render_mode cull_disabled;
uniform bool compacted = false;
uniform bool upland = false;
uniform sampler2D stone : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 ground;
varying vec3 terrain_normal;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
vec2 cells(vec2 p) {
	vec2 cell=floor(p), f=fract(p);
	float first=8.0, second=8.0;
	for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
		vec2 o=vec2(float(x),float(y));
		vec2 site=o+vec2(hash(cell+o),hash(cell+o+vec2(42,13)))-f;
		float d=dot(site,site);
		if(d<first) { second=first; first=d; } else { second=min(second,d); }
	}
	return vec2(second-first,first);
}
void vertex() {
	ground=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	terrain_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
	vec2 p=ground.xz;
	vec2 warp=vec2(noise(p*0.16),noise(p*0.16+19.0));
	float broad=noise(p*0.065);
	float fine=noise(p*4.0);
	vec3 clay=mix(vec3(0.46,0.215,0.125),vec3(0.65,0.345,0.19),noise(p*0.24)*0.7+broad*0.3);
	// Fractures live in eroded patches, leaving quiet sandy expanses between.
	float patch=smoothstep(0.48,0.72,noise(p*0.23+warp*1.2));
	vec2 plates=cells(p*1.25+warp*1.4);
	float aa=max(fwidth(plates.x),0.006);
	float crack=(1.0-smoothstep(0.013,0.027+aa,plates.x))*patch;
	clay=mix(clay,vec3(0.29,0.115,0.075),crack*0.32);
	float lip=smoothstep(0.025,0.04+aa,plates.x)*(1.0-smoothstep(0.04,0.065+aa,plates.x));
	clay+=lip*patch*vec3(0.065,0.033,0.010);
	clay+=(fine-0.5)*0.04;
	float sand=smoothstep(0.51,0.75,broad);
	float ripple=sin(p.x*4.2+p.y*1.3+noise(p*0.27)*10.0)*0.010;
	vec3 col=mix(clay,vec3(0.64,0.365,0.215)+ripple,sand*0.78);
	vec2 stone_uv=1.0-abs(fract(p*0.055)*2.0-1.0);
	vec3 exposed=texture(stone,stone_uv).rgb;
	col=mix(col,exposed*vec3(0.82,0.80,0.75),patch*0.28);
	float salt=1.0-smoothstep(0.9,1.8,length((p-vec2(30,-22))/vec2(7,6))+noise(p*0.8)*0.14);
	col=mix(col,vec3(0.71,0.52,0.35),salt*0.60);
	if(upland) {
		// Rock exposure grows with slope and height; the foot retains identical soil.
		float slope=1.0-smoothstep(0.50,0.94,terrain_normal.y);
		float blend=smoothstep(0.20,2.8,ground.y);
		vec3 weights=pow(abs(terrain_normal),vec3(4.0));
		weights/=max(dot(weights,vec3(1.0)),0.001);
		vec3 rock=texture(stone,1.0-abs(fract(ground.zy*0.055)*2.0-1.0)).rgb*weights.x;
		rock+=texture(stone,stone_uv).rgb*weights.y;
		rock+=texture(stone,1.0-abs(fract(ground.xy*0.055)*2.0-1.0)).rgb*weights.z;
		float drainage=1.0-smoothstep(0.03,0.23,abs(sin(p.x*0.105+noise(p*0.08)*0.7)));
		col=mix(col,rock*vec3(0.88,0.75,0.61),blend*smoothstep(0.15,0.68,slope+patch*0.30)*0.78);
		col*=1.0-drainage*blend*0.10;
	}
	if(compacted) col=mix(col,vec3(0.55,0.30,0.18),0.8);
	ALBEDO=col;
	ROUGHNESS=0.98;
}
