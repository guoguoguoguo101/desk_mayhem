shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float energy = 2.2;
uniform float reveal = 1.0;

void fragment() {
	vec4 color = texture(tex, UV);
	float drawn = 1.0 - smoothstep(reveal, reveal + 0.16, UV.x);
	ALBEDO = color.rgb * tint.rgb * energy;
	ALPHA = color.a * tint.a * drawn;
}
