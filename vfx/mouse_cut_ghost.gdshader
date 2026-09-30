shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D base_texture : source_color;
uniform bool has_texture = false;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.8;
uniform float seed = 0.0;

void fragment() {
	vec4 original = has_texture ? texture(base_texture, UV) : vec4(1.0);
	float block = fract(sin(dot(floor(UV * 48.0) + vec2(seed, seed * 0.37), vec2(12.9898, 78.233))) * 43758.5453);
	float threshold = dissolve * 1.12 - (1.0 - UV.y) * 0.18;
	if (block < threshold || original.a < 0.08) discard;
	float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 2.2);
	float edge = 1.0 - smoothstep(0.0, 0.22, block - threshold);
	vec3 body = mix(vec3(0.08, 0.22, 0.58), original.rgb * vec3(0.22, 0.72, 1.1), 0.43);
	ALBEDO = body + vec3(0.22, 0.72, 1.0) * rim * 1.3 + vec3(0.42, 0.9, 1.0) * edge * 0.42;
	EMISSION = vec3(0.05, 0.36, 1.0) * (rim * 2.4 + edge * 0.55);
	ALPHA = opacity * original.a * (0.73 + rim * 0.27);
}
