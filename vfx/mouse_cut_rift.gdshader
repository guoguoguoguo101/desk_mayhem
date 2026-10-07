shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D space_texture : source_color, repeat_enable;
uniform float grow_t = 0.0;
uniform float dissolve = 0.0;
uniform float age = 0.0;
uniform float surface_kind = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	float outward = abs(UV.x - 0.5) * 2.0;
	if (outward > grow_t) discard;
	float noise = hash(floor(UV * vec2(95.0, 14.0)));
	float erosion = outward * 0.75 + noise * 0.25;
	if (dissolve > 0.0 && erosion > 1.0 - dissolve) discard;
	vec3 cosmic = texture(space_texture, vec2(UV.x * 1.7 - age * 0.24, UV.y * 0.8)).rgb;
	float electric = pow(max(sin(UV.x * 85.0 - age * 32.0 + sin(UV.y * 23.0) * 3.0), 0.0), 12.0);
	float erosion_edge = dissolve > 0.0 ? 1.0 - smoothstep(0.0, 0.08, 1.0 - dissolve - erosion) : 0.0;
	if (surface_kind < 0.5) {
		ALBEDO = vec3(0.006, 0.012, 0.035) + cosmic * 0.3;
		EMISSION = cosmic * 0.35 + vec3(0.02, 0.25, 0.6) * electric * 0.18 + vec3(0.15, 0.65, 1.0) * erosion_edge;
	} else if (surface_kind < 1.5) {
		ALBEDO = vec3(0.02, 0.18, 0.4);
		EMISSION = vec3(0.04, 0.4, 1.0) * (1.5 + electric * 2.5 + erosion_edge);
	} else {
		ALBEDO = vec3(1.0, 0.6, 0.12);
		EMISSION = vec3(1.0, 0.55, 0.06) * (3.0 + electric * 2.0) + vec3(0.5, 0.8, 1.0) * erosion_edge;
	}
}
