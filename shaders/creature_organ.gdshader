// Internal organs, visible only in x-ray mode (CreatureVisual.set_xray).
// COLOR = organ colour (by organ type), CUSTOM1 = (part id, organ code).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/creature_common.gdshaderinc"

varying vec4 v_col;
varying float v_hl;

void vertex() {
	v_col = COLOR;
	v_hl = cv_highlight_of(CUSTOM1.x);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float ndv = clamp(dot(n, VIEW), 0.0, 1.0);
	ALBEDO = v_col.rgb;
	ROUGHNESS = 0.3;
	SPECULAR = 0.6;
	RIM = 0.5;
	RIM_TINT = 0.5;
	EMISSION = v_col.rgb * (0.25 + 0.35 * pow(1.0 - ndv, 2.0)) + cv_highlight_emission(ndv, v_hl);
	ALPHA = 0.9;
}
