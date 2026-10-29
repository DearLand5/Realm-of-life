// Creature body surface: up to 4 covering slots blended by vertex weights
// (COLOR), patterns in rest space (CUSTOM0.xyz), ventral factor / along-body
// coordinate (UV), SDF ambient occlusion and part position (UV2), part id for
// editor highlight (CUSTOM1.x). Include after creature_common.gdshaderinc.

varying vec3 v_rest;
varying vec4 v_slots;
varying vec3 v_attr;     // along (m), ventral, ao
varying float v_part_t;
varying float v_hl;

void vertex() {
	v_rest = CUSTOM0.xyz;
	v_slots = COLOR;
	v_attr = vec3(UV.x, UV.y, UV2.x);
	v_part_t = UV2.y;
	v_hl = cv_highlight_of(CUSTOM1.x);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float ndv = clamp(dot(n, VIEW), 0.0, 1.0);
	CvSurf s = cv_surface(v_slots, v_rest, v_attr.x, v_attr.y, v_part_t, ndv);
	float inv_c = max(cv_individual.y, 1e-4);
	cv_apply_condition(s, v_rest * inv_c);
	float node_scale = length(MODEL_MATRIX[0].xyz);
	// s.bump is the relief amplitude in units of 0.25 % of the body diameter.
	n = cv_bump(n, VERTEX, s.height, s.bump * 0.0025 / inv_c * node_scale);
	float ao = clamp(v_attr.z, 0.0, 1.0);
	ALBEDO = s.albedo * mix(0.6, 1.0, ao);
	ROUGHNESS = s.rough;
	SPECULAR = s.spec * mix(0.4, 1.0, ao);
	METALLIC = s.metal;
	NORMAL = n;
	RIM = s.rim;
	RIM_TINT = s.rim_tint;
	CLEARCOAT = s.clearcoat;
	CLEARCOAT_ROUGHNESS = s.cc_rough;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	BACKLIGHT = s.albedo * s.sss * 0.4;
	EMISSION = vec3(1.0, 0.72, 0.25) * (0.12 + 0.9 * pow(1.0 - ndv, 2.5)) * v_hl;
#ifdef CREATURE_TRANSLUCENT
	ALPHA = clamp(s.alpha, 0.0, 1.0);
#endif
}
