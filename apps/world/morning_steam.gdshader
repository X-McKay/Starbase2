shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
uniform float steam_time = 0.0;
uniform float phase = 0.0;
void vertex() {
 // Quad faces the viewer; the effect stays tied to its actual mug position.
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
void fragment() {
 float height=1.0-UV.y;
 float center=0.5+sin(height*8.0-steam_time*1.3+phase)*0.10;
 float width=0.065+height*0.10;
 float ribbon=exp(-pow((UV.x-center)/width,2.0));
 float envelope=smoothstep(0.0,0.18,height)*(1.0-smoothstep(0.45,1.0,height));
 ALBEDO=vec3(0.91,0.87,0.75);
 ALPHA=ribbon*envelope*0.16;
}
