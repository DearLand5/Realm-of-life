// Thin translucent membranes: bat-like wings, insect wings, fins, webs.
// Double-sided. Attributes:
//   COLOR = slot weights, CUSTOM0 = (rest position, slot), UV = (span 0..1, chord 0..1),
//   UV2 = (ao, span), CUSTOM1 = (part id, kind) kind: 0 skin membrane, 1 fin rays,
//   2 insect wing, 3 web / fluke-like skin.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/creature_common.gdshaderinc"

varying vec3 v_rest;
varying vec4 v_slots;
varying vec2 v_uv;
varying float v_kind;
varying float v_hl;

void vertex() {
	v_rest = CUSTOM0.xyz;
	v_slots = COLOR;
	v_uv = UV;
	v_kind = CUSTOM1.y;
	v_hl = cv_highlight_of(CUSTOM1.x);
}

void fragment() {
	int kind = int(v_kind + 0.5);
	vec3 n = normalize(NORMAL);
	float ndv = abs(dot(n, VIEW));
	int i0;
	int i1;
	float w0;
	float w1;
	cv_top_slots(v_slots, i0, i1, w0, w1);
	vec4 A = cv_slot_a(i0);
	vec4 B = cv_slot_b(i0);
	vec4 S = cv_slot_p(i0);
	int pat = int(B.w + 0.5);
	float inv_c = max(cv_individual.y, 1e-4);
	vec3 Pb = v_rest * inv_c;
	vec3 P = Pb * S.x + cv_seed_offset();
	float span = v_uv.x;
	float chord = v_uv.y;
	float m;
	if (pat == P_GRADIENT) {
		m = smoothstep(0.1, 1.0, max(span, chord * 0.8));
	} else if (pat == P_BANDS || pat == P_RINGS) {
		m = smoothstep(-0.1, 0.3, sin(span * (pat == P_RINGS ? 18.0 : 7.0) * 3.14159));
	} else {
		m = cv_pattern(pat, P, span / inv_c * inv_c * 4.0, 0.5, span);
	}
	vec3 col = mix(A.rgb, B.rgb, m * clamp(S.y * 1.25, 0.0, 1.0));
	float alpha = 0.72;
	float vein = 0.0;
	float rough = 0.35;
	if (kind == 1) {
		// Fin rays run from the root to the edge.
		float rays = abs(sin(chord * 22.0 + span * 1.5));
		vein = smoothstep(0.82, 0.98, rays) * (1.0 - span * 0.3);
		alpha = mix(0.55, 0.8, smoothstep(0.75, 1.0, span));
	} else if (kind == 2) {
		// Insect wing: venation network + thin-film iridescence.
		vec4 v = cv_voronoi(vec3(span * 9.0, chord * 6.0, 0.5));
		float net = 1.0 - smoothstep(0.0, 0.05, v.y - v.x);
		float main = smoothstep(0.9, 1.0, abs(sin(chord * 9.0 + span * 2.0)));
		vein = max(net * 0.8, main);
		col = cv_iridescent(mix(col, vec3(0.85), 0.5), 0.8, ndv, vec3(span * 3.0, chord * 2.0, 0.0));
		alpha = 0.16 + 0.25 * pow(1.0 - ndv, 2.0);
		rough = 0.12;
	} else if (kind == 0) {
		// Skin membrane (bat wing): few radiating veins, wrinkles.
		float rv = smoothstep(0.93, 1.0, abs(sin(chord * 9.0 + span * 0.8)));
		vein = rv * 0.6;
		alpha = 0.86;
		rough = 0.5;
	} else {
		alpha = 0.95;
		rough = 0.45;
	}
	col *= 1.0 - vein * 0.45;
	alpha = clamp(alpha + vein * 0.35, 0.0, 1.0);
	CvSurf s;
	s.albedo = col;
	s.rough = rough;
	s.spec = 0.5;
	s.metal = 0.0;
	s.height = vein;
	s.bump = 0.0;
	s.rim = 0.2;
	s.rim_tint = 0.6;
	s.clearcoat = 0.0;
	s.cc_rough = 0.2;
	s.sss = 1.0;
	s.alpha = alpha;
	cv_apply_condition(s, Pb);
	ALBEDO = s.albedo;
	ROUGHNESS = s.rough;
	SPECULAR = s.spec;
	RIM = s.rim;
	RIM_TINT = s.rim_tint;
	BACKLIGHT = s.albedo * 0.75;
	ALPHA = s.alpha;
	EMISSION = vec3(1.0, 0.72, 0.25) * (0.12 + 0.9 * pow(1.0 - ndv, 2.5)) * v_hl;
}
