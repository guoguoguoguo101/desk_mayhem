shader_type particles;
render_mode disable_force, disable_velocity;

uniform vec3 forward = vec3(1.0, 0.0, 0.0);
uniform float progress = 0.0;
uniform float ground_y = 0.0;
uniform float catchup = 0.0;

float random_value(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void start() {
	float n = float(NUMBER) * 17.0 + float(RANDOM_SEED % uint(1000));
	vec3 side = normalize(cross(forward, vec3(0.0, 1.0, 0.0)));
	float p = smoothstep(0.0, 0.9, progress);
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = EMISSION_TRANSFORM[3].xyz + forward * random_value(n + 1.0) * 0.8 + side * (random_value(n + 2.0) - 0.5) * mix(1.8, 0.5, p);
	TRANSFORM[3].y += mix(0.1, -0.65, p) + random_value(n + 3.0) * mix(2.0, 0.3, p);
	float speed = mix(5.0, 11.0, random_value(n + 4.0));
	VELOCITY = forward * speed + side * (random_value(n + 5.0) - 0.5) * speed * 0.7;
	VELOCITY.y = -length(VELOCITY.xz) * mix(0.12, 1.1, random_value(n + 6.0));
	CUSTOM = vec4(catchup, mix(0.3, 0.65, random_value(n + 7.0)), random_value(n + 8.0) < 0.25 ? 1.0 : 0.0, 0.0);
	bool large = random_value(n + 9.0) < 0.18;
	float len = large ? mix(0.65, 1.15, random_value(n + 10.0)) : mix(0.16, 0.55, random_value(n + 10.0));
	float width = large ? mix(0.2, 0.35, random_value(n + 11.0)) : mix(0.07, 0.18, random_value(n + 11.0));
	TRANSFORM[0].xyz = vec3(len, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, width, 0.0);
	float brightness = mix(0.9, 2.8, pow(random_value(n + 12.0), 1.4));
	COLOR = vec4((random_value(n + 13.0) < 0.22 ? vec3(1.0, 0.57, 0.08) : vec3(0.12, 0.55, 1.0)) * brightness, 1.0);
	TRANSFORM[3].xyz += VELOCITY * catchup;
}

void process() {
	CUSTOM.x += DELTA;
	VELOCITY.y -= 7.0 * DELTA;
	TRANSFORM[3].xyz += VELOCITY * DELTA;
	if (TRANSFORM[3].y < ground_y + 0.04 && VELOCITY.y < 0.0) {
		TRANSFORM[3].y = ground_y + 0.04;
		if (CUSTOM.z > 0.5 && CUSTOM.w < 0.5) {
			VELOCITY.y = min(abs(VELOCITY.y) * 0.28, 1.6);
			VELOCITY.xz *= 0.65;
			CUSTOM.w = 1.0;
		} else { ACTIVE = false; }
	}
	float len = length(TRANSFORM[0].xyz);
	float width = length(TRANSFORM[1].xyz);
	vec3 direction = normalize(VELOCITY);
	vec3 across = normalize(cross(vec3(0.0, 0.0, 1.0), direction));
	if (length(across) < 0.1) { across = vec3(0.0, 1.0, 0.0); }
	TRANSFORM[0].xyz = direction * len;
	TRANSFORM[1].xyz = across * width;
	TRANSFORM[2].xyz = normalize(cross(direction, across));
	COLOR.a = (1.0 - smoothstep(0.45, 1.0, CUSTOM.x / CUSTOM.y));
	if (CUSTOM.x >= CUSTOM.y) { ACTIVE = false; }
}
