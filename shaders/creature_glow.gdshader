// Bioluminescent light organs. COLOR = light colour, CUSTOM0.w = intensity,
// CUSTOM1 = (part id, pulse phase). Pulses slowly; brightest facing the viewer.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/creature_common.gdshaderinc"

varying vec4 v_col;
varying float v_int;
varying float v_phase;
varying float v_hl;

void vertex() {
	v_col = COLOR;
	v_int = CUSTOM0.w;
	v_phase = CUSTOM1.y;
	v_hl = cv_highlight_of(CUSTOM1.x);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float ndv = clamp(dot(n, VIEW), 0.0, 1.0);
	float fatigue = clamp(cv_condition.z, 0.0, 1.0);
	float pulse = 0.75 + 0.25 * sin(TIME * (1.3 + cv_individual.x) + v_phase * 6.28318);
	float core = smoothstep(0.0, 0.9, ndv);
	ALBEDO = v_col.rgb * 0.5;
	ROUGHNESS = 0.15;
	SPECULAR = 0.7;
	EMISSION = v_col.rgb * v_int * (0.6 + 2.2 * core) * pulse * (1.0 - fatigue * 0.6)
		+ vec3(1.0, 0.72, 0.25) * (0.12 + 0.9 * pow(1.0 - ndv, 2.5)) * v_hl;
}
