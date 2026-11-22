// Park around the play area (issue #1, 1. Szenario-Start): drawn on surfaces that stand
// on the play-area boundary (walls, a low cap) and on a ground ring outside it. Each
// pixel follows the ray from the eye: below the horizon it shows the grass where the
// ray meets the floor (correct perspective and parallax), above it the sky and a
// distant tree line. Inside the boundary nothing is drawn, so the real room, the
// mannequin and the hands stay passthrough.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float floor_y = 0.0;
uniform vec2 path_center = vec2(0.0);
uniform float path_radius = 7.0;

varying vec3 world_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 eye = CAMERA_POSITION_WORLD;
	vec3 dir = normalize(world_pos - eye);
	vec3 horizon = vec3(0.78, 0.84, 0.88);
	vec3 col;
	if (dir.y < -0.002) {
		float t = (eye.y - floor_y) / -dir.y;
		vec2 p = eye.xz + dir.xz * t;
		float n = fbm(p * 0.6);
		vec3 grass = mix(vec3(0.16, 0.30, 0.08), vec3(0.32, 0.46, 0.14), n);
		grass *= 0.85 + 0.3 * noise(p * 9.0);
		// A gravel path around the scene, like a park walkway.
		float d = abs(length(p - path_center) - path_radius);
		float path = 1.0 - smoothstep(0.75, 0.9, d + 0.15 * noise(p * 3.0));
		vec3 gravel = vec3(0.55, 0.50, 0.42) * (0.85 + 0.3 * noise(p * 14.0));
		col = mix(grass, gravel, path);
		// Far grass fades into the foot of the tree line, not into the sky.
		col = mix(col, vec3(0.22, 0.32, 0.15), smoothstep(12.0, 90.0, t));
	} else {
		float elev = asin(clamp(dir.y, 0.0, 1.0));
		float az = atan(dir.z, dir.x);
		vec3 sky = mix(horizon, vec3(0.32, 0.52, 0.82), pow(clamp(elev / 1.2, 0.0, 1.0), 0.6));
		// Clouds on a far plane.
		vec2 cp = dir.xz / max(dir.y, 0.05) * 1.5;
		float cloud = smoothstep(0.5, 0.8, fbm(cp * 0.6));
		sky = mix(sky, vec3(0.96), cloud * 0.7 * smoothstep(0.02, 0.2, elev));
		// Distant trees: a wavy line of crowns, seamless around the circle.
		vec2 ring = vec2(cos(az), sin(az));
		float crowns = 0.05 + 0.06 * fbm(ring * 4.0 + 7.0) + 0.025 * noise(ring * 40.0);
		float tree = 1.0 - smoothstep(crowns - 0.004, crowns + 0.004, elev);
		vec3 leaves = mix(vec3(0.10, 0.20, 0.08), vec3(0.20, 0.32, 0.12), noise(vec2(az * 60.0, elev * 80.0)));
		col = mix(sky, mix(leaves, horizon, 0.2 * smoothstep(0.0, crowns, elev)), tree);
	}
	ALBEDO = col;
}
