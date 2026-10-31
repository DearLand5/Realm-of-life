// Noise shared by world shaders (terrain, water, plants, sky); works in the
// Mobile and Compatibility renderers.

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

// Tileable noise textures bound by RlNoise.bind(): one fetch per octave instead
// of 4 hashes (decisive on phone GPUs). Unit noise cells: 64 per texture.
uniform sampler2D rl_noise_v : filter_linear_mipmap, repeat_enable;
uniform sampler2D rl_noise_f : filter_linear_mipmap, repeat_enable;

// Value noise in [0, 1].
float rl_vnoise(vec2 p) {
	return texture(rl_noise_v, p * 0.015625).r;
}

// Three-octave fBm in [0, 1].
float rl_fbm3(vec2 p) {
	return texture(rl_noise_f, p * 0.015625 + vec2(0.27, 0.61)).r;
}

// Triplanar value noise weighted by the world normal.
float rl_triplanar(vec3 p, vec3 n, float freq) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z + 1e-5);
	return rl_vnoise(p.yz * freq) * w.x + rl_vnoise(p.xz * freq + 7.3) * w.y + rl_vnoise(p.xy * freq + 13.1) * w.z;
}
