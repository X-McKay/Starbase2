shader_type spatial;
render_mode cull_disabled;
uniform float breeze_time = 0.0;
uniform vec4 linen_color : source_color = vec4(0.70,0.36,0.22,1.0);
void vertex() {
 float free_end=1.0-UV.y;
 VERTEX.z += sin(breeze_time*1.1+VERTEX.x*0.7)*0.035*free_end*free_end;
}
void fragment() {
 float weave=0.97+0.03*sin(UV.x*220.0)*sin(UV.y*300.0);
 ALBEDO=linen_color.rgb*weave;
 ROUGHNESS=0.92;
 if (!FRONT_FACING) NORMAL=-NORMAL;
}
