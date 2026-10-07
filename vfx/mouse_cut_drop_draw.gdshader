shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform sampler2D sprite_texture : source_color, filter_linear_mipmap;

void vertex() {
	// Face the camera while keeping the projected velocity as the long axis.
	vec3 axis = MODELVIEW_MATRIX[0].xyz;
	float len = length(axis);
	float width = length(MODELVIEW_MATRIX[1].xyz);
	vec3 heading = normalize(vec3(axis.xy, 0.0));
	vec3 across = vec3(-heading.y, heading.x, 0.0);
	MODELVIEW_MATRIX[0].xyz = heading * len;
	MODELVIEW_MATRIX[1].xyz = across * width;
}

void fragment() {
	vec4 tex = texture(sprite_texture, UV);
	float spindle = pow(max(sin(UV.x * 3.14159265), 0.0), 0.8);
	float across = abs(UV.y - 0.5) / max(spindle, 0.001);
	float core = exp(-across * across * 9000.0) * spindle;
	vec3 energy = COLOR.rgb * tex.rgb;
	ALBEDO = energy + vec3(core * 0.75);
	EMISSION = energy * 5.5 + (COLOR.rgb * 0.3 + vec3(0.8)) * core * 5.0;
	ALPHA = max(tex.a, core) * COLOR.a;
}
