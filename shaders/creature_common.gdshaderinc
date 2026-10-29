// Shared code of all creature shaders (body, membranes, feathers, hard parts).
// Per-individual parameters are instance uniforms (max 16 per shader; all
// 16 are used here): one shared material serves every creature.
//
// Slot vectors (filled by CreatureMaterials.instance_params):
//   cv_slotN_a = (colour A rgb, covering type id)      type ids: CreatureMaterials.TYPE_IDS
//   cv_slotN_b = (colour B rgb, pattern id)             pattern ids: CoveringDef.PATTERNS order
//   cv_slotN_p = (pattern scale, contrast, roughness bias, iridescence)
//   cv_slot_thick = covering thickness of slots 0..3
//   cv_condition  = (wetness, damage, fatigue, unused)
//   cv_individual = (seed 0..1, 1 / characteristic size (body diameter), unused, unused)
//   cv_highlight  = up to four highlighted BodyPart ids (-1 = none)

instance uniform vec4 cv_slot0_a = vec4(0.55, 0.45, 0.35, 0.0);
instance uniform vec4 cv_slot0_b = vec4(0.85, 0.8, 0.7, 1.0);
instance uniform vec4 cv_slot0_p = vec4(1.0, 0.6, 0.0, 0.0);
instance uniform vec4 cv_slot1_a = vec4(0.55, 0.45, 0.35, 0.0);
instance uniform vec4 cv_slot1_b = vec4(0.85, 0.8, 0.7, 0.0);
instance uniform vec4 cv_slot1_p = vec4(1.0, 0.6, 0.0, 0.0);
instance uniform vec4 cv_slot2_a = vec4(0.55, 0.45, 0.35, 0.0);
instance uniform vec4 cv_slot2_b = vec4(0.85, 0.8, 0.7, 0.0);
instance uniform vec4 cv_slot2_p = vec4(1.0, 0.6, 0.0, 0.0);
instance uniform vec4 cv_slot3_a = vec4(0.55, 0.45, 0.35, 0.0);
instance uniform vec4 cv_slot3_b = vec4(0.85, 0.8, 0.7, 0.0);
instance uniform vec4 cv_slot3_p = vec4(1.0, 0.6, 0.0, 0.0);
instance uniform vec4 cv_slot_thick = vec4(1.0);
instance uniform vec4 cv_condition = vec4(0.0);
instance uniform vec4 cv_individual = vec4(0.0, 10.0, 0.0, 0.0);
instance uniform vec4 cv_highlight = vec4(-1.0);

const int T_SKIN = 0;
const int T_SCALES = 1;
const int T_PLATES = 2;
const int T_SHELL = 3;
const int T_CHITIN = 4;
const int T_FUR = 5;
const int T_FEATHERS = 6;
const int T_BRISTLES = 7;
const int T_SLIME = 8;
const int T_MEMBRANE = 9;

const int P_NONE = 0;
const int P_COUNTERSHADE = 1;
const int P_STRIPES = 2;
const int P_SPOTS = 3;
const int P_ROSETTES = 4;
const int P_BANDS = 5;
const int P_RINGS = 6;
const int P_MOTTLED = 7;
const int P_GRADIENT = 8;
const int P_RETICULATED = 9;

// --- Hashes and noise (sine-free hashes: stable at large coordinates) ---------

float cv_hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 cv_hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

float cv_vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = cv_hash13(i);
	float b = cv_hash13(i + vec3(1.0, 0.0, 0.0));
	float c = cv_hash13(i + vec3(0.0, 1.0, 0.0));
	float d = cv_hash13(i + vec3(1.0, 1.0, 0.0));
	float e = cv_hash13(i + vec3(0.0, 0.0, 1.0));
	float g = cv_hash13(i + vec3(1.0, 0.0, 1.0));
	float h = cv_hash13(i + vec3(0.0, 1.0, 1.0));
	float k = cv_hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(a, b, u.x), mix(c, d, u.x), u.y), mix(mix(e, g, u.x), mix(h, k, u.x), u.y), u.z);
}

float cv_fbm(vec3 p) {
	float v = cv_vnoise(p) * 0.55;
	v += cv_vnoise(p * 2.03 + 7.1) * 0.3;
	v += cv_vnoise(p * 4.11 + 3.7) * 0.15;
	return v;
}

// Cellular noise over the 2x2x2 nearest cells (feature points jittered inside
// [0.1, 0.9] of their cell, so the nearest point is almost always found).
// Returns (F1, F2, cell hash, unused).
vec4 cv_voronoi(vec3 p) {
	vec3 b = floor(p - 0.5);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int z = 0; z < 2; z++) {
		for (int y = 0; y < 2; y++) {
			for (int x = 0; x < 2; x++) {
				vec3 c = b + vec3(float(x), float(y), float(z));
				vec3 j = cv_hash33(c);
				vec3 fp = c + 0.1 + 0.8 * j;
				float d = length(p - fp);
				if (d < f1) {
					f2 = f1;
					f1 = d;
					id = j.x;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
	}
	return vec4(f1, f2, id, 0.0);
}

vec3 cv_seed_offset() {
	return cv_hash33(vec3(cv_individual.x * 937.0, 17.0, 3.0)) * 50.0;
}

// --- Slot access -----------------------------------------------------------------

vec4 cv_slot_a(int i) { return i == 0 ? cv_slot0_a : (i == 1 ? cv_slot1_a : (i == 2 ? cv_slot2_a : cv_slot3_a)); }
vec4 cv_slot_b(int i) { return i == 0 ? cv_slot0_b : (i == 1 ? cv_slot1_b : (i == 2 ? cv_slot2_b : cv_slot3_b)); }
vec4 cv_slot_p(int i) { return i == 0 ? cv_slot0_p : (i == 1 ? cv_slot1_p : (i == 2 ? cv_slot2_p : cv_slot3_p)); }
float cv_slot_t(int i) { return i == 0 ? cv_slot_thick.x : (i == 1 ? cv_slot_thick.y : (i == 2 ? cv_slot_thick.z : cv_slot_thick.w)); }
int cv_slot_type(int i) { return int(cv_slot_a(i).w + 0.5); }

// Indices of the two largest slot weights and their normalised weights.
void cv_top_slots(vec4 w, out int i0, out int i1, out float w0, out float w1) {
	i0 = 0;
	w0 = w.x;
	if (w.y > w0) { i0 = 1; w0 = w.y; }
	if (w.z > w0) { i0 = 2; w0 = w.z; }
	if (w.w > w0) { i0 = 3; w0 = w.w; }
	i1 = -1;
	w1 = 0.0;
	if (i0 != 0 && w.x > w1) { i1 = 0; w1 = w.x; }
	if (i0 != 1 && w.y > w1) { i1 = 1; w1 = w.y; }
	if (i0 != 2 && w.z > w1) { i1 = 2; w1 = w.z; }
	if (i0 != 3 && w.w > w1) { i1 = 3; w1 = w.w; }
	float s = max(w0 + w1, 1e-4);
	w0 /= s;
	w1 /= s;
}

float cv_highlight_of(float part) {
	vec4 d = abs(cv_highlight - vec4(part));
	float m = min(min(d.x, d.y), min(d.z, d.w));
	return part >= 0.0 && m < 0.5 ? 1.0 : 0.0;
}

// --- Patterns (rest space: they stick to the body while it animates) -----------
// P: rest position in body-diameter units × pattern scale (+ individual offset)
// along: along-body coordinate in the same units, ventral 0 (back) .. 1 (belly),
// part_t: 0 part root .. 1 tip. Returns the amount of colour B (0..1).

float cv_pattern(int pat, vec3 P, float along, float ventral, float part_t) {
	if (pat == P_NONE) {
		return 0.0;
	} else if (pat == P_COUNTERSHADE) {
		return smoothstep(0.42, 0.74, ventral + (cv_vnoise(P * 3.0) - 0.5) * 0.14);
	} else if (pat == P_STRIPES) {
		float warp = cv_fbm(P * 1.3) * 1.8;
		float s = sin((along * 3.2 + warp) * 3.14159);
		float belly = 1.0 - smoothstep(0.62, 0.86, ventral);
		return smoothstep(0.2, 0.55, s) * belly;
	} else if (pat == P_SPOTS) {
		vec4 v = cv_voronoi(P * 3.2);
		float r = 0.2 + 0.16 * v.z;
		return 1.0 - smoothstep(r - 0.07, r + 0.07, v.x + (cv_vnoise(P * 9.0) - 0.5) * 0.08);
	} else if (pat == P_ROSETTES) {
		vec4 v = cv_voronoi(P * 2.6);
		float n = cv_vnoise(P * 7.0);
		float ring = smoothstep(0.17, 0.24, v.x) * (1.0 - smoothstep(0.31, 0.4, v.x + n * 0.06));
		ring *= smoothstep(0.25, 0.45, n + 0.2 * v.z);
		float inner = (1.0 - smoothstep(0.12, 0.2, v.x)) * 0.35;
		float belly = 1.0 - smoothstep(0.66, 0.9, ventral);
		return (ring + inner) * belly;
	} else if (pat == P_BANDS) {
		float s = sin(along * 1.9 * 3.14159 + cv_vnoise(P * 2.0) * 0.8);
		return smoothstep(-0.15, 0.25, s);
	} else if (pat == P_RINGS) {
		float s = sin(along * 6.0 * 3.14159) * 0.5 + 0.5;
		return smoothstep(0.72, 0.9, s);
	} else if (pat == P_MOTTLED) {
		return smoothstep(0.42, 0.66, cv_fbm(P * 2.6));
	} else if (pat == P_GRADIENT) {
		return smoothstep(0.12, 0.92, ventral * 0.75 + part_t * 0.25 + (cv_vnoise(P * 2.0) - 0.5) * 0.1);
	} else if (pat == P_RETICULATED) {
		vec4 v = cv_voronoi(P * 2.8);
		return 1.0 - smoothstep(0.025, 0.085, v.y - v.x);
	}
	return 0.0;
}

// --- Covering looks ----------------------------------------------------------------

struct CvSurf {
	vec3 albedo;
	float rough;
	float spec;
	float metal;
	float height;     // bump height (body-diameter units scale, applied by caller)
	float bump;       // bump strength
	float rim;
	float rim_tint;
	float clearcoat;
	float cc_rough;
	float sss;        // wrap / translucency amount
	float alpha;
};

vec3 cv_iridescent(vec3 base, float amount, float ndv, vec3 P) {
	vec3 film = 0.5 + 0.5 * cos(6.28318 * (vec3(0.0, 0.33, 0.67) + ndv * 1.7 + P.x * 0.35 + P.z * 0.2));
	return mix(base, base * 0.45 + film * (0.35 + 0.6 * dot(base, vec3(0.33))), amount);
}

// Full look of one covering slot at a surface point.
CvSurf cv_slot_surface(int slot, vec3 rest, float along, float ventral, float part_t, float ndv) {
	vec4 A = cv_slot_a(slot);
	vec4 B = cv_slot_b(slot);
	vec4 S = cv_slot_p(slot);
	float thick = cv_slot_t(slot);
	int type = int(A.w + 0.5);
	int pat = int(B.w + 0.5);
	float inv_c = cv_individual.y;
	vec3 Pb = rest * inv_c;                      // body-diameter units
	vec3 P = Pb * S.x + cv_seed_offset();        // pattern space
	float al = along * inv_c * S.x;
	float m = cv_pattern(pat, P, al, ventral, part_t) * clamp(S.y * 1.25, 0.0, 1.0);
	vec3 col = mix(A.rgb, B.rgb, m);
	float n1 = cv_vnoise(Pb * 9.0 + 11.0);
	CvSurf s;
	s.albedo = col * (0.93 + 0.14 * n1);
	s.rough = 0.55;
	s.spec = 0.35;
	s.metal = 0.0;
	s.height = 0.0;
	s.bump = 0.0;
	s.rim = 0.0;
	s.rim_tint = 0.5;
	s.clearcoat = 0.0;
	s.cc_rough = 0.3;
	s.sss = 0.0;
	s.alpha = 1.0;
	if (type == T_SKIN) {
		s.height = cv_fbm(Pb * 22.0) * 0.6 + cv_vnoise(Pb * 70.0) * 0.4;
		s.bump = 0.35;
		s.rough = 0.58;
		s.spec = 0.32;
		s.sss = 0.35;
		s.rim = 0.08;
	} else if (type == T_SCALES) {
		vec4 v = cv_voronoi(Pb * vec3(26.0, 26.0, 20.0) / max(thick, 0.3));
		float dome = 1.0 - smoothstep(0.0, 0.55, v.x);
		float edge = smoothstep(0.0, 0.12, v.y - v.x);
		s.height = dome * 0.8 + edge * 0.4;
		s.bump = 0.9;
		s.albedo *= mix(0.68, 1.05, edge) * (0.92 + 0.16 * v.z);
		s.rough = 0.38;
		s.spec = 0.55;
		s.rim = 0.12;
	} else if (type == T_PLATES) {
		vec4 v = cv_voronoi(Pb * 7.0 / max(thick, 0.3));
		float groove = smoothstep(0.0, 0.07, v.y - v.x);
		float bevel = smoothstep(0.0, 0.25, v.y - v.x);
		s.height = bevel + cv_vnoise(Pb * 40.0) * 0.15;
		s.bump = 1.1;
		s.albedo *= mix(0.5, 1.0, groove) * (0.9 + 0.2 * v.z);
		s.rough = 0.62;
		s.spec = 0.3;
	} else if (type == T_SHELL) {
		vec4 v = cv_voronoi(Pb * 3.6);
		float seam = smoothstep(0.0, 0.05, v.y - v.x);
		float growth = 0.5 + 0.5 * sin((v.y - v.x) * 70.0);
		s.height = smoothstep(0.0, 0.2, v.y - v.x) + growth * 0.08;
		s.bump = 1.0;
		s.albedo *= mix(0.45, 1.0, seam) * (0.88 + 0.12 * growth) * (0.9 + 0.2 * v.z);
		s.rough = 0.34;
		s.spec = 0.45;
		s.clearcoat = 0.35;
		s.cc_rough = 0.25;
	} else if (type == T_CHITIN) {
		float seg = smoothstep(0.86, 0.98, sin(along * inv_c * 9.0) * 0.5 + 0.5);
		s.height = cv_vnoise(Pb * 30.0) * 0.25 - seg * 0.6;
		s.bump = 0.5;
		s.albedo *= 1.0 - seg * 0.35;
		s.rough = 0.2;
		s.spec = 0.65;
		s.clearcoat = 0.9;
		s.cc_rough = 0.12;
		s.rim = 0.15;
	} else if (type == T_FUR) {
		// Soft coat: fine low-contrast strands, larger clumps, velvet rim sheen.
		float strands = cv_vnoise(Pb * vec3(120.0, 120.0, 40.0));
		float clumps = cv_fbm(Pb * 11.0);
		s.albedo *= 0.88 + 0.1 * strands + 0.16 * (clumps - 0.5);
		s.height = strands * 0.35 + clumps * 0.65;
		s.bump = 0.22 * min(thick, 2.0);
		s.rough = 0.88;
		s.spec = 0.1;
		s.rim = 0.32 * min(thick, 1.5);
		s.rim_tint = 0.9;
		s.sss = 0.4;
	} else if (type == T_FEATHERS) {
		vec3 q = Pb * vec3(13.0, 13.0, 9.0);
		vec4 v = cv_voronoi(q);
		float vane = sin((v.x * 26.0) + q.y * 3.0) * 0.5 + 0.5;
		float tip = smoothstep(0.25, 0.5, v.x);
		s.albedo *= (0.84 + 0.16 * vane) * mix(1.0, 0.78, tip);
		s.height = (1.0 - v.x) * 0.7 + vane * 0.15;
		s.bump = 0.55;
		s.rough = 0.72;
		s.spec = 0.22;
		s.rim = 0.3;
		s.rim_tint = 0.7;
		s.sss = 0.2;
	} else if (type == T_BRISTLES) {
		vec4 v = cv_voronoi(Pb * 46.0);
		float hair = 1.0 - smoothstep(0.05, 0.16, v.x);
		s.albedo *= mix(1.0, 0.55, hair * 0.8);
		s.height = hair + cv_vnoise(Pb * 25.0) * 0.3;
		s.bump = 0.6;
		s.rough = 0.82;
		s.spec = 0.15;
		s.rim = 0.35;
		s.rim_tint = 0.6;
	} else if (type == T_SLIME) {
		s.height = cv_fbm(Pb * 14.0);
		s.bump = 0.4;
		s.rough = 0.08;
		s.spec = 0.75;
		s.clearcoat = 1.0;
		s.cc_rough = 0.05;
		s.sss = 0.5;
		s.rim = 0.1;
	} else if (type == T_MEMBRANE) {
		vec4 v = cv_voronoi(Pb * 5.0);
		float vein = 1.0 - smoothstep(0.0, 0.05, v.y - v.x);
		s.albedo = mix(s.albedo, s.albedo * 0.7, vein * 0.5);
		s.height = cv_vnoise(Pb * 12.0) * 0.3 + vein * 0.2;
		s.bump = 0.25;
		s.rough = 0.22;
		s.spec = 0.6;
		s.sss = 0.9;
		s.rim = 0.3;
		s.alpha = mix(0.38, 0.92, pow(1.0 - ndv, 2.0));
	}
	s.rough = clamp(s.rough + S.z, 0.03, 1.0);
	if (S.w > 0.0) {
		s.albedo = cv_iridescent(s.albedo, S.w, ndv, Pb);
		s.metal = max(s.metal, S.w * 0.3);
	}
	return s;
}

CvSurf cv_mix_surf(CvSurf a, CvSurf b, float t) {
	CvSurf s;
	s.albedo = mix(a.albedo, b.albedo, t);
	s.rough = mix(a.rough, b.rough, t);
	s.spec = mix(a.spec, b.spec, t);
	s.metal = mix(a.metal, b.metal, t);
	s.height = mix(a.height, b.height, t);
	s.bump = mix(a.bump, b.bump, t);
	s.rim = mix(a.rim, b.rim, t);
	s.rim_tint = mix(a.rim_tint, b.rim_tint, t);
	s.clearcoat = mix(a.clearcoat, b.clearcoat, t);
	s.cc_rough = mix(a.cc_rough, b.cc_rough, t);
	s.sss = mix(a.sss, b.sss, t);
	s.alpha = mix(a.alpha, b.alpha, t);
	return s;
}

// Blend of the two dominant slots (secondary only evaluated where it matters).
CvSurf cv_surface(vec4 slot_w, vec3 rest, float along, float ventral, float part_t, float ndv) {
	int i0;
	int i1;
	float w0;
	float w1;
	cv_top_slots(slot_w, i0, i1, w0, w1);
	CvSurf s = cv_slot_surface(i0, rest, along, ventral, part_t, ndv);
	if (i1 >= 0 && w1 > 0.02) {
		CvSurf s1 = cv_slot_surface(i1, rest, along, ventral, part_t, ndv);
		s = cv_mix_surf(s, s1, w1);
	}
	return s;
}

// Wetness / damage / fatigue (cv_condition) on top of the covering look.
void cv_apply_condition(inout CvSurf s, vec3 Pb) {
	float wet = clamp(cv_condition.x, 0.0, 1.0);
	float dmg = clamp(cv_condition.y, 0.0, 1.0);
	float fat = clamp(cv_condition.z, 0.0, 1.0);
	if (wet > 0.0) {
		s.albedo *= mix(1.0, 0.72, wet);
		s.rough = mix(s.rough, 0.08, wet * 0.85);
		s.clearcoat = max(s.clearcoat, wet * 0.8);
		s.cc_rough = mix(s.cc_rough, 0.05, wet);
		s.rim *= 1.0 - wet * 0.6;
	}
	if (dmg > 0.0) {
		float n = cv_fbm(Pb * 4.0 + 5.0);
		float wound = smoothstep(1.0 - dmg * 0.55, 1.05 - dmg * 0.5, n);
		float bruise = smoothstep(1.0 - dmg * 0.8, 1.0 - dmg * 0.4, n) * 0.5;
		s.albedo = mix(s.albedo, s.albedo * vec3(0.55, 0.4, 0.45), bruise);
		s.albedo = mix(s.albedo, vec3(0.32, 0.03, 0.03), wound);
		s.rough = mix(s.rough, 0.25, wound);
	}
	if (fat > 0.0) {
		float g = dot(s.albedo, vec3(0.3, 0.59, 0.11));
		s.albedo = mix(s.albedo, vec3(g), fat * 0.35) * (1.0 - fat * 0.15);
		s.rough = min(1.0, s.rough + fat * 0.12);
		s.rim *= 1.0 - fat * 0.5;
	}
}

// Screen-space derivative bump mapping (Mikkelsen 2010): works on deformed,
// skinned surfaces without tangents and in every renderer.
vec3 cv_bump(vec3 n, vec3 pos, float h, float strength) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	float dhdx = dFdx(h) * strength;
	float dhdy = dFdy(h) * strength;
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	if (abs(det) < 1e-12) {
		return n;
	}
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	return normalize(abs(det) * n - grad);
}
