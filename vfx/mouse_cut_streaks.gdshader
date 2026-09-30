shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float time = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float thin_core = pow(1.0 - abs(UV.y * 2.0 - 1.0), 2.2);
	float packet = pow(max(sin(UV.x * 21.0 - time * 38.0), 0.0), 12.0);
	ALBEDO = COLOR.rgb * (0.7 + thin_core * 1.5 + packet * 0.7);
	ALPHA = COLOR.a * opacity * (0.2 + thin_core * 0.63 + packet * 0.2);
}
