shader_type sky;

uniform sampler2D moon_tex : filter_linear, repeat_disable, source_color;
uniform vec3 moon_dir = vec3(0.0, 0.38, 0.925);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

vec3 star_layer(vec3 dir, float scale, float threshold, float gain, float twinkle) {
	vec3 scaled = dir * scale;
	vec3 cell = floor(scaled);
	float n = hash13(cell);
	if (n < threshold) {
		return vec3(0.0);
	}
	vec3 jitter = vec3(hash13(cell + vec3(1.7, 0.0, 0.0)), hash13(cell + vec3(0.0, 2.3, 0.0)), hash13(cell + vec3(0.0, 0.0, 3.1)));
	vec3 center = cell + 0.5 + (jitter - 0.5) * 0.55;
	float dist = length(scaled - center);
	float size = mix(0.045, 0.16, fract(n * 13.0));
	float point = smoothstep(size, size * 0.2, dist);
	float blink = 1.0;
	if (twinkle > 0.0) {
		blink = mix(1.0, 0.72 + 0.28 * sin(TIME * (0.7 + n * 1.8) + n * 40.0), twinkle);
	}
	vec3 tint = mix(vec3(0.72, 0.82, 1.0), vec3(1.0, 0.92, 0.75), step(0.62, fract(n * 17.0)));
	return tint * point * gain * blink;
}

vec3 meteor(vec3 dir, float seed) {
	float period = 9.0 + seed * 8.0;
	float t = fract(TIME / period + seed);
	float life = smoothstep(0.0, 0.015, t) * (1.0 - smoothstep(0.11, 0.17, t));
	if (life <= 0.001 || dir.y < 0.08) {
		return vec3(0.0);
	}
	float travel = clamp(t / 0.17, 0.0, 1.0);
	float yaw = seed * 6.2831853;
	vec3 start = normalize(vec3(cos(yaw), 0.42 + fract(seed * 3.1) * 0.35, sin(yaw)));
	vec3 finish = normalize(start + vec3(sin(yaw + 1.1) * 0.85, -0.55, cos(yaw + 0.4) * 0.55));
	vec3 head = normalize(mix(start, finish, travel));
	vec3 flight = normalize(finish - start);
	vec3 offset = dir - head;
	float along = dot(offset, -flight);
	float side = length(offset + flight * along);
	float behind = smoothstep(-0.004, 0.0, along);
	float fade = exp(-max(along, 0.0) * 9.5);
	float width = mix(280000.0, 90000.0, clamp(along * 6.0, 0.0, 1.0));
	float tail = fade * exp(-side * side * width) * behind;
	float spark = exp(-dot(offset, offset) * 420000.0);
	vec3 tail_color = mix(vec3(1.0, 0.72, 0.38), vec3(1.0, 0.96, 0.88), fade);
	return (vec3(1.0, 0.97, 0.9) * spark * 1.15 + tail_color * tail * 0.85) * life;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float height = clamp(dir.y, 0.0, 1.0);
	vec3 horizon = vec3(0.16, 0.075, 0.09);
	vec3 mid = vec3(0.045, 0.055, 0.13);
	vec3 zenith = vec3(0.012, 0.016, 0.045);
	vec3 color = mix(horizon, mid, smoothstep(0.0, 0.28, height));
	color = mix(color, zenith, smoothstep(0.18, 0.9, height));

	float star_fade = smoothstep(-0.02, 0.2, dir.y);
	color += star_layer(dir, 70.0, 0.965, 0.85, 0.0) * star_fade;
	color += star_layer(dir, 34.0, 0.93, 1.35, 0.85) * star_fade;

	vec3 moon = normalize(moon_dir);
	vec3 helper = abs(moon.y) > 0.92 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 tangent = normalize(cross(helper, moon));
	vec3 bitangent = cross(moon, tangent);
	vec2 plane = vec2(dot(dir, tangent), dot(dir, bitangent));
	vec2 moon_uv = plane / 0.36 + 0.5;
	float on_moon = step(0.0, moon_uv.x) * step(moon_uv.x, 1.0) * step(0.0, moon_uv.y) * step(moon_uv.y, 1.0);
	on_moon *= step(0.0, dot(dir, moon));
	vec3 moon_color = texture(moon_tex, moon_uv).rgb * on_moon;
	float moon_cover = smoothstep(0.04, 0.28, max(moon_color.r, max(moon_color.g, moon_color.b)));
	color *= 1.0 - moon_cover * 0.85;
	color += moon_color;
	float glow = pow(clamp(dot(dir, moon), 0.0, 1.0), 48.0);
	color += vec3(0.42, 0.34, 0.18) * glow * 0.35;

	color += meteor(dir, 0.17);
	color += meteor(dir, 0.63);

	COLOR = color;
}
