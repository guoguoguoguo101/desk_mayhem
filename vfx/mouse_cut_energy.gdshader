shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.14, 0.78, 1.0, 0.75);

void fragment() {
	float center = pow(1.0 - abs(UV.x * 2.0 - 1.0), 1.8);
	float height_fade = pow(1.0 - UV.y, 0.75);
	float flicker = 0.78 + 0.22 * sin(UV.y * 23.0 + TIME * 19.0);
	ALBEDO = mix(tint.rgb, vec3(0.87, 0.98, 1.0), center * 0.72) * 2.8;
	ALPHA = tint.a * center * height_fade * flicker;
}
