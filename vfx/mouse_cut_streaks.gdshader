shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float time = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform bool drop_profile = false;
uniform sampler2D drop_texture : source_color, filter_linear_mipmap;

void fragment() {
	if (drop_profile) {
		vec4 sprite = texture(drop_texture, UV);
		float core = smoothstep(0.7, 1.0, sprite.a);
		vec3 energy = mix(COLOR.rgb, vec3(1.0), core * 0.2);
		ALBEDO = energy;
		EMISSION = energy * sprite.rgb * (0.35 + core * 0.65);
		ALPHA = COLOR.a * opacity * sprite.a * 0.65;
	} else {
	float thin_core = pow(1.0 - abs(UV.y * 2.0 - 1.0), 2.2);
	float taper = smoothstep(0.0, 0.18, UV.x) * (1.0 - smoothstep(0.85, 1.0, UV.x));
	ALBEDO = COLOR.rgb * (1.0 + thin_core * 2.0);
	EMISSION = COLOR.rgb * thin_core * 2.0;
	ALPHA = COLOR.a * opacity * thin_core * taper;
	}
}
