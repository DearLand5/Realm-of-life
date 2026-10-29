// Individual feathers (flight feathers, tail feathers, coverts). Opaque,
// double-sided. Attributes:
//   COLOR = slot weights, CUSTOM0 = (rest position, slot),
//   UV = (t along the feather 0 base .. 1 tip, s across -1 .. 1),
//   UV2 = (ao, position along the wing / tail 0..1), CUSTOM1 = (part id, feather index).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/creature_common.gdshaderinc"

varying vec3 v_rest;
varying vec4 v_slots;
varying vec2 v_uv;
varying vec2 v_uv2;
varying float v_idx;
varying float v_hl;

void vertex() {
	v_rest = CUSTOM0.xyz;
	v_slots = COLOR;
	v_uv = UV;
	v_uv2 = UV2;
	v_idx = CUSTOM1.y;
	v_hl = cv_highlight_of(CUSTOM1.x);
}

void fragment() {
	int i0;
	int i1;
	float w0;
	float w1;
	cv_top_slots(v_slots, i0, i1, w0, w1);
	vec4 A = cv_slot_a(i0);
	vec4 B = cv_slot_b(i0);
	vec4 S = cv_slot_p(i0);
	int pat = int(B.w + 0.5);
	float t = clamp(v_uv.x, 0.0, 1.0);
	float s = v_uv.y;
	float along_wing = v_uv2.y;
	float inv_c = max(cv_individual.y, 1e-4);
	vec3 Pb = v_rest * inv_c;
	vec3 P = Pb * S.x + cv_seed_offset();
	// Plumage patterns are defined per feather (t = base..tip), which is how
	// real wing bars, barring and pale tips arise.
	float m;
	float edge_noise = (cv_vnoise(vec3(v_idx * 3.1, t * 6.0, s * 2.0)) - 0.5) * 0.08;
	if (pat == P_BANDS) {
		// Pale tip bar on every feather -> continuous wing bars across rows.
		m = smoothstep(0.66, 0.74, t + edge_noise) * (1.0 - smoothstep(0.9, 0.98, t) * 0.4);
	} else if (pat == P_RINGS || pat == P_STRIPES) {
		m = smoothstep(0.55, 0.8, sin((t * 4.5 * S.x + abs(s) * 0.4) * 3.14159) * 0.5 + 0.5);
	} else if (pat == P_SPOTS) {
		m = 1.0 - smoothstep(0.1, 0.16, length(vec2(t - 0.78, s * 0.35)));
	} else if (pat == P_GRADIENT) {
		m = smoothstep(0.2, 1.0, t * 0.7 + along_wing * 0.3);
	} else if (pat == P_COUNTERSHADE) {
		m = FRONT_FACING ? smoothstep(0.75, 0.95, t) * 0.3 : 0.85;
	} else {
		m = cv_pattern(pat, P, t / inv_c, 0.5, t);
	}
	vec3 col = mix(A.rgb, B.rgb, m * clamp(S.y * 1.25, 0.0, 1.0));
	float hseed = cv_hash13(vec3(v_idx, cv_individual.x * 91.0, 3.0));
	col *= 0.9 + 0.18 * hseed;
	float rachis = 1.0 - smoothstep(0.03, 0.09, abs(s));
	float barbs = 0.5 + 0.5 * sin((t * 70.0 - abs(s) * 26.0));
	col *= 0.86 + 0.14 * barbs;
	col = mix(col, mix(col, vec3(0.92, 0.9, 0.85), 0.5), rachis * 0.6);
	col *= mix(1.0, 0.75, smoothstep(0.8, 1.0, abs(s)));
	CvSurf sf;
	sf.albedo = col;
	sf.rough = 0.68;
	sf.spec = 0.25;
	sf.metal = 0.0;
	sf.height = barbs * 0.3 + rachis;
	sf.bump = 0.0;
	sf.rim = 0.25;
	sf.rim_tint = 0.7;
	sf.clearcoat = 0.0;
	sf.cc_rough = 0.3;
	sf.sss = 0.3;
	sf.alpha = 1.0;
	if (S.w > 0.0) {
		sf.albedo = cv_iridescent(sf.albedo, S.w, abs(dot(normalize(NORMAL), VIEW)), Pb);
	}
	cv_apply_condition(sf, Pb);
	vec3 n = cv_bump(normalize(NORMAL), VERTEX, sf.height, 0.0004 * length(MODEL_MATRIX[0].xyz) / inv_c * 0.3);
	float ndv = clamp(dot(n, VIEW), 0.0, 1.0);
	float ao = clamp(v_uv2.x, 0.0, 1.0);
	ALBEDO = sf.albedo * mix(0.55, 1.0, ao);
	ROUGHNESS = sf.rough;
	SPECULAR = sf.spec;
	NORMAL = n;
	RIM = sf.rim;
	RIM_TINT = sf.rim_tint;
	BACKLIGHT = sf.albedo * 0.25;
	AO = ao;
	EMISSION = vec3(1.0, 0.72, 0.25) * (0.12 + 0.9 * pow(1.0 - ndv, 2.5)) * v_hl;
}
