// Lightweight creature body surface for phones (CreatureMaterials.lite): same
// vertex contract as creature_body.gdshaderinc, but no fbm/voronoi patterns,
// no derivative bump mapping, no surface structs and only three varyings.
// Some mobile GPU drivers fail to build the full body pipeline, leaving the
// body invisible while eyes and teeth still render. Include after
// creature_common.gdshaderinc.

varying vec3 v_rest;
varying vec4 v_slots;
varying vec4 v_attr;     // along (m), ventral, ao, highlight

void vertex() {
	v_rest = CUSTOM0.xyz;
	v_slots = COLOR;
	v_attr = vec4(UV.x, UV.y, UV2.x, cv_highlight_of(CUSTOM1.x));
}

// Cheap stand-ins of cv_pattern (value noise only). Returns the amount of colour B.
float cl_pattern(int pat, vec3 P, float along, float ventral) {
	if (pat == P_COUNTERSHADE) {
		return smoothstep(0.42, 0.74, ventral);
	} else if (pat == P_STRIPES) {
		float s = sin((along * 3.2 + cv_vnoise(P * 1.3) * 1.8) * 3.14159);
		float thr = mix(0.25, 0.85, smoothstep(0.35, 0.85, ventral));
		return smoothstep(thr, thr + 0.12, s);
	} else if (pat == P_SPOTS || pat == P_ROSETTES) {
		return smoothstep(0.66, 0.74, cv_vnoise(P * 3.2)) * (1.0 - smoothstep(0.66, 0.9, ventral));
	} else if (pat == P_BANDS) {
		return smoothstep(-0.15, 0.25, sin(along * 1.9 * 3.14159));
	} else if (pat == P_RINGS) {
		return smoothstep(0.72, 0.9, sin(along * 6.0 * 3.14159) * 0.5 + 0.5);
	} else if (pat == P_MOTTLED) {
		return smoothstep(0.42, 0.66, cv_vnoise(P * 2.6));
	} else if (pat == P_GRADIENT) {
		return smoothstep(0.12, 0.92, ventral);
	} else if (pat == P_RETICULATED) {
		return 1.0 - smoothstep(0.03, 0.09, abs(cv_vnoise(P * 2.8) - 0.5));
	}
	return 0.0;
}

vec3 cl_colour(int slot, vec3 Pb, float along, float ventral) {
	vec4 A = cv_slot_a(slot);
	vec4 B = cv_slot_b(slot);
	vec4 S = cv_slot_p(slot);
	vec3 P = Pb * S.x + vec3(cv_individual.x * 50.0, 0.0, 0.0);
	float m = cl_pattern(int(B.w + 0.5), P, along * cv_individual.y * S.x, ventral);
	return mix(A.rgb, B.rgb, m * clamp(S.y * 1.25, 0.0, 1.0));
}

// x = roughness, y = specular, z = clearcoat, w = rim.
vec4 cl_finish(int type) {
	if (type == T_SCALES) return vec4(0.42, 0.45, 0.0, 0.05);
	if (type == T_PLATES || type == T_SHELL) return vec4(0.5, 0.4, 0.15, 0.0);
	if (type == T_CHITIN) return vec4(0.3, 0.55, 0.5, 0.0);
	if (type == T_FUR || type == T_BRISTLES) return vec4(0.85, 0.15, 0.0, 0.35);
	if (type == T_FEATHERS) return vec4(0.7, 0.25, 0.0, 0.2);
	if (type == T_SLIME || type == T_MEMBRANE) return vec4(0.15, 0.5, 0.6, 0.1);
	return vec4(0.58, 0.32, 0.0, 0.08);
}

void fragment() {
	int i0;
	int i1;
	float w0;
	float w1;
	cv_top_slots(v_slots, i0, i1, w0, w1);
	float inv_c = max(cv_individual.y, 1e-4);
	vec3 Pb = v_rest * inv_c;
	vec3 col = cl_colour(i0, Pb, v_attr.x, v_attr.y);
	if (i1 >= 0 && w1 > 0.02) {
		col = mix(col, cl_colour(i1, Pb, v_attr.x, v_attr.y), w1);
	}
	col *= 0.93 + 0.14 * cv_vnoise(Pb * 9.0 + 11.0);
	vec4 A0 = cv_slot_a(i0);
	vec4 fin = cl_finish(int(A0.w + 0.5));
	float rough = clamp(fin.x + cv_slot_p(i0).z, 0.03, 1.0);
	// Condition: wet darkens and glosses, damage reddens, fatigue greys out.
	float wet = clamp(cv_condition.x, 0.0, 1.0);
	float dmg = clamp(cv_condition.y, 0.0, 1.0);
	float fat = clamp(cv_condition.z, 0.0, 1.0);
	col *= mix(1.0, 0.72, wet);
	rough = mix(rough, 0.08, wet * 0.85);
	float wound = smoothstep(1.0 - dmg * 0.55, 1.05 - dmg * 0.5, cv_vnoise(Pb * 4.0 + 5.0) + dmg * 0.2);
	col = mix(col, vec3(0.32, 0.03, 0.03), wound);
	float g = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(g), fat * 0.35) * (1.0 - fat * 0.15);
	float ao = clamp(v_attr.z, 0.0, 1.0);
	float ndv = clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
	ALBEDO = col * mix(0.6, 1.0, ao);
	ROUGHNESS = rough;
	SPECULAR = fin.y * mix(0.4, 1.0, ao);
	RIM = fin.w;
	RIM_TINT = 0.5;
	CLEARCOAT = max(fin.z, wet * 0.8);
	CLEARCOAT_ROUGHNESS = 0.3;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	EMISSION = cv_highlight_emission(ndv, v_attr.w);
#ifdef CREATURE_TRANSLUCENT
	ALPHA = mix(0.38, 0.92, pow(1.0 - ndv, 2.0));
#endif
}
