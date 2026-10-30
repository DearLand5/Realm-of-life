// Cheap procedural noise shared by world shaders (terrain, water, plants, sky).
// No textures; works in Mobile and Compatibility renderers.

float rl_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float rl_hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

// Value noise in [0, 1].
float rl_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = rl_hash12(i);
	float b = rl_hash12(i + vec2(1.0, 0.0));
	float c = rl_hash12(i + vec2(0.0, 1.0));
	float d = rl_hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Three-octave fBm in [0, 1].
float rl_fbm3(vec2 p) {
	return rl_vnoise(p) * 0.5 + rl_vnoise(p * 2.03 + vec2(17.1, 3.7)) * 0.3 + rl_vnoise(p * 4.07 + vec2(41.7, 29.3)) * 0.2;
}

// Triplanar value noise weighted by the world normal.
float rl_triplanar(vec3 p, vec3 n, float freq) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z + 1e-5);
	return rl_vnoise(p.yz * freq) * w.x + rl_vnoise(p.xz * freq + 7.3) * w.y + rl_vnoise(p.xy * freq + 13.1) * w.z;
}
