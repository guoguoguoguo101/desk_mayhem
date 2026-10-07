shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float opacity = 1.0;
uniform float age = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float angle = atan(p.y,p.x);
	float broken = 0.35 + 0.65 * smoothstep(-0.5,0.5,sin(angle*11.0+sin(angle*5.0)*2.0));
	float rim = exp(-pow((radius-0.82)/0.018,2.0));
	float echo = exp(-pow((radius-0.75)/0.04,2.0))*0.2;
	ALBEDO = vec3(0.05,0.55,1.0);
	EMISSION = vec3(0.06,0.45,1.0)*rim*1.8;
	ALPHA = (rim+echo)*broken*opacity;
}
