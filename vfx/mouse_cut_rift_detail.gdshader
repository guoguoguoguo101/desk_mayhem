shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform sampler2D detail_texture : source_color, filter_linear_mipmap;
uniform float grow_t = 0.0;
uniform float dissolve = 0.0;
uniform float age = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
void fragment() {
	float outward = abs(UV.x - 0.5) * 2.0;
	if (outward > grow_t) discard;
	float noise = hash(floor(UV * vec2(100.0, 45.0)));
	float erosion = outward * 0.8 + noise * 0.2;
	if (dissolve > 0.0 && erosion > 1.0 - dissolve) discard;
	vec4 tex = texture(detail_texture, UV);
	float edge = dissolve > 0.0 ? 1.0 - smoothstep(0.0,0.07,1.0-dissolve-erosion) : 0.0;
	float detail_light = max(tex.r,max(tex.g,tex.b));
	float pulse = 0.9 + 0.1 * sin(UV.x * 45.0 - age * 28.0);
	ALBEDO = tex.rgb;
	EMISSION = tex.rgb * (1.4 * pulse) * smoothstep(0.08,0.4,detail_light) + vec3(0.12,0.55,1.0) * edge;
	ALPHA = tex.a * (1.0 - smoothstep(0.85,1.0,dissolve));
}
