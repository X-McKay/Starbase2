shader_type canvas_item;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void fragment() {
	vec2 uv=UV;
	float nebula=noise(uv*5.0)*0.6+noise(uv*13.0)*0.25;
	float band=exp(-pow((uv.y-0.54+uv.x*0.17)*3.8,2.0));
	vec3 col=mix(vec3(0.025,0.045,0.10),vec3(0.11,0.17,0.27),uv.y);
	col+=vec3(0.14,0.07,0.19)*nebula*band;
	vec2 cells=floor(uv*vec2(420,250));
	float star=step(0.990,hash(cells))*step(length(fract(uv*vec2(420,250))-0.5),0.15);
	col+=star*vec3(0.52,0.66,0.76);
	vec2 p=(uv-vec2(0.87,0.22))*vec2(1.6,1);
	float r=length(p);
	float disc=1.0-smoothstep(0.16,0.161,r);
	float nz=sqrt(max(0.0,1.0-dot(p,p)/(0.16*0.16)));
	float light=clamp(dot(vec3(p/0.16,nz),normalize(vec3(-0.7,-0.4,0.65))),0.045,1.0);
	float bands=0.5+0.18*sin((p.y+p.x*0.23)*165.0+noise(p*52.0)*4.0)+0.20*noise(p*175.0);
	vec3 planet=mix(vec3(0.12,0.29,0.43),vec3(0.53,0.67,0.71),bands)*light;
	float ring_r=length(vec2(p.x,(p.y+p.x*0.28)*3.3));
	float ring_mask=smoothstep(0.205,0.210,ring_r)*(1.0-smoothstep(0.249,0.254,ring_r));
	vec3 rings=mix(vec3(0.27,0.35,0.44),vec3(0.65,0.63,0.57),0.5+0.5*sin(ring_r*980.0));
	col=mix(col,rings,ring_mask*0.64);
	col=mix(col,planet,disc);
	col+=vec3(0.13,0.37,0.51)*exp(-abs(r-0.162)*195.0)*0.42;
	COLOR=vec4(col,1.0);
}
