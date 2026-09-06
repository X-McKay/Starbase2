shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
void fragment() {
    vec2 q=abs(UV*2.0-1.0);
    float falloff=1.0-smoothstep(0.62,1.0,max(q.x,q.y));
    ALBEDO=vec3(0.025,0.035,0.05);
    ALPHA=falloff*0.38;
}
