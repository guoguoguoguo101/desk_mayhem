shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;

uniform vec3 warm_color : source_color = vec3(1.0, 0.31, 0.045);

void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(1.65, 2.15);
	float flow = sin(TIME * 2.6 + p.x * 9.0) * 0.025;
	p.y += flow;
	float d = length(p);
	float irregular = sin(atan(p.y, p.x) * 7.0 + TIME * 1.3) * 0.035;
	float edge = 1.0 - smoothstep(0.15, 0.77 + irregular, d);
	float core = 1.0 - smoothstep(0.02, 0.39, d);
	float breathe = 0.87 + 0.08 * sin(TIME * 3.1);
	ALBEDO = mix(warm_color, vec3(1.0, 0.66, 0.19), core * 0.65);
	EMISSION = ALBEDO * (0.35 + core * 0.4) * breathe;
	ALPHA = edge * (0.34 + core * 0.30) * breathe;
}
