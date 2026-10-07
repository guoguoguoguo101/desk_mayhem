shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.18, 0.82, 1.0, 0.9);
uniform float time = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float core = pow(1.0 - abs(UV.y * 2.0 - 1.0), 2.5);
	float packet = pow(max(0.0, sin(UV.x * 17.0 - time * 31.0)), 9.0);
	float shimmer = 0.7 + 0.3 * sin(UV.x * 34.0 + time * 18.0);
	ALBEDO = tint.rgb * (0.7 + core * 1.4 + packet * 0.6);
	ALPHA = tint.a * opacity * (core * 0.24 + packet * 0.09) * shimmer;
}
