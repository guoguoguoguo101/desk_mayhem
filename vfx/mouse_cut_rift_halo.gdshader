shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float grow_t = 0.0;
uniform float dissolve = 0.0;
uniform float age = 0.0;
void fragment() {
	float outward = abs(UV.x - 0.5) * 2.0;
	if (outward > grow_t || outward > 1.0 - dissolve) discard;
	float core = pow(max(1.0 - abs(UV.y * 2.0 - 1.0), 0.0), 3.0);
	ALBEDO = vec3(0.12, 0.6, 1.0);
	EMISSION = vec3(0.1, 0.45, 1.0) * core * 3.0;
	ALPHA = core * 0.7 * (1.0 - dissolve);
}
