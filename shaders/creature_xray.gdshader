// X-ray ghost of the body surface: fresnel-weighted translucent shell so the
// organs inside stay readable. Highlighted parts glow warmer.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

#include "res://shaders/creature_common.gdshaderinc"

varying float v_hl;

void vertex() {
	v_hl = cv_highlight_of(CUSTOM1.x);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float ndv = clamp(abs(dot(n, VIEW)), 0.0, 1.0);
	float f = pow(1.0 - ndv, 2.2);
	vec3 tint = mix(vec3(0.45, 0.78, 1.0), vec3(1.0, 0.75, 0.3), v_hl);
	ALBEDO = tint * (0.4 + 0.8 * f);
	ALPHA = 0.05 + 0.6 * f + 0.1 * v_hl;
}
