shader_type spatial;
render_mode cull_disabled;
uniform float canyon_haze = 0.0;
uniform vec4 rock_color : source_color = vec4(0.58,0.30,0.20,1.0);
uniform sampler2D stone : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 geology_position;
varying vec3 geology_normal;
varying vec3 view_position;
vec2 mirrored(vec2 uv) { return 1.0-abs(fract(uv*0.5)*2.0-1.0); }
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void vertex() {
	geology_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	geology_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
	view_position=(MODELVIEW_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	vec3 p=geology_position;
	vec3 weight=pow(abs(geology_normal),vec3(5.0));
	weight/=max(dot(weight,vec3(1.0)),0.001);
	vec3 paint=texture(stone,mirrored(p.zy*0.10)).rgb*weight.x;
	paint+=texture(stone,mirrored(p.xz*0.10)).rgb*weight.y;
	paint+=texture(stone,mirrored(p.xy*0.10)).rgb*weight.z;
	float relief=dot(paint,vec3(0.30,0.52,0.18));
	float weather=noise(p.xz*0.16+vec2(p.y*0.13));
	float bed=p.y*0.32+noise(p.xz*0.19)*1.1;
	float seams=pow(0.5+0.5*sin(bed*6.28),18.0);
	float vertical=noise(vec2(p.x*0.7+p.z*0.9,p.y*0.075));
	float seep=smoothstep(0.59,0.78,vertical)*(1.0-max(geology_normal.y,0.0));
	vec3 col=rock_color.rgb*(0.68+relief*1.40);
	col*=mix(0.85,1.06,weather)*(1.0-seep*0.19-seams*0.035);
	float dust=smoothstep(0.2,0.85,geology_normal.y)*(0.4+weather*0.6);
	col=mix(col,vec3(0.65,0.43,0.27),dust*0.25);
	// Screen derivatives add subtle surface relief without stretching tangent maps.
	// This is art-directed relief from color, not a measured rock height map.
	float height=relief*0.12-seams*0.007;
	vec3 dx=dFdx(view_position), dy=dFdy(view_position);
	vec3 n=normalize(NORMAL);
	vec3 r1=cross(dy,n), r2=cross(n,dx);
	float det=dot(dx,r1);
	vec3 gradient=sign(det)*(dFdx(height)*r1+dFdy(height)*r2);
	NORMAL=normalize(abs(det)*n-gradient);
	float haze=smoothstep(2.0,28.0,-p.y)*canyon_haze;
	ALBEDO=mix(col*0.78,vec3(0.20,0.29,0.34),haze*0.65);
	ROUGHNESS=mix(0.96,0.80,seep*0.6+relief*0.4);
}
