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
	float detail = dot(original.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 body = mix(vec3(0.025, 0.075, 0.3), vec3(0.08, 0.36, 0.9), detail);
	ALBEDO = body + vec3(0.22, 0.75, 1.0) * rim * 1.7;
	EMISSION = vec3(0.12, 0.58, 1.0) * (0.55 + detail * 0.45 + rim * 3.5) + vec3(0.4, 0.88, 1.0) * edge * 1.2;
	ALPHA = opacity * original.a * (0.73 + rim * 0.27);
}
