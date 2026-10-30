// Procedural day/night sky: gradient, sun disc + glow, moon, stars and
// fBm cloud layer driven by cloud cover. Colours are set by DayNightCycle.
// Background only (ambient light comes from a colour), so it stays cheap.
shader_type sky;

#include "res://shaders/terrain_noise.gdshaderinc"

uniform vec3 zenith_color : source_color = vec3(0.18, 0.4, 0.82);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.78, 0.9);
uniform vec3 ground_color : source_color = vec3(0.35, 0.38, 0.4);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 glow_color : source_color = vec3(1.0, 0.6, 0.3);
uniform vec3 sun_dir = vec3(0.0, 0.5, 0.86);
uniform vec3 moon_dir = vec3(0.0, 0.6, -0.8);
uniform float sun_size = 0.9994;          // cos of disc radius
uniform float glow_strength = 0.3;        // sunrise/sunset horizon glow
uniform float star_intensity = 0.0;
uniform float moon_intensity = 0.0;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.25;
uniform float cloud_darkness : hint_range(0.0, 1.0) = 0.0;
uniform vec3 cloud_light : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow : source_color = vec3(0.55, 0.6, 0.68);
uniform vec2 cloud_offset = vec2(0.0);
uniform float flash = 0.0;                // lightning

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	float up = clamp(h, 0.0, 1.0);
	vec3 col = mix(horizon_color, zenith_color, pow(up, 0.5));
	col = mix(col, ground_color, smoothstep(0.0, -0.2, h));

	float sd = dot(d, normalize(sun_dir));
	float sun_up = smoothstep(-0.12, 0.05, sun_dir.y);
	// Horizon glow around the sun (strong at dawn/dusk).
	float near_h = 1.0 - smoothstep(0.0, 0.45, abs(h));
	col += glow_color * pow(max(sd, 0.0), 3.0) * glow_strength * near_h;
	col += sun_color * pow(max(sd, 0.0), 24.0) * 0.35 * sun_up;
	float disc = smoothstep(sun_size - 0.00035, sun_size, sd) * sun_up;

	// Stars and moon at night.
	if (star_intensity > 0.001 && h > 0.0) {
		vec3 sp = d * 260.0;
		vec3 cell = floor(sp);
		float r = rl_hash13(cell);
		float tw = 0.6 + 0.4 * rl_hash13(cell + 7.0);
		float star = step(0.9972, r) * (1.0 - smoothstep(0.08, 0.38, length(fract(sp) - 0.5)));
		col += vec3(0.85, 0.9, 1.0) * star * star_intensity * tw * smoothstep(0.0, 0.25, h);
	}
	float md = dot(d, normalize(moon_dir));
	float moon = smoothstep(0.99955, 0.9997, md) * moon_intensity;
	col += vec3(0.6, 0.65, 0.75) * pow(max(md, 0.0), 60.0) * moon_intensity * 0.15;

	// Cloud layer projected onto a plane; denser cover → larger, darker clouds.
	float cov = 0.0;
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.08) * 0.9 + cloud_offset;
		float n = rl_fbm3(uv * 1.3) * 0.65 + rl_vnoise(uv * 5.2) * 0.35;
		float thr = mix(0.78, 0.18, cloud_cover);
		cov = smoothstep(thr, thr + 0.22, n) * smoothstep(0.0, 0.12, h);
		cov = max(cov, smoothstep(0.75, 1.0, cloud_cover) * 0.85 * smoothstep(-0.02, 0.1, h));
		float lit = clamp(0.55 + 0.45 * sd, 0.0, 1.0) * (1.0 - cloud_darkness);
		vec3 cc = mix(cloud_shadow, cloud_light, lit * (0.6 + 0.4 * (1.0 - n)));
		col = mix(col, cc, cov);
	}
	col += sun_color * disc * 6.0 * (1.0 - cov * 0.95);
	col += vec3(0.95, 0.95, 0.9) * moon * (1.0 - cov);
	col += vec3(0.75, 0.8, 1.0) * flash * (0.4 + cov);
	COLOR = col;
}
