// Cell organelles (nucleus, plastids, vacuoles) seen through a translucent
// membrane. COLOR = organelle colour, CUSTOM0 = (local sphere position, kind).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/creature_common.gdshaderinc"

varying vec4 v_col;
varying vec3 v_loc;
varying float v_hl;

void vertex() {
	v_col = COLOR;
	v_loc = CUSTOM0.xyz;
	v_hl = cv_highlight_of(CUSTOM1.x);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float ndv = clamp(dot(n, VIEW), 0.0, 1.0);
	float grain = cv_fbm(v_loc * 4.0 + cv_individual.x * 10.0);
	vec3 col = v_col.rgb * (0.75 + 0.45 * grain);
	ALBEDO = col;
	ROUGHNESS = 0.35;
	SPECULAR = 0.5;
	RIM = 0.4;
	RIM_TINT = 0.8;
	BACKLIGHT = col * 0.6;
	EMISSION = col * 0.12 + vec3(1.0, 0.72, 0.25) * (0.12 + 0.9 * pow(1.0 - ndv, 2.5)) * v_hl;
}
