// Hard and dark accessories: horns, claws, hooves, teeth, beaks, mandibles,
// whiskers, spikes, rhinarium and dark detail strips (lip line, gill slits,
// nostrils, pores). Attributes:
//   COLOR = covering slot weights of the part, CUSTOM0 = (local x, t along, local z, code),
//   CUSTOM1 = (part id, code), UV = (t, around), UV2 = (ao, t).
// Codes: 0 horn, 1 claw, 2 hoof, 3 tooth, 4 beak, 5 mandible, 6 whisker,
//        7 dark detail, 8 rhinarium (wet nose), 9 spike.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/creature_common.gdshaderinc"

varying vec4 v_slots;
varying vec3 v_loc;
varying float v_code;
varying float v_ao;
varying float v_hl;

void vertex() {
	v_slots = COLOR;
	v_loc = CUSTOM0.xyz;
	v_code = CUSTOM1.y;
	v_ao = UV2.x;
	v_hl = cv_highlight_of(CUSTOM1.x);
}

bool cv_hard_type(int t) {
	return t == T_SCALES || t == T_PLATES || t == T_SHELL || t == T_CHITIN;
}

void fragment() {
	int code = int(v_code + 0.5);
	float t = clamp(v_loc.y, 0.0, 1.0);
	int i0;
	int i1;
	float w0;
	float w1;
	cv_top_slots(v_slots, i0, i1, w0, w1);
	vec4 A = cv_slot_a(i0);
	vec4 B = cv_slot_b(i0);
	bool hard_slot = cv_hard_type(int(A.w + 0.5));
	float seed = cv_individual.x;
	vec3 keratin = mix(vec3(0.78, 0.71, 0.58), vec3(0.62, 0.55, 0.45), seed);
	vec3 col = keratin;
	float rough = 0.45;
	float spec = 0.45;
	float cc = 0.0;
	float h = 0.0;
	float n1 = cv_vnoise(vec3(t * 40.0, v_loc.x * 3.0, v_loc.z * 3.0));
	if (code == 0) {
		col = hard_slot ? mix(A.rgb, keratin, 0.25) : keratin;
		col *= mix(1.0, 0.42, smoothstep(0.35, 1.0, t));
		float rings = 0.5 + 0.5 * sin(t * 48.0 + n1 * 2.0);
		col *= 0.9 + 0.12 * rings;
		h = rings * (1.0 - t);
		rough = 0.42;
	} else if (code == 1) {
		col = mix(vec3(0.16, 0.14, 0.12), vec3(0.55, 0.5, 0.42), smoothstep(0.55, 1.0, t));
		rough = 0.3;
		spec = 0.55;
		cc = 0.3;
	} else if (code == 2) {
		col = vec3(0.13, 0.11, 0.1) * (0.85 + 0.3 * cv_vnoise(vec3(v_loc.x * 9.0, t * 3.0, v_loc.z * 9.0)));
		h = cv_vnoise(vec3(v_loc.x * 30.0, t * 2.0, v_loc.z * 30.0));
		rough = 0.55;
	} else if (code == 3) {
		col = vec3(0.93, 0.9, 0.8) * mix(1.0, 0.85, t);
		rough = 0.28;
		spec = 0.55;
	} else if (code == 4) {
		col = hard_slot ? A.rgb : mix(B.rgb, keratin, 0.5);
		col = mix(col, col * vec3(0.55, 0.5, 0.48), smoothstep(0.6, 1.0, t));
		rough = 0.32;
		cc = 0.35;
		h = n1 * 0.3;
	} else if (code == 5) {
		col = mix(A.rgb, vec3(0.06, 0.05, 0.04), smoothstep(0.3, 1.0, t));
		rough = 0.2;
		spec = 0.65;
		cc = 0.8;
	} else if (code == 6) {
		col = mix(vec3(0.92, 0.9, 0.85), B.rgb, 0.25);
		rough = 0.35;
	} else if (code == 7) {
		col = vec3(0.045, 0.035, 0.03);
		rough = 0.65;
		spec = 0.2;
	} else if (code == 8) {
		col = vec3(0.1, 0.075, 0.075) * (0.8 + 0.4 * cv_vnoise(v_loc * 40.0));
		h = cv_vnoise(v_loc * 60.0);
		rough = 0.18;
		spec = 0.6;
		cc = 0.6;
	} else {
		col = hard_slot ? A.rgb : keratin;
		col = mix(col, keratin * 1.1, smoothstep(0.5, 1.0, t) * 0.6);
		rough = 0.38;
	}
	CvSurf s;
	s.albedo = col;
	s.rough = rough;
	s.spec = spec;
	s.metal = 0.0;
	s.height = h;
	s.bump = 0.0;
	s.rim = 0.0;
	s.rim_tint = 0.0;
	s.clearcoat = cc;
	s.cc_rough = 0.2;
	s.sss = 0.0;
	s.alpha = 1.0;
	cv_apply_condition(s, v_loc * 4.0);
	vec3 n = normalize(NORMAL);
	if (h > 0.0) {
		n = cv_bump(n, VERTEX, h, 0.0015 * length(MODEL_MATRIX[0].xyz) / max(cv_individual.y, 1e-4) * 0.2);
	}
	float ndv = clamp(dot(n, VIEW), 0.0, 1.0);
	float ao = clamp(v_ao, 0.0, 1.0);
	ALBEDO = s.albedo * mix(0.6, 1.0, ao);
	ROUGHNESS = s.rough;
	SPECULAR = s.spec;
	NORMAL = n;
	CLEARCOAT = s.clearcoat;
	CLEARCOAT_ROUGHNESS = s.cc_rough;
	AO = ao;
	EMISSION = vec3(1.0, 0.72, 0.25) * (0.12 + 0.9 * pow(1.0 - ndv, 2.5)) * v_hl;
}
