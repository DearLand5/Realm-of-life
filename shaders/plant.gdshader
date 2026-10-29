// Procedural plants (one material per species). Leaf shapes are drawn here
// on alpha-scissor cards — no image textures. Vertex data (PlantMeshBuilder):
//   COLOR.r ambient occlusion, COLOR.g per-card random,
//   UV = part coordinates, UV2 = (part kind, sway weight).
// INSTANCE_CUSTOM = (colour variation −1..1, dryness 0..1, phase 0..1, unused).
// Colours are combined in sRGB and converted to linear at the end.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx, world_vertex_coords;

#include "res://shaders/terrain_noise.gdshaderinc"

uniform vec3 leaf_color = vec3(0.3, 0.52, 0.2);
uniform vec3 trunk_color = vec3(0.36, 0.27, 0.18);
uniform vec3 flower_color = vec3(0.95, 0.85, 0.3);
uniform vec3 stem_color = vec3(0.4, 0.5, 0.25);
uniform float plant_height = 1.0;
uniform float sway_amount = 1.0;          // grass 1 .. trees ~0.3
uniform bool aquatic = false;
uniform vec2 wind = vec2(1.5, 0.4);
uniform float seasonal = 0.3;             // species: 0 evergreen .. 1 deciduous
uniform float autumn = 0.0;
uniform float leaf_loss = 0.0;
uniform float blossom = 0.0;
uniform float snow = 0.0;
uniform float dryness = 0.0;              // regional drought
uniform float fade_end = 60.0;            // instances vanish (dithered) beyond this camera distance

varying float v_kind;
varying vec2 v_uv;
varying vec4 v_col;
varying vec4 v_inst;
varying float v_fade;

void vertex() {
	v_kind = UV2.x;
	v_uv = UV;
	v_col = COLOR;
	v_inst = INSTANCE_CUSTOM;
	float sw = UV2.y;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float cam_d = distance(CAMERA_POSITION_WORLD, origin);
	v_fade = clamp((fade_end - cam_d) / (fade_end * 0.18), 0.0, 1.0);
	if (cam_d > fade_end) {
		VERTEX = origin;   // collapse: culled on the GPU
	}
	float wl = length(wind);
	vec2 wd = wl > 0.01 ? wind / wl : vec2(1.0, 0.0);
	float t = TIME * (aquatic ? 0.45 : 1.0);
	float phase = v_inst.z * 6.2831 + dot(origin.xz, vec2(0.11, 0.07));
	float gust = 0.55 + 0.45 * sin(t * 0.6 + origin.x * 0.021 + origin.z * 0.017);
	float wind_eff = aquatic ? 1.5 : wl;
	float bend = (0.02 + 0.014 * wind_eff * gust) * sway_amount * plant_height;
	vec2 off = wd * bend * (0.55 + 0.45 * sin(t * 1.7 + phase));
	off += vec2(-wd.y, wd.x) * bend * 0.3 * sin(t * 2.3 + phase * 1.3);
	VERTEX.xz += off * sw;
	VERTEX.y -= dot(off, off) * sw * 0.2 / max(plant_height, 0.2);
	// Leaf flutter on foliage cards.
	if (v_kind > 0.5 && v_kind < 7.5) {
		VERTEX += NORMAL * sin(t * 7.0 + phase + VERTEX.x * 3.0 + VERTEX.z * 2.0) * 0.012 * sw * (0.5 + wl * 0.12) * plant_height;
	}
}

// Single pointed leaf, p.x across (−1..1), p.y along (0..1).
float leaf_shape(vec2 p) {
	float w = sin(clamp(p.y, 0.0, 1.0) * 3.14159) * (1.0 - 0.35 * p.y);
	return step(abs(p.x), w) * step(0.0, p.y) * step(p.y, 1.0);
}

// Cluster of jittered, rotated leaves; returns mask, writes the leaf's random value.
float leaf_cluster(vec2 uv, float seed, out float leaf_rnd) {
	vec2 c = uv - 0.5;
	float r = length(c);
	leaf_rnd = 0.5;
	float edge = 0.4 + 0.1 * rl_vnoise(vec2(atan(c.y, c.x) * 2.0 + seed * 9.0, seed * 3.0));
	if (r > edge + 0.06) {
		return 0.0;
	}
	vec2 g = uv * 3.6 + seed * 7.0;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float m = 0.0;
	for (int j = 0; j < 2; j++) {
		for (int i = 0; i < 2; i++) {
			vec2 id = cell + vec2(float(i), float(j)) + step(0.5, f) - 1.0;
			float h = rl_hash12(id);
			float ang = h * 6.2831;
			vec2 center = id + 0.5 + (vec2(rl_hash12(id + 3.1), rl_hash12(id + 7.7)) - 0.5) * 0.45;
			vec2 d = g - center;
			vec2 dir = vec2(cos(ang), sin(ang));
			vec2 lp = vec2(dot(d, vec2(-dir.y, dir.x)), dot(d, dir)) / (0.8 + 0.35 * h);
			float lm = leaf_shape(vec2(lp.x * 2.6, lp.y + 0.45));
			if (lm > 0.5) {
				m = 1.0;
				leaf_rnd = h;
			}
		}
	}
	return m * step(r, edge + 0.06 * rl_hash12(cell));
}

float grass_blades(vec2 uv, float seed) {
	float n = 7.0;
	float x = uv.x * n;
	float id = floor(x);
	float h = rl_hash12(vec2(id, seed * 31.0));
	float top = 0.5 + 0.5 * h;
	float fx = fract(x) - 0.5 - (h - 0.5) * 0.5 * uv.y * uv.y;
	float w = 0.42 * (1.0 - uv.y / top);
	return step(abs(fx), w) * step(uv.y, top);
}

float needles(vec2 uv, float seed) {
	float x = abs(uv.x - 0.5) * 2.0;
	float half_w = (1.0 - uv.y * 0.9) * (0.8 + 0.2 * sin(uv.y * 3.14159));
	float serr = 0.12 * sin(uv.y * 60.0 + seed * 10.0) * x;
	float sprig = rl_vnoise(vec2(uv.y * 12.0 + seed * 5.0, x * 6.0));
	return step(x, half_w * 0.92 + serr) * step(0.28, sprig + 0.45 * (1.0 - x));
}

float frond(vec2 uv) {
	float x = abs(uv.x - 0.5) * 2.0;
	float env = sin(clamp(uv.y * 1.05, 0.0, 1.0) * 3.14159) * (1.05 - uv.y * 0.25);
	float rach = step(x, 0.06) * step(uv.y, 0.97);
	float l = fract((uv.y - x * 0.1) * 15.0);
	float leaflet = step(abs(l - 0.5), 0.34 * (1.0 - x * 0.7)) * step(x, env);
	return max(rach, leaflet);
}

void fragment() {
	int kind = int(v_kind + 0.5);
	vec2 uv = v_uv;
	float cardv = v_col.g;
	float var = v_inst.x;
	float dry = clamp(v_inst.y + dryness * 0.6, 0.0, 1.0);
	// Two-sided cards keep their crown normals on both faces.
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;

	vec3 leaf = leaf_color * (1.0 + 0.14 * var);
	leaf = mix(leaf, leaf * vec3(1.12, 1.06, 0.72), clamp(var, 0.0, 1.0) * 0.35);
	vec3 autumn_col = mix(vec3(0.88, 0.5, 0.12), vec3(0.72, 0.16, 0.07), step(0.62, cardv));
	autumn_col = mix(autumn_col, vec3(0.92, 0.76, 0.2), step(cardv, 0.3));
	leaf = mix(leaf, autumn_col, clamp(autumn * seasonal * 1.2, 0.0, 1.0));
	leaf = mix(leaf, vec3(0.6, 0.53, 0.32), dry * 0.75);

	vec3 col = leaf;
	float alpha = 1.0;
	float foliage = 1.0;
	float leaf_rnd = cardv;
	if (kind == 0) {
		float n = rl_vnoise(vec2(uv.x * 6.0, uv.y * 4.0));
		float fissure = rl_vnoise(vec2(uv.x * 16.0, uv.y * 0.9));
		col = trunk_color * (0.72 + 0.32 * n) * (0.8 + 0.3 * smoothstep(0.3, 0.7, fissure));
		foliage = 0.0;
	} else if (kind == 1) {
		alpha = leaf_cluster(uv, cardv, leaf_rnd);
		col = leaf * (0.82 + 0.36 * leaf_rnd);
		if (blossom > 0.0 && rl_hash12(floor(uv * 9.0) + cardv * 13.0) < blossom * 0.25) {
			col = flower_color;
		}
	} else if (kind == 2) {
		alpha = grass_blades(uv, cardv);
		col = leaf * mix(0.72, 1.05, uv.y);
	} else if (kind == 3) {
		alpha = needles(uv, cardv);
		col = leaf * (0.8 + 0.3 * rl_vnoise(uv * vec2(4.0, 20.0)));
	} else if (kind == 4) {
		alpha = frond(uv);
		col = leaf * (0.85 + 0.25 * uv.y);
	} else if (kind == 5) {
		vec2 c = uv - 0.5;
		float r = length(c) * 2.0;
		float a = atan(c.y, c.x);
		float petals = 5.0 + floor(cardv * 3.0);
		float pr = 0.5 + 0.5 * abs(cos(a * petals * 0.5));
		alpha = step(r, pr * 0.95);
		col = mix(flower_color, vec3(0.95, 0.78, 0.2), step(r, 0.22)) * (0.85 + 0.25 * (1.0 - r));
		foliage = 0.5;
	} else if (kind == 6) {
		alpha = step(abs(uv.x - 0.5) * 2.0, 1.0 - pow(uv.y, 2.0) * 0.85);
		col = leaf * mix(0.7, 1.08, uv.y);
	} else if (kind == 7) {
		alpha = step(abs(uv.x - 0.5) * 2.0, 0.82 + 0.18 * sin(uv.y * 37.0 + cardv * 9.0));
		col = leaf * (0.8 + 0.3 * uv.y);
	} else if (kind == 8) {
		float ribs = 0.72 + 0.28 * sqrt(abs(sin(uv.x * 3.14159 * 12.0)));
		col = leaf * ribs;
		float spine = step(0.93, rl_hash12(floor(vec2(uv.x * 24.0, uv.y * 14.0))));
		col = mix(col, vec3(0.92, 0.88, 0.75), spine * 0.8);
		foliage = 0.0;
	} else if (kind == 9) {
		col = flower_color * (0.85 + 0.2 * rl_vnoise(uv * vec2(10.0, 3.0)));
		float spots = step(0.86, rl_hash12(floor(uv * vec2(14.0, 5.0)))) * step(0.5, flower_color.r - flower_color.g);
		col = mix(col, vec3(0.95, 0.93, 0.88), spots);
		col *= mix(1.0, 0.55, smoothstep(0.7, 1.0, uv.y));
		foliage = 0.0;
	} else if (kind == 10) {
		col = stem_color * (0.85 + 0.2 * rl_vnoise(uv * vec2(4.0, 12.0)));
		foliage = 0.0;
	} else if (kind == 11) {
		float x = abs(uv.x - 0.5) * 2.0;
		float saw = fract(uv.y * 8.0);
		float half_w = (1.0 - uv.y) * (0.7 + 0.3 * saw) * 0.95;
		alpha = max(step(x, half_w) * step(0.06, uv.y), step(x, 0.05) * step(uv.y, 0.1));
		col = mix(leaf * (0.7 + 0.35 * saw), trunk_color, step(uv.y, 0.06));
	} else {
		col = flower_color * (0.8 + 0.25 * rl_vnoise(uv * vec2(3.0, 9.0)));
		foliage = 0.0;
	}
	// Deciduous leaf loss in winter thins the foliage.
	if (foliage > 0.75) {
		alpha *= step(leaf_loss * seasonal * 1.05, fract(leaf_rnd * 7.31 + cardv * 3.7));
	}
	// Snow settles on upward-facing parts.
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	col = mix(col, vec3(0.92, 0.94, 0.98), snow * smoothstep(0.2, 0.75, wn.y) * (aquatic ? 0.0 : 1.0));
	col *= 0.4 + 0.6 * v_col.r;

	ALBEDO = pow(max(col, vec3(0.0)), vec3(2.2));
	alpha *= step(rl_hash12(FRAGCOORD.xy), v_fade);
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = foliage > 0.5 ? 0.75 : 0.9;
	SPECULAR = 0.3;
	BACKLIGHT = ALBEDO * 0.35 * foliage;
}
